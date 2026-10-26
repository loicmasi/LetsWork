import AppKit
import Observation
import os

private let logger = Logger(subsystem: "dev.projects.letswork", category: "media")

/// Lecture en cours sur le Mac : choisit la source (adaptateur, sinon repli AppleScript),
/// expose l'état aux vues et relaie les commandes.
@MainActor
@Observable
final class MediaService {
    enum Status: Equatable {
        case stopped
        case adapter
        /// `adapterMissing` : framework non embarqué ; sinon l'adaptateur a échoué à répétition.
        case appleScriptFallback(adapterMissing: Bool)
    }

    /// Une source qui s'arrête avant ce délai compte comme un échec rapide.
    static let quickFailureThreshold: Duration = .seconds(10)
    static let maxQuickFailures = 2

    private(set) var status: Status = .stopped
    private(set) var nowPlaying: NowPlaying?
    private(set) var artwork: NSImage?
    private(set) var accentColor: NSColor?
    private(set) var sourceApp: SourceApp?

    /// Appelé à chaque changement d'état de lecture, avec l'état précédent.
    @ObservationIgnored var onChange: ((_ previous: NowPlaying?, _ current: NowPlaying?) -> Void)?

    @ObservationIgnored private var source: (any NowPlayingSource)?
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var quickFailures = 0

    func start() {
        guard status == .stopped else { return }
        if let paths = AdapterPaths.bundled() {
            MediaRemoteAdapterSource.terminateOrphans(paths: paths)
            use(MediaRemoteAdapterSource(paths: paths), status: .adapter)
        } else {
            logger.notice("MediaRemoteAdapter.framework absent : repli AppleScript")
            use(AppleScriptSource(), status: .appleScriptFallback(adapterMissing: true))
        }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        source = nil
        status = .stopped
    }

    func togglePlayPause() {
        source?.send(.togglePlayPause)
    }

    func nextTrack() {
        source?.send(.nextTrack)
    }

    func previousTrack() {
        source?.send(.previousTrack)
    }

    func seek(to position: TimeInterval) {
        source?.seek(to: position)
        // Évite que la barre revienne en arrière en attendant la confirmation de la source.
        guard var current = nowPlaying else { return }
        current.elapsedTime = position
        current.timestamp = .now
        apply(current)
    }

    func activateSourceApp() {
        guard let bundleIdentifier = nowPlaying?.sourceBundleIdentifier else { return }
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first?.activate()
    }

    private func use(_ source: any NowPlayingSource, status: Status) {
        streamTask?.cancel()
        self.source = source
        self.status = status
        let startedAt = ContinuousClock.now
        streamTask = Task { [weak self] in
            do {
                for try await update in source.updates() {
                    self?.apply(update)
                }
            } catch {
                self?.sourceDidFail(source, error: error, uptime: ContinuousClock.now - startedAt)
            }
        }
    }

    private func sourceDidFail(_ failed: any NowPlayingSource, error: any Error, uptime: Duration) {
        guard failed === source else { return }
        logger.error("Source média en échec : \(String(describing: error), privacy: .public)")
        apply(nil)
        guard failed.kind == .mediaRemoteAdapter else { return }

        quickFailures = uptime < Self.quickFailureThreshold ? quickFailures + 1 : 0
        if quickFailures >= Self.maxQuickFailures {
            use(AppleScriptSource(), status: .appleScriptFallback(adapterMissing: false))
            return
        }
        streamTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self, let paths = AdapterPaths.bundled() else { return }
            self.use(MediaRemoteAdapterSource(paths: paths), status: .adapter)
        }
    }

    private func apply(_ update: NowPlaying?) {
        let previous = nowPlaying
        guard update != previous else { return }
        nowPlaying = update
        if update?.artworkData != previous?.artworkData {
            let image = update?.artworkData.flatMap(NSImage.init(data:))
            artwork = image
            accentColor = image?.islandAccentColor
        }
        if update?.sourceBundleIdentifier != previous?.sourceBundleIdentifier {
            sourceApp = update?.sourceBundleIdentifier.flatMap(SourceApp.init(bundleIdentifier:))
        }
        onChange?(previous, update)
    }
}

/// Application d'où vient la lecture (Musique, Spotify, Safari…).
struct SourceApp: Equatable {
    let bundleIdentifier: String
    let name: String
    let icon: NSImage

    @MainActor
    init?(bundleIdentifier: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return nil }
        self.bundleIdentifier = bundleIdentifier
        name = (FileManager.default.displayName(atPath: url.path) as NSString).deletingPathExtension
        icon = NSWorkspace.shared.icon(forFile: url.path)
    }
}

extension NSImage {
    /// Couleur moyenne de l'image, éclaircie pour rester lisible sur le fond noir de l'Island.
    var islandAccentColor: NSColor? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return nil }
        let average = NSColor(
            deviceRed: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1
        )
        return NSColor(
            deviceHue: average.hueComponent,
            saturation: min(average.saturationComponent * 1.2, 0.9),
            brightness: max(average.brightnessComponent, 0.75),
            alpha: 1
        )
    }
}
