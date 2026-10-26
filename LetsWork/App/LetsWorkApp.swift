import SwiftUI

@main
struct LetsWorkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("LetsWork", systemImage: "capsule.fill") {
            Button("Réglages…") { appDelegate.showSettings() }
                .keyboardShortcut(",")
            #if DEBUG
            Button("Simuler une activité (état compact)") { appDelegate.toggleSimulatedActivity() }
            #endif
            Divider()
            Button("Quitter LetsWork") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
