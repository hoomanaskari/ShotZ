import Carbon.HIToolbox
import ShotzCore

/// Where `HotkeyCenter` registers shortcuts. The Carbon implementation is the
/// real one; tests inject a fake so they can simulate failures and never
/// register global shortcuts that could collide with a running Shotz.
@MainActor protocol HotkeyRegistrar: AnyObject {
    /// Registers `combo` under `id`; returns `noErr` or the Carbon status.
    func register(_ combo: KeyCombo, id: UInt32) -> OSStatus
    func unregister(id: UInt32)
}

@MainActor final class CarbonHotkeyRegistrar: HotkeyRegistrar {
    private var refs: [UInt32: EventHotKeyRef] = [:]

    func register(_ combo: KeyCombo, id: UInt32) -> OSStatus {
        unregister(id: id)
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: HotkeyCenter.signature, id: id)
        let status = RegisterEventHotKey(
            combo.keyCode, HotkeyCenter.carbonModifiers(combo.modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref
        )
        if status == noErr, let ref {
            refs[id] = ref
            return noErr
        }
        return status == noErr ? OSStatus(eventInternalErr) : status
    }

    func unregister(id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
    }
}
