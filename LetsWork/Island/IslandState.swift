import Foundation

enum IslandState: Equatable {
    case closed
    case compact
    /// Compact enrichi (titre de la piste) affiché brièvement après un changement de piste.
    case peek
    /// Alerte de réunion imminente, temporaire.
    case alert
    /// Notification d'une autre app, temporaire, au style de l'aperçu de piste.
    case notification
    /// Alerte de batterie faible : il faut brancher le Mac. Temporaire.
    case lowBattery
    /// Indicateur temporaire de charge, au branchement du chargeur.
    case charging
    /// Indicateur temporaire de volume ou de luminosité.
    case hud
    case expanded
}

/// Activité de fond affichée par l'Island en compact.
enum IslandActivity: Equatable {
    case media
    case calendar
}

/// Ce qui détermine l'état de l'Island à un instant donné.
struct IslandInputs: Equatable {
    var isHovering = false
    var isPinned = false
    var hasActivity = false
    var isPeeking = false
    var isShowingHUD = false
    var isShowingAlert = false
    var isShowingNotification = false
    var isShowingLowBattery = false
    var isShowingCharging = false
}

extension IslandState {
    /// Le HUD interrompt tout ; puis le survol ou l'épinglage, la batterie faible, l'alerte de réunion,
    /// la notification, l'indicateur de charge, l'aperçu de piste et enfin l'activité de fond
    /// (FEATURES.md, F0 › Arbitrage).
    static func resolve(_ inputs: IslandInputs) -> IslandState {
        if inputs.isShowingHUD { return .hud }
        if inputs.isPinned || inputs.isHovering { return .expanded }
        if inputs.isShowingLowBattery { return .lowBattery }
        if inputs.isShowingAlert { return .alert }
        if inputs.isShowingNotification { return .notification }
        if inputs.isShowingCharging { return .charging }
        guard inputs.hasActivity else { return .closed }
        return inputs.isPeeking ? .peek : .compact
    }
}
