import AppKit
import SwiftUI

/// Fenêtre de réglages gérée à la main : la scène `Settings` de SwiftUI s'ouvre mal
/// depuis une app sans icône dans le Dock (`LSUIElement`).
@MainActor
final class SettingsWindowController {
    private let media: MediaService
    private let hud: HUDService
    private let calendar: CalendarService
    private var window: NSWindow?

    init(media: MediaService, hud: HUDService, calendar: CalendarService) {
        self.media = media
        self.hud = hud
        self.calendar = calendar
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(media: media, hud: hud, calendar: calendar)))
        window.title = String(localized: "Réglages LetsWork")
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
