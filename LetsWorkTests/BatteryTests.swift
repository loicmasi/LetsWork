import CoreGraphics
import IOKit.ps
import Testing
@testable import LetsWork

struct BatteryStatusTests {
    /// Description d'une batterie interne telle que la renvoie `IOPSGetPowerSourceDescription`.
    private func description(
        percent: Int = 16,
        onACPower: Bool = false,
        charging: Bool = false,
        minutesToEmpty: Int = 95,
        minutesToFull: Int = 0
    ) -> [String: Any] {
        [
            kIOPSTypeKey: kIOPSInternalBatteryType,
            kIOPSIsPresentKey: true,
            kIOPSCurrentCapacityKey: percent,
            kIOPSMaxCapacityKey: 100,
            kIOPSPowerSourceStateKey: onACPower ? kIOPSACPowerValue : kIOPSBatteryPowerValue,
            kIOPSIsChargingKey: charging,
            kIOPSTimeToEmptyKey: minutesToEmpty,
            kIOPSTimeToFullChargeKey: minutesToFull,
        ]
    }

    @Test func decodesInternalBatteryOnBatteryPower() throws {
        let status = try #require(BatteryStatus(powerSourceDescription: description()))
        #expect(status.percent == 16)
        #expect(!status.isPluggedIn)
        #expect(!status.isCharging)
        #expect(status.minutesToEmpty == 95)
        #expect(status.minutesToFullCharge == nil)
        #expect(status.isLow)
    }

    @Test func decodesChargingOnACPower() throws {
        let status = try #require(BatteryStatus(powerSourceDescription: description(onACPower: true, charging: true, minutesToEmpty: 0, minutesToFull: 160)))
        #expect(status.isPluggedIn)
        #expect(status.isCharging)
        #expect(status.minutesToEmpty == nil)
        #expect(status.minutesToFullCharge == 160)
        #expect(!status.isLow)
    }

    /// -1 : macOS calcule encore l'estimation.
    @Test func ignoresPendingEstimates() throws {
        let status = try #require(BatteryStatus(powerSourceDescription: description(minutesToEmpty: -1)))
        #expect(status.minutesToEmpty == nil)
    }

    @Test func ignoresOtherPowerSources() {
        var ups = description()
        ups[kIOPSTypeKey] = kIOPSUPSType
        #expect(BatteryStatus(powerSourceDescription: ups) == nil)
        var missing = description()
        missing[kIOPSIsPresentKey] = false
        #expect(BatteryStatus(powerSourceDescription: missing) == nil)
    }

    @Test(arguments: [(25, "25 min"), (60, "1 h"), (65, "1 h 05"), (160, "2 h 40")])
    func formatsDurations(minutes: Int, expected: String) {
        #expect(BatteryStatus.duration(minutes: minutes) == expected)
    }

    @Test func summarizesPowerState() {
        let charging = BatteryStatus(level: 0.16, isPluggedIn: true, isCharging: true, minutesToFullCharge: 160)
        #expect(charging.summary == "En charge · pleine dans 2 h 40")
        let onHold = BatteryStatus(level: 0.8, isPluggedIn: true, isCharging: false)
        #expect(onHold.summary == "Sur secteur")
        let charged = BatteryStatus(level: 1, isPluggedIn: true, isCharging: false, isCharged: true)
        #expect(charged.summary == "Chargée")
        let discharging = BatteryStatus(level: 0.6, isPluggedIn: false, isCharging: false, minutesToEmpty: 190)
        #expect(discharging.summary == "Sur batterie · environ 3 h 10 restantes")
    }

    @Test func adviceIncludesRemainingTimeWhenKnown() {
        let known = BatteryStatus(level: 0.1, isPluggedIn: false, isCharging: false, minutesToEmpty: 25)
        #expect(known.lowBatteryAdvice == "Branchez votre Mac sur le secteur · environ 25 min restantes")
        let unknown = BatteryStatus(level: 0.1, isPluggedIn: false, isCharging: false)
        #expect(unknown.lowBatteryAdvice == "Branchez votre Mac sur le secteur")
    }
}

struct LowBatteryWatchTests {
    private func onBattery(_ percent: Int) -> BatteryStatus {
        BatteryStatus(level: Double(percent) / 100, isPluggedIn: false, isCharging: false)
    }

    private func pluggedIn(_ percent: Int) -> BatteryStatus {
        BatteryStatus(level: Double(percent) / 100, isPluggedIn: true, isCharging: true)
    }

