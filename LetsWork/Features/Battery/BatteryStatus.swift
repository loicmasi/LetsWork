import Foundation
import IOKit.ps

/// État de la batterie interne, lu dans les sources d'alimentation d'IOKit.
struct BatteryStatus: Equatable, Sendable {
    /// Sous ce niveau, sur batterie, la jauge passe au rouge (comme sur l'iPhone).
    static let lowPercent = 20

    /// Entre 0 et 1.
    var level: Double
    /// Branché sur le secteur, que la batterie charge ou non.
    var isPluggedIn: Bool
    var isCharging: Bool
    /// Charge terminée.
    var isCharged = false
    /// Minutes avant la décharge complète ; `nil` tant que macOS calcule l'estimation.
    var minutesToEmpty: Int?
    /// Minutes avant la fin de la charge ; `nil` tant que macOS calcule l'estimation.
    var minutesToFullCharge: Int?

    var percent: Int {
        Int((level * 100).rounded())
    }

    var isLow: Bool {
        !isPluggedIn && percent <= Self.lowPercent
    }

    /// « En charge », « Chargée » ou « Sur secteur » (charge suspendue par macOS, par exemple la recharge optimisée).
    var powerTitle: String {
        if isCharged || percent >= 100 {
            return String(localized: "Chargée")
        }
        return isCharging ? String(localized: "En charge") : String(localized: "Sur secteur")
    }

    /// « En charge · pleine dans 2 h 40 », « Sur batterie · environ 3 h 10 restantes »…
    var summary: String {
        guard isPluggedIn else {
            return minutesToEmpty.map { String(localized: "Sur batterie · environ \(Self.duration(minutes: $0)) restantes") }
                ?? String(localized: "Sur batterie")
        }
        if isCharging, let minutes = minutesToFullCharge {
            return String(localized: "En charge · pleine dans \(Self.duration(minutes: minutes))")
        }
        return powerTitle
    }

    /// Conseil de l'alerte de batterie faible, avec l'autonomie restante si macOS l'a estimée.
    var lowBatteryAdvice: String {
        guard let minutes = minutesToEmpty else { return String(localized: "Branchez votre Mac sur le secteur") }
        return String(localized: "Branchez votre Mac sur le secteur · environ \(Self.duration(minutes: minutes)) restantes")
    }

    /// « 25 min », « 2 h », « 2 h 05 ».
    static func duration(minutes: Int) -> String {
        guard minutes >= 60 else { return String(localized: "\(minutes) min") }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0
            ? String(localized: "\(hours) h")
            : String(localized: "\(hours) h \(String(format: "%02d", rest))")
    }
}

extension BatteryStatus {
    /// Description d'une source d'alimentation (`IOPSGetPowerSourceDescription`) ; `nil` si ce n'est pas la batterie interne.
    init?(powerSourceDescription description: [String: Any]) {
        guard
            description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
            description[kIOPSIsPresentKey] as? Bool ?? true,
            let current = description[kIOPSCurrentCapacityKey] as? Int,
            let capacity = description[kIOPSMaxCapacityKey] as? Int,
            capacity > 0
        else { return nil }
        // Les durées valent -1 pendant le calcul de l'estimation, et 0 quand elles ne s'appliquent pas.
        func minutes(_ key: String) -> Int? {
            (description[key] as? Int).flatMap { $0 > 0 ? $0 : nil }
        }
        self.init(
            level: min(1, max(0, Double(current) / Double(capacity))),
            isPluggedIn: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
            isCharging: description[kIOPSIsChargingKey] as? Bool ?? false,
            isCharged: description[kIOPSIsChargedKey] as? Bool ?? false,
            minutesToEmpty: minutes(kIOPSTimeToEmptyKey),
            minutesToFullCharge: minutes(kIOPSTimeToFullChargeKey)
        )
    }
}

/// Ce que l'Island signale après une mise à jour de la batterie.
enum BatteryEvent: Equatable, Sendable {
    case pluggedIn
    case unplugged
    /// Sur batterie, la charge vient de passer sous un seuil d'alerte.
    case low
}

/// Suit les seuils d'alerte de batterie faible déjà signalés depuis le dernier branchement.
struct LowBatteryWatch {
    /// Seuils du plus haut au plus bas : celui choisi, puis des rappels à 10 % et 5 %.
    static func thresholds(startingAt first: Int) -> [Int] {
        Set([first, 10, 5].filter { $0 <= first }).sorted(by: >)
    }

    var thresholds: [Int]
    /// Plus bas seuil déjà signalé pendant la décharge en cours.
    private(set) var lowestAlerted: Int?

    init(firstThreshold: Int) {
        thresholds = Self.thresholds(startingAt: firstThreshold)
    }

    /// `previous` vaut `nil` à la première lecture : on ne signale alors pas de branchement, mais une batterie
    /// déjà faible déclenche l'alerte.
    mutating func events(from previous: BatteryStatus?, to current: BatteryStatus) -> [BatteryEvent] {
        var events: [BatteryEvent] = []
        if let previous, previous.isPluggedIn != current.isPluggedIn {
            events.append(current.isPluggedIn ? .pluggedIn : .unplugged)
        }
        guard !current.isPluggedIn else {
            lowestAlerted = nil
            return events
        }
        // Une chute de plusieurs seuils d'un coup (sortie de veille) ne donne qu'une alerte.
        if let crossed = thresholds.filter({ current.percent <= $0 }).min(), crossed < lowestAlerted ?? .max {
            lowestAlerted = crossed
            events.append(.low)
        }
        return events
    }
}
