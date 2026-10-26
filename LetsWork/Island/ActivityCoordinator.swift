import Foundation

/// Réaction de l'Island à un changement d'état de lecture.
enum MediaTransition: Equatable {
    case playing(isNewTrack: Bool)
    case stopped

    init(from previous: NowPlaying?, to current: NowPlaying?) {
        guard let current, current.isPlaying else {
            self = .stopped
            return
        }
        self = .playing(isNewTrack: previous?.trackIdentity != current.trackIdentity)
    }
}

/// Décide de ce que l'Island affiche selon les activités en cours (FEATURES.md, F0 › Arbitrage).
@MainActor
final class ActivityCoordinator {
    static let trackChangePeekDuration: Duration = .seconds(3)
    static let playbackEndGrace: Duration = .seconds(5)
    /// Durée d'affichage du HUD après la dernière pression.
    static let hudDuration: Duration = .milliseconds(1500)

    private let island: IslandModel
    private var peekTask: Task<Void, Never>?
    private var graceTask: Task<Void, Never>?
    private var hudTask: Task<Void, Never>?

    init(island: IslandModel, media: MediaService, hud: HUDService) {
        self.island = island
        media.onChange = { [weak self] previous, current in
            self?.mediaDidChange(from: previous, to: current)
        }
        hud.onShow = { [weak self] state in
            self?.showHUD(state)
        }
    }

    /// Chaque pression relance le délai avant que l'Island revienne à son état précédent.
    func showHUD(_ state: HUDState) {
        island.setHUD(state)
        hudTask?.cancel()
        hudTask = Task { [weak self] in
            try? await Task.sleep(for: Self.hudDuration)
            guard !Task.isCancelled else { return }
            self?.island.setHUD(nil)
        }
    }

    func mediaDidChange(from previous: NowPlaying?, to current: NowPlaying?) {
        switch MediaTransition(from: previous, to: current) {
        case .playing(let isNewTrack):
            graceTask?.cancel()
            graceTask = nil
            island.setActivity(.media)
            if isNewTrack {
                peek()
            }
        case .stopped:
            // Pause ou fin de lecture : l'Island reste en compact quelques secondes avant de se fermer.
            guard island.activity == .media, graceTask == nil else { return }
            graceTask = Task { [weak self] in
                try? await Task.sleep(for: Self.playbackEndGrace)
                guard !Task.isCancelled, let self else { return }
                self.island.setActivity(nil)
                self.graceTask = nil
            }
        }
    }

    private func peek() {
        peekTask?.cancel()
        island.setPeeking(true)
        peekTask = Task { [weak self] in
            try? await Task.sleep(for: Self.trackChangePeekDuration)
            guard !Task.isCancelled else { return }
            self?.island.setPeeking(false)
        }
    }
}
