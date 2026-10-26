import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let media = MediaService()
    private let hud = HUDService()
    private let calendar = CalendarService()
    private var islandController: IslandWindowController?
    private var coordinator: ActivityCoordinator?
    private lazy var settingsController = SettingsWindowController(media: media, hud: hud, calendar: calendar)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // L'app sert d'hôte aux tests unitaires : ni Island ni adaptateur, qui survivrait à l'arrêt des tests.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        let controller = IslandWindowController(media: media, calendar: calendar)
        coordinator = ActivityCoordinator(island: controller.model, media: media, hud: hud, calendar: calendar)
        controller.show()
        islandController = controller
        media.start()
        hud.start()
        calendar.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Arrête le processus de l'adaptateur média et rend les touches à macOS.
        media.stop()
        hud.stop()
        calendar.stop()
    }

    func showSettings() {
        settingsController.show()
    }
}
