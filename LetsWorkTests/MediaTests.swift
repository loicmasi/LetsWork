import Foundation
import Testing
@testable import LetsWork

struct AdapterStreamDecoderTests {
    private static let fullLine = """
        {"type":"data","diff":false,"payload":{"processIdentifier":412,"bundleIdentifier":"com.apple.WebKit.GPU",\
        "parentApplicationBundleIdentifier":"com.apple.Safari","playing":true,"title":"Never Gonna Give You Up",\
        "artist":"Rick Astley","album":"","durationMicros":213000000,"elapsedTimeMicros":42500000,\
        "timestampEpochMicros":1793000000000000,"playbackRate":1,"artworkData":"AQID"}}
        """

    @Test func decodesFullPayload() throws {
        var decoder = AdapterStreamDecoder()
        let changed = decoder.apply(line: Self.fullLine)
        #expect(changed)
        let nowPlaying = try #require(decoder.nowPlaying)
        #expect(nowPlaying.title == "Never Gonna Give You Up")
        #expect(nowPlaying.artist == "Rick Astley")
        #expect(nowPlaying.album == nil)
        #expect(nowPlaying.sourceBundleIdentifier == "com.apple.Safari")
        #expect(nowPlaying.duration == 213)
        #expect(nowPlaying.elapsedTime == 42.5)
        #expect(nowPlaying.timestamp == Date(timeIntervalSince1970: 1_793_000_000))
        #expect(nowPlaying.isPlaying)
        #expect(nowPlaying.artworkData == Data([1, 2, 3]))
    }

    @Test func emptyPayloadMeansNothingPlaying() {
        var decoder = AdapterStreamDecoder()
        _ = decoder.apply(line: Self.fullLine)
        let changed = decoder.apply(line: #"{"type":"data","diff":false,"payload":{}}"#)
        #expect(changed)
        #expect(decoder.nowPlaying == nil)
    }

    @Test func mergesDiffs() {
        var decoder = AdapterStreamDecoder()
        _ = decoder.apply(line: Self.fullLine)
        let changed = decoder.apply(line: #"{"type":"data","diff":true,"payload":{"playing":false,"artist":null}}"#)
        #expect(changed)
        #expect(decoder.nowPlaying?.isPlaying == false)
        #expect(decoder.nowPlaying?.artist == nil)
        #expect(decoder.nowPlaying?.title == "Never Gonna Give You Up")
    }

    @Test func ignoresUnchangedAndInvalidLines() {
        var decoder = AdapterStreamDecoder()
        _ = decoder.apply(line: Self.fullLine)
        let repeated = decoder.apply(line: Self.fullLine)
        let invalid = decoder.apply(line: "perl: warning")
        #expect(!repeated)
        #expect(!invalid)
        #expect(decoder.nowPlaying != nil)
    }
}

struct NowPlayingTests {
    private let start = Date(timeIntervalSince1970: 1_000)

    @Test func interpolatesWhilePlaying() {
        let nowPlaying = NowPlaying(title: "A", duration: 100, elapsedTime: 10, timestamp: start, playbackRate: 1, isPlaying: true)
        #expect(nowPlaying.elapsed(at: start.addingTimeInterval(5)) == 15)
        #expect(nowPlaying.elapsed(at: start.addingTimeInterval(500)) == 100)
    }

    @Test func staysStillWhilePaused() {
        let nowPlaying = NowPlaying(title: "A", duration: 100, elapsedTime: 10, timestamp: start, playbackRate: 0, isPlaying: false)
        #expect(nowPlaying.elapsed(at: start.addingTimeInterval(5)) == 10)
    }

    @Test(arguments: [(0.0, "0:00"), (187.4, "3:07"), (3765, "1:02:45")])
    func formatsPlaybackTime(seconds: Double, expected: String) {
        #expect(PlaybackTime.format(seconds) == expected)
    }
}

struct MediaTransitionTests {
    private let song = NowPlaying(bundleIdentifier: "com.spotify.client", title: "A", artist: "X", isPlaying: true)

    @Test func firstPlaybackIsANewTrack() {
        #expect(MediaTransition(from: nil, to: song) == .playing(isNewTrack: true))
    }

    @Test func resumingTheSameTrackDoesNotPeek() {
        var paused = song
        paused.isPlaying = false
        #expect(MediaTransition(from: paused, to: song) == .playing(isNewTrack: false))
    }

    @Test func changingTrackPeeks() {
        var next = song
        next.title = "B"
        #expect(MediaTransition(from: song, to: next) == .playing(isNewTrack: true))
    }

    @Test func pausingOrStoppingStops() {
        var paused = song
        paused.isPlaying = false
        #expect(MediaTransition(from: song, to: paused) == .stopped)
        #expect(MediaTransition(from: song, to: nil) == .stopped)
    }
}

struct AppleScriptSourceTests {
    private let now = Date(timeIntervalSince1970: 2_000)

    @Test func parsesSpotifyNotification() throws {
        let userInfo: [AnyHashable: Any] = [
            "Player State": "Playing", "Name": "Song", "Artist": "Band", "Album": "Record",
            "Duration": 200_000, "Playback Position": 12.5,
        ]
        let nowPlaying = try #require(AppleScriptSource.nowPlaying(from: userInfo, player: .spotify, at: now))
        #expect(nowPlaying.bundleIdentifier == "com.spotify.client")
        #expect(nowPlaying.duration == 200)
        #expect(nowPlaying.elapsedTime == 12.5)
        #expect(nowPlaying.isPlaying)
    }

    @Test func parsesMusicNotificationWithoutPosition() throws {
        let userInfo: [AnyHashable: Any] = ["Player State": "Paused", "Name": "Song", "Total Time": 180_000]
        let nowPlaying = try #require(AppleScriptSource.nowPlaying(from: userInfo, player: .music, at: now))
        #expect(nowPlaying.duration == 180)
        #expect(nowPlaying.elapsedTime == nil)
        #expect(!nowPlaying.isPlaying)
    }

    @Test func stoppedPlayerHasNothingPlaying() {
        let userInfo: [AnyHashable: Any] = ["Player State": "Stopped", "Name": "Song"]
        #expect(AppleScriptSource.nowPlaying(from: userInfo, player: .music, at: now) == nil)
    }
}

@MainActor
struct ActivityCoordinatorTests {
    let island = IslandModel(metrics: IslandMetrics(notch: NotchGeometry(size: CGSize(width: 185, height: 32), hasNotch: true)))
    let media = MediaService()

    @Test func newTrackShowsMediaAndPeeks() {
        let coordinator = ActivityCoordinator(island: island, media: media)
        let song = NowPlaying(title: "A", isPlaying: true)
        coordinator.mediaDidChange(from: nil, to: song)
        #expect(island.activity == .media)
        #expect(island.state == .peek)
    }

    @Test func pauseKeepsCompactDuringGracePeriod() {
        let coordinator = ActivityCoordinator(island: island, media: media)
        var song = NowPlaying(title: "A", isPlaying: true)
        coordinator.mediaDidChange(from: nil, to: song)
        song.isPlaying = false
        coordinator.mediaDidChange(from: NowPlaying(title: "A", isPlaying: true), to: song)
        #expect(island.activity == .media)
    }
}
