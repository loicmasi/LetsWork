import CoreGraphics
import Testing
@testable import LetsWork

struct MediaKeyPressTests {
    /// `data1` d'un événement système : code de touche << 16 | état << 8 | répétition.
    private func data1(key: Int, down: Bool, repeating: Bool = false) -> Int {
        key << 16 | (down ? 0x0A : 0x0B) << 8 | (repeating ? 1 : 0)
    }

    @Test(arguments: [(0, HUDKey.volumeUp), (1, .volumeDown), (7, .mute), (2, .brightnessUp), (3, .brightnessDown)])
    func decodesSystemKeys(code: Int, key: HUDKey) throws {
        let press = try #require(MediaKeyPress(systemDefinedData1: data1(key: code, down: true), flags: []))
        #expect(press.key == key)
        #expect(press.isDown)
        #expect(!press.isRepeat)
    }

    @Test func decodesKeyUpAndRepeat() throws {
        let up = try #require(MediaKeyPress(systemDefinedData1: data1(key: 0, down: false), flags: []))
        #expect(!up.isDown)
        let repeating = try #require(MediaKeyPress(systemDefinedData1: data1(key: 1, down: true, repeating: true), flags: []))
        #expect(repeating.isRepeat)
    }

    @Test func ignoresOtherSystemKeys() {
        // 16 : lecture/pause, géré par macOS et les lecteurs.
        #expect(MediaKeyPress(systemDefinedData1: data1(key: 16, down: true), flags: []) == nil)
    }

    @Test func modifiersSelectFineStepOrSystemSettings() throws {
        let fine = try #require(MediaKeyPress(systemDefinedData1: data1(key: 0, down: true), flags: [.maskAlternate, .maskShift]))
        #expect(fine.isFineStep)
        #expect(!fine.opensSystemSettings)
        let settings = try #require(MediaKeyPress(systemDefinedData1: data1(key: 0, down: true), flags: [.maskAlternate]))
        #expect(settings.opensSystemSettings)
    }

    @Test func decodesBrightnessFunctionKeys() {
        #expect(HUDKey(functionKeyCode: 144) == .brightnessUp)
        #expect(HUDKey(functionKeyCode: 145) == .brightnessDown)
        #expect(HUDKey(functionKeyCode: 0) == nil)
    }

    /// F1/F2 d'un MX Keys S, réémises par Logi Options+ en F14/F15.
    @Test func decodesF14AndF15AsBrightness() {
        #expect(HUDKey(functionKeyCode: 107) == .brightnessDown)
        #expect(HUDKey(functionKeyCode: 113) == .brightnessUp)
    }
}

struct LevelStepTests {
    @Test func movesOneStepOnTheGrid() {
        #expect(LevelStep.next(from: 0.375, up: true, step: LevelStep.normal) == 0.4375)
        #expect(LevelStep.next(from: 0.375, up: false, step: LevelStep.normal) == 0.3125)
    }

    @Test func snapsOffGridLevelsToTheNextGridPoint() {
        #expect(LevelStep.next(from: 0.33, up: true, step: LevelStep.normal) == 0.375)
        #expect(LevelStep.next(from: 0.33, up: false, step: LevelStep.normal) == 0.3125)
    }

    @Test func absorbsFloatImprecision() {
        #expect(LevelStep.next(from: Double(Float(0.375)) + 0.000_000_3, up: true, step: LevelStep.normal) == 0.4375)
    }

    @Test func clampsBetweenZeroAndOne() {
        #expect(LevelStep.next(from: 1, up: true, step: LevelStep.normal) == 1)
        #expect(LevelStep.next(from: 0.01, up: false, step: LevelStep.normal) == 0)
    }

    @Test func fineStepIsAQuarterOfTheNormalStep() {
        #expect(LevelStep.next(from: 0.5, up: true, step: LevelStep.fine) == 0.5 + 1.0 / 64)
    }
}

struct VolumeLevelTests {
    @Test func muteToggles() {
        let level = VolumeLevel(level: 0.5, isMuted: false)
        #expect(level.applying(.mute, fine: false) == VolumeLevel(level: 0.5, isMuted: true))
        #expect(level.applying(.mute, fine: false).applying(.mute, fine: false) == level)
    }

    @Test func volumeKeysUnmute() {
        let muted = VolumeLevel(level: 0.5, isMuted: true)
        #expect(muted.applying(.volumeUp, fine: false) == VolumeLevel(level: 0.5625, isMuted: false))
        #expect(muted.applying(.volumeDown, fine: false) == VolumeLevel(level: 0.4375, isMuted: false))
    }
}

struct HUDStateTests {
    @Test(arguments: [
        (HUDState(kind: .volume, level: 0.8), "speaker.wave.3.fill"),
        (HUDState(kind: .volume, level: 0.5), "speaker.wave.2.fill"),
        (HUDState(kind: .volume, level: 0.1), "speaker.wave.1.fill"),
        (HUDState(kind: .volume, level: 0), "speaker.slash.fill"),
        (HUDState(kind: .volume, level: 0.8, isMuted: true), "speaker.slash.fill"),
        (HUDState(kind: .volume, level: 0, isAvailable: false), "speaker.slash.fill"),
        (HUDState(kind: .brightness, level: 0.3), "sun.min.fill"),
        (HUDState(kind: .brightness, level: 0.9), "sun.max.fill"),
    ])
    func symbolMatchesLevel(state: HUDState, symbol: String) {
        #expect(state.symbolName == symbol)
    }

    @Test func mutedGaugeIsEmpty() {
        #expect(HUDState(kind: .volume, level: 0.8, isMuted: true).displayedLevel == 0)
    }
}

@MainActor
struct HUDIslandTests {
    let island = IslandModel(metrics: IslandMetrics(notch: NotchGeometry(size: CGSize(width: 185, height: 32), hasNotch: true)))

    @Test func hudInterruptsEveryOtherState() {
        #expect(IslandState.resolve(IslandInputs(isPinned: true, hasActivity: true, isShowingHUD: true)) == .hud)
        island.togglePinned()
        island.setHUD(HUDState(kind: .volume, level: 0.5))
        #expect(island.state == .hud)
        island.setHUD(nil)
        #expect(island.state == .expanded)
    }

    @Test func hudStretchesTheWings() {
        let metrics = island.metrics
        #expect(metrics.size(for: .hud).width == 185 + 2 * IslandMetrics.hudWingWidth)
        #expect(metrics.size(for: .hud).height == 32)
    }

    @Test func coordinatorHidesTheHUDAfterADelay() async throws {
        let coordinator = ActivityCoordinator(island: island, media: MediaService(), hud: HUDService(), calendar: CalendarService(providers: []), notifications: NotificationService(), battery: BatteryService())
        coordinator.showHUD(HUDState(kind: .brightness, level: 0.6))
        #expect(island.state == .hud)
        try await Task.sleep(for: ActivityCoordinator.hudDuration + .milliseconds(300))
        #expect(island.state == .closed)
    }
}
