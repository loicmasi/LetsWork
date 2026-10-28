import SwiftUI

struct IslandView: View {
    let model: IslandModel
    let media: MediaService
    let calendar: CalendarService
    let battery: BatteryService

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let state = model.state
        let metrics = model.metrics
        let size = metrics.size(for: state, activity: model.activity)
        let top = metrics.topCornerRadius(for: state)
        let shape = NotchShape(topCornerRadius: top, bottomCornerRadius: metrics.bottomCornerRadius(for: state))

        ZStack(alignment: .top) {
            shape.fill(.black)
            content(state: state, metrics: metrics)
                .padding(.horizontal, top)
                .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
                .id(state)
        }
        .frame(width: size.width + 2 * top, height: size.height)
        .clipShape(shape)
        .contentShape(shape)
        .onTapGesture {
            // Un clic sur une alerte la referme ; sur une notification, il ouvre l'app ; ailleurs, il épingle l'Island.
            switch state {
            case .alert:
                model.setAlert(nil)
            case .lowBattery:
                model.setLowBattery(false)
            case .notification:
                if let notification = model.notification {
                    NotificationApp.open(bundleIdentifier: notification.bundleIdentifier)
                }
                model.onNotificationTap?()
            default:
                model.togglePinned()
            }
        }
        // Sur un écran sans encoche, l'Island fermée n'a rien à prolonger : elle reste invisible.
        .opacity(state == .closed && !metrics.notch.hasNotch ? 0 : 1)
        .shadow(color: .black.opacity(state == .expanded ? 0.4 : 0), radius: 12, y: 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .animation(
            reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.38, dampingFraction: 0.78),
            value: state
        )
        .animation(.easeInOut(duration: 0.2), value: metrics)
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: model.activity)
    }

    @ViewBuilder
    private func content(state: IslandState, metrics: IslandMetrics) -> some View {
        switch state {
        case .closed:
            Color.clear
        case .compact:
            switch model.activity {
            case .media:
                MediaCompactView(media: media, notch: metrics.notch)
            case .calendar:
                if let event = calendar.upcoming {
                    CalendarCompactView(event: event, notch: metrics.notch)
                }
            case nil:
                Color.clear
            }
        case .peek:
            MediaPeekView(media: media, notch: metrics.notch)
        case .alert:
            if let event = model.alert {
                CalendarAlertView(event: event, notch: metrics.notch) {
                    calendar.join(event)
                    model.setAlert(nil)
                }
            }
        case .notification:
            if let notification = model.notification {
                NotificationPopupView(notification: notification, notch: metrics.notch)
            }
        case .lowBattery:
            if let status = battery.status {
                LowBatteryAlertView(status: status, notch: metrics.notch)
            }
        case .charging:
            if let status = battery.status {
                ChargingIndicatorView(status: status, notch: metrics.notch)
            }
        case .hud:
            if let hud = model.hud {
                HUDView(state: hud, notch: metrics.notch)
            }
        case .expanded:
            ExpandedIslandView(
                model: model,
                media: media,
                calendar: calendar,
                battery: battery,
                notchHeight: metrics.notch.size.height
            )
        }
    }
}
