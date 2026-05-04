import AppKit

// MARK: - ClipboardMonitor
// Polls NSPasteboard.general.changeCount every 0.5 s.
// There is no push API for clipboard changes on macOS — polling is the standard approach.

final class ClipboardMonitor {
    private var timer: Timer?
    private var lastChangeCount: Int

    init() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let current = NSPasteboard.general.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current

        guard let content = NSPasteboard.general.string(forType: .string),
              !content.isEmpty else { return }

        let source = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        ClipStore.shared.insert(content: content, source: source)

        NotificationCenter.default.post(name: .clipStoreDidChange, object: nil)
    }
}

extension Notification.Name {
    static let clipStoreDidChange = Notification.Name("clipStoreDidChange")
    static let hotkeyChanged      = Notification.Name("hotkeyChanged")
}
