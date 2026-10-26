import Foundation

/// Script perl et framework embarqués dans l'app par `scripts/embed-mediaremote-adapter.sh`.
struct AdapterPaths: Sendable {
    var script: URL
    var framework: URL

    static func bundled(in bundle: Bundle = .main) -> AdapterPaths? {
        guard
            let script = bundle.url(forResource: "mediaremote-adapter", withExtension: "pl"),
            let framework = bundle.privateFrameworksURL?.appendingPathComponent("MediaRemoteAdapter.framework"),
            FileManager.default.fileExists(atPath: framework.path)
        else { return nil }
        return AdapterPaths(script: script, framework: framework)
    }
}

enum AdapterError: Error {
    case exited(status: Int32)
}

/// Lit le « Now Playing » de macOS via mediaremote-adapter : `/usr/bin/perl`, binaire système autorisé,
/// charge le framework et écrit chaque changement en JSON sur sa sortie standard.
@MainActor
final class MediaRemoteAdapterSource: NowPlayingSource {
    let kind = MediaSourceKind.mediaRemoteAdapter

    private let paths: AdapterPaths

    init(paths: AdapterPaths) {
        self.paths = paths
    }

    /// Un adaptateur survit à l'app si elle est tuée sans se terminer (plantage, arrêt depuis Xcode) :
    /// rattaché à launchd, il ne s'arrête qu'à sa prochaine écriture. On nettoie ceux de cette copie de l'app.
    static func terminateOrphans(paths: AdapterPaths) {
        let pkill = Process()
        pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkill.arguments = ["-P", "1", "-f", paths.script.path]
        try? pkill.run()
        pkill.waitUntilExit()
    }

    func updates() -> AsyncThrowingStream<NowPlaying?, any Error> {
        let adapter = AdapterProcess(
            paths: paths,
            arguments: ["stream", "--no-diff", "--micros", "--debounce=100"],
            capturesOutput: true
        )
        return AsyncThrowingStream { continuation in
            let reader = Task.detached {
                do {
                    try adapter.run()
                    var decoder = AdapterStreamDecoder()
                    for try await line in adapter.outputLines where decoder.apply(line: line) {
                        continuation.yield(decoder.nowPlaying)
                    }
                    continuation.finish(throwing: AdapterError.exited(status: adapter.waitUntilExit()))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                reader.cancel()
                adapter.terminate()
            }
        }
    }

    func send(_ command: MediaCommand) {
        runCommand(["send", String(command.adapterID)])
    }

    func seek(to position: TimeInterval) {
        runCommand(["seek", String(Int((position * 1_000_000).rounded()))])
    }

    private func runCommand(_ arguments: [String]) {
        let adapter = AdapterProcess(paths: paths, arguments: arguments, capturesOutput: false)
        Task.detached {
            try? adapter.run()
            _ = adapter.waitUntilExit()
        }
    }
}

/// Processus perl de l'adaptateur. `Process` n'est utilisé qu'à travers run, terminate
/// et waitUntilExit, sûrs depuis n'importe quel thread.
final class AdapterProcess: @unchecked Sendable {
    private let process = Process()
    private let output = Pipe()

    init(paths: AdapterPaths, arguments: [String], capturesOutput: Bool) {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [paths.script.path, paths.framework.path] + arguments
        process.standardOutput = capturesOutput ? output : FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
    }

    var outputLines: AsyncLineSequence<FileHandle.AsyncBytes> {
        output.fileHandleForReading.bytes.lines
    }

    func run() throws {
        try process.run()
    }

    func terminate() {
        if process.isRunning {
            process.terminate()
        }
    }

    func waitUntilExit() -> Int32 {
        process.waitUntilExit()
        return process.terminationStatus
    }
}
