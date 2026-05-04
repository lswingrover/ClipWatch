import AppKit

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {

    // Accessible from PanelController's paste callback
    static weak var shared: AppDelegate?

    private let store    = ClipStore.shared
    private let monitor  = ClipboardMonitor()
    private let hotkey   = HotkeyManager()
    private let panel    = PanelController()

    private var statusItem: NSStatusItem!

    // MARK: - Launch

    func applicationDidFinishLaunching(_ note: Notification) {
        AppDelegate.shared = self

        setupStatusItem()
        monitor.start()

        hotkey.onActivate = { [weak self] in self?.panel.toggle() }
        hotkey.start()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(rebuildMenu),
            name: .clipStoreDidChange,
            object: nil
        )
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            btn.image = NSImage(systemSymbolName: "doc.on.clipboard",
                                accessibilityDescription: "ClipWatch")
            btn.image?.isTemplate = true
        }
        buildMenu()
    }

    @objc func rebuildMenu() { buildMenu() }

    private func buildMenu() {
        let menu   = NSMenu()
        let clips  = store.recent(limit: Prefs.menuCount())

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
                item.image = NSImage(systemSymbolName: "pin.fill",
                                     accessibilityDescription: nil)
            }
            menu.addItem(item)
        }

        if clips.isEmpty {
            let empty = NSMenuItem(title: "No clips yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }

        menu.addItem(.separator())
        let prefs = NSMenuItem(title: "Preferences…",
                               action: #selector(openPreferences),
                               keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit ClipWatch",
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")

        statusItem.menu = menu
    }

    @objc private func menuClipClicked(_ sender: NSMenuItem) {
        guard let content = sender.representedObject as? String else { return }
        // Menu item click: dismiss menu first, then paste
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.paste(content)
        }
    }

    @objc private func openPreferences() {
        PreferencesWindowController.shared.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Paste

    /// Places `content` on the clipboard, then simulates ⌘V so it pastes
    /// into whatever app had focus before ClipWatch was invoked.
    func paste(_ content: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)

        let src     = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9   // kVK_ANSI_V
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
