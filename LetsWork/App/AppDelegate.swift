import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let media = MediaService()
    private var islandController: IslandWindowController?
    private var coordinator: ActivityCoordinator?
    private lazy var settingsController = SettingsWindowController(media: media)

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = IslandWindowController(media: media)
        coordinator = ActivityCoordinator(island: controller.model, media: media)
        controller.show()
        islandController = controller
        media.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Arrête le processus de l'adaptateur média.
        media.stop()
    }

    func showSettings() {
        settingsController.show()
    }
}
