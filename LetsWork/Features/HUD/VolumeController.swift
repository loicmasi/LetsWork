import AudioToolbox
import CoreAudio

/// Volume et sourdine de la sortie audio par défaut, via Core Audio.
/// Signale aussi les changements faits ailleurs (Centre de contrôle, AirPods, autre app).
@MainActor
final class VolumeController {
    /// Appelé quand le volume, la sourdine ou la sortie par défaut change.
    var onChange: ((HUDState) -> Void)?

    private var device = AudioObjectID(kAudioObjectUnknown)
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var volumeListener: AudioObjectPropertyListenerBlock?

    private static var defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private static var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    private static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    func start() {
        guard deviceListener == nil else { return }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.defaultDeviceDidChange()
            }
        }
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.defaultOutputAddress, .main, listener)
        deviceListener = listener
        observe(Self.defaultOutputDevice())
    }

    func stop() {
        if let deviceListener {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.defaultOutputAddress, .main, deviceListener)
        }
        deviceListener = nil
        observe(AudioObjectID(kAudioObjectUnknown))
    }

    var state: HUDState {
        guard let level = read(Self.volumeAddress, initial: Float32(0)), isSettable(Self.volumeAddress) else {
            return HUDState(kind: .volume, level: 0, isAvailable: false)
        }
        let isMuted = (read(Self.muteAddress, initial: UInt32(0)) ?? 0) != 0
        return HUDState(kind: .volume, level: Double(level), isMuted: isMuted)
    }

    /// Applique la touche et renvoie l'état à afficher, ou `nil` si Core Audio a refusé le changement.
    func apply(_ key: HUDKey, fine: Bool) -> HUDState? {
        let current = state
        guard current.isAvailable else { return current }
        let next = VolumeLevel(level: current.level, isMuted: current.isMuted).applying(key, fine: fine)
        if next.level != current.level, !write(Float32(next.level), Self.volumeAddress) {
            return nil
        }
        if next.isMuted != current.isMuted, isSettable(Self.muteAddress) {
            guard write(UInt32(next.isMuted ? 1 : 0), Self.muteAddress) else { return nil }
        }
        return HUDState(kind: .volume, level: next.level, isMuted: next.isMuted)
    }

    private func defaultDeviceDidChange() {
        observe(Self.defaultOutputDevice())
        onChange?(state)
    }

    private func observe(_ newDevice: AudioObjectID) {
        if let volumeListener, device != kAudioObjectUnknown {
            AudioObjectRemovePropertyListenerBlock(device, &Self.volumeAddress, .main, volumeListener)
            AudioObjectRemovePropertyListenerBlock(device, &Self.muteAddress, .main, volumeListener)
        }
        device = newDevice
        volumeListener = nil
        guard device != kAudioObjectUnknown else { return }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.onChange?(self.state)
            }
        }
        AudioObjectAddPropertyListenerBlock(device, &Self.volumeAddress, .main, listener)
        AudioObjectAddPropertyListenerBlock(device, &Self.muteAddress, .main, listener)
        volumeListener = listener
    }

    private static func defaultOutputDevice() -> AudioObjectID {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultOutputAddress, 0, nil, &size, &device)
        return status == noErr ? device : AudioObjectID(kAudioObjectUnknown)
    }

    private func read<Value>(_ address: AudioObjectPropertyAddress, initial: Value) -> Value? {
        var address = address
        guard device != kAudioObjectUnknown, AudioObjectHasProperty(device, &address) else { return nil }
        var value = initial
        var size = UInt32(MemoryLayout<Value>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private func write<Value>(_ value: Value, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        var value = value
        let size = UInt32(MemoryLayout<Value>.size)
        return AudioObjectSetPropertyData(device, &address, 0, nil, size, &value) == noErr
    }

    private func isSettable(_ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        var settable: DarwinBoolean = false
        guard device != kAudioObjectUnknown, AudioObjectHasProperty(device, &address) else { return false }
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }
}
