import Foundation

/// Signale les écritures dans des fichiers (kqueue, via `DispatchSource`). FSEvents ne remonte rien
/// pour le dossier protégé de la base des notifications ; la surveillance directe des fichiers, si.
@MainActor
final class FileChangeWatcher {
    private let urls: [URL]
    private let onChange: @MainActor () -> Void
    private var sources: [DispatchSourceFileSystemObject] = []

    init(urls: [URL], onChange: @escaping @MainActor () -> Void) {
        self.urls = urls
        self.onChange = onChange
    }

    /// Faux si un fichier manquait au dernier armement (le journal `db-wal` n'existe pas toujours).
    var isWatchingAllFiles: Bool {
        sources.count == urls.count
    }

    func start() {
        stop()
        for url in urls {
            let descriptor = open(url.path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .extend, .delete, .rename],
                queue: .main
            )
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    // Fichier supprimé ou remplacé (point de contrôle SQLite), ou fichier recréé dans le dossier
                    // surveillé : on réarme pour suivre les nouveaux fichiers.
                    if !source.data.isDisjoint(with: [.delete, .rename]) || !self.isWatchingAllFiles {
                        self.start()
                    }
                    self.onChange()
                }
            }
            source.setCancelHandler {
                close(descriptor)
            }
            source.resume()
            sources.append(source)
        }
    }

    func stop() {
        sources.forEach { $0.cancel() }
        sources.removeAll()
    }
}
