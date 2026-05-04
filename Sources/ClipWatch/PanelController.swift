import AppKit

// MARK: - PanelController
//
// Manages the floating search panel.
//
// Focus strategy:
//   NSApp.activate IS called so the panel reliably receives keyboard events.
//   Before activating, the current frontmost app is captured in `previousApp`.
//   When the user pastes OR dismisses with Esc, we re-activate `previousApp`
//   so focus returns to the right text field.
//
//   makeFirstResponder is attempted twice: once async after makeKeyAndOrderFront,
//   and again when NSWindow.didBecomeKeyNotification fires. The notification path
//   is the reliable one — by the time it fires, the window is definitely key and
//   the field editor can be installed correctly.
//
// Dismiss strategy (belt-and-suspenders):
//   1. Global mouse monitor — catches clicks anywhere outside the panel,
//      including on the desktop where no app-switch occurs.
//   2. NSApplication.didResignActiveNotification — catches switching to
//      another app via Cmd-Tab, Dock click, etc.

final class PanelController {
    private var panel:        NSPanel?
    private var searchVC:     SearchViewController?
    private var clickMonitor: Any?                   // global mouse-down monitor
    private var previousApp:  NSRunningApplication?  // app that owned focus before panel

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() { isVisible ? hide() : show() }

    // MARK: - Show / Hide

    func show() {
        if panel == nil { buildPanel() }

        // Snapshot whoever has focus RIGHT NOW before we steal it.
        previousApp = NSWorkspace.shared.frontmostApplication

        position()
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // First attempt — may still be in flight when NSApp.activate is settling.
        // The didBecomeKeyNotification handler below is the reliable backstop.
        DispatchQueue.main.async { [weak self] in
            self?.searchVC?.prepareForDisplay()
        }

        // Global click monitor: any mouse-down outside the panel → dismiss
        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            self?.hide()
        }
    }

    func hide() {
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
        panel?.orderOut(nil)
        searchVC?.reset()
    }

    // MARK: - Build

    private func buildPanel() {
        let vc = SearchViewController()

        vc.onPaste = { [weak self] content in
            guard let self else { return }
            let target = self.previousApp
            self.hide()
            // Re-activate the previous app first, then fire ⌘V into it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                target?.activate(options: .activateIgnoringOtherApps)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                    AppDelegate.shared?.paste(content)
                }
            }
        }

        vc.onDismiss = { [weak self] in
            guard let self else { return }
            let target = self.previousApp
            self.hide()
            // Return focus to wherever the user was before invoking the panel.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                target?.activate(options: .activateIgnoringOtherApps)
            }
        }

        searchVC = vc

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 440),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.contentViewController = vc
        p.isOpaque              = false
        p.backgroundColor       = .clear
        p.hasShadow             = true
        p.level                 = .floating
        p.hidesOnDeactivate     = false
        p.isMovableByWindowBackground = true

        // Reliable focus: fire makeFirstResponder once the window is actually key.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey),
            name: NSWindow.didBecomeKeyNotification,
            object: p
        )

        // Dismiss when another app activates (Cmd-Tab, Dock click, etc.)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDeactivated),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
        panel = p
    }

    /// Called when the panel is definitely the key window — safe to focus the search field.
    @objc private func windowDidBecomeKey() {
        searchVC?.focusSearchField()
    }

    @objc private func appDeactivated() { hide() }

    // MARK: - Positioning

    private func position() {
        guard let panel else { return }
        let screen = targetScreen()
        let sf     = screen.visibleFrame
        let x = sf.midX - panel.frame.width / 2
        let y = sf.midY + sf.height * 0.10
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func targetScreen() -> NSScreen {
        if Prefs.screenMode() == "cursor" {
            let pt = NSEvent.mouseLocation
            return NSScreen.screens.first { NSMouseInRect(pt, $0.frame, false) }
                ?? NSScreen.main ?? NSScreen.screens[0]
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }
}
