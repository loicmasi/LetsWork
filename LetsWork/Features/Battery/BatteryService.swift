import Foundation
import IOKit.ps
import Observation
import notify
import os

private let logger = Logger(subsystem: "dev.projects.letswork", category: "battery")

/// Batterie interne : niveau affiché dans l'Island, indicateur au branchement du chargeur et alerte quand il faut
/// brancher le Mac (FEATURES.md, F6).
@MainActor
@Observable
final class BatteryService {
    static let thresholdChoices = [10, 15, 20, 30]

    private enum Key {
        static let showsChargingIndicator = "batteryShowsChargingIndicator"
        static let warnsWhenLow = "batteryWarnsWhenLow"
        static let lowThreshold = "batteryLowThreshold"
    }

    /// `nil` sur un Mac sans batterie.
    private(set) var status: BatteryStatus?

    var showsChargingIndicator: Bool {
        didSet {
            UserDefaults.standard.set(showsChargingIndicator, forKey: Key.showsChargingIndicator)
        }
    }

    var warnsWhenLow: Bool {
        didSet {
            UserDefaults.standard.set(warnsWhenLow, forKey: Key.warnsWhenLow)
        }
    }

    /// Première alerte, en pourcentage ; des rappels suivent à 10 % et 5 %.
    var lowThreshold: Int {
        didSet {
            UserDefaults.standard.set(lowThreshold, forKey: Key.lowThreshold)
            watch.thresholds = LowBatteryWatch.thresholds(startingAt: lowThreshold)
        }
    }

    /// Branchement, débranchement et alerte de batterie faible (si elle est activée).
    @ObservationIgnored var onEvent: ((BatteryEvent) -> Void)?

    @ObservationIgnored private var watch: LowBatteryWatch
    @ObservationIgnored private var notifyToken: Int32?

    init() {
        let defaults = UserDefaults.standard
        showsChargingIndicator = defaults.object(forKey: Key.showsChargingIndicator) as? Bool ?? true
        warnsWhenLow = defaults.object(forKey: Key.warnsWhenLow) as? Bool ?? true
        let threshold = defaults.object(forKey: Key.lowThreshold) as? Int ?? 20
        lowThreshold = threshold
        watch = LowBatteryWatch(firstThreshold: threshold)
    }

    func start() {
        guard notifyToken == nil else { return }
        // macOS publie chaque changement des sources d'alimentation (branchement, pourcentage, estimation) :
        // aucune interrogation périodique n'est nécessaire.
        var token: Int32 = 0
        let result = notify_register_dispatch(kIOPSNotifyAnyPowerSource, &token, .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
        if result == NOTIFY_STATUS_OK {
            notifyToken = token
        } else {
            logger.error("Abonnement aux changements d'alimentation impossible (\(result, privacy: .public))")
        }
        refresh()
    }

    func stop() {
        if let notifyToken {
            notify_cancel(notifyToken)
        }
        notifyToken = nil
    }

    private func refresh() {
        let current = Self.internalBattery()
        let previous = status
        guard current != previous else { return }
        status = current
        guard let current else { return }
        for event in watch.events(from: previous, to: current) {
            switch event {
            case .pluggedIn:
                logger.notice("Chargeur branché (\(current.percent, privacy: .public) %)")
            case .unplugged:
                logger.notice("Chargeur débranché (\(current.percent, privacy: .public) %)")
            case .low:
                logger.notice("Batterie faible (\(current.percent, privacy: .public) %)")
                guard warnsWhenLow else { continue }
            }
            onEvent?(event)
        }
    }

    /// Batterie interne parmi les sources d'alimentation, ou `nil` sur un Mac sans batterie.
    private static func internalBattery() -> BatteryStatus? {
        guard
            let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        return sources.lazy
            .compactMap { IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any] }
            .compactMap(BatteryStatus.init(powerSourceDescription:))
            .first
    }
}
