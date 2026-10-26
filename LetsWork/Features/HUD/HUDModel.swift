import CoreGraphics

/// Touches système remplacées par le HUD de l'Island.
enum HUDKey: Equatable, Sendable {
    case volumeUp
    case volumeDown
    case mute
    case brightnessUp
    case brightnessDown

    /// Code `NX_KEYTYPE_*` des événements système (sous-type 8, « aux control buttons »).
    init?(auxKeyCode: Int) {
        switch auxKeyCode {
        case 0: self = .volumeUp
        case 1: self = .volumeDown
        case 2: self = .brightnessUp
        case 3: self = .brightnessDown
        case 7: self = .mute
        default: return nil
        }
    }

    /// Touches de luminosité qui arrivent en `keyDown` plutôt qu'en événement système :
    /// - 144/145 : touches dédiées de certains claviers ;
    /// - F14/F15 (107/113) : associées à la luminosité par défaut dans macOS, et émises par Logi Options+
    ///   pour les touches F1/F2 des claviers Logitech (MX Keys).
    init?(functionKeyCode: Int64) {
        switch functionKeyCode {
        case 144, 113: self = .brightnessUp
        case 145, 107: self = .brightnessDown
        default: return nil
        }
    }

    var isVolume: Bool {
        switch self {
        case .volumeUp, .volumeDown, .mute: true
        case .brightnessUp, .brightnessDown: false
        }
    }
}

/// Un appui (ou relâchement) sur une touche du HUD.
struct MediaKeyPress: Equatable, Sendable {
    var key: HUDKey
    var isDown: Bool
    var isRepeat = false
    /// ⌥⇧ : pas fin de 1/64, comme macOS.
    var isFineStep = false
    /// ⌥ seul : macOS ouvre le réglage correspondant ; on laisse passer l'événement.
    var opensSystemSettings = false

    init(key: HUDKey, isDown: Bool, isRepeat: Bool = false, flags: CGEventFlags = []) {
        self.key = key
        self.isDown = isDown
        self.isRepeat = isRepeat
        let option = flags.contains(.maskAlternate)
        let shift = flags.contains(.maskShift)
        isFineStep = option && shift
        opensSystemSettings = option && !shift
    }

    /// `data1` d'un événement système : code de touche sur 16 bits, puis état (0x0A appui, 0x0B relâchement) et répétition.
    init?(systemDefinedData1 data1: Int, flags: CGEventFlags) {
        guard let key = HUDKey(auxKeyCode: (data1 & 0xFFFF_0000) >> 16) else { return nil }
        let keyFlags = data1 & 0xFFFF
        self.init(key: key, isDown: (keyFlags & 0xFF00) >> 8 == 0x0A, isRepeat: keyFlags & 0x1 != 0, flags: flags)
    }
}

/// Niveaux alignés sur une grille de pas, comme les touches de macOS.
enum LevelStep {
    static let normal = 1.0 / 16
    static let fine = 1.0 / 64

    static func next(from level: Double, up: Bool, step: Double) -> Double {
        // La tolérance absorbe l'imprécision des Float32 renvoyés par Core Audio et DisplayServices.
        let position = level / step
        let index = up ? (position + 1e-4).rounded(.down) + 1 : (position - 1e-4).rounded(.up) - 1
        return min(1, max(0, index * step))
    }
}

struct VolumeLevel: Equatable, Sendable {
    var level: Double
    var isMuted: Bool

    /// Une touche de volume rétablit le son ; la touche muet bascule.
    func applying(_ key: HUDKey, fine: Bool) -> VolumeLevel {
        let step = fine ? LevelStep.fine : LevelStep.normal
        switch key {
        case .mute:
            return VolumeLevel(level: level, isMuted: !isMuted)
        case .volumeUp:
            return VolumeLevel(level: LevelStep.next(from: level, up: true, step: step), isMuted: false)
        case .volumeDown:
            return VolumeLevel(level: LevelStep.next(from: level, up: false, step: step), isMuted: false)
        case .brightnessUp, .brightnessDown:
            return self
        }
    }
}

/// Ce que le HUD affiche.
struct HUDState: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case volume
        case brightness
    }

    var kind: Kind
    var level: Double
    var isMuted = false
    /// Faux quand la sortie audio ne permet pas de régler le volume (HDMI, certaines cartes son).
    var isAvailable = true

    var displayedLevel: Double {
        isMuted || !isAvailable ? 0 : level
    }

    var symbolName: String {
        switch kind {
        case .volume:
            guard isAvailable, !isMuted, level > 0 else { return "speaker.slash.fill" }
            if level < 1.0 / 3 { return "speaker.wave.1.fill" }
            if level < 2.0 / 3 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        case .brightness:
            return level < 0.5 ? "sun.min.fill" : "sun.max.fill"
        }
    }
}
