import AppKit
import Network
import Observation
import os

private let logger = Logger(subsystem: "dev.projects.letswork", category: "spotify")

/// Commandes propres à Spotify dans l'onglet Multimédia : aléatoire et répétition par AppleScript,
/// « J'aime » par l'API Web une fois le compte connecté dans les réglages.
@MainActor
@Observable
final class SpotifyService {
    enum Account: Equatable {
        case disconnected
        /// Page de connexion ouverte dans le navigateur, en attente de la redirection.
        case connecting
        case connected
    }

    /// Le « J'aime » connu pour un titre.
    struct Like: Equatable {
        var uri: String
        var isLiked: Bool
    }

    private enum Key {
        static let clientID = "spotifyClientID"
        static let isConnected = "spotifyIsConnected"
    }

    /// La page de connexion de Spotify reste ouverte au plus ce délai.
    static let connectionTimeout: Duration = .seconds(300)
    /// Laisse à Spotify le temps de passer au titre suivant avant de le lire par AppleScript.
    private static let trackChangeDelay: Duration = .milliseconds(300)
    /// Spotify applique l'aléatoire et la répétition un instant après la commande.
    private static let confirmationDelay: Duration = .milliseconds(500)

    /// Identifiant de l'app créée sur developer.spotify.com.
    var clientID: String {
        didSet {
            defaults.set(clientID, forKey: Key.clientID)
        }
    }

    private(set) var account: Account
    /// Dernière erreur de connexion ou de « J'aime », affichée dans les réglages.
    private(set) var lastError: String?
    /// `nil` tant que l'état n'est pas connu : Spotify fermé ou autorisation Automatisation pas encore accordée.
    private(set) var playback: SpotifyPlayback?
    private(set) var like: Like?

    /// `nil` tant que l'API Web n'a pas répondu pour le titre en cours.
    var isLiked: Bool? {
        guard let uri = playback?.likableURI, like?.uri == uri else { return nil }
        return like?.isLiked
    }

