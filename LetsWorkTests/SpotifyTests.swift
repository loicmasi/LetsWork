import AppKit
import Network
import Testing
@testable import LetsWork

struct SpotifyAuthorizationTests {
    private let authorization = SpotifyAuthorization(clientID: "client", codeVerifier: "verifier", state: "state-42")

    /// Exemple de l'annexe B de la RFC 7636.
    @Test func challengeFollowsRFC7636() {
        let challenge = SpotifyAuthorization.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        #expect(challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func randomTokensAreURLSafeAndUnique() {
        let token = SpotifyAuthorization.randomToken()
        #expect(token.count == 43)
        #expect(token.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        #expect(token != SpotifyAuthorization.randomToken())
    }

    @Test func authorizationURLAsksForTheLibraryScopes() throws {
        let components = try #require(URLComponents(url: authorization.authorizationURL, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        #expect(components.host == "accounts.spotify.com")
        #expect(items["client_id"] == "client")
        #expect(items["redirect_uri"] == "http://127.0.0.1:43219/callback")
        #expect(items["code_challenge_method"] == "S256")
        #expect(items["code_challenge"] == SpotifyAuthorization.challenge(for: "verifier"))
        #expect(items["scope"] == "user-library-read user-library-modify")
        #expect(items["state"] == "state-42")
    }

    @Test func acceptsOnlyTheRedirectOfThisRequest() throws {
        let code = try authorization.code(fromCallback: [URLQueryItem(name: "code", value: "abc"), URLQueryItem(name: "state", value: "state-42")])
        #expect(code == "abc")
        #expect(throws: SpotifyAuthorization.CallbackError.stateMismatch) {
            try authorization.code(fromCallback: [URLQueryItem(name: "code", value: "abc"), URLQueryItem(name: "state", value: "other")])
        }
        #expect(throws: SpotifyAuthorization.CallbackError.denied("access_denied")) {
            try authorization.code(fromCallback: [URLQueryItem(name: "error", value: "access_denied"), URLQueryItem(name: "state", value: "state-42")])
        }
        #expect(throws: SpotifyAuthorization.CallbackError.missingCode) {
            try authorization.code(fromCallback: [URLQueryItem(name: "state", value: "state-42")])
        }
    }

    @Test func tokenRequestIsFormEncoded() throws {
        let request = authorization.tokenRequest(code: "abc")
        let body = try #require(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        #expect(request.httpMethod == "POST")
        #expect(request.url == SpotifyAuthorization.tokenURL)
        #expect(body == "client_id=client&code=abc&code_verifier=verifier&grant_type=authorization_code&redirect_uri=http%3A%2F%2F127.0.0.1%3A43219%2Fcallback")
    }

    @Test func decodesTokenResponse() throws {
        let json = #"{"access_token":"A","token_type":"Bearer","scope":"user-library-read","expires_in":3600,"refresh_token":"R"}"#
        let token = try JSONDecoder().decode(SpotifyToken.self, from: Data(json.utf8))
        #expect(token == SpotifyToken(accessToken: "A", expiresIn: 3600, refreshToken: "R"))
    }
}

@MainActor
struct LoopbackRedirectListenerTests {
    @Test func readsTheCallbackQuery() {
        let request = "GET /callback?code=abc&state=xyz HTTP/1.1\r\nHost: 127.0.0.1:43219\r\n\r\n"
        let query = LoopbackRedirectListener.callbackQuery(inRequest: request, path: "/callback")
        #expect(query == [URLQueryItem(name: "code", value: "abc"), URLQueryItem(name: "state", value: "xyz")])
    }

    @Test func ignoresOtherRequests() {
        #expect(LoopbackRedirectListener.callbackQuery(inRequest: "GET /favicon.ico HTTP/1.1\r\n\r\n", path: "/callback") == nil)
        #expect(LoopbackRedirectListener.callbackQuery(inRequest: "POST /callback?code=abc HTTP/1.1\r\n\r\n", path: "/callback") == nil)
        #expect(LoopbackRedirectListener.callbackQuery(inRequest: "garbage", path: "/callback") == nil)
    }

