import Foundation

enum IslandState: Equatable {
    case closed
    case compact
    case expanded
}

/// Ce qui détermine l'état de l'Island à un instant donné.
struct IslandInputs: Equatable {
    var isHovering = false
    var isPinned = false
    var hasActivity = false
}

extension IslandState {
    /// Survol ou épinglage priment sur l'activité de fond (FEATURES.md, F0).
    static func resolve(_ inputs: IslandInputs) -> IslandState {
        if inputs.isPinned || inputs.isHovering { return .expanded }
        if inputs.hasActivity { return .compact }
        return .closed
    }
}
