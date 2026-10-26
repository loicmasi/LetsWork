import SwiftUI

extension MediaService {
    /// Teinte d'accent dérivée de la pochette, blanc par défaut.
    var accent: Color {
        accentColor.map(Color.init(nsColor:)) ?? .white
    }
}

/// Ailes de l'Island en compact : pochette à gauche, égaliseur (ou pause) à droite.
struct MediaCompactView: View {
    let media: MediaService
    let notch: NotchGeometry

    var body: some View {
        HStack(spacing: 0) {
            ArtworkView(media: media, size: 22, cornerRadius: 6)
                .frame(width: IslandMetrics.compactWingWidth)
            Spacer()
                .frame(width: notch.size.width)
            Group {
                if media.nowPlaying?.isPlaying == true {
                    EqualizerView(color: media.accent)
                        .frame(width: 20, height: 14)
                } else {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(media.accent)
                }
            }
            .frame(width: IslandMetrics.compactWingWidth)
        }
        .frame(height: notch.size.height)
    }
}

/// Aperçu après un changement de piste : les ailes du compact et le titre en dessous.
struct MediaPeekView: View {
    let media: MediaService
    let notch: NotchGeometry

    var body: some View {
        VStack(spacing: 0) {
            MediaCompactView(media: media, notch: notch)
            if let nowPlaying = media.nowPlaying {
                Text([nowPlaying.title, nowPlaying.artist].compactMap { $0 }.joined(separator: " — "))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 18)
                    .frame(maxHeight: .infinity)
            }
        }
    }
}

/// Pochette, sinon icône de l'app source sur fond flouté, sinon une note.
struct ArtworkView: View {
    let media: MediaService
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            if let artwork = media.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if let icon = media.sourceApp?.icon {
                Image(nsImage: icon)
                    .resizable()
                    .blur(radius: size / 6)
                    .opacity(0.5)
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(size * 0.15)
            } else {
                Color.white.opacity(0.1)
                Image(systemName: "music.note")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Barres animées pendant la lecture.
struct EqualizerView: View {
    let color: Color

    private static let barCount = 4

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.3)) { context in
            GeometryReader { proxy in
                HStack(spacing: proxy.size.width * 0.12) {
                    ForEach(0..<Self.barCount, id: \.self) { _ in
                        Capsule()
                            .fill(color)
                            .frame(height: proxy.size.height * CGFloat.random(in: 0.25...1))
                    }
                }
                .frame(maxHeight: .infinity)
                .animation(.easeInOut(duration: 0.3), value: context.date)
            }
        }
    }
}
