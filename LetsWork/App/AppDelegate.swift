import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let media = MediaService()
    private let hud = HUDService()
    private let calendar = CalendarService()
    private let notifications = NotificationService()
    private let battery = BatteryService()
    private var islandController: IslandWindowController?
    private var coordinator: ActivityCoordinator?
    private lazy var settingsController = SettingsWindowController(
        media: media,
        hud: hud,
        calendar: calendar,
        notifications: notifications,
        battery: battery
    )
    private lazy var eventEditor = EventEditorWindowController(calendar: calendar)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // L'app sert d'hôte aux tests unitaires : ni Island ni adaptateur, qui survivrait à l'arrêt des tests.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        let controller = IslandWindowController(media: media, calendar: calendar, battery: battery)
        coordinator = ActivityCoordinator(
            island: controller.model,
            media: media,
            hud: hud,
            calendar: calendar,
            notifications: notifications,
            battery: battery
        )
        controller.show()
        islandController = controller
        media.start()
        hud.start()
        calendar.onCreateEventRequest = { [weak self] day in
            self?.eventEditor.show(day: day)
        }
        calendar.start()
        notifications.start()
        battery.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Arrête le processus de l'adaptateur média et rend les touches à macOS.
        media.stop()
        hud.stop()
        calendar.stop()
        notifications.stop()
        battery.stop()
    }

    func showSettings() {
        settingsController.show()
    }

    func showNewEvent() {
        eventEditor.show(day: .now)
    }
}
