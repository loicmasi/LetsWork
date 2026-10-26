import AppKit
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

/// Barres animées pendant la lecture. L'animation est confiée à Core Animation : elle tourne dans le serveur
/// d'affichage, alors qu'une animation SwiftUI recalculerait toute l'Island à chaque image (≈ 15 % de CPU).
struct EqualizerView: NSViewRepresentable {
    let color: Color

    func makeNSView(context: Context) -> EqualizerBarsView {
        EqualizerBarsView()
    }

    func updateNSView(_ view: EqualizerBarsView, context: Context) {
        view.barColor = NSColor(color)
    }
}

final class EqualizerBarsView: NSView {
    /// Hauteurs relatives successives de chaque barre ; des durées différentes évitent un mouvement synchrone.
    private static let levels: [[CGFloat]] = [
        [0.35, 1, 0.55, 0.85, 0.3, 0.7, 0.35],
        [0.8, 0.4, 1, 0.5, 0.9, 0.3, 0.8],
        [0.5, 0.9, 0.3, 1, 0.45, 0.75, 0.5],
        [0.7, 0.3, 0.85, 0.4, 1, 0.55, 0.7],
    ]
    private static let durations: [CFTimeInterval] = [1.9, 1.6, 2.1, 1.75]

    private var bars: [CALayer] = []

    var barColor: NSColor = .white {
        didSet {
            bars.forEach { $0.backgroundColor = barColor.cgColor }
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        bars = Self.levels.indices.map { _ in
            let bar = CALayer()
            bar.backgroundColor = barColor.cgColor
            layer?.addSublayer(bar)
            return bar
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) n'est pas pris en charge")
    }

    /// Les clics vont à SwiftUI (épinglage de l'Island).
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func layout() {
        super.layout()
        let spacing = bounds.width * 0.12
        let width = (bounds.width - spacing * CGFloat(bars.count - 1)) / CGFloat(bars.count)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            bar.frame = CGRect(x: CGFloat(index) * (width + spacing), y: 0, width: width, height: bounds.height)
            bar.cornerRadius = width / 2
            if bar.animation(forKey: "level") == nil {
                bar.add(Self.levelAnimation(for: index), forKey: "level")
            }
        }
        CATransaction.commit()
    }

    /// Variation de hauteur autour du centre de la barre, en boucle.
    private static func levelAnimation(for index: Int) -> CAAnimation {
        let animation = CAKeyframeAnimation(keyPath: "transform.scale.y")
        animation.values = levels[index]
        animation.duration = durations[index]
        animation.calculationMode = .cubic
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        return animation
    }
}
