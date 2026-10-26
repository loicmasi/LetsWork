import Foundation

/// Notification d'une autre app, lue dans la base du centre de notifications de macOS.
struct SystemNotification: Identifiable, Equatable, Sendable {
    /// `rec_id` de la base : croissant, il sert aussi à repérer les nouvelles notifications.
    var id: Int64
    var bundleIdentifier: String
    var title: String?
    var subtitle: String?
    var body: String?
    var deliveredAt: Date?

    /// Première ligne de la pop-up : le titre, sinon le sous-titre, sinon le nom de l'app.
    func headline(appName: String) -> String {
        title ?? subtitle ?? appName
    }

    /// Seconde ligne : sous-titre (s'il n'a pas servi de titre) et corps.
    var detail: String? {
        let parts = [title == nil ? nil : subtitle, body].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " — ")
    }
}

/// Décode la colonne `record.data` : une plist dont le dictionnaire `req` contient `titl`, `subt` et `body`.
enum NotificationRecordDecoder {
    static func decode(id: Int64, bundleIdentifier: String, data: Data, deliveredDate: Double?) -> SystemNotification? {
        guard let request = request(in: data) else { return nil }
        func text(_ key: String) -> String? {
            (request[key] as? String)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .flatMap { $0.isEmpty ? nil : $0 }
        }
        let notification = SystemNotification(
            id: id,
            bundleIdentifier: bundleIdentifier,
            title: text("titl"),
            subtitle: text("subt"),
            body: text("body"),
            // `delivered_date` est en secondes depuis le 1er janvier 2001 (temps Cocoa).
            deliveredAt: deliveredDate.map(Date.init(timeIntervalSinceReferenceDate:))
        )
        guard notification.title != nil || notification.subtitle != nil || notification.body != nil else { return nil }
        return notification
    }

    /// Noms des clés du blob, sans aucune valeur, pour diagnostiquer un format inattendu.
    static func keyDescription(of data: Data) -> String {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return "plist illisible (\(data.count) octets)"
        }
        let requestKeys = (plist["req"] as? [String: Any]).map { $0.keys.sorted().joined(separator: ",") } ?? "absent"
        return "clés : \(plist.keys.sorted().joined(separator: ",")) ; req : \(requestKeys)"
    }

    private static func request(in data: Data) -> [String: Any]? {
        let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        return plist?["req"] as? [String: Any]
    }
}
