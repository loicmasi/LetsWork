import CryptoKit
import Foundation

/// Une connexion au compte Spotify par le flux « Authorization Code with PKCE », sans secret client dans l'app :
/// le navigateur ouvre la page de Spotify, qui renvoie un code sur `redirectURI`, échangé contre des jetons.
struct SpotifyAuthorization: Sendable {
    /// À déclarer à l'identique dans l'app créée sur developer.spotify.com. Spotify n'accepte en HTTP
    /// que l'adresse de bouclage écrite en IP, jamais `localhost`.
    static let redirectPort: UInt16 = 43219
    static let redirectPath = "/callback"
    static let redirectURI = "http://127.0.0.1:43219/callback"
    /// Savoir si le titre est dans « Titres likés », l'y ajouter et l'en retirer.
    static let scopes = "user-library-read user-library-modify"

    private static let authorizeURL = URL(string: "https://accounts.spotify.com/authorize")!
    static let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!

    enum CallbackError: Error, Equatable {
        /// Refus sur la page de Spotify (`access_denied`).
        case denied(String)
        /// Réponse à une autre demande de connexion que celle en cours.
        case stateMismatch
        case missingCode
    }

    let clientID: String
    let codeVerifier: String
    let state: String

    init(clientID: String, codeVerifier: String = Self.randomToken(), state: String = Self.randomToken()) {
        self.clientID = clientID
        self.codeVerifier = codeVerifier
        self.state = state
    }

    var codeChallenge: String {
        Self.challenge(for: codeVerifier)
    }

    /// Page de connexion de Spotify, à ouvrir dans le navigateur.
    var authorizationURL: URL {
        var components = URLComponents(url: Self.authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url!
    }

    /// Code d'autorisation transmis par la redirection, après vérification qu'elle répond à cette demande.
    func code(fromCallback items: [URLQueryItem]) throws -> String {
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }
        guard value("state") == state else { throw CallbackError.stateMismatch }
        if let error = value("error") { throw CallbackError.denied(error) }
        guard let code = value("code"), !code.isEmpty else { throw CallbackError.missingCode }
        return code
    }

    func tokenRequest(code: String) -> URLRequest {
        Self.tokenRequest([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
            "client_id": clientID,
            "code_verifier": codeVerifier,
        ])
    }

    static func refreshRequest(clientID: String, refreshToken: String) -> URLRequest {
        tokenRequest([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ])
    }

    /// `code_challenge` de la RFC 7636 : SHA-256 du vérificateur, en base64url sans remplissage.
    static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
    }

    /// 32 octets aléatoires en base64url : 43 caractères, longueur minimale d'un vérificateur PKCE.
    static func randomToken() -> String {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }).base64URLEncoded
    }

    private static func tokenRequest(_ parameters: [String: String]) -> URLRequest {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(formEncoded(parameters).utf8)
        return request
    }

    static func formEncoded(_ parameters: [String: String]) -> String {
        // Caractères non réservés de la RFC 3986, en ASCII (`alphanumerics` inclurait les lettres accentuées).
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return parameters.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }
            .joined(separator: "&")
    }
}

/// Réponse de `accounts.spotify.com/api/token`.
struct SpotifyToken: Decodable, Equatable, Sendable {
    var accessToken: String
    var expiresIn: Int
    /// Renouvelé à chaque rafraîchissement : le nouveau remplace l'ancien.
    var refreshToken: String?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }
}

extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
