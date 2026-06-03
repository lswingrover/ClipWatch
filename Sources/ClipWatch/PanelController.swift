import AppKit
import LocalAuthentication
import ClipWatchCore

// MARK: - PanelController
//
// Manages the floating search panel.
//
// Lock/unlock delegates to LockManager.shared. When secure mode is ON:
//   - show() checks LockManager.isLocked; if locked, calls tryUnlock() first.
//   - clipWatchDidLock notification hides the panel immediately if open.
// When secure mode is OFF:
//   - Panel always opens with isAuthenticated = false.
//   - Sensitive clips render as lock cards; pressing Return calls authenticateForClip().
//
// GH: lswingrover/clipwatch#2

private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool  { true  }
    override var canBecomeMain: Bool { false }
}

final class PanelController {
    private var panel:        NSPanel?
    private var searchVC:     SearchViewController?
    private var clickMonitor: Any?
    private var previousApp:  NSRunningApplication?

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() { isVisible ? hide() : show() }

    // MARK: - Show / Hide

    func show() {
        if panel == nil { buildPanel() }
        previousApp = NSWorkspace.shared.frontmostApplication
        LockManager.shared.touchActivity()

        if Prefs.isSecureModeEnabled() {
            if !LockManager.shared.isLocked {
                presentPanel()
            } else {
                LockManager.shared.tryUnlock(
                    reason: "Unlock ClipWatch clipboard history"
                ) { [weak self] success in
                    if success { self?.presentPanel() }
                }
            }
        } else {
            presentPanel()
        }
    }

    func hide() {
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
        panel?.orderOut(nil)
        searchVC?.reset()
        // LockManager owns lock state — do NOT reset it here.
    }

    // MARK: - Per-clip authentication (secure mode OFF only)

    func authenticateForClip(completion: @escaping (Bool) -> Void) {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            completion(true); return
        }
        ctx.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "View sensitive clipboard item"
        ) { success, _ in
            DispatchQueue.main.async { completion(success) }
        }
    }

    // MARK: - Present

    private var isAuthenticated: Bool {
        Prefs.isSecureModeEnabled() && !LockManager.shared.isLocked
    }

    private func presentPanel() {
        position()
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
        searchVC?.prepareForDisplay(isAuthenticated: isAuthenticated)
        DispatchQueue.main.async { [weak self] in
            self?.searchVC?.focusSearchField()
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in self?.hide() }
    }

    // MARK: - Build

    private func buildPanel() {
        let vc = SearchViewController()

        vc.onPaste = { [weak self] content in
            guard let self else { return }
            let target = self.previousApp
            self.hide()
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                target?.activate(options: .activateIgnoringOtherApps)
            }
        }

        vc.onAuthNeeded = { [weak self] completion in
            self?.authenticateForClip { _ in completion() }
        }

        searchVC = vc

        let p = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 440),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.contentViewController       = vc
        p.isOpaque                    = false
        p.backgroundColor             = .clear
        p.hasShadow                   = true
        p.level                       = .floating
        p.hidesOnDeactivate           = false
        p.isMovableByWindowBackground = true

        NotificationCenter.default.addObserver(self, selector: #selector(windowDidBecomeKey),
            name: NSWindow.didBecomeKeyNotification, object: p)
        NotificationCenter.default.addObserver(self, selector: #selector(appDeactivated),
            name: NSApplication.didResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didLock),
            name: .clipWatchDidLock, object: nil)

        panel = p
    }

    @objc private func windowDidBecomeKey() { searchVC?.focusSearchField() }
    @objc private func appDeactivated()     { hide() }
    @objc private func didLock()            { if isVisible { hide() } }

    // MARK: - Positioning

    private func position() {
        guard let panel else { return }
        guard let screen = targetScreen() else { return }
        let sf = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: sf.midX - panel.frame.width / 2,
                                     y: sf.midY + sf.height * 0.10))
    }

    private func targetScreen() -> NSScreen? {
        screenForApp(previousApp) ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func screenForApp(_ app: NSRunningApplication?) -> NSScreen? {
        guard let app else { return nil }
        let pid = app.processIdentifier
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return nil }
        let screenMaxY = NSScreen.screens.map { $0.frame.maxY }.max() ?? 0
        for win in list {
            guard (win[kCGWindowOwnerPID as String] as? Int32) == Int32(pid),
                  let b  = win[kCGWindowBounds as String] as? [String: CGFloat],
                  let wx = b["X"], let wy = b["Y"],
                  let ww = b["Width"], let wh = b["Height"],
                  ww > 0, wh > 0 else { continue }
            let pt = NSPoint(x: wx + ww / 2, y: screenMaxY - (wy + wh / 2))
            if let scr = NSScreen.screens.first(where: { $0.frame.contains(pt) }) { return scr }
        }
        return nil
    }
}
