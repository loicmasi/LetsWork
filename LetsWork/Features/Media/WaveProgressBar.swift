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
/// la partie restante reste un trait discret. Le défilement est confié à Core Animation : il tourne dans
/// le serveur d'affichage, alors qu'un dessin SwiftUI à 30 images/s recalculait toute l'Island en continu.
struct WaveProgressBar: NSViewRepresentable {
    /// Part écoulée, entre 0 et 1.
    let fraction: Double
    let palette: WavePalette
    let isPlaying: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// En pause, les dômes s'aplatissent et se figent.
    static let pausedAmplitude: CGFloat = 0.35

    func makeNSView(context: Context) -> WaveBarView {
        WaveBarView()
    }

    func updateNSView(_ view: WaveBarView, context: Context) {
        view.update(
            fraction: CGFloat(min(max(fraction, 0), 1)),
            palette: palette,
            amplitudeScale: isPlaying ? 1 : Self.pausedAmplitude,
            isMoving: isPlaying && !reduceMotion
        )
    }
}

final class WaveBarView: NSView {
    private static let trackHeight: CGFloat = 4
    /// Amortit les dômes aux extrémités de la partie écoulée pour éviter une coupure nette.
    private static let edgeFade: CGFloat = 10
    private static let waves: [WaveLayer] = [.back, .middle, .front]

    private let trackLayer = CALayer()
    /// Contient les dômes ; sa largeur suit la partie écoulée et un masque dégradé en adoucit les bords.
    private let wavesContainer = CALayer()
    private let fadeMask = CAGradientLayer()
    private let waveLayers = WaveBarView.waves.map { _ in CAShapeLayer() }
    private let elapsedLayer = CALayer()

    private var fraction: CGFloat = 0
    private var amplitudeScale: CGFloat = 1
    private var isMoving = false
    private var builtSize: CGSize = .zero
    private var builtAmplitude: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        guard let layer else { return }
        trackLayer.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
        fadeMask.startPoint = CGPoint(x: 0, y: 0.5)
        fadeMask.endPoint = CGPoint(x: 1, y: 0.5)
        wavesContainer.mask = fadeMask
        waveLayers.forEach(wavesContainer.addSublayer)
        [trackLayer, wavesContainer, elapsedLayer].forEach(layer.addSublayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) n'est pas pris en charge")
    }

    /// Les clics vont à SwiftUI, qui gère le glisser pour se déplacer dans la piste.
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func update(fraction: CGFloat, palette: WavePalette, amplitudeScale: CGFloat, isMoving: Bool) {
        self.fraction = fraction
        self.amplitudeScale = amplitudeScale
        let colors = [palette.low, palette.medium, palette.high]
        for (layer, color) in zip(waveLayers, colors) {
            layer.fillColor = color.withAlphaComponent(0.9).cgColor
        }
        elapsedLayer.backgroundColor = palette.high.cgColor
        if isMoving != self.isMoving {
            self.isMoving = isMoving
            isMoving ? resumeWaves() : pauseWaves()
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let size = bounds.size
        let trackY = size.height / 2
        let elapsedWidth = size.width * fraction
        trackLayer.frame = CGRect(x: 0, y: trackY - Self.trackHeight / 2, width: size.width, height: Self.trackHeight)
        trackLayer.cornerRadius = Self.trackHeight / 2
        elapsedLayer.frame = CGRect(x: 0, y: trackY - Self.trackHeight / 2, width: elapsedWidth, height: Self.trackHeight)
        elapsedLayer.cornerRadius = Self.trackHeight / 2

        wavesContainer.frame = CGRect(x: 0, y: 0, width: elapsedWidth, height: size.height)
        fadeMask.frame = wavesContainer.bounds
        let fade = elapsedWidth > 0 ? min(0.5, Self.edgeFade / elapsedWidth) : 0
        fadeMask.colors = [NSColor.clear, .black, .black, .clear].map(\.cgColor)
        fadeMask.locations = [0, fade, 1 - fade, 1].map { NSNumber(value: Double($0)) }

        if size != builtSize || amplitudeScale != builtAmplitude {
            builtSize = size
            builtAmplitude = amplitudeScale
            buildWaves(size: size)
        }
        CATransaction.commit()
    }

    /// Chaque couche dessine ses dômes sur toute la largeur plus une période, puis défile d'une période
    /// en boucle : le motif étant périodique, la boucle est invisible.
    private func buildWaves(size: CGSize) {
        let baseline = size.height / 2
        let maxHeight = (baseline - 1) * amplitudeScale
        for (wave, layer) in zip(Self.waves, waveLayers) {
            let path = CGMutablePath()
            let start = -wave.wavelength
            let end = size.width + wave.wavelength
            path.move(to: CGPoint(x: start, y: baseline))
            var x = start
            while x <= end {
                path.addLine(to: CGPoint(x: x, y: baseline + wave.height(at: x, time: 0) * maxHeight))
                x += 1
            }
            path.addLine(to: CGPoint(x: end, y: baseline))
            path.closeSubpath()
            layer.path = path

            layer.removeAnimation(forKey: "scroll")
            let scroll = CABasicAnimation(keyPath: "transform.translation.x")
            scroll.fromValue = 0
            scroll.toValue = wave.wavelength * wave.direction
            scroll.duration = CFTimeInterval(wave.wavelength / wave.speed)
            scroll.repeatCount = .infinity
            scroll.isRemovedOnCompletion = false
            layer.add(scroll, forKey: "scroll")
        }
        if !isMoving {
            pauseWaves()
        }
    }

    /// Fige le défilement là où il en est.
    private func pauseWaves() {
        guard wavesContainer.speed != 0 else { return }
        let pausedTime = wavesContainer.convertTime(CACurrentMediaTime(), from: nil)
        wavesContainer.speed = 0
        wavesContainer.timeOffset = pausedTime
    }

    private func resumeWaves() {
        guard wavesContainer.speed == 0 else { return }
        let pausedTime = wavesContainer.timeOffset
        wavesContainer.speed = 1
        wavesContainer.timeOffset = 0
        wavesContainer.beginTime = 0
        wavesContainer.beginTime = wavesContainer.convertTime(CACurrentMediaTime(), from: nil) - pausedTime
    }
}
