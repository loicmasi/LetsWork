import SwiftUI

/// Pages de l'Island étendue, dans l'ordre de la barre d'onglets.
enum IslandTab: CaseIterable, Identifiable {
    case home
    case media
    case calendar

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .home: "Accueil"
        case .media: "Multimédia"
        case .calendar: "Calendrier"
        }
    }

    var symbolName: String {
        switch self {
        case .home: "house.fill"
        case .media: "music.note"
        case .calendar: "calendar"
        }
    }
}
