import SwiftUI

/// Onglet Multimédia : pochette, titre, source, progression et contrôles, ou un message si rien ne joue.
struct MediaExpandedView: View {
    let media: MediaService
    let notchHeight: CGFloat

    var body: some View {
        if let nowPlaying = media.nowPlaying {
            VStack(spacing: 14) {
                HStack(spacing: 18) {
                    Button(action: media.activateSourceApp) {
                        ArtworkView(media: media, size: 96, cornerRadius: 12)
                    }
                    .buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(nowPlaying.title)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                        if let subtitle = Self.subtitle(of: nowPlaying) {
                            Text(subtitle)
                                .font(.title3)
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
            // Avec une encoche de 32 pt, remplit exactement IslandMetrics.expandedSize (230 pt).
            .padding(.horizontal, 28)
            .padding(.top, notchHeight + 8)
            .padding(.bottom, 16)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "music.note")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text("Aucune lecture en cours")
                    .font(.title3.weight(.semibold))
                Text("Lancez Musique, Spotify ou une vidéo dans votre navigateur.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, notchHeight)
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
            WaveProgressBar(fraction: fraction, palette: media.wavePalette, isPlaying: nowPlaying.isPlaying)
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
        .frame(height: 22)
        .accessibilityElement()
        .accessibilityLabel("Progression de la lecture")
        .accessibilityValue(PlaybackTime.format(fraction * duration))
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
