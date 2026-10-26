import AppKit
import Observation
import os

private let logger = Logger(subsystem: "dev.projects.letswork", category: "notifications")

/// Affiche dans l'Island les notifications des autres apps, lues dans la base du centre de notifications.
/// Les bannières de macOS sont masquées par un mode Concentration que l'utilisateur active (FEATURES.md, F4).
@MainActor
@Observable
final class NotificationService {
    enum Status: Equatable {
        case disabled
        case needsFullDiskAccess
        case unavailable(String)
        case active
    }

    static let enabledKey = "notificationsEnabled"
    /// Sans accès complet au disque, on revérifie régulièrement : l'accès peut être accordé à tout moment.
    static let accessRetryInterval: Duration = .seconds(10)
    /// Filet de sécurité si la surveillance des fichiers manque une écriture.
    static let fallbackPollInterval: Duration = .seconds(10)

    private(set) var status: Status = .disabled

    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            restart()
        }
    }

    /// Appelé pour chaque nouvelle notification d'une autre app.
    @ObservationIgnored var onNotification: ((SystemNotification) -> Void)?

    @ObservationIgnored private let database: NotificationDatabase
    @ObservationIgnored private var watcher: FileChangeWatcher?
    @ObservationIgnored private var lastSeenID: Int64 = 0
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var hasLoggedSchema = false

    init(database: NotificationDatabase = NotificationDatabase()) {
        self.database = database
        isEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    func start() {
        restart()
    }

    func stop() {
        retryTask?.cancel()
        pollTask?.cancel()
        watcher?.stop()
        watcher = nil
        database.close()
    }

    func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }

    func openFocusSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Focus-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    private func restart() {
        stop()
        guard isEnabled else {
            status = .disabled
            return
        }
        do {
            try database.open()
            // Seules les notifications reçues après le lancement sont affichées.
            lastSeenID = try database.latestRecordID()
            if !hasLoggedSchema {
                let schema = database.schemaDescription()
                logger.notice("Base des notifications ouverte, \(schema, privacy: .public)")
                hasLoggedSchema = true
            }
            logger.notice("Lecture active à partir de rec_id \(self.lastSeenID, privacy: .public)")
            let databaseURL = database.url
            let watcher = FileChangeWatcher(urls: [
                databaseURL.deletingLastPathComponent(),
                databaseURL,
                URL(fileURLWithPath: databaseURL.path + "-wal"),
            ]) { [weak self] in
                self?.checkForNewNotifications(trigger: "fichier")
            }
            watcher.start()
            self.watcher = watcher
            pollTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.fallbackPollInterval)
                    guard !Task.isCancelled, let self else { return }
                    if self.watcher?.isWatchingAllFiles == false {
                        self.watcher?.start()
                    }
                    self.checkForNewNotifications(trigger: "secours")
                }
            }
            status = .active
        } catch .accessDenied {
            status = .needsFullDiskAccess
            scheduleRetry()
        } catch {
            status = .unavailable(error.localizedDescription)
            logger.error("Base des notifications : \(error.localizedDescription, privacy: .public)")
        }
    }

    private func scheduleRetry() {
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: Self.accessRetryInterval)
            guard !Task.isCancelled, let self, self.status == .needsFullDiskAccess else { return }
            self.restart()
        }
    }

    private func checkForNewNotifications(trigger: String) {
        let ownBundleIdentifier = Bundle.main.bundleIdentifier
        do {
            let records = try database.records(after: lastSeenID)
            // Diagnostic sans contenu : déclencheur et nombre de nouveaux enregistrements.
            if !records.isEmpty {
                logger.notice("Vérification (\(trigger, privacy: .public)) : \(records.count, privacy: .public) nouvel(s) enregistrement(s)")
            }
            for record in records {
                lastSeenID = max(lastSeenID, record.id)
                guard record.bundleIdentifier != ownBundleIdentifier else { continue }
                if let notification = NotificationRecordDecoder.decode(
                    id: record.id,
                    bundleIdentifier: record.bundleIdentifier,
                    data: record.data,
                    deliveredDate: record.deliveredDate
                ) {
                    onNotification?(notification)
                } else {
                    // Jamais le contenu : seulement les noms des clés, pour adapter le décodage.
                    logger.notice("Notification non décodée (\(record.bundleIdentifier, privacy: .public)), \(NotificationRecordDecoder.keyDescription(of: record.data), privacy: .public)")
                }
            }
        } catch {
            logger.error("Lecture des notifications : \(error.localizedDescription, privacy: .public)")
            restart()
        }
    }
}
