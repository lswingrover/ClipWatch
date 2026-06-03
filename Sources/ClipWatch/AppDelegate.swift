import AppKit
import ClipWatchCore

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Accessible from PanelController's paste callback
    static weak var shared: AppDelegate?

    private let store     = ClipStore.shared
    private let apiServer = ClipWatchAPIServer()
    let monitor           = ClipboardMonitor()
    private let hotkey    = HotkeyManager()
    private let panel     = PanelController()

    private var statusItem:       NSStatusItem!
    private var pendingUpdate:    UpdateInfo?
    private var menuRebuildTimer: Timer?

    // MARK: - Launch

    func applicationDidFinishLaunching(_ note: Notification) {
        AppDelegate.shared = self
        setupStatusItem()
        monitor.start()
        hotkey.onActivate = { [weak self] in self?.panel.toggle() }
        hotkey.start()

        // Clipboard + update notifications
        NotificationCenter.default.addObserver(self, selector: #selector(rebuildMenu),
            name: .clipStoreDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateAvailable(_:)),
            name: .updateAvailable, object: nil)

        // Lock state → update icon + menu
        NotificationCenter.default.addObserver(self, selector: #selector(didLock),
            name: .clipWatchDidLock, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didUnlock),
            name: .clipWatchDidUnlock, object: nil)

        // Screen sleep / wake — ties ClipWatch to the system lock cycle,
        // matching the 1Password "Lock when device locks or sleeps" behaviour.
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(screenDidSleep),
            name: NSWorkspace.screensDidSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(screenDidWake),
            name: NSWorkspace.screensDidWakeNotification, object: nil)
        // Fast user switching
        ws.addObserver(self, selector: #selector(screenDidSleep),
            name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        ws.addObserver(self, selector: #selector(screenDidWake),
            name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)

        UpdateChecker.checkInBackground()
        apiServer.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        apiServer.stop()
    }

    // MARK: - Screen sleep / wake

    @objc private func screenDidSleep() {
        guard Prefs.lockOnSleepEnabled() else { return }
        LockManager.shared.lock()
    }

    @objc private func screenDidWake() {
        // Silently re-unlock if the keychain token is still readable and the
        // unlock window has not expired — same pattern as 1Password on wake.
        LockManager.shared.checkKeychainUnlock()
    }

    // MARK: - Lock state → UI

    @objc private func didLock()   { updateStatusIcon(); rebuildMenu() }
    @objc private func didUnlock() { updateStatusIcon(); rebuildMenu() }

    private func updateStatusIcon() {
        let isLocked = Prefs.isSecureModeEnabled() && LockManager.shared.isLocked
        let name = isLocked ? "lock.fill" : "doc.on.clipboard"
        statusItem.button?.image = NSImage(systemSymbolName: name,
                                           accessibilityDescription: "ClipWatch")
        statusItem.button?.image?.isTemplate = true
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon()
        buildMenu()
    }

    @objc func rebuildMenu() {
        menuRebuildTimer?.invalidate()
        menuRebuildTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
            self?.buildMenu()
        }
    }

    private func buildMenu() {
        let menu   = NSMenu()
        let locked = Prefs.isSecureModeEnabled() && LockManager.shared.isLocked

        // Update banner
        if let update = pendingUpdate {
            let item = NSMenuItem(title: "⬆ Update available: v\(update.tagName)",
                                  action: #selector(openUpdatePage), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            menu.addItem(.separator())
        }

        if locked {
            // ── Locked state ──────────────────────────────────────────────
            let lockLabel = NSMenuItem(title: "ClipWatch is Locked", action: nil, keyEquivalent: "")
            lockLabel.isEnabled = false
            menu.addItem(lockLabel)

            let unlockItem = NSMenuItem(title: "Unlock…",
                                        action: #selector(unlockFromMenu),
                                        keyEquivalent: "")
            unlockItem.target = self
            menu.addItem(unlockItem)
        } else {
            // ── Unlocked: show clips ───────────────────────────────────────
            let clips = store.recent(limit: Prefs.menuCount())
            for clip in clips {
                let preview = clip.content
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                    .prefix(60)
                let item = NSMenuItem(
                    title:  String(preview),
                    action: #selector(menuClipClicked(_:)),
                    keyEquivalent: ""
                )
                item.representedObject = clip.content
                item.target = self
                if clip.pinned {
                    item.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: nil)
                }
                menu.addItem(item)
            }
            if clips.isEmpty {
                let empty = NSMenuItem(title: "No clips yet", action: nil, keyEquivalent: "")
                empty.isEnabled = false
                menu.addItem(empty)
            }
        }

        menu.addItem(.separator())

        // Lock Now — only when secure mode is on and currently unlocked
        if Prefs.isSecureModeEnabled() && !locked {
            let lockItem = NSMenuItem(title: "Lock Now",
                                      action: #selector(lockNow),
                                      keyEquivalent: "l")
            lockItem.keyEquivalentModifierMask = [.command, .shift]
            lockItem.target = self
            menu.addItem(lockItem)
            menu.addItem(.separator())
        }

        if !locked {
            let clearItem = NSMenuItem(title: "Clear History…",
                                       action: #selector(clearAllHistory),
                                       keyEquivalent: "")
            clearItem.target = self
            menu.addItem(clearItem)
            menu.addItem(.separator())
        }

        let prefs = NSMenuItem(title: "Preferences…",
                               action: #selector(openPreferences), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)

        let ghItem = NSMenuItem(title: "View on GitHub",
                                action: #selector(openGitHub), keyEquivalent: "")
        ghItem.target = self
        menu.addItem(ghItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit ClipWatch",
                     action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        statusItem.menu = menu
    }

    // MARK: - Menu actions

    @objc private func menuClipClicked(_ sender: NSMenuItem) {
        guard let content = sender.representedObject as? String else { return }
        LockManager.shared.touchActivity()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.paste(content)
        }
    }

    @objc private func lockNow() {
        LockManager.shared.lock()
    }

    @objc private func unlockFromMenu() {
        LockManager.shared.tryUnlock(reason: "Unlock ClipWatch clipboard history") { [weak self] success in
            if success { self?.rebuildMenu() }
        }
    }

    @objc private func updateAvailable(_ note: Notification) {
        pendingUpdate = note.object as? UpdateInfo
        buildMenu()
    }

    @objc private func openGitHub() {
        guard let url = URL(string: "https://github.com/lswingrover/clipwatch") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openUpdatePage() {
        if let url = pendingUpdate?.releaseURL {
            NSWorkspace.shared.open(url)
        } else {
            UpdateChecker.openReleasePage()
        }
    }

    @objc private func clearAllHistory() {
        let alert = NSAlert()
        alert.messageText     = "Clear all clipboard history?"
        alert.informativeText = "This permanently deletes all clips. Pinned items are also removed. This cannot be undone."
        alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.deleteAll()
    }

    @objc private func openPreferences() {
        PreferencesWindowController.shared.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Paste

    func paste(_ content: String) {
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(content, forType: .string) else {
            print("ClipWatch: pasteboard write failed — aborting paste")
            return
        }
        let src     = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9
        guard
            let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true),
            let up   = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags   = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
