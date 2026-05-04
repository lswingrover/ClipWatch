# ClipWatch

A fast, keyboard-driven clipboard history manager for macOS. Lives in the menu bar. Zero dependencies. Built to last.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange) ![License](https://img.shields.io/badge/license-MIT-green)

## What it does

ClipWatch silently records everything you copy as plain text. When you need something from your clipboard history, one shortcut opens a searchable panel — type to filter across your full history, arrow to the item you want, hit Enter. It pastes immediately.

Pinned items always float to the top. Passwords from 1Password and other credential managers are silently excluded.

## Install

```bash
git clone https://github.com/lswingrover/clipwatch
cd clipwatch
./build_app.sh
```

The script builds, assembles the `.app` bundle, installs to `~/Applications`, and launches ClipWatch. On first launch, macOS will prompt for Accessibility access — grant it. That permission is required for the global shortcut and the automatic paste.

## Usage

| Action | How |
|---|---|
| Open panel | `⌥⌘V` (configurable) |
| Navigate list | `↑` / `↓` |
| Paste selected | `↩` |
| Filter | Just start typing |
| Pin / unpin | `⌘P` |
| Delete | `⌘⌫` |
| Dismiss | `Esc` or click outside |
| Paste from menu bar | Click the clipboard icon → click any item |

## Preferences

Open via the menu bar icon → **Preferences…** (or `⌘,`).

- **Hotkey** — click the field, press your desired shortcut
- **Recent items in menu** — how many clips appear in the menu bar dropdown (5–25, default 10)
- **History retention** — how many days to keep (30–730, default 365)
- **Panel appears on** — active app's screen or the screen with your cursor
- **Launch at login** — start ClipWatch automatically
- **Never capture from these apps** — bundle IDs excluded from history. Pre-seeded with 1Password variants. Add any password manager or sensitive app here.

## Storage

History is stored at `~/Library/Application Support/ClipWatch/clips.db` — a plain SQLite database. You can open it with any SQLite browser. Backups happen automatically with Time Machine. The database is capped at 50,000 items and your configured retention period; older unpinned clips are pruned silently on launch.

## Building from source

Requirements: macOS 13+, Xcode Command Line Tools (`xcode-select --install`).

```bash
# Development build (faster, unoptimized)
./build_app.sh --debug

# Build without installing
./build_app.sh --no-install

# Compile check only
swift build
```

No package manager, no third-party dependencies, no Xcode project file. The entire app is six Swift files and a Package.swift.

## Architecture

```
Sources/ClipWatch/
  main.swift                     Entry point — NSApplication setup
  AppDelegate.swift              Status item, menu bar, paste via CGEvent
  ClipStore.swift                SQLite via import SQLite3, FTS5 search
  ClipboardMonitor.swift         NSPasteboard polling (0.5 s timer)
  HotkeyManager.swift            NSEvent global monitor, Accessibility check
  PanelController.swift          Floating NSPanel, screen positioning
  SearchViewController.swift     Search field + table + ClipCellView
  PreferencesWindowController.swift  All user settings + ShortcutRecorderField
  Prefs.swift                    UserDefaults keys and defaults
```

The clipboard monitor polls `NSPasteboard.general.changeCount` every 500 ms. There is no push API for clipboard changes on macOS — polling is the standard approach used by every clipboard manager on the platform.

FTS5 is built into the SQLite that ships with macOS. Prefix search (e.g. `hel` finds `hello`) is enabled with a `*` wildcard appended to the query.

Paste is simulated by posting a `CGEvent` for `⌘V` after placing the selected text on `NSPasteboard.general`. A 120 ms delay ensures the previous app has regained focus before the keystroke fires.

## Privacy

ClipWatch runs entirely on your Mac. Nothing leaves your machine. The clipboard database is a local SQLite file. Apps in the exclusion list (Preferences → Never capture from…) are filtered at insert time — their clipboard contents never touch the database.

## License

MIT. See [LICENSE](LICENSE).

---

Part of the [*Watch suite](https://github.com/lswingrover): MacWatch · NetWatch · NarWatch · VolleyWatch · ClipWatch.
