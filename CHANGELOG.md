# Changelog

All notable changes to ClipWatch are documented here.  
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [1.5.4] — 2026-05-05
### Fixed
- **AppDelegate `URL(string:)!`** — guarded with `guard let`; silent pasteboard write failure
  now returns early instead of proceeding with corrupted state.
- **ClipStore `FileManager.urls().first!`** — replaced with `guard let` and temp directory
  fallback to avoid crash in sandboxed/restricted environments.
- **ClipStore `sqlite3_column_text` nil dereference** — guarded with
  `guard let rawContent = sqlite3_column_text(stmt, 1)` to skip NULL rows instead of
  passing a nil pointer to `String(cString:)` (undefined behaviour / crash).
- **PanelController `NSScreen.screens[0]`** — replaced with `.first` guard; `position()`
  guards on nil screen to avoid crash with no attached displays.
- **UpdateChecker static URL(string:)! properties** — made Optional with `guard let` checks.
- **PreferencesWindowController / SearchViewController `fatalError()` in coder inits** —
  changed to `return nil` (graceful failure instead of guaranteed crash on storyboard decode).


## [Unreleased]

---

## [1.6.0] -- 2026-06-02
### Added
- **Keychain-backed lock/unlock** -- LockManager ties ClipWatch lock state to the
  macOS user keychain via kSecAttrAccessibleWhenUnlocked, matching 1Password model.
  Token unreadable when screen is locked.
- **Touch ID / Apple Watch / Mac password** -- LAContext .deviceOwnerAuthentication
  covers all three automatically.
- **Auto-lock timer** -- fires when unlock-duration window expires.
- **Idle lock timer** -- fires after N minutes of ClipWatch inactivity.
- **Screen sleep -> auto-lock** (configurable, default on). Wake silently re-unlocks
  if keychain token still readable and unlock window has not expired.
- **Status bar icon** -- lock.fill when locked, doc.on.clipboard when unlocked.
- **Lock Now menu item** (Cmd+Shift+L).
- **Locked menu state** -- shows Unlock... instead of clips.
- **Panel hides immediately on lock** via clipWatchDidLock notification.
- **Preferences Auto-lock section** -- Lock when device locks or sleeps (checkbox,
  default on) + Lock after idle for (Never/1/5/10/30/60 min popup).
- **API**: GET /lock; locked + secureModeEnabled in /ping + /health; HTTP 423 on
  all data endpoints when locked.
- **New prefs**: lockOnSleep (Bool, default true), idleLockMinutes (Int, default 0).

---

## [1.5.3] — 2026-05-05

### Added
- **⌘A selects all text in the search field** — explicitly handled in the key
  monitor so it always targets the search field regardless of where focus is.
  Hint bar updated to document the shortcut.

---

## [1.5.2] — 2026-05-05

### Fixed
- **Search field still not receiving keyboard input** — root cause: borderless
  windows return `false` from `NSWindow.canBecomeKey` by default (only titled or
  resizable windows return `true`). `makeKeyAndOrderFront` was ordering the panel
  front but silently failing to make it key, so `makeFirstResponder` had no effect.
  Fixed by subclassing `NSPanel` as `KeyablePanel` and overriding
  `canBecomeKey → true` / `canBecomeMain → false`.

---

## [1.5.1] — 2026-05-05

### Fixed
- **Search field focus not acquired** — `NSApp.activate` was called *after*
  `makeKeyAndOrderFront`, so `windowDidBecomeKey` fired while the app was still
  inactive and `makeFirstResponder` silently failed. Since the window was already
  key when `activate` completed, `didBecomeKeyNotification` never re-fired.
  Fixed by calling `NSApp.activate(ignoringOtherApps: true)` *before*
  `makeKeyAndOrderFront`, and adding a belt-and-suspenders
  `DispatchQueue.main.async` focus call one runloop pass later.

---

## [1.5.0] — 2026-05-05

### Fixed
- **Search panel not accepting keyboard input** — `NSPanel` was created with `.nonactivatingPanel`
  in the style mask, which prevented `makeKeyAndOrderFront` from reliably making the window key.
  `makeFirstResponder` on the search field therefore silently failed, leaving the panel visible but
  unable to receive any keystrokes. Removed `.nonactivatingPanel`; the panel is now a standard
  activating window that properly takes focus when summoned.
- **`prepareForDisplay` called asynchronously after focus** — previously wrapped in
  `DispatchQueue.main.async`, which introduced a one-runloop delay that could race with the window
  becoming key. Now called directly after `makeKeyAndOrderFront + NSApp.activate`.