    @Test func receivesTheRedirectOnTheLoopbackPort() async throws {
        let listener = LoopbackRedirectListener()
        var client: NWConnection?
        let query = try await listener.waitForCallback(port: 43298, path: "/callback", timeout: .seconds(5)) {
            let connection = NWConnection(host: .ipv4(.loopback), port: 43298, using: .tcp)
            client = connection
            connection.start(queue: .main)
            let request = "GET /callback?code=abc&state=xyz HTTP/1.1\r\nHost: 127.0.0.1:43298\r\n\r\n"
            connection.send(content: Data(request.utf8), completion: .idempotent)
        }
        client?.cancel()
        #expect(query == [URLQueryItem(name: "code", value: "abc"), URLQueryItem(name: "state", value: "xyz")])
    }

    @Test func givesUpAfterTheTimeout() async {
        let listener = LoopbackRedirectListener()
        await #expect(throws: LoopbackRedirectListener.ListenerError.self) {
            try await listener.waitForCallback(port: 43297, path: "/callback", timeout: .milliseconds(100)) {}
        }
    }
}

@MainActor
struct SpotifyPlayerTests {
    private func scriptResult(_ items: [NSAppleEventDescriptor]) -> NSAppleEventDescriptor {
        let list = NSAppleEventDescriptor.list()
        for item in items {
            list.insert(item, at: list.numberOfItems + 1)
        }
        return list
    }

    @Test func parsesPlaybackState() throws {
        let result = scriptResult([
            NSAppleEventDescriptor(boolean: true),
            NSAppleEventDescriptor(boolean: false),
            NSAppleEventDescriptor(string: "spotify:track:6rqhFgbbKwnb9MLmUQDhG6"),
        ])
        let playback = try #require(SpotifyPlayer.playback(fromScriptResult: result))
        #expect(playback.isShuffling)
        #expect(!playback.isRepeating)
        #expect(playback.likableURI == "spotify:track:6rqhFgbbKwnb9MLmUQDhG6")
    }

    @Test func stoppedSpotifyHasNoTrack() throws {
        let result = scriptResult([NSAppleEventDescriptor(boolean: false), NSAppleEventDescriptor(boolean: true)])
        let playback = try #require(SpotifyPlayer.playback(fromScriptResult: result))
        #expect(playback.isRepeating)
        #expect(playback.trackURI == nil)
    }

    @Test(arguments: [
        ("spotify:track:abc", true),
        ("spotify:episode:abc", true),
        ("spotify:ad:abc", false),
        ("spotify:local:Artist:Album:Title:180", false),
    ])
    func onlyTracksAndEpisodesCanBeLiked(uri: String, likable: Bool) {
        let playback = SpotifyPlayback(isShuffling: false, isRepeating: false, trackURI: uri)
        #expect((playback.likableURI != nil) == likable)
    }
}

/// Jeton de rafraîchissement en mémoire, pour ne pas toucher au trousseau.
@MainActor
final class MemoryTokenStore: SpotifyTokenStore {
    var refreshToken: String?

    init(_ refreshToken: String? = nil) {
        self.refreshToken = refreshToken
    }

    func readRefreshToken() -> String? { refreshToken }
    func writeRefreshToken(_ token: String) { refreshToken = token }
    func deleteRefreshToken() { refreshToken = nil }
}

