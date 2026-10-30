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

        /// Renvoie {état} si arrêté, sinon {état, titre, artiste, album, durée en ms, position en s}.
        var stateScript: String {
            let durationMillis = switch self {
            case .music: "(duration of t) * 1000"
            case .spotify: "duration of t"
            }
            return """
                tell application "\(applicationName)"
                    set playerState to player state as string
                    if playerState is "stopped" then return {playerState}
                    set t to current track
                    return {playerState, name of t, artist of t, album of t, (\(durationMillis)) as real, player position as real}
                end tell
                """
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

    /// Résultat de `Player.stateScript`, converti au format des notifications.
    nonisolated static func nowPlaying(fromScriptResult result: NSAppleEventDescriptor, player: Player, at date: Date) -> NowPlaying? {
        guard result.numberOfItems >= 6 else { return nil }
        let userInfo: [AnyHashable: Any] = [
            "Player State": result.atIndex(1)?.stringValue?.capitalized ?? "",
            "Name": result.atIndex(2)?.stringValue ?? "",
            "Artist": result.atIndex(3)?.stringValue ?? "",
            "Album": result.atIndex(4)?.stringValue ?? "",
            "Duration": result.atIndex(5)?.doubleValue ?? 0,
            "Playback Position": result.atIndex(6)?.doubleValue ?? 0,
        ]
        return nowPlaying(from: userInfo, player: player, at: date)
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
        // Les notifications n'arrivent qu'au prochain changement : lire l'état des lecteurs déjà ouverts.
        for player in Player.allCases {
            if let state = currentState(of: player) {
                update(player, with: state)
            }
        }
    }

    /// Ne déclenche jamais la demande d'autorisation : sans accord préalable, on attend les notifications.
    private func currentState(of player: Player) -> NowPlaying? {
        guard
            AppAutomation.isAllowed(player.bundleIdentifier),
            let result = AppAutomation.run(player.stateScript, in: player.bundleIdentifier, name: player.applicationName)
        else { return nil }
        return Self.nowPlaying(fromScriptResult: result, player: player, at: .now)
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
        AppAutomation.run(source, in: player.bundleIdentifier, name: player.applicationName)
    }
}

/// AppleScript vers une app de lecture, sans jamais la lancer : `tell application` ouvrirait une app fermée.
@MainActor
enum AppAutomation {
    static func isRunning(_ bundleIdentifier: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    /// Autorisation Automatisation déjà accordée ; ne déclenche jamais la demande.
    static func isAllowed(_ bundleIdentifier: String) -> Bool {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleIdentifier)
        return AEDeterminePermissionToAutomateTarget(
            target.aeDesc,
            AEEventClass(typeWildCard),
            AEEventID(typeWildCard),
            false
        ) == noErr
    }

    /// Résultat du script, ou `nil` si l'app est fermée ou si le script échoue (erreur journalisée).
    /// Le premier script vers une app déclenche la demande d'autorisation de macOS.
    @discardableResult
    static func run(_ source: String, in bundleIdentifier: String, name: String) -> NSAppleEventDescriptor? {
        guard isRunning(bundleIdentifier) else { return nil }
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            logger.error("AppleScript \(name, privacy: .public) : \(error, privacy: .public)")
            return nil
        }
        return result
    }
}