- **Panel positioned by mouse cursor** — `targetScreen()` used `NSEvent.mouseLocation` to decide
  which monitor to open the panel on. Unreliable when invoked via a global keyboard hotkey (cursor
  may be on a different display than the user's attention). Replaced with a
  `CGWindowListCopyWindowInfo`-based lookup that finds the previous frontmost app's window centre,
  placing the panel on the correct display without any cursor dependency.

---

## [1.4.0] — 2026-05-05

### Added
- **Configurable clipboard check interval** — Preferences → Monitoring → "Clipboard check interval"
  stepper (0.5–5.0 s, 0.5 s steps). Default changed from 0.5 s to **1.0 s**. Applied immediately
  without restarting the app. Stored in UserDefaults `pollInterval`.

### Fixed
- **Timer RunLoop mode** — `ClipboardMonitor` timer was added to `.common` mode, causing it to
  fire during menu tracking and scroll events. Changed to `.default` — correct for a background
  polling timer with no UI interaction requirement.
- **`AXIsProcessTrusted()` called every poll** — cached with a 30 s TTL so the system call runs
  at most once per 30 s instead of 1–2× per second.
- **`rebuildMenu()` debounce** — menu was rebuilt synchronously on every `clipStoreDidChange`
  notification. Now coalesced behind a 200 ms timer so rapid clipboard events produce one rebuild.
- **`pruneCount()` full-table scan on every insert** — the `NOT IN (SELECT ... LIMIT 50000)`
  delete ran unconditionally on every clip insertion. Now guarded by a `COUNT(*)` check; the
  expensive delete only runs when the unpinned clip count actually exceeds 50 000.

---

## [1.3.0] — 2026-04-20

### Added
- **Auto-update checker** — polls `api.github.com/repos/lswingrover/ClipWatch/releases/latest` once per launch; fires a macOS notification and shows an **"⬆ Update available: vX.X.X"** item at the top of the menu bar dropdown when a newer version is available
- **`UpdateChecker.swift`** — `@MainActor ObservableObject` with semver integer comparison, system notification delivery, and one-shot launch check (no background timer)

---

## [1.2.0] — 2026-04-10

### Added
- **Secure mode** — Preferences → Security → *Require Touch ID to open panel*: locks the entire panel behind biometric auth; no clips visible until authenticated
- **Unlock window** — configurable stay-unlocked duration after one Touch ID: Every use / 5 min / 15 min / 30 min / 1 hour / Until restart
- **Security section in Preferences** — unlock window picker + secure mode toggle

### Changed
- `PanelController` Touch ID gate now respects unlock window: a single successful auth unlocks all subsequent sensitive clip pastes until the window expires
- Closing the panel no longer resets the unlock window (correct behavior for multi-key workflows)

---

## [1.1.0] — 2026-03-28

### Added
- **Sensitive clip auto-detection** — `SensitiveDetector.swift` scans every new clip against 11 `NSRegularExpression` pattern classes: AWS access keys, generic API keys, credit card numbers (Luhn-valid), SSNs, PEM private keys, JWT tokens, GitHub PATs, generic `password=` assignments, Slack tokens, Stripe keys, database connection strings
- **Touch ID gate for sensitive clips** — sensitive clips render as `••••••••` in the panel; paste requires `LAContext.evaluatePolicy(.deviceOwnerAuthentication)` (Touch ID or Mac login password); uses the Secure Enclave on Apple Silicon
- **⌘S shortcut** — manually mark/unmark any clip as sensitive from the panel
- **`sensitive` column** in SQLite `clips` table — set at insert time; content stored as-is, never displayed without auth

### Changed
- `ClipStore.insert()` calls `SensitiveDetector.isSensitive(_:)` synchronously before writing; flagged clips write with `sensitive = 1`
- `ClipCellView` shows a lock icon on sensitive rows

---

## [1.0.0] — 2026-03-15

### Added
- Initial release — clipboard history manager for macOS 13+
- `NSPasteboard.general.changeCount` polling at 500 ms (only approach available — no push API on macOS)
- Plain-text-only storage — RTF/HTML stripped at insert time
- SQLite database with FTS5 full-text search (`clips_fts` virtual table, content-table triggers)
- Floating `NSPanel` search interface (non-activating — target app keeps focus)
- `⌥⌘V` global hotkey via `NSEvent.addGlobalMonitorForEvents`; requires Accessibility permission
- Type-to-filter, arrow-key navigation, Enter-to-paste, Esc-to-dismiss
- Paste via `CGEvent` to `cghidEventTap` — posts synthetic `⌘V` to the hardware-level HID event stream so the keystroke reaches the frontmost app directly; 150 ms delay after panel dismiss ensures focus transfer completes
- Pin items to top with `⌘P`
- Delete items with `⌘⌫`
- Menu bar status item (📋) with configurable recent-clip dropdown (5–25 items)
- App and URL exclusion list — filtered at insert time (excluded content never touches the database); pre-seeded with 1Password, Bitwarden, LastPass; URL-level exclusion via `AXUIElement` browser tab reading
- Preferences: hotkey recorder, menu item count, retention days (30–730), screen mode (active app / cursor), launch at login
- Data management: Clear All History with confirmation
- `~/Library/Application Support/ClipWatch/clips.db` — WAL journal mode; pruned on launch (retention limit + 50,000 unpinned cap)
- `build_app.sh` — one-shot compile → bundle → sign → install to `~/Applications/ClipWatch.app` → launch
- `make_icon.swift` — programmatic app icon via AppKit + iconutil
- Ad-hoc code signing and LaunchServices registration for Dock presence
