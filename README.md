# ClipWatch

A fast, keyboard-driven clipboard history manager for macOS. Lives in the menu bar. Zero dependencies. Built to last.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange) ![License](https://img.shields.io/badge/license-MIT-green) ![Version](https://img.shields.io/badge/version-1.3.0-lightgrey)

---

## Why this exists

macOS has no native clipboard history. If you copy something and then copy something else, the first thing is gone — permanently. Every other operating system solved this a decade ago.

The existing solutions all have the same problems:

- **Paid apps** (Paste, Clipboard Manager Pro, etc.) require subscriptions, App Store accounts, or iCloud sync. A clipboard manager doesn't need to be a service.
- **Free apps** are usually abandoned, bloated with features you don't want, or require permissions they shouldn't need.
- **Most clipboard managers capture everything** — including passwords from 1Password, API keys you paste into a terminal, and credit card numbers you copy from a statement. You don't want those in a searchable history visible to anyone who opens your Mac.

ClipWatch does one thing: it remembers what you copied, lets you find it instantly, and keeps the sensitive stuff locked. No cloud. No subscription. No images or rich text. No settings you don't need. It's a 2,000-line Swift program that runs invisibly in your menu bar and costs nothing.

**Typical use cases:**
- You copied a URL, then copied something else — ClipWatch has both
- You're filling out a form and need three things from three different places — open the panel, arrow through your recent clips, paste each one
- You copied an API key earlier and didn't save it — it's in ClipWatch (and it's locked behind Touch ID)
- A colleague's email address keeps coming up — pin it to the top

---

## Features

### Clipboard history

ClipWatch polls `NSPasteboard.general.changeCount` every 500 ms. There is no push API for clipboard change events on macOS — this is the standard approach used by every clipboard manager on the platform, including Alfred, Raycast, and Pastebot. The poll is inexpensive: it's a single integer comparison, and the full read only happens when the count changes.

Every copy event is stored as **plain text only**. This is a deliberate choice: formatted text (RTF, HTML) is stripped. When you paste from ClipWatch, you always get the text without the formatting — no surprise font changes, no invisible HTML, no rich text artifacts. If you've ever pasted something into Slack or a Google Doc and ended up with three different font sizes, you understand why this matters.

History is stored in a local SQLite database with **FTS5 full-text search**. FTS5 builds an inverted index on insert, so searching across hundreds or thousands of clips is instantaneous regardless of history size — the same technology powering search in mail clients and note apps.

---

### Search panel

The search panel is a floating `NSPanel` — a non-activating window that appears above your current app without stealing focus from it. This is critical: when you paste, the target app still has focus, so the paste lands in the right place.

Type to filter. Arrow to select. Enter to paste. Esc to dismiss. The whole interaction takes under two seconds once you've built the muscle memory.

**How paste works:** ClipWatch writes the selected text to `NSPasteboard.general`, then posts a synthetic `⌘V` `CGEvent` to the `cghidEventTap` — the hardware-level event stream. `cghidEventTap` reaches the frontmost app directly, bypassing the normal event dispatch chain. This is the same mechanism used by system-level automation tools. It requires Accessibility permission, which ClipWatch requests on first use. Without it, ClipWatch still writes to the pasteboard — you just have to press `⌘V` yourself.

A 150 ms delay between dismissing the panel and posting the keystroke ensures the previous app has fully regained focus before the paste fires. Too short and the event lands in ClipWatch's own window. Too long and the interaction feels sluggish.

---

### Sensitive clip detection

ClipWatch automatically scans every new clip against 11 pattern classes:

| Pattern class | Examples |
|--------------|---------|
| AWS access keys | `AKIA...` — 20-char alphanumeric starting with AKIA |
| Generic API keys | High-entropy strings in key/token/secret contexts |
| Credit card numbers | Luhn-valid 13–19 digit sequences (Visa, MC, Amex, Discover) |
| Social security numbers | `XXX-XX-XXXX` format |
| Private keys | PEM blocks (`-----BEGIN RSA PRIVATE KEY-----`, etc.) |
| JWT tokens | Three base64url segments separated by `.` |
| GitHub personal access tokens | `ghp_...` and `github_pat_...` prefix patterns |
| Generic passwords | Strings appearing in `password=` / `pwd=` assignment contexts |
| Slack tokens | `xoxb-`, `xoxp-`, `xoxs-` prefixes |
| Stripe keys | `sk_live_...`, `pk_live_...` |
| Database connection strings | `postgres://`, `mysql://`, `mongodb://` with credentials |

Detection runs synchronously on insert — a clip is either flagged sensitive before it ever hits the database or it isn't. Sensitive clips are stored with a `sensitive` column set to 1; the raw content is stored as-is but never displayed in the UI without authentication.

**Why auto-detect instead of requiring manual marking?** Because you won't remember. The moment you copy an API key and move on to whatever you needed it for, you're not thinking about clipboard hygiene. Auto-detection is the only approach that works in practice.

---

### Touch ID and unlock window

Locked clips require Touch ID (or your Mac login password if Touch ID isn't available) to reveal or paste. ClipWatch uses `LAContext.evaluatePolicy(.deviceOwnerAuthentication)` — the same API used by 1Password, banking apps, and the Keychain. On Apple Silicon, this invokes the Secure Enclave; the biometric data never leaves the chip.

The **unlock window** configures how long ClipWatch stays unlocked after one successful authentication:

| Setting | Behavior |
|---------|----------|
| Every use | Authenticate every time you paste a sensitive clip |
| 5 / 15 / 30 min | Re-authenticate after the window expires |
| 1 hour | Authenticate once per working session |
| Until restart | Authenticate once per Mac login |

The unlock window persists across panel open/close cycles — closing the panel doesn't reset it. This is the right behavior: if you're working with several API keys at once, you shouldn't need to Touch ID for each one.

**Secure mode** (Preferences → Security → *Require Touch ID to open panel*) locks the entire panel — no clips are visible at all until you authenticate. This is for shared workspaces or situations where the clipboard itself contains sensitive context.

---

### App and URL exclusion

ClipWatch watches the frontmost app at copy time using the Accessibility API (`AXUIElement`). If the app is on the exclusion list, the clipboard change is ignored entirely — the content never reaches the database.

The exclusion list is pre-seeded with **1Password, Bitwarden, and LastPass**. These apps write to the clipboard when you autofill credentials; you almost never want that in your history.

**URL-level exclusion** works similarly: ClipWatch reads the active browser tab's URL via `AXUIElement` before recording a copy event. Add a domain pattern (e.g., `chase.com`, `schwab.com`) and anything copied while that domain is in the foreground is silently ignored. This covers bank sites, HR portals, and other places you routinely handle sensitive data without thinking about it.

Adding to the exclusion list: drag any `.app` file from Finder onto the list, click `+` to browse for one, or type a URL/domain pattern directly.

---

### Menu bar integration

The menu bar dropdown shows your most recent clips (5–25, configurable), so you can paste without opening the full panel. Click any clip to paste it into whatever was frontmost. A small pin icon marks pinned items.

When a new ClipWatch version is available, an **"⬆ Update available: vX.X.X"** item appears at the top of the dropdown. ClipWatch checks the GitHub releases API once per launch — no background timer, no repeated network calls.

---

## Install

> **This repo contains source code only — there is no pre-built binary.** You build it yourself in about 30 seconds. The script handles everything.

### What you need

- **macOS Ventura (13) or later**
- **Xcode Command Line Tools** (free — the build script will prompt you if missing)

You do not need a paid Apple Developer account or the full Xcode app.

### Step by step

**Step 1 — Open Terminal.**
Press **⌘ Space**, type `Terminal`, and press Return. A window with a command prompt appears.

**Step 2 — Install developer tools** (skip if you've done this before):
```bash
xcode-select --install
```
A dialog appears — click **Install**, then **Agree**. Takes 2–5 minutes. Skip if it says "already installed."

**Step 3 — Download ClipWatch:**
```bash
git clone https://github.com/lswingrover/ClipWatch.git ~/Developer/ClipWatch
```

**Step 4 — Build and install:**
```bash
bash ~/Developer/ClipWatch/build_app.sh
```
The script compiles ClipWatch, assembles the app bundle, and installs it to `~/Applications/ClipWatch.app`. Takes about 30 seconds.

**Step 5 — Launch ClipWatch:**
```bash
open ~/Applications/ClipWatch.app
```
A clipboard icon (📋) appears in your menu bar near the clock.

### Gatekeeper warning

Because ClipWatch is built locally and not notarized through Apple, macOS may block the first launch:

> *"ClipWatch cannot be opened because it is from an unidentified developer."*

**Fix — Option A (GUI):** Open Finder, go to `~/Applications`, right-click `ClipWatch.app` → **Open** → click **Open** in the dialog. One-time only.

**Fix — Option B (Terminal):**
```bash
xattr -dr com.apple.quarantine ~/Applications/ClipWatch.app
open ~/Applications/ClipWatch.app
```

**Step 6 — Grant Accessibility access.**
The first time you press the hotkey (`⌥⌘V`), macOS will ask for Accessibility permission. Click **Open System Settings** and flip the toggle next to ClipWatch. This is required for the paste keystroke injection to work. Without it, ClipWatch still records your history and copies items to the pasteboard — you just have to press `⌘V` yourself.

---

## Using ClipWatch

Press **⌥⌘V** (Option + Command + V) to open the panel. Start typing to filter. Arrow keys to navigate. Enter to paste.

| Action | How |
|--------|-----|
| Open the panel | `⌥⌘V` (configurable in Preferences) |
| Move up / down | `↑` `↓` |
| Paste selected item | `↩` Enter |
| Search history | Just start typing |
| Pin item to top | `⌘P` |
| Mark / unmark sensitive | `⌘S` |
| Delete item | `⌘⌫` |
| Close without pasting | `Esc` or hotkey again |
| Paste from menu bar | Click the 📋 icon → click any item |
| Clear all history | Menu bar → **Clear History…** |

---

## Preferences

Open via the menu bar → **Preferences…** or press `⌘,` when the panel is open.

**Hotkey** — click the field and press your preferred shortcut. Stored in UserDefaults; survives updates.

**Menu** — how many recent clips appear in the menu bar dropdown (5–25, default 10).

**History** — how many days to keep clipboard history (30–730 days, default 365). Clips older than the limit are pruned on launch.

**Panel appears on** — which screen the panel opens on: the screen your active app is on, or the screen your cursor is on. Matters on multi-monitor setups.

**Launch at login** — adds ClipWatch to your Login Items so it starts automatically.

**Security**
- *Require Touch ID to open panel* — the entire panel is locked until you authenticate. No clips visible until then.
- *Stay unlocked for* — how long after one Touch ID before ClipWatch asks again: Every use / 5 min / 15 min / 30 min / 1 hour / Until restart.

**Data** — *Clear All History…* deletes all clips immediately, including pinned items. Cannot be undone. Pinned clips are not exempt.

**Never capture from** — exclusion list of apps and URL patterns. Drag `.app` files onto the list, click `+` to browse, or type a domain pattern. Pre-seeded with 1Password, Bitwarden, LastPass.

---

## Privacy

ClipWatch runs entirely on your Mac. Nothing is sent anywhere, ever. No analytics, no telemetry, no crash reporting.

The clipboard database lives at:
```
~/Library/Application Support/ClipWatch/clips.db
```

Apps on the exclusion list are filtered at insert time — their clipboard contents never touch the database. Sensitive clips are stored in the database but the raw content is only revealed after Touch ID or password authentication. The file itself is protected by your Mac's filesystem permissions.

Time Machine backs up `~/Library/Application Support/ClipWatch/` automatically as part of your normal backup rotation.

---

## Architecture

```
Sources/ClipWatch/
  main.swift                        NSApplication setup, NSApp.run()
  AppDelegate.swift                 Status item, menu bar, CGEvent paste, update banner
  ClipStore.swift                   SQLite + FTS5 (clips table, sensitive column, pin column)
  ClipboardMonitor.swift            NSPasteboard polling (500 ms), AX URL exclusion
  HotkeyManager.swift               NSEvent global monitor, Accessibility permission prompt
  PanelController.swift             Floating NSPanel, Touch ID gate, unlock window logic
  SearchViewController.swift        Search field + NSTableView + ClipCellView
  PreferencesWindowController.swift All user settings, ShortcutRecorderField, exclusion list
  Prefs.swift                       UserDefaults keys and typed accessors
  SensitiveDetector.swift           NSRegularExpression — 11 pattern classes, min-length guard
  UpdateChecker.swift               GitHub releases API, semver comparison, .updateAvailable
```

### Design decisions worth knowing about

**Why plain text only?** Rich text clipboard content (RTF, HTML, attributed strings) varies wildly between apps. Storing it requires format negotiation on paste; stripping it at read time loses data; keeping it inflates storage. Plain text is always the right format for a clipboard history manager. If you specifically want formatted paste, paste directly from the source app.

**Why poll instead of waiting for a push event?** macOS has no `NSPasteboard` change notification API. The only way to watch the clipboard is to check `changeCount` periodically. 500 ms is the standard interval — fast enough to catch rapid copies, slow enough to be invisible in Activity Monitor.

**Why `cghidEventTap` for paste injection instead of `NSApplication.sendAction`?** `sendAction` requires the target app to be the current `NSApp` responder, which ClipWatch isn't. `cghidEventTap` posts to the hardware-level HID event stream, reaching the frontmost app regardless of which process owns the event loop. This is the same approach used by Raycast, Alfred, and most system-level tools.

**Why local SQLite instead of Core Data or CloudKit?** Core Data adds abstraction overhead for a schema this simple. CloudKit would require an iCloud account, sync conflicts, and access to your clipboard history by Apple's servers. SQLite is fast, portable, inspectable with any DB browser, and backs up with Time Machine. FTS5 gives full-text search for free. There's no reason to reach for anything heavier.

**Why no images or file clips?** Images bloat the database quickly, their content isn't searchable, and they're rarely what you need from clipboard history. The 5% of use cases where you want a copied image are better served by saving the image intentionally. ClipWatch optimizes for the 95%.

---

## Updating

```bash
cd ~/Developer/ClipWatch
git pull
bash build_app.sh
```

The script replaces `~/Applications/ClipWatch.app` automatically. Relaunch the app after installing.

Or: click the **"⬆ Update available"** banner in the menu bar dropdown to go to the GitHub release page.

---

## License

MIT. See [LICENSE](LICENSE).

---

## Related tools

These apps are built by the same author and follow the same install pattern — build from source, no App Store, optional Claude companion plugin:

| App | What it does |
|-----|-------------|
| [NetWatch](https://github.com/lswingrover/NetWatch) | Network monitoring — ping latency, DNS health, Wi-Fi metrics, automatic incident bundling and ISP escalation drafts |
| [MacWatch](https://github.com/lswingrover/MacWatch) | Mac system health — CPU temps, memory pressure, battery health, process monitoring, composite health score |
