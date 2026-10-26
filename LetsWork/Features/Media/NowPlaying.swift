import Foundation

/// État de lecture d'une source média, tel que rapporté par l'adaptateur ou le repli AppleScript.
struct NowPlaying: Equatable, Sendable {
    var bundleIdentifier: String?
    /// Application hôte quand la lecture vient d'un sous-processus (ex. moteur web d'un navigateur).
    var parentApplicationBundleIdentifier: String?
    var title: String
    var artist: String?
    var album: String?
    var duration: TimeInterval?
    /// Position de lecture mesurée à `timestamp`.
    var elapsedTime: TimeInterval?
    var timestamp: Date?
    var playbackRate: Double = 1
    var isPlaying = false
    var artworkData: Data?

    /// Application à afficher et à activer : l'hôte quand il est connu.
    var sourceBundleIdentifier: String? {
        parentApplicationBundleIdentifier ?? bundleIdentifier
    }

    var trackIdentity: TrackIdentity {
        TrackIdentity(source: sourceBundleIdentifier, title: title, artist: artist, album: album)
    }

    /// Position interpolée localement, pour une progression fluide sans interroger la source.
    func elapsed(at date: Date) -> TimeInterval? {
        guard var position = elapsedTime else { return nil }
        if isPlaying, let timestamp {
            position += date.timeIntervalSince(timestamp) * playbackRate
        }
        if let duration, duration > 0 {
            position = min(position, duration)
        }
        return max(0, position)
    }
}

/// Ce qui distingue une piste d'une autre, pour détecter un changement de piste.
struct TrackIdentity: Equatable, Sendable {
    var source: String?
    var title: String
    var artist: String?
    var album: String?
}

enum MediaCommand: Sendable {
    case play
    case pause
    case togglePlayPause
    case nextTrack
    case previousTrack

    /// Identifiant MRCommand attendu par `mediaremote-adapter.pl send`.
    var adapterID: Int {
        switch self {
        case .play: 0
        case .pause: 1
        case .togglePlayPause: 2
        case .nextTrack: 4
        case .previousTrack: 5
        }
    }
}

enum MediaSourceKind: Equatable, Sendable {
    case mediaRemoteAdapter
    case appleScript
}

/// Une origine d'informations de lecture. Le flux se termine en erreur quand la source devient inutilisable.
@MainActor
protocol NowPlayingSource: AnyObject {
    var kind: MediaSourceKind { get }
    func updates() -> AsyncThrowingStream<NowPlaying?, any Error>
    func send(_ command: MediaCommand)
    func seek(to position: TimeInterval)
}
