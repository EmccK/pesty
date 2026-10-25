import AppKit
import Carbon.HIToolbox

@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    var onTrigger: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let signature: OSType = 0x50535459

    private init() {}

    func start() {
        installHandlerIfNeeded()
        reload()
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            DispatchQueue.main.async { HotKeyCenter.shared.onTrigger?() }
            return noErr
        }, 1, &spec, nil, &handlerRef)
    }

    /// Bumped on every reload so an in-flight retry chain can tell it is stale.
    ///
    /// `reload()` runs from the Settings pane (twice for a single shortcut
    /// change, once per field) and from wake. A chain started by an earlier
    /// reload captured that call's key code and modifiers, and its first act is
    /// `unregister()` - which would take out whatever the *current* reload just
    /// registered. Left unchecked, a stale chain either rolls the user's new
    /// shortcut back to the old one or kills it once per retry, forever.
    private var retryGeneration = 0

    /// Re-registers the global hotkey.
    ///
    /// The old registration has to be released before the new one can take the
    /// same combination, so a failed `RegisterEventHotKey` leaves the app with
    /// no hotkey at all - unrecoverable without a relaunch, and one of the ways
    /// the bar "stops opening" (issue #64). Another process can hold the
    /// combination briefly during login or a display change, so retry instead of
    /// giving up. Nothing is restored here: `unregister()` has already released
    /// the old reference, and putting it back would hand the app a registration
    /// Carbon no longer honours.
    func reload() {
        retryGeneration &+= 1
        unregister()

        let keyCode = UInt32(Settings.shared.hotkeyKeyCode)
        let modifiers = UInt32(Settings.shared.hotkeyModifiers)
        guard keyCode != 0 else { return }

        if register(keyCode: keyCode, modifiers: modifiers) { return }

        retryRegister(keyCode: keyCode,
                      modifiers: modifiers,
                      fastAttemptsLeft: Self.fastRetries,
                      generation: retryGeneration)
    }

    private func register(keyCode: UInt32, modifiers: UInt32) -> Bool {
        let id = EventHotKeyID(signature: signature, id: 1)
        var ref: EventHotKeyRef?
        guard RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr
        else { return false }
        hotKeyRef = ref
        return true
    }

    /// How many one-second attempts come before the slow poll takes over.
    private static let fastRetries = 5

    /// Keeps trying after a transient failure instead of leaving the app deaf.
    ///
    /// A failed retry must not put the stale `EventHotKeyRef` back: that would
    /// make the app believe it holds a hotkey while Carbon holds nothing, and
    /// every later reload would unregister a dead reference.
    ///
    /// The chain is bounded by `generation`, not by an attempt count: a reload
    /// that lands mid-chain bumps the counter, and this closure then exits
    /// without touching the registration the new reload owns.
    ///
    /// Fast attempts come first because a login-time or display-change conflict
    /// usually clears in a second or two; past that the poll drops to ten
    /// seconds so a combination held by another app for hours costs nothing.
    private func retryRegister(keyCode: UInt32,
                               modifiers: UInt32,
                               fastAttemptsLeft: Int,
                               generation: Int) {
        let fast = fastAttemptsLeft > 0
        let delay = fast ? 1.0 : Self.slowRetryInterval
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.retryGeneration == generation else { return }
            self.unregister()
            if self.register(keyCode: keyCode, modifiers: modifiers) { return }
            self.retryRegister(keyCode: keyCode,
                               modifiers: modifiers,
                               fastAttemptsLeft: max(fastAttemptsLeft - 1, 0),
                               generation: generation)
        }
    }

    /// How often the chain re-checks once the fast attempts are spent.
    private static let slowRetryInterval: TimeInterval = 10

    private func unregister() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref); hotKeyRef = nil }
    }

    static func describe(keyCode: Int, modifiers: Int) -> String {
        var s = ""
        if modifiers & controlKey != 0 { s += "⌃" }
        if modifiers & optionKey  != 0 { s += "⌥" }
        if modifiers & shiftKey   != 0 { s += "⇧" }
        if modifiers & cmdKey     != 0 { s += "⌘" }
        s += keyName(for: keyCode)
        return s
    }

    static func keyName(for keyCode: Int) -> String {
        let map: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
            kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
            kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
            kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
            kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
            kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
            kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
            kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
            kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
            kVK_ANSI_8: "8", kVK_ANSI_9: "9",
            kVK_Space: "Space", kVK_Return: "↩", kVK_Escape: "⎋",
            kVK_ANSI_Period: ".", kVK_ANSI_Comma: ",", kVK_ANSI_Slash: "/"
        ]
        return map[keyCode] ?? "?"
    }
}
