import AppKit

/// Mode aléatoire, répétition et titre en cours, tels que les rapporte l'AppleScript de Spotify.
struct SpotifyPlayback: Equatable, Sendable {
    var isShuffling: Bool
    var isRepeating: Bool
    /// `spotify:track:…`, `spotify:episode:…`, `spotify:ad:…` pendant une publicité ; `nil` à l'arrêt.
    var trackURI: String?

    /// Titre ou épisode qu'on peut ajouter à la bibliothèque : ni une publicité ni un fichier local.
    var likableURI: String? {
        guard let trackURI, trackURI.hasPrefix("spotify:track:") || trackURI.hasPrefix("spotify:episode:") else { return nil }
        return trackURI
    }
}

/// Pilotage de Spotify par AppleScript : le « Now Playing » de macOS ne rapporte ni l'aléatoire ni la répétition
/// de Spotify, ni l'identifiant du titre qu'attend l'API Web.
@MainActor
enum SpotifyPlayer {
    static let bundleIdentifier = "com.spotify.client"
    private static let name = "Spotify"

    /// Renvoie {aléatoire, répétition} à l'arrêt, sinon {aléatoire, répétition, URI du titre}.
    private static let stateScript = """
        tell application "Spotify"
            set playbackState to {shuffling, repeating}
            if player state is not stopped then set end of playbackState to id of current track
            return playbackState
        end tell
        """

    /// Lit l'état de Spotify ; sans `prompting`, renonce plutôt que de demander l'autorisation Automatisation.
    static func playback(prompting: Bool) -> SpotifyPlayback? {
        guard prompting || AppAutomation.isAllowed(bundleIdentifier) else { return nil }
        return AppAutomation.run(stateScript, in: bundleIdentifier, name: name).flatMap(playback(fromScriptResult:))
    }

    @discardableResult
    static func setShuffling(_ isOn: Bool) -> Bool {
        AppAutomation.run("tell application \"Spotify\" to set shuffling to \(isOn)", in: bundleIdentifier, name: name) != nil
    }

    @discardableResult
    static func setRepeating(_ isOn: Bool) -> Bool {
        AppAutomation.run("tell application \"Spotify\" to set repeating to \(isOn)", in: bundleIdentifier, name: name) != nil
    }

    nonisolated static func playback(fromScriptResult result: NSAppleEventDescriptor) -> SpotifyPlayback? {
        guard result.numberOfItems >= 2, let shuffling = result.atIndex(1), let repeating = result.atIndex(2) else { return nil }
        return SpotifyPlayback(
            isShuffling: shuffling.booleanValue,
            isRepeating: repeating.booleanValue,
            trackURI: result.atIndex(3)?.stringValue.flatMap { $0.isEmpty ? nil : $0 }
        )
    }
}
