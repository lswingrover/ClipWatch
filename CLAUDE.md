# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
# Build (requires macOS 13+ SDK via Xcode Command Line Tools)
swift build

# Build + assemble .app + install to ~/Applications + launch
./build_app.sh

# Debug build (faster compile, unoptimized)
./build_app.sh --debug

# Build without installing (output at /tmp/ClipWatch.app)
./build_app.sh --no-install

# Clean
swift package clean
```

No Xcode project file — SPM only. `open Package.swift` to open in Xcode if needed.

The app installs to `~/Applications/ClipWatch.app`, not `/Applications/`. The build script handles icon generation, ad-hoc signing, Launch Services registration, and launch.

## Architecture

ClipWatch is a macOS 13+ AppKit menu bar app. Entry point is `main.swift` (SPM executable target). No SwiftUI, no third-party dependencies, zero external packages.

**Data flow:**
```
NSPasteboard (polled 0.5s) → ClipboardMonitor → ClipStore.insert()
                                                       ↓
                                              SQLite clips table
                                              SQLite clips_fts (FTS5)
                                                       ↓
HotkeyManager (global ⌥⌘V) → PanelController.show()
                                       ↓
                             SearchViewController
                             NSTextField (search) + NSTableView (clips)
                                       ↓ Enter
                             AppDelegate.paste(content)
                             CGEvent ⌘V → frontmost app
```

**Files and responsibilities:**

- `main.swift` — Creates NSApplication, sets `.accessory` policy, assigns AppDelegate, calls `app.run()`
- `AppDelegate.swift` — Owns `NSStatusItem`, builds the menu bar menu, wires all components together, implements `paste()` via CGEvent simulation
- `ClipStore.swift` — All SQLite operations. FTS5 virtual table with content triggers for search. `insert/search/recent/togglePin/delete`. Exclusion list checked at insert time
- `ClipboardMonitor.swift` — 0.5s `Timer` polling `NSPasteboard.general.changeCount`. Posts `clipStoreDidChange` notification on new content
- `HotkeyManager.swift` — `NSEvent.addGlobalMonitorForEvents` for global key detection. Checks `AXIsProcessTrusted()` and prompts if needed. Refreshes on `hotkeyChanged` notification
- `PanelController.swift` — `NSPanel` with `.borderless .nonactivatingPanel`. Positions on active app's screen or cursor screen per `Prefs.screenMode()`. Dismisses on `NSWindow.didResignKeyNotification`
- `SearchViewController.swift` — `NSTextField` delegate intercepts ↑↓/Enter/Esc/⌘P/⌘⌫. Table view never takes focus. `ClipCellView` renders one-liner preview + relative timestamp + pin indicator
- `PreferencesWindowController.swift` — `NSWindowController` singleton. Contains `ShortcutRecorderField` (custom `NSTextField` subclass that captures key combos and saves to UserDefaults)
- `Prefs.swift` — All `UserDefaults` keys, defaults, and typed accessors. Single source of truth for preference keys

**Key design decisions:**
- `NSPasteboard` has no push notification API on macOS — polling is the only option and is used by all clipboard managers
- The paste flow: hide panel → 120ms delay → place content on `NSPasteboard.general` → post CGEvent `⌘V` to `cghidEventTap`. The delay is critical: without it, ClipWatch's panel window may still be frontmost when the keystroke fires
- FTS5 prefix search: query is wrapped as `"<escaped>"*` to match word prefixes without matching mid-word
- `NSScreen.main` reliably follows the frontmost app's display when "Displays have separate Spaces" is enabled (macOS default). This is used for "active app" screen mode
- Global exclusion list is checked at insert time in `ClipStore.insert()`, not at display time — excluded content never touches the database

**Storage:**
`~/Library/Application Support/ClipWatch/clips.db`
- `clips` table: id, content (TEXT), ts (INTEGER unix timestamp), pinned (INTEGER 0/1), source (TEXT bundle ID)
- `clips_fts` virtual table: FTS5 content table backed by `clips`, maintained by INSERT/UPDATE/DELETE triggers
- WAL journal mode enabled
- Pruned on launch: items older than `retentionDays` (default 365) and items beyond 50,000 unpinned are deleted

**Notifications used (all on `NotificationCenter.default`):**
- `.clipStoreDidChange` — posted by `ClipboardMonitor` and by pin/delete actions in `SearchViewController`; observed by `AppDelegate` to rebuild the menu
- `.hotkeyChanged` — posted by `ShortcutRecorderField` when user records a new shortcut; observed by `HotkeyManager` to re-register the global monitor

**Accessibility permission:**
Required for both `NSEvent.addGlobalMonitorForEvents` (key monitoring) and `CGEvent` (paste simulation). `HotkeyManager.start()` calls `AXIsProcessTrusted()` and falls back to `AXIsProcessTrustedWithOptions` with `kAXTrustedCheckOptionPrompt: true` if not granted. The app degrades gracefully — clipboard capture and menu bar still work without it; only the hotkey and auto-paste are disabled.
