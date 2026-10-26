import AppKit
import SwiftUI

/// Trois nuances de la couleur de la pochette, de la plus discrète à la plus contrastée sur le noir de l'Island.
struct WavePalette: Equatable {
    var low: NSColor
    var medium: NSColor
    var high: NSColor

    init(accent: NSColor) {
        let color = accent.usingColorSpace(.deviceRGB) ?? .white
        let hue = color.hueComponent
        let saturation = color.saturationComponent
        let brightness = color.brightnessComponent
        low = NSColor(deviceHue: hue, saturation: min(1, saturation * 1.15), brightness: brightness * 0.55, alpha: 1)
        medium = NSColor(deviceHue: hue, saturation: saturation, brightness: brightness * 0.85, alpha: 1)
        high = NSColor(deviceHue: hue, saturation: saturation * 0.55, brightness: min(1, brightness * 1.1 + 0.1), alpha: 1)
    }
}

/// Une rangée de dômes qui défile : un dôme en demi-sinusoïde, puis un creux de même largeur.
struct WaveLayer: Equatable {
    /// Largeur d'un dôme et de son creux, en points.
    var wavelength: CGFloat
    /// Hauteur maximale, en fraction de la hauteur disponible.
    var amplitude: CGFloat
    /// Vitesse de défilement, en points par seconde.
    var speed: CGFloat
    /// 1 : de gauche à droite, -1 : de droite à gauche.
    var direction: CGFloat

    /// Du fond vers le premier plan : grands dômes lents, puis de plus en plus petits et rapides.
    static let back = WaveLayer(wavelength: 38, amplitude: 1, speed: 12, direction: -1)
    static let middle = WaveLayer(wavelength: 28, amplitude: 0.75, speed: 18, direction: 1)
    static let front = WaveLayer(wavelength: 20, amplitude: 0.5, speed: 26, direction: 1)

    /// Hauteur du dôme (entre 0 et `amplitude`) à l'abscisse `x`, à l'instant `time` en secondes.
    func height(at x: CGFloat, time: TimeInterval) -> CGFloat {
        let shift = (CGFloat(time) * speed * direction).truncatingRemainder(dividingBy: wavelength)
        let phase = (x - shift) / wavelength
        return amplitude * max(0, sin(2 * .pi * phase))
    }
}

/// Barre de progression : la partie écoulée porte trois couches de dômes animées,
/// la partie restante reste un trait discret.
struct WaveProgressBar: View {
    /// Part écoulée, entre 0 et 1.
    let fraction: Double
    let palette: WavePalette
    let isPlaying: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let trackHeight: CGFloat = 4
    /// Amortit les dômes aux extrémités de la partie écoulée pour éviter une coupure nette.
    private static let edgeFade: CGFloat = 10
    /// En pause, les dômes s'aplatissent et se figent.
    private static let pausedAmplitude: CGFloat = 0.35

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isPlaying || reduceMotion)) { context in
            Canvas { canvas, size in
                draw(in: &canvas, size: size, time: context.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private func draw(in canvas: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let trackY = size.height / 2
        let elapsedWidth = size.width * CGFloat(min(max(fraction, 0), 1))
        let track = CGRect(x: 0, y: trackY - Self.trackHeight / 2, width: size.width, height: Self.trackHeight)

        canvas.fill(Path(roundedRect: track, cornerRadius: Self.trackHeight / 2), with: .color(.white.opacity(0.18)))
        guard elapsedWidth > 0 else { return }

        let maxHeight = trackY - 1
        let scale = isPlaying ? 1 : Self.pausedAmplitude
        let layers: [(WaveLayer, NSColor)] = [(.back, palette.low), (.middle, palette.medium), (.front, palette.high)]
        for (layer, color) in layers {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: trackY))
            var x: CGFloat = 0
            while x <= elapsedWidth {
                let fade = min(1, x / Self.edgeFade, (elapsedWidth - x) / Self.edgeFade)
                let height = layer.height(at: x, time: time) * maxHeight * scale * max(0, fade)
                path.addLine(to: CGPoint(x: x, y: trackY - height))
                x += 1
            }
            path.addLine(to: CGPoint(x: elapsedWidth, y: trackY))
            path.closeSubpath()
            canvas.fill(path, with: .color(Color(nsColor: color).opacity(0.9)))
        }

        let elapsedTrack = CGRect(x: 0, y: track.minY, width: elapsedWidth, height: Self.trackHeight)
        canvas.fill(Path(roundedRect: elapsedTrack, cornerRadius: Self.trackHeight / 2), with: .color(Color(nsColor: palette.high)))
    }
}