/// Réponses préparées pour l'API Web, servies dans l'ordre.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responses: [(status: Int, body: String)] = []
    nonisolated(unsafe) static var requests: [URLRequest] = []

    static func session(responding responses: [(status: Int, body: String)]) -> URLSession {
        self.responses = responses
        requests = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        let (status, body) = Self.responses.isEmpty ? (500, "") : Self.responses.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
@Suite(.serialized)
struct SpotifyWebAPITests {
    private static func token(_ access: String, refresh: String) -> (status: Int, body: String) {
        (200, #"{"access_token":"\#(access)","token_type":"Bearer","expires_in":3600,"refresh_token":"\#(refresh)"}"#)
    }

    @Test func refreshesTheAccessTokenThenAsksTheLibrary() async throws {
        let tokens = MemoryTokenStore("R1")
        let session = StubURLProtocol.session(responding: [Self.token("A1", refresh: "R2"), (200, "[true]")])
        let api = SpotifyWebAPI(clientID: "client", session: session, tokens: tokens)

        let saved = try await api.isSaved("spotify:track:abc")

        #expect(saved)
        #expect(tokens.refreshToken == "R2")
        let requests = StubURLProtocol.requests
        #expect(requests.map(\.url?.host) == ["accounts.spotify.com", "api.spotify.com"])
        #expect(requests[1].url?.absoluteString == "https://api.spotify.com/v1/me/library/contains?uris=spotify:track:abc")
        #expect(requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer A1")
    }

    @Test func reusesTheAccessTokenUntilItExpires() async throws {
        let session = StubURLProtocol.session(responding: [Self.token("A1", refresh: "R2"), (200, ""), (200, "")])
        let api = SpotifyWebAPI(clientID: "client", session: session, tokens: MemoryTokenStore("R1"))

        try await api.save("spotify:track:abc")
        try await api.remove("spotify:track:abc")

        #expect(StubURLProtocol.requests.map(\.httpMethod) == ["POST", "PUT", "DELETE"])
    }

    @Test func renewsARevokedAccessTokenOnce() async throws {
        let session = StubURLProtocol.session(responding: [
            Self.token("A1", refresh: "R2"), (401, ""), Self.token("A2", refresh: "R3"), (200, ""),
        ])
        let api = SpotifyWebAPI(clientID: "client", session: session, tokens: MemoryTokenStore("R1"))

        try await api.save("spotify:track:abc")

        #expect(StubURLProtocol.requests.count == 4)
        #expect(StubURLProtocol.requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer A2")
    }

    @Test func revokedRefreshTokenExpiresTheSession() async {
        let session = StubURLProtocol.session(responding: [(400, #"{"error":"invalid_grant","error_description":"Refresh token revoked"}"#)])
        let api = SpotifyWebAPI(clientID: "client", session: session, tokens: MemoryTokenStore("R1"))

        await #expect(throws: SpotifyWebAPI.APIError.sessionExpired) {
            try await api.isSaved("spotify:track:abc")
        }
    }

    @Test func withoutAccountNothingIsSent() async {
        let session = StubURLProtocol.session(responding: [])
        let api = SpotifyWebAPI(clientID: "client", session: session, tokens: MemoryTokenStore())

        await #expect(throws: SpotifyWebAPI.APIError.notConnected) {
            try await api.save("spotify:track:abc")
        }
        #expect(StubURLProtocol.requests.isEmpty)
    }
}

@MainActor
struct SpotifyServiceTests {
    /// Réglages isolés, supprimés à la fin du test.
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let name = "dev.projects.letswork.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        body(defaults)
        defaults.removePersistentDomain(forName: name)
    }

    @Test func likeWithoutAccountOpensTheSettings() {
        withDefaults { defaults in
            let spotify = SpotifyService(defaults: defaults, tokens: MemoryTokenStore())
            var openedSettings = false
            spotify.onSettingsRequest = { openedSettings = true }
            spotify.toggleLike()
            #expect(openedSettings)
            #expect(spotify.like == nil)
        }
    }

    @Test func connectionSurvivesARelaunchUntilDisconnected() {
        withDefaults { defaults in
            defaults.set(true, forKey: "spotifyIsConnected")
            let tokens = MemoryTokenStore("R1")
            let spotify = SpotifyService(defaults: defaults, tokens: tokens)
            #expect(spotify.account == .connected)

            spotify.disconnect()

            #expect(spotify.account == .disconnected)
            #expect(tokens.refreshToken == nil)
            #expect(SpotifyService(defaults: defaults, tokens: tokens).account == .disconnected)
        }
    }

    @Test func otherSourcesForgetTheSpotifyState() {
        withDefaults { defaults in
            let spotify = SpotifyService(defaults: defaults, tokens: MemoryTokenStore())
            spotify.trackDidChange(isSpotify: false)
            #expect(spotify.playback == nil)
            #expect(spotify.isLiked == nil)
        }
    }

    @Test func explainsAccessErrors() {
        #expect(SpotifyService.message(for: SpotifyWebAPI.APIError.http(status: 403)).contains("Premium"))
        #expect(SpotifyService.message(for: SpotifyWebAPI.APIError.sessionExpired).contains("reconnectez-vous"))
        #expect(SpotifyService.message(for: SpotifyAuthorization.CallbackError.denied("access_denied")).contains("refusée"))
    }
}
