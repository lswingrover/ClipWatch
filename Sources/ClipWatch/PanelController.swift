import AppKit

// MARK: - PanelController
// Manages the floating search panel. Borderless, non-activating, dismisses on blur.

final class PanelController {
    private var panel: NSPanel?
    private var searchVC: SearchViewController?

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        if panel == nil { buildPanel() }
        position()
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        searchVC?.prepareForDisplay()
    }

    func hide() {
        panel?.orderOut(nil)
        searchVC?.reset()
    }

    // MARK: - Build

    private func buildPanel() {
        let vc = SearchViewController()
        vc.onPaste = { [weak self] content in
            self?.hide()
            // Small delay lets the previous app regain focus before we simulate ⌘V
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                AppDelegate.shared?.paste(content)
            }
        }
        vc.onDismiss = { [weak self] in self?.hide() }
        searchVC = vc

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.contentViewController = vc
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isMovableByWindowBackground = false

        // Dismiss when panel loses key status
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelResignedKey),
            name: NSWindow.didResignKeyNotification,
            object: p
        )
        panel = p
    }

    @objc private func panelResignedKey() { hide() }

    // MARK: - Positioning

    private func position() {
        guard let panel else { return }
        let screen = targetScreen()
        let sf = screen.visibleFrame
        let pw = panel.frame.width
        let ph = panel.frame.height
        let x = sf.midX - pw / 2
        let y = sf.midY + sf.height * 0.08   // slightly above centre
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func targetScreen() -> NSScreen {
        if Prefs.screenMode() == "cursor" {
            return screenAtCursor() ?? NSScreen.main ?? NSScreen.screens[0]
        }
        // "activeApp": use NSScreen.main which follows the frontmost app's display
        return NSScreen.main ?? NSScreen.screens[0]
    }

    private func screenAtCursor() -> NSScreen? {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) }
    }
}
