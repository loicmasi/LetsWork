import SwiftUI

/// Pages de l'Island étendue, dans l'ordre de la barre d'onglets.
enum IslandTab: CaseIterable, Identifiable {
    case home
    case media

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .home: "Accueil"
        case .media: "Multimédia"
        }
    }

    var symbolName: String {
        switch self {
        case .home: "house.fill"
        case .media: "music.note"
        }
    }
}
