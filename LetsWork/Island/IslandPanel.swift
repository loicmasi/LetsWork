import AppKit
import SwiftUI

/// Fenêtre sans bordure, non activante, affichée au-dessus de la barre de menus sur tous les Spaces.
final class IslandPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        // Laisse passer les clics tant que la souris n'est pas sur l'Island (voir IslandWindowController).
        ignoresMouseEvents = true
    }
}

/// Contenu de la fenêtre : héberge la vue SwiftUI et signale les mouvements de souris
/// reçus pendant que la fenêtre capte les événements (les moniteurs globaux ne les voient pas).
final class IslandContainerView: NSView {
    var onMouseEvent: (() -> Void)?

    private var trackingArea: NSTrackingArea?

    init<Content: View>(rootView: Content) {
        super.init(frame: .zero)
        let hostingView = FirstMouseHostingView(rootView: rootView)
        hostingView.sizingOptions = []
        hostingView.frame = bounds
        hostingView.autoresizingMask = [.width, .height]
        addSubview(hostingView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) n'est pas pris en charge")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        onMouseEvent?()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseEvent?()
    }
}

/// Le premier clic sur l'Island doit agir directement, sans activer l'application.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
