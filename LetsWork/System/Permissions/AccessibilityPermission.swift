import AppKit
import ApplicationServices

/// Autorisation Accessibilité, requise pour intercepter les touches (FEATURES.md, F2).
enum AccessibilityPermission {
    static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Affiche la demande système si l'autorisation n'est pas encore accordée.
    static func request() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Notification distribuée publiée quand la liste des apps autorisées change.
    static let didChangeNotification = Notification.Name("com.apple.accessibility.api")
}
