import AppKit
import Observation
import os

private let logger = Logger(subsystem: "dev.projects.letswork", category: "hud")

/// Remplace les indicateurs de volume et de luminosité de macOS : intercepte les touches, applique
/// le changement et annonce l'état à afficher dans l'Island.
@MainActor
@Observable
final class HUDService {
    static let enabledKey = "hudEnabled"

    private(set) var isAccessibilityGranted = AccessibilityPermission.isGranted
    /// Vrai quand les touches passent réellement par LetsWork.
    private(set) var isIntercepting = false

    /// Préférence utilisateur ; sans autorisation Accessibilité, le HUD natif reste affiché.
    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            updateInterception()
        }
    }

    /// Appelé à chaque état à afficher (touche pressée ou volume changé ailleurs).
    @ObservationIgnored var onShow: ((HUDState) -> Void)?

    @ObservationIgnored private let volume = VolumeController()
    @ObservationIgnored private let brightness = BrightnessController()
    @ObservationIgnored private var tap: MediaKeyTap?
    @ObservationIgnored private var permissionObserver: NSObjectProtocol?
    @ObservationIgnored private var permissionPolling: Task<Void, Never>?

    init() {
        isEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    func start() {
        volume.onChange = { [weak self] state in
            guard let self, self.isIntercepting else { return }
            self.onShow?(state)
        }
        volume.start()
        permissionObserver = DistributedNotificationCenter.default().addObserver(
            forName: AccessibilityPermission.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.watchPermission()
            }
        }
        updateInterception()
    }

    func stop() {
        tap?.stop()
        tap = nil
        volume.stop()
        permissionPolling?.cancel()
        if let permissionObserver {
            DistributedNotificationCenter.default().removeObserver(permissionObserver)
        }
        permissionObserver = nil
    }

    /// Affiche la demande système, puis surveille l'autorisation jusqu'à ce qu'elle soit accordée.
    func requestAccessibility() {
        AccessibilityPermission.request()
        watchPermission()
    }

    private func updateInterception() {
        isAccessibilityGranted = AccessibilityPermission.isGranted
        defer { isIntercepting = tap?.isRunning == true }
        guard isEnabled, isAccessibilityGranted else {
            if tap != nil {
                logger.notice("Interception des touches arrêtée")
            }
            tap?.stop()
            tap = nil
            return
        }
        guard tap == nil else { return }
        let tap = MediaKeyTap { [weak self] press in
            self?.handle(press) ?? false
        }
        if tap.start() {
            self.tap = tap
            logger.notice("Interception des touches active")
        } else {
            logger.error("Impossible de créer l'event tap malgré l'autorisation Accessibilité")
        }
    }

    /// La base des autorisations est mise à jour en différé : on revérifie quelques secondes.
    private func watchPermission() {
        permissionPolling?.cancel()
        permissionPolling = Task { [weak self] in
            for _ in 0..<60 {
                guard let self, !Task.isCancelled else { return }
                self.updateInterception()
                if self.isAccessibilityGranted { return }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Renvoie `true` pour absorber l'événement ; `false` laisse macOS le traiter normalement.
    private func handle(_ press: MediaKeyPress) -> Bool {
        guard isEnabled, !press.opensSystemSettings else { return false }

        if press.key.isVolume {
            guard press.isDown else { return true }
            guard let state = volume.apply(press.key, fine: press.isFineStep) else { return false }
            onShow?(state)
            if !press.isRepeat {
                VolumeFeedback.playIfEnabled(for: press.key)
            }
            return true
        }

        guard brightness?.targetDisplay != nil else { return false }
        guard press.isDown else { return true }
        guard let level = brightness?.apply(press.key, fine: press.isFineStep) else { return false }
        onShow?(HUDState(kind: .brightness, level: level))
        return true
    }
}

/// Le « pop » joué par macOS à chaque changement de volume, si l'option est activée
/// (Réglages Système › Son › « Émettre un retour sonore lors du réglage du volume »).
@MainActor
enum VolumeFeedback {
    private static let sound = NSSound(
        contentsOfFile: "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff",
        byReference: true
    )

    static func playIfEnabled(for key: HUDKey) {
        guard key != .mute, UserDefaults.standard.integer(forKey: "com.apple.sound.beep.feedback") == 1 else { return }
        sound?.stop()
        sound?.play()
    }
}
