import Foundation
import Security

/// Garde le jeton de rafraîchissement du compte Spotify entre deux lancements.
@MainActor
protocol SpotifyTokenStore: AnyObject {
    func readRefreshToken() -> String?
    func writeRefreshToken(_ token: String)
    func deleteRefreshToken()
}

/// Bibliothèque « Titres likés » du compte connecté, par l'API Web de Spotify. Le jeton d'accès reste en mémoire
/// et se renouvelle à partir du jeton de rafraîchissement, conservé dans le trousseau.
@MainActor
final class SpotifyWebAPI {
    enum APIError: Error, Equatable {
        /// Aucun compte connecté.
        case notConnected
        /// Jeton de rafraîchissement refusé (révoqué, expiré, autre Client ID) : il faut se reconnecter.
        case sessionExpired
        case http(status: Int)
        case invalidResponse
    }

    private struct AccessToken {
        var value: String
        var expiresAt: Date

        init(_ token: SpotifyToken) {
            value = token.accessToken
            expiresAt = .now.addingTimeInterval(TimeInterval(token.expiresIn))
        }
    }

    private static let baseURL = URL(string: "https://api.spotify.com/v1/")!
    /// Marge avant l'expiration du jeton d'accès (une heure) au-delà de laquelle on le renouvelle.
    private static let expiryMargin: TimeInterval = 60

    var clientID: String
    private let session: URLSession
    private let tokens: any SpotifyTokenStore
    private var accessToken: AccessToken?
    private var refreshTask: Task<String, any Error>?

    init(clientID: String, session: URLSession = .shared, tokens: any SpotifyTokenStore = KeychainSpotifyTokenStore()) {
        self.clientID = clientID
        self.session = session
        self.tokens = tokens
    }

    /// Échange le code reçu par la redirection contre les jetons du compte.
    func connect(authorization: SpotifyAuthorization, code: String) async throws {
        let token = try await requestToken(authorization.tokenRequest(code: code))
        guard let refreshToken = token.refreshToken else { throw APIError.invalidResponse }
        clientID = authorization.clientID
        tokens.writeRefreshToken(refreshToken)
        accessToken = AccessToken(token)
    }

    func disconnect() {
        refreshTask?.cancel()
        refreshTask = nil
        accessToken = nil
        tokens.deleteRefreshToken()
    }

    func isSaved(_ uri: String) async throws -> Bool {
        let data = try await send(Self.libraryRequest(method: "GET", path: "me/library/contains", uri: uri))
        guard let saved = (try? JSONDecoder().decode([Bool].self, from: data))?.first else { throw APIError.invalidResponse }
        return saved
    }

    func save(_ uri: String) async throws {
        _ = try await send(Self.libraryRequest(method: "PUT", path: "me/library", uri: uri))
    }

    func remove(_ uri: String) async throws {
        _ = try await send(Self.libraryRequest(method: "DELETE", path: "me/library", uri: uri))
    }

    static func libraryRequest(method: String, path: String, uri: String) -> URLRequest {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "uris", value: uri)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        return request
    }

    /// Un 401 signale un jeton d'accès révoqué avant son expiration : on le renouvelle, une seule fois.
    private func send(_ request: URLRequest, isRetry: Bool = false) async throws -> Data {
        var authorized = request
        authorized.setValue("Bearer \(try await validAccessToken())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: authorized)
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw APIError.invalidResponse }
        switch status {
        case 200..<300:
            return data
        case 401 where !isRetry:
            accessToken = nil
            return try await send(request, isRetry: true)
        default:
            throw APIError.http(status: status)
        }
    }

    private func validAccessToken() async throws -> String {
        if let accessToken, accessToken.expiresAt.timeIntervalSinceNow > Self.expiryMargin {
            return accessToken.value
        }
        if let refreshTask {
            return try await refreshTask.value
        }
        guard let refreshToken = tokens.readRefreshToken() else { throw APIError.notConnected }
        let task = Task {
            defer { refreshTask = nil }
            let token = try await requestToken(SpotifyAuthorization.refreshRequest(clientID: clientID, refreshToken: refreshToken))
            if let rotated = token.refreshToken {
                tokens.writeRefreshToken(rotated)
            }
            accessToken = AccessToken(token)
            return token.accessToken
        }
        refreshTask = task
        return try await task.value
    }

    private func requestToken(_ request: URLRequest) async throws -> SpotifyToken {
        let (data, response) = try await session.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw APIError.invalidResponse }
        guard (200..<300).contains(status) else {
            let error = try? JSONDecoder().decode(TokenError.self, from: data)
            throw error?.error == "invalid_grant" ? APIError.sessionExpired : APIError.http(status: status)
        }
        guard let token = try? JSONDecoder().decode(SpotifyToken.self, from: data) else { throw APIError.invalidResponse }
        return token
    }

    private struct TokenError: Decodable {
        var error: String
    }
}

/// Jeton de rafraîchissement dans le trousseau de session.
final class KeychainSpotifyTokenStore: SpotifyTokenStore {
    private let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "dev.projects.letswork.spotify",
        kSecAttrAccount as String: "refresh-token",
    ]

    func readRefreshToken() -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func writeRefreshToken(_ token: String) {
        let data = Data(token.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard status == errSecItemNotFound else { return }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }

    func deleteRefreshToken() {
        SecItemDelete(query as CFDictionary)
    }
}
