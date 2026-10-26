import SwiftUI

@main
struct LetsWorkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("LetsWork", systemImage: "capsule.fill") {
            Button("Nouvel événement…") { appDelegate.showNewEvent() }
                .keyboardShortcut("n")
            Button("Réglages…") { appDelegate.showSettings() }
                .keyboardShortcut(",")
            Divider()
            Button("Quitter LetsWork") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
