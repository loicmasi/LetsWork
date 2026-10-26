import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let media = MediaService()
    private let hud = HUDService()
    private var islandController: IslandWindowController?
    private var coordinator: ActivityCoordinator?
    private lazy var settingsController = SettingsWindowController(media: media, hud: hud)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // L'app sert d'hôte aux tests unitaires : ni Island ni adaptateur, qui survivrait à l'arrêt des tests.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        let controller = IslandWindowController(media: media)
        coordinator = ActivityCoordinator(island: controller.model, media: media, hud: hud)
        controller.show()
        islandController = controller
        media.start()
        hud.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Arrête le processus de l'adaptateur média et rend les touches à macOS.
        media.stop()
        hud.stop()
    }

    func showSettings() {
        settingsController.show()
    }
}
