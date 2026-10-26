import SwiftUI

/// Lecteur complet de l'état étendu : pochette, titre, source, progression et contrôles.
struct MediaExpandedView: View {
    let media: MediaService
    let notchHeight: CGFloat

    var body: some View {
        if let nowPlaying = media.nowPlaying {
            VStack(spacing: 10) {
                HStack(spacing: 14) {
                    Button(action: media.activateSourceApp) {
                        ArtworkView(media: media, size: 64, cornerRadius: 12)
                    }
                    .buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(nowPlaying.title)
                            .font(.headline)
                            .foregroundStyle(.white)
                        if let subtitle = Self.subtitle(of: nowPlaying) {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .lineLimit(1)
                    Spacer(minLength: 0)
                    if let app = media.sourceApp {
                        Button(action: media.activateSourceApp) {
                            Image(nsImage: app.icon)
                                .resizable()
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.plain)
                        .help(app.name)
                    }
                }
                PlaybackProgressView(media: media, nowPlaying: nowPlaying)
                HStack(spacing: 36) {
                    ControlButton(symbol: "backward.fill", label: "Piste précédente", action: media.previousTrack)
                    ControlButton(
                        symbol: nowPlaying.isPlaying ? "pause.fill" : "play.fill",
                        label: nowPlaying.isPlaying ? "Pause" : "Lecture",
                        size: 22,
                        action: media.togglePlayPause
                    )
                    ControlButton(symbol: "forward.fill", label: "Piste suivante", action: media.nextTrack)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, notchHeight + 6)
            .padding(.bottom, 12)
        }
    }

    private static func subtitle(of nowPlaying: NowPlaying) -> String? {
        let parts = [nowPlaying.artist, nowPlaying.album].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " — ")
    }
}

private struct ControlButton: View {
    let symbol: String
    let label: LocalizedStringKey
    var size: CGFloat = 16
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Barre de progression interpolée localement ; glisser dessus déplace la lecture.
struct PlaybackProgressView: View {
    let media: MediaService
    let nowPlaying: NowPlaying

    @State private var dragFraction: Double?

    var body: some View {
        if let duration = nowPlaying.duration, duration > 0 {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let position = dragFraction.map { $0 * duration } ?? nowPlaying.elapsed(at: context.date) ?? 0
                HStack(spacing: 8) {
                    Text(PlaybackTime.format(position))
                    bar(fraction: min(1, position / duration), duration: duration)
                    Text("-" + PlaybackTime.format(duration - position))
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
    }

    private func bar(fraction: Double, duration: TimeInterval) -> some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.2))
                Capsule()
                    .fill(media.accent)
                    .frame(width: width * fraction)
            }
            .frame(height: 5)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragFraction = min(max(value.location.x / width, 0), 1)
                    }
                    .onEnded { value in
                        media.seek(to: min(max(value.location.x / width, 0), 1) * duration)
                        dragFraction = nil
                    }
            )
        }
        .frame(height: 14)
    }
}

enum PlaybackTime {
    /// « 3:07 », ou « 1:02:45 » au-delà d'une heure.
    static func format(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = total % 3600 / 60
        let remainder = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainder)
        }
        return String(format: "%d:%02d", minutes, remainder)
    }
}