    @Test(arguments: [(20, [20, 10, 5]), (10, [10, 5]), (30, [30, 10, 5]), (15, [15, 10, 5])])
    func remindsAtTenAndFivePercent(first: Int, expected: [Int]) {
        #expect(LowBatteryWatch.thresholds(startingAt: first) == expected)
    }

    @Test func unpluggingALowBatteryWarnsOnce() {
        var watch = LowBatteryWatch(firstThreshold: 20)
        #expect(watch.events(from: nil, to: pluggedIn(16)).isEmpty)
        #expect(watch.events(from: pluggedIn(16), to: onBattery(16)) == [.unplugged, .low])
        #expect(watch.events(from: onBattery(16), to: onBattery(15)).isEmpty)
    }

    @Test func remindsAtEachLowerThreshold() {
        var watch = LowBatteryWatch(firstThreshold: 20)
        #expect(watch.events(from: onBattery(22), to: onBattery(20)) == [.low])
        #expect(watch.events(from: onBattery(20), to: onBattery(11)).isEmpty)
        #expect(watch.events(from: onBattery(11), to: onBattery(10)) == [.low])
        #expect(watch.events(from: onBattery(10), to: onBattery(5)) == [.low])
        #expect(watch.events(from: onBattery(5), to: onBattery(4)).isEmpty)
    }

    /// Sortie de veille : de 25 % à 8 % d'un coup, une seule alerte, puis celle de 5 %.
    @Test func dropAcrossSeveralThresholdsWarnsOnce() {
        var watch = LowBatteryWatch(firstThreshold: 20)
        #expect(watch.events(from: onBattery(25), to: onBattery(8)) == [.low])
        #expect(watch.events(from: onBattery(8), to: onBattery(6)).isEmpty)
        #expect(watch.events(from: onBattery(6), to: onBattery(5)) == [.low])
    }

    @Test func pluggingInResetsTheAlerts() {
        var watch = LowBatteryWatch(firstThreshold: 20)
        #expect(watch.events(from: onBattery(21), to: onBattery(19)) == [.low])
        #expect(watch.events(from: onBattery(19), to: pluggedIn(19)) == [.pluggedIn])
        #expect(watch.events(from: pluggedIn(19), to: onBattery(19)) == [.unplugged, .low])
    }

    /// Au lancement de LetsWork, une batterie déjà faible déclenche l'alerte, sans annoncer de débranchement.
    @Test func firstReadingOfALowBatteryWarns() {
        var watch = LowBatteryWatch(firstThreshold: 20)
        #expect(watch.events(from: nil, to: onBattery(12)) == [.low])
    }

    @Test func healthyBatteryNeverWarns() {
        var watch = LowBatteryWatch(firstThreshold: 20)
        #expect(watch.events(from: nil, to: onBattery(80)).isEmpty)
        #expect(watch.events(from: onBattery(80), to: onBattery(21)).isEmpty)
    }
}

@MainActor
struct BatteryIslandTests {
    let island = IslandModel(metrics: IslandMetrics(notch: NotchGeometry(size: CGSize(width: 185, height: 32), hasNotch: true)))

    private func coordinator() -> ActivityCoordinator {
        ActivityCoordinator(
            island: island, media: MediaService(), hud: HUDService(),
            calendar: CalendarService(providers: []), notifications: NotificationService(), battery: BatteryService()
        )
    }

    @Test func pluggingInReplacesTheLowBatteryAlertWithTheChargingIndicator() {
        let coordinator = coordinator()
        coordinator.batteryDidChange(.low, showsChargingIndicator: true)
        #expect(island.state == .lowBattery)
        coordinator.batteryDidChange(.pluggedIn, showsChargingIndicator: true)
        #expect(island.state == .charging)
        coordinator.batteryDidChange(.unplugged, showsChargingIndicator: true)
        #expect(island.state == .closed)
    }

    @Test func chargingIndicatorCanBeTurnedOff() {
        let coordinator = coordinator()
        coordinator.batteryDidChange(.low, showsChargingIndicator: false)
        coordinator.batteryDidChange(.pluggedIn, showsChargingIndicator: false)
        #expect(island.state == .closed)
    }

    @Test func chargingIndicatorDoesNotHideTheMediaForLong() {
        let coordinator = coordinator()
        island.setActivity(.media)
        coordinator.batteryDidChange(.pluggedIn, showsChargingIndicator: true)
        #expect(island.state == .charging)
        island.setCharging(false)
        #expect(island.state == .compact)
    }

    @Test func clickDismissesTheLowBatteryAlert() {
        let coordinator = coordinator()
        coordinator.batteryDidChange(.low, showsChargingIndicator: true)
        island.setLowBattery(false)
        #expect(island.state == .closed)
    }
}
