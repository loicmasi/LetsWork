import Foundation
import SwiftUI

enum DisplayTarget: String, CaseIterable, Identifiable {
    case notchScreen
    case primaryScreen

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .notchScreen: "Écran avec encoche"
        case .primaryScreen: "Écran principal (barre des menus)"
        }
    }
}

/// Clés et lecture des préférences stockées dans `UserDefaults`.
enum AppSettings {
    static let displayTargetKey = "displayTarget"

    static var displayTarget: DisplayTarget {
        UserDefaults.standard.string(forKey: displayTargetKey).flatMap(DisplayTarget.init(rawValue:)) ?? .notchScreen
    }
}
