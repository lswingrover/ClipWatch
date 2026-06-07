# ClipWatch Roadmap

ClipWatch is a fast, keyboard-driven clipboard history manager for macOS. It stores history in SQLite with FTS5 search, automatically detects and locks sensitive clips, and exposes a companion API for Claude integration. The core feature set is shipped. This document tracks what comes next.

---

## Phase 1: Core (Complete -- v1.6.0)

- Clipboard polling with 500ms interval, plain-text-only storage
- SQLite + FTS5 full-text search history
- Floating search panel (non-activating, keyboard-driven)
- Synthetic ⌘V paste via CGEvent cghidEventTap
- 11-pattern sensitive clip detection (API keys, credit cards, SSNs, JWTs, private keys, etc.)
- Touch ID / device authentication for locked clips
- Companion API (localhost) for Claude plugin
- Claude companion plugin (clipwatch-companion.plugin)

---

## Phase 2: Behavioral Refinements

**Goal:** Plug the gaps that power users hit within the first week.

- **Ignore apps list** -- configure apps whose clipboard activity is never captured (1Password, banking apps, credential managers). Implemented as a bundle ID exclusion list in preferences.
- **Paste and clear** -- for sensitive clips: once revealed and pasted, prompt to remove from history. For all clips: optional "paste and forget" mode so one-use values don't accumulate.
- **Configurable retention** -- user-set maximum clip count (50, 200, unlimited). Older clips are pruned automatically. Separate retention setting for sensitive vs. non-sensitive.
- **Clip pinning via UI** -- pin clips in the search panel directly (currently only via API). Pinned clips appear at the top and are exempt from retention pruning.
- **"Clear all sensitive"** -- one-action button to wipe all sensitive clips from history. For privacy audits or before handing over the machine.
- **Plain text coercion feedback** -- subtle visual indicator in the panel that a clip will be pasted as plain text (some users expect formatting).

---

## Phase 3: Intelligence Layer

**Goal:** The clipboard tells you things you didn't know to look for.

- **Content classification beyond sensitivity** -- in addition to "is this an API key," label clips by type: URL, email address, code snippet, UUID, phone number, credit card. Show type badges in the panel.
- **Duplicate detection** -- when you copy something already in history, surface it at the top rather than creating a second entry. Reduces history noise.
- **Session context** -- track which app generated each clip and surface it in the panel ("from Slack", "from Terminal", "from Chrome"). FTS search can filter by source app.
- **Recency weighting** -- weight FTS5 search results by recency so typing a short query surfaces what you copied today before what you copied last month.
- **Weekly digest** -- optional notification: "You copied 142 things this week; 3 were flagged sensitive." Awareness without surveillance.
- **Pattern-based suggestions** -- if you copy the same partial string repeatedly (an email address format, a URL prefix), suggest adding it to Summon as a snippet.

---

## Phase 4: iOS Companion

**Goal:** Clipboard history that follows you across devices when you choose to share it.

- **iOS ClipWatch app** -- view and paste from clipboard history on iPhone/iPad
- **Selective sync via iCloud** -- only explicitly pinned clips sync; sensitive clips never sync; user controls what crosses the boundary
- **Secure sync** -- end-to-end encrypted before hitting iCloud Drive; key derived from device authentication credential
- **Handoff integration** -- pick up a clip on Mac and continue on iPhone

---

## Distribution

- **Sparkle auto-update** -- in-app update check from GitHub releases
- **Homebrew cask** -- `brew install --cask clipwatch`
- **Notarization** -- Apple Developer ID for Gatekeeper
- **TestFlight** (if iOS ships) -- beta distribution before App Store

---

*Last updated: 2026-06*
