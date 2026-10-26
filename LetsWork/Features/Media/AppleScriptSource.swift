import AppKit
import os

private let logger = Logger(subsystem: "dev.projects.letswork", category: "media")

/// Repli quand l'adaptateur est indisponible : lit les notifications distribuées de Musique et Spotify
/// (sans autorisation) et pilote ces apps par AppleScript (autorisation Automatisation).
@MainActor
final class AppleScriptSource: NowPlayingSource {
    enum Player: CaseIterable, Sendable {
        case music
        case spotify

        var bundleIdentifier: String {
            switch self {
            case .music: "com.apple.Music"
            case .spotify: "com.spotify.client"
            }
        }

        var applicationName: String {
            switch self {
            case .music: "Music"
            case .spotify: "Spotify"
            }
        }

        var notificationName: Notification.Name {
            switch self {
            case .music: Notification.Name("com.apple.Music.playerInfo")
            case .spotify: Notification.Name("com.spotify.client.PlaybackStateChanged")
            }
        }
    }

    let kind = MediaSourceKind.appleScript

    private var states: [Player: NowPlaying] = [:]
    private var currentPlayer: Player?
    private var observers: [NSObjectProtocol] = []
    private var continuation: AsyncThrowingStream<NowPlaying?, any Error>.Continuation?

    func updates() -> AsyncThrowingStream<NowPlaying?, any Error> {
        let (stream, continuation) = AsyncThrowingStream<NowPlaying?, any Error>.makeStream()
        self.continuation = continuation
        startObserving()
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in
                self?.stopObserving()
            }
        }
        return stream
    }

    func send(_ command: MediaCommand) {
        guard let player = currentPlayer else { return }
        let verb = switch command {
        case .play: "play"
        case .pause: "pause"
        case .togglePlayPause: "playpause"
        case .nextTrack: "next track"
        case .previousTrack: "previous track"
        }
        run("tell application \"\(player.applicationName)\" to \(verb)", on: player)
    }

    func seek(to position: TimeInterval) {
        guard let player = currentPlayer else { return }
        run("tell application \"\(player.applicationName)\" to set player position to \(position)", on: player)
    }

    /// Spotify : « Player State », « Name », « Artist », « Album », « Duration » (ms), « Playback Position » (s).
    /// Musique : les mêmes clés, avec « Total Time » (ms) et sans position.
    nonisolated static func nowPlaying(from userInfo: [AnyHashable: Any]?, player: Player, at date: Date) -> NowPlaying? {
        func text(_ key: String) -> String? {
            (userInfo?[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
        // Entier ou flottant selon l'app : NSNumber accepte les deux.
        func number(_ key: String) -> Double? {
            (userInfo?[key] as? NSNumber)?.doubleValue
        }

        guard let state = text("Player State"), state != "Stopped", let title = text("Name") else { return nil }
        let isPlaying = state == "Playing"
        let durationMillis = number("Duration") ?? number("Total Time")
        return NowPlaying(
            bundleIdentifier: player.bundleIdentifier,
            title: title,
            artist: text("Artist"),
            album: text("Album"),
            duration: durationMillis.map { $0 / 1000 },
            elapsedTime: number("Playback Position"),
            timestamp: date,
            playbackRate: isPlaying ? 1 : 0,
            isPlaying: isPlaying
        )
    }

    private func startObserving() {
        let center = DistributedNotificationCenter.default()
        for player in Player.allCases {
            let observer = center.addObserver(forName: player.notificationName, object: nil, queue: .main) { [weak self] notification in
                let state = Self.nowPlaying(from: notification.userInfo, player: player, at: .now)
                MainActor.assumeIsolated {
                    self?.update(player, with: state)
                }
            }
            observers.append(observer)
        }
    }

    private func stopObserving() {
        let center = DistributedNotificationCenter.default()
        observers.forEach(center.removeObserver)
        observers.removeAll()
        continuation = nil
    }

    private func update(_ player: Player, with state: NowPlaying?) {
        states[player] = state
        if state?.isPlaying == true {
            currentPlayer = player
        } else if currentPlayer == player || currentPlayer == nil {
            currentPlayer = states.first { $0.value.isPlaying }?.key ?? (state != nil ? player : states.keys.first)
        }
        continuation?.yield(currentPlayer.flatMap { states[$0] })
    }

    private func run(_ source: String, on player: Player) {
        // `tell application` lancerait l'app si elle était fermée.
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleIdentifier).isEmpty else { return }
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            logger.error("AppleScript \(player.applicationName, privacy: .public) : \(error, privacy: .public)")
        }
    }
}
