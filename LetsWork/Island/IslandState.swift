import Foundation

enum IslandState: Equatable {
    case closed
    case compact
    /// Compact enrichi (titre de la piste) affiché brièvement après un changement de piste.
    case peek
    case expanded
}

/// Activité de fond affichée par l'Island en compact.
enum IslandActivity: Equatable {
    case media
}

/// Ce qui détermine l'état de l'Island à un instant donné.
struct IslandInputs: Equatable {
    var isHovering = false
    var isPinned = false
    var hasActivity = false
    var isPeeking = false
}

extension IslandState {
    /// Survol ou épinglage priment sur l'activité de fond (FEATURES.md, F0).
    static func resolve(_ inputs: IslandInputs) -> IslandState {
        if inputs.isPinned || inputs.isHovering { return .expanded }
        guard inputs.hasActivity else { return .closed }
        return inputs.isPeeking ? .peek : .compact
    }
}
