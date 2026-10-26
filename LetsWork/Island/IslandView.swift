import SwiftUI

struct IslandView: View {
    let model: IslandModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let state = model.state
        let metrics = model.metrics
        let size = metrics.size(for: state)
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
        .onTapGesture { model.togglePinned() }
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
    }

    @ViewBuilder
    private func content(state: IslandState, metrics: IslandMetrics) -> some View {
        switch state {
        case .closed:
            Color.clear
        case .compact:
            CompactPlaceholderView(notch: metrics.notch)
        case .expanded:
            ExpandedPlaceholderView(notchHeight: metrics.notch.size.height)
        }
    }
}

/// Contenu provisoire de l'état compact, en attendant les activités réelles (M1+).
private struct CompactPlaceholderView: View {
    let notch: NotchGeometry

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "waveform")
                .foregroundStyle(.white)
                .frame(width: IslandMetrics.compactWingWidth)
            Spacer()
                .frame(width: notch.size.width)
            Circle()
                .fill(.green)
                .frame(width: 8, height: 8)
                .frame(width: IslandMetrics.compactWingWidth)
        }
        .font(.system(size: 13, weight: .semibold))
        .frame(height: notch.size.height)
    }
}

/// Contenu provisoire de l'état étendu (M0) : date, heure et absence d'activité.
private struct ExpandedPlaceholderView: View {
    let notchHeight: CGFloat

    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 6) {
                Text(context.date, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Aucune activité pour le moment")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, notchHeight + 8)
        }
    }
}
