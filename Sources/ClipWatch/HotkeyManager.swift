import AppKit

// MARK: - HotkeyManager
// Monitors global key events via NSEvent. Requires Accessibility permission.
// If permission is not granted, prompts the user and does not crash.

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
