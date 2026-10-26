import Foundation
import Observation

/// État observable de l'Island : applique les délais de survol et l'épinglage au clic.
@MainActor
@Observable
final class IslandModel {
    static let hoverInDelay: Duration = .milliseconds(150)
    static let hoverOutDelay: Duration = .milliseconds(250)

    private(set) var state: IslandState = .closed
    private(set) var metrics: IslandMetrics
    private(set) var activity: IslandActivity?

    @ObservationIgnored private var inputs = IslandInputs()
    @ObservationIgnored private var pendingTransition: Task<Void, Never>?

    init(metrics: IslandMetrics) {
        self.metrics = metrics
    }

    func updateMetrics(_ metrics: IslandMetrics) {
        guard metrics != self.metrics else { return }
        self.metrics = metrics
    }

    func setHovering(_ hovering: Bool) {
        guard hovering != inputs.isHovering else { return }
        inputs.isHovering = hovering
        scheduleResolve(after: hovering ? Self.hoverInDelay : Self.hoverOutDelay)
    }

    func togglePinned() {
        inputs.isPinned.toggle()
        resolveNow()
    }

    /// Clic en dehors de l'Island : retire l'épinglage.
    func dismissPin() {
        guard inputs.isPinned else { return }
        inputs.isPinned = false
        resolveNow()
    }

    func setActivity(_ activity: IslandActivity?) {
        guard activity != self.activity else { return }
        self.activity = activity
        inputs.hasActivity = activity != nil
        resolveNow()
    }

    func setPeeking(_ peeking: Bool) {
        guard peeking != inputs.isPeeking else { return }
        inputs.isPeeking = peeking
        resolveNow()
    }

    private func scheduleResolve(after delay: Duration) {
        pendingTransition?.cancel()
        pendingTransition = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.resolveNow()
        }
    }

    private func resolveNow() {
        pendingTransition?.cancel()
        pendingTransition = nil
        let next = IslandState.resolve(inputs)
        if next != state {
            state = next
        }
    }
}
