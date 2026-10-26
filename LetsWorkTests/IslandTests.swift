import CoreGraphics
import Testing
@testable import LetsWork

struct NotchGeometryTests {
    @Test func notchOfMacBookPro16() {
        let geometry = NotchGeometry.compute(
            screenWidth: 1728,
            safeAreaTop: 32,
            topLeftAreaWidth: 771.5,
            topRightAreaWidth: 771.5,
            menuBarHeight: 32
        )
        #expect(geometry == NotchGeometry(size: CGSize(width: 185, height: 32), hasNotch: true))
    }

    @Test func screenWithoutNotchGetsSimulatedNotch() {
        let geometry = NotchGeometry.compute(
            screenWidth: 1920,
            safeAreaTop: 0,
            topLeftAreaWidth: nil,
            topRightAreaWidth: nil,
            menuBarHeight: 0
        )
        #expect(!geometry.hasNotch)
        #expect(geometry.size == CGSize(width: NotchGeometry.simulatedWidth, height: NotchGeometry.minimumSimulatedHeight))
    }
}

struct IslandStateTests {
    @Test(arguments: [
        (IslandInputs(), IslandState.closed),
        (IslandInputs(hasActivity: true), .compact),
        (IslandInputs(isHovering: true), .expanded),
        (IslandInputs(isPinned: true), .expanded),
        (IslandInputs(isHovering: true, hasActivity: true), .expanded),
        (IslandInputs(hasActivity: true, isPeeking: true), .peek),
        (IslandInputs(isPeeking: true), .closed),
        (IslandInputs(isPinned: true, hasActivity: true, isPeeking: true), .expanded),
    ])
    func resolve(inputs: IslandInputs, expected: IslandState) {
        #expect(IslandState.resolve(inputs) == expected)
    }
}

struct IslandMetricsTests {
    let metrics = IslandMetrics(notch: NotchGeometry(size: CGSize(width: 185, height: 32), hasNotch: true))
    let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)

    @Test func closedIslandMatchesNotch() {
        #expect(metrics.size(for: .closed) == CGSize(width: 185, height: 32))
        #expect(metrics.topCornerRadius(for: .closed) == 0)
    }

    @Test func compactAddsWingsOnBothSides() {
        #expect(metrics.size(for: .compact).width == 185 + 2 * IslandMetrics.compactWingWidth)
    }

    @Test func peekAddsATitleLineBelowTheNotch() {
        let size = metrics.size(for: .peek)
        #expect(size.height == 32 + IslandMetrics.peekExtraHeight)
        #expect(size.width >= metrics.size(for: .compact).width)
    }

    @Test func expandedIslandFitsInCanvas() {
        let size = metrics.size(for: .expanded)
        let flare = metrics.topCornerRadius(for: .expanded)
        #expect(size.width + 2 * flare <= IslandMetrics.canvasSize.width)
        #expect(size.height <= IslandMetrics.canvasSize.height)
    }

    @Test func hitZoneIsAnchoredAtTopCenter() {
        let zone = metrics.hitZone(for: .closed, in: screen)
        #expect(zone.contains(CGPoint(x: 864, y: 1110)))
        #expect(!zone.contains(CGPoint(x: 864, y: 1000)))
        #expect(!zone.contains(CGPoint(x: 100, y: 1110)))
    }
}

@MainActor
struct IslandModelTests {
    let model = IslandModel(metrics: IslandMetrics(notch: NotchGeometry(size: CGSize(width: 185, height: 32), hasNotch: true)))

    @Test func clickPinsAndClickOutsideUnpins() {
        model.togglePinned()
        #expect(model.state == .expanded)
        model.dismissPin()
        #expect(model.state == .closed)
    }

    @Test func activityShowsCompactIsland() {
        model.setActivity(.media)
        #expect(model.state == .compact)
        model.setPeeking(true)
        #expect(model.state == .peek)
        model.setPeeking(false)
        model.setActivity(nil)
        #expect(model.state == .closed)
    }

    @Test func tabsStartOnHomeInBarOrder() {
        #expect(IslandTab.allCases == [.home, .media])
        #expect(model.selectedTab == .home)
    }

    @Test func selectedTabSurvivesClosingAndReopening() {
        model.togglePinned()
        model.selectTab(.media)
        model.dismissPin()
        #expect(model.state == .closed)
        model.togglePinned()
        #expect(model.selectedTab == .media)
    }

    @Test func hoverExpandsAfterDelay() async throws {
        model.setHovering(true)
        #expect(model.state == .closed)
        try await Task.sleep(for: IslandModel.hoverInDelay * 3)
        #expect(model.state == .expanded)
    }
}

@MainActor
struct HomeViewTests {
    @Test func summarizesPlayingTrack() {
        let nowPlaying = NowPlaying(title: "Club", artist: "Lomepal", isPlaying: true)
        #expect(HomeView.mediaSummary(of: nowPlaying) == "En lecture : Club — Lomepal")
    }

    @Test func summarizesPausedTrackWithoutArtist() {
        let nowPlaying = NowPlaying(title: "Vidéo YouTube", isPlaying: false)
        #expect(HomeView.mediaSummary(of: nowPlaying) == "En pause : Vidéo YouTube")
    }
}