    /// Ouvre les réglages, pour connecter le compte quand on clique sur « J'aime ».
    @ObservationIgnored var onSettingsRequest: (() -> Void)?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let api: SpotifyWebAPI
    @ObservationIgnored private let redirectListener = LoopbackRedirectListener()
    @ObservationIgnored private var readTask: Task<Void, Never>?
    @ObservationIgnored private var likeCheckTask: Task<Void, Never>?
    @ObservationIgnored private var likeSaveTask: Task<Void, Never>?
    @ObservationIgnored private var connectTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard, tokens: (any SpotifyTokenStore)? = nil) {
        self.defaults = defaults
        let clientID = defaults.string(forKey: Key.clientID) ?? ""
        self.clientID = clientID
        api = SpotifyWebAPI(clientID: clientID, tokens: tokens ?? KeychainSpotifyTokenStore())
        account = defaults.bool(forKey: Key.isConnected) ? .connected : .disconnected
    }

    // MARK: - Lecture

    /// Appelé par `MediaService` à chaque changement de titre ou de source.
    func trackDidChange(isSpotify: Bool) {
        readTask?.cancel()
        guard isSpotify else {
            playback = nil
            return
        }
        readTask = Task { [weak self] in
            try? await Task.sleep(for: Self.trackChangeDelay)
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    /// Relit l'état de Spotify et le « J'aime » du titre, pour suivre les changements faits dans Spotify.
    /// Ne demande jamais l'autorisation Automatisation : c'est un clic sur un bouton qui la déclenche.
    func refresh() {
        guard let current = SpotifyPlayer.playback(prompting: false) else { return }
        playback = current
        checkLike()
    }

    func toggleShuffle() {
        guard let current = playback ?? SpotifyPlayer.playback(prompting: true) else { return }
        guard SpotifyPlayer.setShuffling(!current.isShuffling) else { return }
        playback = current
        playback?.isShuffling.toggle()
        confirmPlayback()
    }

    func toggleRepeat() {
        guard let current = playback ?? SpotifyPlayer.playback(prompting: true) else { return }
        guard SpotifyPlayer.setRepeating(!current.isRepeating) else { return }
        playback = current
        playback?.isRepeating.toggle()
        confirmPlayback()
    }

    /// Relit l'état réellement appliqué par Spotify, sans recharger le « J'aime ».
    private func confirmPlayback() {
        readTask?.cancel()
        readTask = Task { [weak self] in
            try? await Task.sleep(for: Self.confirmationDelay)
            guard !Task.isCancelled, let current = SpotifyPlayer.playback(prompting: false) else { return }
            self?.playback = current
        }
    }

    // MARK: - J'aime

    /// Ajoute le titre aux « Titres likés » ou l'en retire ; sans compte connecté, ouvre les réglages.
    func toggleLike() {
        guard account == .connected else {
            onSettingsRequest?()
            return
        }
        guard likeSaveTask == nil else { return }
        if playback == nil {
            playback = SpotifyPlayer.playback(prompting: true)
        }
        guard let uri = playback?.likableURI else { return }
        // État inconnu : on ajoute, ce qui ne change rien à un titre déjà liké.
        let previous = like
        let liked = !(isLiked ?? false)
        like = Like(uri: uri, isLiked: liked)
        likeCheckTask?.cancel()
        likeSaveTask = Task { [weak self] in
            guard let self else { return }
            defer { likeSaveTask = nil }
            do {
                if liked {
                    try await api.save(uri)
                } else {
                    try await api.remove(uri)
                }
                lastError = nil
                logger.notice("\(liked ? "Titre ajouté aux" : "Titre retiré des", privacy: .public) Titres likés")
            } catch {
                if like?.uri == uri {
                    like = previous
                }
                apiDidFail(error)
            }
        }
    }

    private func checkLike() {
        guard account == .connected, likeSaveTask == nil, let uri = playback?.likableURI else { return }
        likeCheckTask?.cancel()
        likeCheckTask = Task { [weak self] in
            guard let self else { return }
            do {
                let liked = try await api.isSaved(uri)
                guard !Task.isCancelled else { return }
                like = Like(uri: uri, isLiked: liked)
            } catch is CancellationError {
            } catch let error as URLError where error.code == .cancelled {
            } catch {
                apiDidFail(error)
            }
        }
    }

    private func apiDidFail(_ error: any Error) {
        logger.error("API Web Spotify : \(String(describing: error), privacy: .public)")
        lastError = Self.message(for: error)
        switch error as? SpotifyWebAPI.APIError {
        case .notConnected, .sessionExpired:
            signOut()
        default:
            break
        }
    }

    // MARK: - Compte

    /// Ouvre la page de connexion de Spotify et attend sa redirection vers LetsWork.
    func connect() {
        let clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty, account == .disconnected else { return }
        let authorization = SpotifyAuthorization(clientID: clientID)
        account = .connecting
        lastError = nil
        connectTask = Task { [weak self] in
            guard let self else { return }
            do {
                let callback = try await redirectListener.waitForCallback(
                    port: SpotifyAuthorization.redirectPort,
                    path: SpotifyAuthorization.redirectPath,
                    timeout: Self.connectionTimeout
                ) {
                    NSWorkspace.shared.open(authorization.authorizationURL)
                }
                let code = try authorization.code(fromCallback: callback)
                try await api.connect(authorization: authorization, code: code)
                defaults.set(true, forKey: Key.isConnected)
                account = .connected
                logger.notice("Compte Spotify connecté")
                refresh()
            } catch {
                account = .disconnected
                if !(error is CancellationError) {
                    logger.error("Connexion Spotify : \(String(describing: error), privacy: .public)")
                    lastError = Self.message(for: error)
                }
            }
        }
    }

    func cancelConnection() {
        connectTask?.cancel()
    }

    func disconnect() {
        lastError = nil
        signOut()
        logger.notice("Compte Spotify déconnecté")
    }

    private func signOut() {
        likeCheckTask?.cancel()
        api.disconnect()
        defaults.set(false, forKey: Key.isConnected)
        account = .disconnected
        like = nil
    }

    static func message(for error: any Error) -> String {
        switch error {
        case SpotifyAuthorization.CallbackError.denied:
            return String(localized: "Connexion refusée sur la page de Spotify.")
        case is SpotifyAuthorization.CallbackError:
            return String(localized: "Réponse de Spotify inattendue : réessayez.")
        case LoopbackRedirectListener.ListenerError.timedOut:
            return String(localized: "Connexion abandonnée : Spotify n'a pas répondu. Vérifiez le Client ID et l'URI de redirection.")
        case NWError.posix(.EADDRINUSE):
            return String(localized: "Le port \(String(SpotifyAuthorization.redirectPort)) est déjà utilisé par une autre app : fermez-la, puis réessayez.")
        case SpotifyWebAPI.APIError.notConnected, SpotifyWebAPI.APIError.sessionExpired:
            return String(localized: "La connexion à Spotify a expiré : reconnectez-vous.")
        case SpotifyWebAPI.APIError.http(status: 400):
            return String(localized: "Spotify a refusé la connexion : vérifiez le Client ID et l'URI de redirection.")
        case SpotifyWebAPI.APIError.http(status: 403):
            return String(localized: "Spotify a refusé l'accès (403) : le propriétaire de l'app doit être abonné à Premium, et votre compte inscrit dans « User Management ».")
        case SpotifyWebAPI.APIError.http(status: 429):
            return String(localized: "Trop de requêtes vers Spotify : réessayez dans un instant.")
        case SpotifyWebAPI.APIError.http(let status):
            return String(localized: "Erreur de Spotify (\(status)).")
        case SpotifyWebAPI.APIError.invalidResponse:
            return String(localized: "Réponse de Spotify inattendue : réessayez.")
        default:
            return String(localized: "Spotify est injoignable : vérifiez la connexion à Internet.")
        }
    }
}
