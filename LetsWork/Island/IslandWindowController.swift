import AppKit

/// Place la fenêtre de l'Island sur l'écran cible et traduit la position de la souris
/// en survol, clics traversants et fin d'épinglage.
@MainActor
final class IslandWindowController {
    let model: IslandModel

    private let panel = IslandPanel()
    private var screen: NSScreen?
    private var eventMonitors: [Any] = []
    private var notificationObservers: [NSObjectProtocol] = []

    init(media: MediaService, calendar: CalendarService, battery: BatteryService) {
        let fallback = NotchGeometry(size: CGSize(width: NotchGeometry.simulatedWidth, height: NotchGeometry.minimumSimulatedHeight), hasNotch: false)
        model = IslandModel(metrics: IslandMetrics(notch: fallback))
        let container = IslandContainerView(rootView: IslandView(model: model, media: media, calendar: calendar, battery: battery))
        container.onMouseEvent = { [weak self] in
            self?.handleMouse(at: NSEvent.mouseLocation)
        }
        panel.contentView = container
        panel.keyHandler = { [weak model] event in
            model?.handleKey(event.keyCode) ?? false
        }
        model.onKeyboardFocusChange = { [weak self] wantsFocus in
            self?.setKeyboardFocus(wantsFocus)
        }
    }

    /// Donne le clavier à l'Island pendant une partie, puis le rend à l'app au premier plan.
    private func setKeyboardFocus(_ wantsFocus: Bool) {
        panel.acceptsKeyboardFocus = wantsFocus
        if wantsFocus {
            panel.makeKey()
        } else if panel.isKeyWindow {
            panel.resignKey()
            // LetsWork n'est jamais activée par l'Island : l'app au premier plan est celle de l'utilisateur.
            NSWorkspace.shared.frontmostApplication?.activate()
        }
    }

    func show() {
        reposition()
        panel.orderFrontRegardless()
        startObserving()
    }

    private func reposition() {
        guard let screen = targetScreen() else {
            panel.orderOut(nil)
            return
        }
        self.screen = screen
        model.updateMetrics(IslandMetrics(notch: NotchGeometry(screen: screen)))
        let size = IslandMetrics.canvasSize
        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    private func targetScreen() -> NSScreen? {
        let primary = NSScreen.screens.first
        switch AppSettings.displayTarget {
        case .notchScreen:
            return NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? primary
        case .primaryScreen:
            return primary
        }
    }

    private func handleMouse(at location: NSPoint) {
        guard let screen else { return }
        let isInside = model.metrics.hitZone(for: model.state, activity: model.activity, in: screen.frame).contains(location)
        if panel.ignoresMouseEvents == isInside {
            panel.ignoresMouseEvents = !isInside
        }
        model.setHovering(isInside)
    }

    private func startObserving() {
        guard eventMonitors.isEmpty else { return }

        // Mouvements envoyés aux autres applications (la fenêtre ignore alors la souris).
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleMouse(at: NSEvent.mouseLocation)
            }
        }) {
            eventMonitors.append(monitor)
        }

        // Un clic ailleurs retire l'épinglage.
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated {
                self?.model.dismissPin()
            }
        }) {
            eventMonitors.append(monitor)
        }

        let center = NotificationCenter.default
        notificationObservers.append(center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reposition()
            }
        })
        notificationObservers.append(center.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reposition()
            }
        })
    }
}
