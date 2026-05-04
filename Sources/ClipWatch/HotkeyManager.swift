import AppKit

// MARK: - HotkeyManager
//
// Detects the configured global hotkey using NSEvent.addGlobalMonitorForEvents.
//
// Accessibility permission requirement:
//   Apple requires Accessibility access for apps to monitor key events in OTHER
//   applications. Without it, addGlobalMonitorForEvents returns nil and no
//   events are delivered. The app degrades gracefully — clipboard capture and
//   the menu bar still work; only the hotkey and auto-paste are disabled.
//
// Why not Carbon RegisterEventHotKey?
//   Carbon hotkeys work without Accessibility, but the API is formally
//   deprecated and Carbon itself is not guaranteed to survive future OS changes.
//   NSEvent is the documented modern path.
//
// Modifier flag note:
//   event.modifierFlags must be masked with .deviceIndependentFlagsMask before
//   comparison. Without the mask, bits from capslock, numpad, and function keys
//   leak in and cause false negatives on some keyboards.

final class HotkeyManager {
    var onActivate: (() -> Void)?
    private var monitor: Any?

    func start() {
        registerMonitor()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotkeyChanged),
            name: .hotkeyChanged,
            object: nil
        )
    }

    func stop() {
        removeMonitor()
        NotificationCenter.default.removeObserver(self)
    }

    private func registerMonitor() {
        guard AXIsProcessTrusted() else {
            promptForAccessibility()
            return
        }
        removeMonitor()
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
        }
    }

    private func removeMonitor() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) {
        let targetKey  = Prefs.hotkeyVirtualKey()
        let targetMods = Prefs.hotkeyModifierFlags()

        let eventMods = Int(event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .rawValue)
        let eventKey  = Int(event.keyCode)

        guard eventKey == targetKey, eventMods == targetMods else { return }
        DispatchQueue.main.async { self.onActivate?() }
    }

    @objc private func hotkeyChanged() {
        registerMonitor()
    }

    private func promptForAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        AXIsProcessTrustedWithOptions(opts as CFDictionary)
    }
}
