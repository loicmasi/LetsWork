import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var islandController: IslandWindowController?
    private let settingsController = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = IslandWindowController()
        controller.show()
        islandController = controller
    }

    func showSettings() {
        settingsController.show()
    }

    /// Force l'état compact pour travailler l'Island avant l'arrivée des vraies activités (M1+).
    func toggleSimulatedActivity() {
        guard let model = islandController?.model else { return }
        model.setHasActivity(!model.hasActivity)
    }
}
