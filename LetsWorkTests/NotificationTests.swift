import Foundation
import SQLite3
import Testing
@testable import LetsWork

/// Blob `record.data` au format du centre de notifications : une plist binaire avec un dictionnaire `req`.
private func recordData(_ request: [String: String], extra: [String: Any] = ["app": "com.apple.MobileSMS"]) throws -> Data {
    var plist = extra
    plist["req"] = request
    return try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
}

struct NotificationRecordDecoderTests {
    @Test func decodesTitleSubtitleAndBody() throws {
        let data = try recordData(["titl": "Alice", "subt": "Groupe projet", "body": "On se voit à 14 h ?"])
        let notification = try #require(NotificationRecordDecoder.decode(id: 7, bundleIdentifier: "com.apple.MobileSMS", data: data, deliveredDate: 0))
        #expect(notification.title == "Alice")
        #expect(notification.headline(appName: "Messages") == "Alice")
        #expect(notification.detail == "Groupe projet — On se voit à 14 h ?")
        #expect(notification.deliveredAt == Date(timeIntervalSinceReferenceDate: 0))
    }

    @Test func fallsBackToTheAppNameWithoutTitle() throws {
        let data = try recordData(["titl": "  ", "body": "Sauvegarde terminée"])
        let notification = try #require(NotificationRecordDecoder.decode(id: 1, bundleIdentifier: "com.apple.backupd", data: data, deliveredDate: nil))
        #expect(notification.title == nil)
        #expect(notification.headline(appName: "Time Machine") == "Time Machine")
        #expect(notification.detail == "Sauvegarde terminée")
    }

    @Test func ignoresUnknownOrEmptyRecords() throws {
        let noRequest = try PropertyListSerialization.data(fromPropertyList: ["app": "x"], format: .binary, options: 0)
        #expect(NotificationRecordDecoder.decode(id: 1, bundleIdentifier: "x", data: noRequest, deliveredDate: nil) == nil)
        #expect(NotificationRecordDecoder.decode(id: 1, bundleIdentifier: "x", data: try recordData([:]), deliveredDate: nil) == nil)
        #expect(NotificationRecordDecoder.decode(id: 1, bundleIdentifier: "x", data: Data("pas une plist".utf8), deliveredDate: nil) == nil)
    }

    @Test func diagnosticListsKeyNamesOnly() throws {
        let description = NotificationRecordDecoder.keyDescription(of: try recordData(["titl": "Secret", "body": "Code 123456"]))
        #expect(description.contains("titl"))
        #expect(!description.contains("Secret"))
        #expect(!description.contains("123456"))
    }
}

@MainActor
struct NotificationDatabaseTests {
    /// Base temporaire avec les tables `app` et `record` du centre de notifications.
    private func makeDatabase(records: [(appID: Int64, data: Data)]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("notifications-\(UUID().uuidString).db")
        var handle: OpaquePointer?
        #expect(sqlite3_open(url.path, &handle) == SQLITE_OK)
        defer { sqlite3_close(handle) }
        let schema = """
            CREATE TABLE app (app_id INTEGER PRIMARY KEY, identifier VARCHAR);
            CREATE TABLE record (rec_id INTEGER PRIMARY KEY, app_id INTEGER, uuid BLOB, data BLOB,
                request_date REAL, request_last_date REAL, delivered_date REAL, presented Bool, style INTEGER, snooze_fire_date REAL);
            INSERT INTO app VALUES (1, 'com.apple.MobileSMS'), (2, 'com.tinyspeck.slackmacgap');
            """
        #expect(sqlite3_exec(handle, schema, nil, nil, nil) == SQLITE_OK)
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for record in records {
            var statement: OpaquePointer?
            sqlite3_prepare_v2(handle, "INSERT INTO record (app_id, data, delivered_date) VALUES (?, ?, 800000000)", -1, &statement, nil)
            sqlite3_bind_int64(statement, 1, record.appID)
            _ = record.data.withUnsafeBytes { sqlite3_bind_blob(statement, 2, $0.baseAddress, Int32($0.count), transient) }
            #expect(sqlite3_step(statement) == SQLITE_DONE)
            sqlite3_finalize(statement)
        }
        return url
    }

    @Test func readsRecordsAddedAfterAnIdentifier() throws {
        let url = try makeDatabase(records: [
            (1, try recordData(["titl": "Alice", "body": "Salut"])),
            (2, try recordData(["titl": "#général", "body": "Nouveau message"])),
        ])
        defer { try? FileManager.default.removeItem(at: url) }
        let database = NotificationDatabase(url: url)
        try database.open()
        #expect(try database.latestRecordID() == 2)
        let records = try database.records(after: 1)
        #expect(records.map(\.bundleIdentifier) == ["com.tinyspeck.slackmacgap"])
        let notification = NotificationRecordDecoder.decode(
            id: records[0].id, bundleIdentifier: records[0].bundleIdentifier, data: records[0].data, deliveredDate: records[0].deliveredDate
        )
        #expect(notification?.title == "#général")
        #expect(notification?.deliveredAt == Date(timeIntervalSinceReferenceDate: 800_000_000))
        #expect(database.schemaDescription().contains("record : rec_id,app_id"))
    }

    @Test func reportsAMissingDatabase() {
        let database = NotificationDatabase(url: URL(fileURLWithPath: "/tmp/letswork-absente-\(UUID().uuidString).db"))
        #expect(throws: NotificationDatabaseError.notFound) {
            try database.open()
        }
    }
}

@MainActor
struct NotificationIslandTests {
    let island = IslandModel(metrics: IslandMetrics(notch: NotchGeometry(size: CGSize(width: 185, height: 32), hasNotch: true)))

    private func notification(_ id: Int64) -> SystemNotification {
        SystemNotification(id: id, bundleIdentifier: "com.apple.MobileSMS", title: "Message \(id)")
    }

    @Test func notificationsWaitTheirTurn() {
        let coordinator = ActivityCoordinator(
            island: island, media: MediaService(), hud: HUDService(),
            calendar: CalendarService(providers: []), notifications: NotificationService(), battery: BatteryService()
        )
        coordinator.showNotification(notification(1))
        coordinator.showNotification(notification(2))
        #expect(island.state == .notification)
        #expect(island.notification?.id == 1)
        island.onNotificationTap?()
        #expect(island.notification?.id == 2)
        coordinator.dismissNotification()
        #expect(island.notification == nil)
        #expect(island.state == .closed)
    }

    @Test func notificationSitsBetweenTheMeetingAlertAndTheTrackPeek() {
        #expect(IslandState.resolve(IslandInputs(hasActivity: true, isPeeking: true, isShowingNotification: true)) == .notification)
        #expect(IslandState.resolve(IslandInputs(isShowingAlert: true, isShowingNotification: true)) == .alert)
        #expect(IslandState.resolve(IslandInputs(isHovering: true, isShowingNotification: true)) == .expanded)
    }
}
