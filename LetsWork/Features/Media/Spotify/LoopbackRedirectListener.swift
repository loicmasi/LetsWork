import Foundation
import Network

/// Petit serveur HTTP sur 127.0.0.1, ouvert le temps de recevoir la redirection de Spotify après la connexion.
@MainActor
final class LoopbackRedirectListener {
    enum ListenerError: Error {
        case timedOut
    }

    private static let maximumRequestSize = 16_384
    private static let successPage = """
        <!doctype html><meta charset="utf-8"><title>LetsWork</title>
        <body style="font: 15px -apple-system, sans-serif; text-align: center; margin-top: 20vh">
        <h2>Retournez dans LetsWork</h2><p>Vous pouvez fermer cet onglet.</p></body>
        """

    private var listener: NWListener?
    private var continuation: CheckedContinuation<[URLQueryItem], any Error>?
    private var timeoutTask: Task<Void, Never>?
    private var path = ""
    private var onReady: (() -> Void)?

    /// Écoute sur `port` et renvoie les paramètres de la première requête reçue sur `path`.
    /// `onReady` est appelé une fois le port ouvert : c'est le moment d'ouvrir la page de connexion.
    func waitForCallback(
        port: UInt16,
        path: String,
        timeout: Duration,
        onReady: @escaping () -> Void
    ) async throws -> [URLQueryItem] {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                start(port: port, path: path, timeout: timeout, onReady: onReady, continuation: continuation)
            }
        } onCancel: {
            Task { @MainActor in
                self.finish(.failure(CancellationError()))
            }
        }
    }

    /// Paramètres de la requête `GET <path>?…` ; `nil` pour une autre requête (favicon…).
    nonisolated static func callbackQuery(inRequest request: String, path: String) -> [URLQueryItem]? {
        // « \r\n » forme un seul caractère Swift : `isNewline` le reconnaît, une comparaison à "\r" non.
        let requestLine = request.prefix { !$0.isNewline }.split(separator: " ")
        guard
            requestLine.count == 3,
            requestLine[0] == "GET",
            let components = URLComponents(string: String(requestLine[1])),
            components.path == path
        else { return nil }
        return components.queryItems ?? []
    }

    private func start(
        port: UInt16,
        path: String,
        timeout: Duration,
        onReady: @escaping () -> Void,
        continuation: CheckedContinuation<[URLQueryItem], any Error>
    ) {
        self.continuation = continuation
        self.path = path
        self.onReady = onReady
        guard !Task.isCancelled else {
            finish(.failure(CancellationError()))
            return
        }
        do {
            // Seulement l'interface de bouclage : rien n'est exposé au réseau.
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port)!)
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters)
            listener.stateUpdateHandler = { [weak self] state in
                MainActor.assumeIsolated {
                    self?.listenerDidChange(state)
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated {
                    self?.accept(connection)
                }
            }
            self.listener = listener
            listener.start(queue: .main)
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                self?.finish(.failure(ListenerError.timedOut))
            }
        } catch {
            finish(.failure(error))
        }
    }

    private func listenerDidChange(_ state: NWListener.State) {
        switch state {
        case .ready:
            onReady?()
            onReady = nil
        case .failed(let error):
            finish(.failure(error))
        default:
            break
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: Self.maximumRequestSize) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                var buffer = buffer
                if let data {
                    buffer.append(data)
                }
                if let request = String(data: buffer, encoding: .utf8), request.contains("\r\n\r\n") {
                    self?.handle(request, on: connection)
                } else if self == nil || isComplete || error != nil || buffer.count > Self.maximumRequestSize {
                    connection.cancel()
                } else {
                    self?.receive(on: connection, buffer: buffer)
                }
            }
        }
    }

    private func handle(_ request: String, on connection: NWConnection) {
        guard let query = Self.callbackQuery(inRequest: request, path: path) else {
            respond(on: connection, status: "404 Not Found", body: "")
            return
        }
        respond(on: connection, status: "200 OK", body: Self.successPage)
        finish(.success(query))
    }

    private func respond(on connection: NWConnection, status: String, body: String) {
        let body = Data(body.utf8)
        let head = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func finish(_ result: Result<[URLQueryItem], any Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        listener?.cancel()
        listener = nil
        onReady = nil
        continuation?.resume(with: result)
        continuation = nil
    }
}
