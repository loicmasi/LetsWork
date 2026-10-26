import Foundation

/// Décode la sortie de `mediaremote-adapter.pl stream --micros` : une ligne JSON par mise à jour,
/// `{"type":"data","diff":false,"payload":{…}}`. Les mises à jour partielles (`diff: true`) sont fusionnées.
struct AdapterStreamDecoder {
    private var payload: [String: Any] = [:]

    private(set) var nowPlaying: NowPlaying?

    /// Applique une ligne ; renvoie `true` si l'état de lecture a changé.
    mutating func apply(line: String) -> Bool {
        guard
            let data = line.data(using: .utf8),
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            object["type"] as? String == "data",
            let update = object["payload"] as? [String: Any]
        else { return false }

        if object["diff"] as? Bool == true {
            for (key, value) in update {
                if value is NSNull {
                    payload.removeValue(forKey: key)
                } else {
                    payload[key] = value
                }
            }
        } else {
            payload = update
        }

        let next = Self.nowPlaying(from: payload)
        guard next != nowPlaying else { return false }
        nowPlaying = next
        return true
    }

    /// Un payload vide ou sans titre signifie que rien n'est en lecture.
    static func nowPlaying(from payload: [String: Any]) -> NowPlaying? {
        func text(_ key: String) -> String? {
            (payload[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
        func seconds(fromMicros key: String) -> TimeInterval? {
            (payload[key] as? Double).map { $0 / 1_000_000 }
        }

        guard let title = text("title") else { return nil }
        let isPlaying = payload["playing"] as? Bool ?? false
        return NowPlaying(
            bundleIdentifier: text("bundleIdentifier"),
            parentApplicationBundleIdentifier: text("parentApplicationBundleIdentifier"),
            title: title,
            artist: text("artist"),
            album: text("album"),
            duration: seconds(fromMicros: "durationMicros"),
            elapsedTime: seconds(fromMicros: "elapsedTimeMicros"),
            timestamp: seconds(fromMicros: "timestampEpochMicros").map(Date.init(timeIntervalSince1970:)),
            playbackRate: payload["playbackRate"] as? Double ?? (isPlaying ? 1 : 0),
            isPlaying: isPlaying,
            artworkData: text("artworkData").flatMap { Data(base64Encoded: $0) }
        )
    }
}
