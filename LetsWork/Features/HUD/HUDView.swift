import SwiftUI

/// Indicateur de volume ou de luminosité dans les ailes de l'Island.
struct HUDView: View {
    let state: HUDState
    let notch: NotchGeometry

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: state.symbolName)
                .font(.system(size: 15, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: IslandMetrics.hudWingWidth)
            Spacer()
                .frame(width: notch.size.width)
            Group {
                if state.isAvailable {
                    HStack(spacing: 8) {
                        LevelGauge(level: state.displayedLevel)
                        Text(state.isMuted ? "–" : "\(Int((state.level * 100).rounded()))")
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .frame(width: 24, alignment: .trailing)
                            .contentTransition(.numericText())
                    }
                    .padding(.horizontal, 14)
                } else {
                    Text("Non réglable")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: IslandMetrics.hudWingWidth)
        }
        .foregroundStyle(.white)
        .frame(height: notch.size.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.kind == .volume ? "Volume" : "Luminosité")
        .accessibilityValue(state.isMuted ? "Muet" : "\(Int((state.level * 100).rounded())) %")
    }
}

/// Jauge horizontale qui rebondit légèrement à chaque changement.
private struct LevelGauge: View {
    let level: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.22))
                Capsule()
                    .fill(.white)
                    .frame(width: proxy.size.width * min(max(level, 0), 1))
            }
        }
        .frame(height: 5)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: level)
    }
}
