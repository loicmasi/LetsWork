import Foundation
import SQLite3

enum NotificationDatabaseError: LocalizedError, Equatable {
    /// La base est protégée : LetsWork a besoin de l'accès complet au disque.
    case accessDenied
    case notFound
    case sqlite(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied: String(localized: "Accès complet au disque requis.")
        case .notFound: String(localized: "Base des notifications introuvable sur cette version de macOS.")
        case .sqlite(let message): String(localized: "Base des notifications illisible : \(message)")
        }
    }
}

/// Ligne brute de la table `record`, jointe à l'identifiant de l'app.
struct NotificationRecord: Equatable {
    var id: Int64
    var bundleIdentifier: String
    var data: Data
    var deliveredDate: Double?
}

/// Lecture seule de la base du centre de notifications (format privé de macOS, tables `app` et `record`).
@MainActor
final class NotificationDatabase {
    static let systemURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/db2/db")

    let url: URL
    private var handle: OpaquePointer?

    init(url: URL = systemURL) {
        self.url = url
    }

    func open() throws(NotificationDatabaseError) {
        guard handle == nil else { return }
        // Distingue un refus de TCC d'une base absente, ce que SQLite ne fait pas.
        if access(url.path, R_OK) != 0 {
            throw errno == ENOENT ? .notFound : .accessDenied
        }
        var connection: OpaquePointer?
        guard sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            let message = connection.map { String(cString: sqlite3_errmsg($0)) } ?? "ouverture impossible"
            sqlite3_close_v2(connection)
            throw .sqlite(message)
        }
        sqlite3_busy_timeout(connection, 200)
        handle = connection
    }

    func close() {
        sqlite3_close_v2(handle)
        handle = nil
    }

    func latestRecordID() throws(NotificationDatabaseError) -> Int64 {
        var latest: Int64 = 0
        try query("SELECT IFNULL(MAX(rec_id), 0) FROM record") { statement in
            latest = sqlite3_column_int64(statement, 0)
        }
        return latest
    }

    func records(after id: Int64, limit: Int = 50) throws(NotificationDatabaseError) -> [NotificationRecord] {
        let sql = """
            SELECT r.rec_id, a.identifier, r.data, r.delivered_date
            FROM record r JOIN app a ON a.app_id = r.app_id
            WHERE r.rec_id > ? ORDER BY r.rec_id LIMIT ?
            """
        var records: [NotificationRecord] = []
        try query(sql, bind: { statement in
            sqlite3_bind_int64(statement, 1, id)
            sqlite3_bind_int64(statement, 2, Int64(limit))
        }) { statement in
            guard let identifier = sqlite3_column_text(statement, 1) else { return }
            let bytes = sqlite3_column_blob(statement, 2)
            let count = Int(sqlite3_column_bytes(statement, 2))
            records.append(NotificationRecord(
                id: sqlite3_column_int64(statement, 0),
                bundleIdentifier: String(cString: identifier),
                data: bytes.map { Data(bytes: $0, count: count) } ?? Data(),
                deliveredDate: sqlite3_column_type(statement, 3) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 3)
            ))
        }
        return records
    }

    /// Tables et colonnes, pour le journal de diagnostic (jamais de contenu).
    func schemaDescription() -> String {
        var tables: [String] = []
        try? query("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name") { statement in
            if let name = sqlite3_column_text(statement, 0) {
                tables.append(String(cString: name))
            }
        }
        let columns = ["record", "requests", "delivered", "displayed"].map { table in
            var names: [String] = []
            try? query("PRAGMA table_info(\(table))") { statement in
                if let name = sqlite3_column_text(statement, 1) {
                    names.append(String(cString: name))
                }
            }
            return "\(table) : \(names.joined(separator: ","))"
        }
        return "tables : \(tables.joined(separator: ",")) ; \(columns.joined(separator: " ; "))"
    }

    private func query(
        _ sql: String,
        bind: (OpaquePointer?) -> Void = { _ in },
        row: (OpaquePointer?) -> Void
    ) throws(NotificationDatabaseError) {
        guard let handle else { throw .sqlite("base fermée") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw .sqlite(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        bind(statement)
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                row(statement)
            case SQLITE_DONE:
                return
            default:
                throw .sqlite(String(cString: sqlite3_errmsg(handle)))
            }
        }
    }
}
