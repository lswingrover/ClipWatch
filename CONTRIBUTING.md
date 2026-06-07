# Contributing to ClipWatch

ClipWatch is a macOS clipboard manager — a native Swift app that monitors the system clipboard, flags sensitive content, and provides Claude Cowork skills to search, analyze, and act on clipboard history. This document covers how to build, test, and extend it.

---

## Before you write code

1. **Read the README.** The 11 sensitive-pattern classes, the Touch ID integration, the app/URL exclusion model, and the FTS5 search architecture are all documented there.
2. **Check the roadmap.**
3. **Build and run first.** Verify your environment works before touching any code.

---

## Environment

- macOS 14+ (Sonoma)
- Xcode 15+ / Swift 5.9+
- No external package manager dependencies
- Build target: `My Mac` (not simulator)
- Signing: **ad-hoc only**. Never reconfigure for App Store or notarization.

---

## Building

Open `ClipWatch.xcodeproj` in Xcode and press ⌘B. For releases, `build_app.sh` handles ad-hoc signing and bundle assembly (used by the `scotty:clipwatch-ship` skill).

---

## Architecture principles

**Privacy is the design constraint.** ClipWatch captures everything the user copies — passwords, tokens, personal data. Every design decision is filtered through: does this make user data more or less exposed?

**Sensitive content detection is the core.** The 11 pattern classes (credentials, PII, financial, health, etc.) must be maintained carefully. Adding a new class requires: a regex, test cases (positive and negative), a classification label, and a flag in the UI.

**Touch ID gates sensitive views.** Any UI that exposes sensitive flagged content requires Touch ID. Do not route around this.

**App/URL exclusion is user trust.** The exclusion list (apps and URLs whose clipboard content is not stored) is a promise to the user. Never capture content from an excluded source.

**SQLite + FTS5 for persistence.** All clipboard entries write to SQLite with FTS5 full-text search. Schema changes require a migration increment.

**Menu bar first.** ClipWatch lives in the menu bar.

---

## Sensitive pattern classes

The 11 classes are:

1. Credentials (passwords, tokens, API keys)
2. Credit card numbers
3. SSN / government IDs
4. Email addresses in sensitive context
5. Phone numbers
6. Physical addresses
7. Bank account / routing numbers
8. Private keys / certificates
9. Medical / health information
10. Authentication codes (OTP, 2FA)
11. Personal names paired with sensitive identifiers

Any new class must have: a regex with documented false-positive rate, positive test cases, negative test cases, a sensitivity level (low/medium/high/critical).

---

## Code standards

- **Swift 5.9+** with structured concurrency.
- **SwiftUI** for UI. AppKit only where unavoidable.
- **No force unwraps** in new code.
- **No hardcoded paths** — use `FileManager` APIs.
- **No personal data in source** — test cases use synthetic data only.
- **Clipboard monitoring must be non-blocking** — the pasteboard poll loop must never stall.

---

## Branch and commit conventions

Branches: `main` (stable), `feature/X`, `fix/X`, `refactor/X`

Commit format (Conventional Commits):

    feat(detection): add OTP/2FA pattern class (class 10)
    fix(exclusion): handle apps with bundle ID prefix collisions
    refactor(db): extract clipboard repository into actor

---

## Testing

1. Build succeeds with zero warnings.
2. Copy a password-looking string — verify it is flagged with the correct class.
3. Copy from an excluded app — verify the entry is NOT captured.
4. Verify Touch ID gates the sensitive content view.
5. Verify FTS5 search finds entries correctly.
6. Verify entries survive an app restart (SQLite roundtrip).
7. Test the companion plugin if you changed any data the API serves.

---

## Companion plugin

The Claude Cowork plugin provides `clipwatch-analyze`, `clipwatch-act`, and `clipwatch-search` skills. Plugin files follow the Cowork plugin spec. Run `scotty:clipwatch-companion-ship` to rebuild after any SKILL.md change.

---

## Related

- [MacWatch](https://github.com/lswingrover/MacWatch) — system health monitor
- [NetWatch](https://github.com/lswingrover/NetWatch) — network health monitor
- [GridForge](https://github.com/lswingrover/GridForge) — window layout manager
- [Summon](https://github.com/lswingrover/Summon) — text expander
