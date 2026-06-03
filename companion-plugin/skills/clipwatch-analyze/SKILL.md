---
name: clipwatch-analyze
description: "Analyze Louis's clipboard history from ClipWatch. Surfaces patterns: which apps copy the most, sensitive items flagged, pinned items, recent activity summary. Trigger phrases: analyze clipboard, clipboard history, what have I copied, clipboard summary, clipwatch analyze, what's in my clipboard history, clipboard patterns."
---

# ClipWatch Analyze

You are analyzing Louis's clipboard history captured by ClipWatch (macOS clipboard manager).

## Data Source

ClipWatch exposes a localhost HTTP API on port 57822.
Primary query method: `curl -s http://localhost:57822/<endpoint>`
Fallback (if ClipWatch not running): `sqlite3 ~/Library/Application\ Support/ClipWatch/clips.db "<sql>"`

---

## Step 1 — Health Check

```bash
curl -s http://localhost:57822/health
```

If this returns a connection error, ClipWatch is not running. Tell the user to open ClipWatch from /Applications/ClipWatch.app and try again.

If it returns JSON with `running: true`, proceed.

---

## Step 2 — Recent Clips Summary

```bash
curl -s 'http://localhost:57822/clips?limit=100'
```

Parse the JSON array. Compute:
- Total clips returned
- Pinned count
- Sensitive count (`.sensitive == true`)
- Top 5 source apps by frequency (`.source` field, bundle ID)
- Time range: earliest and latest `.ts`
- Content type distribution: URLs, code snippets, plain text, credentials (use `.sensitive`)

---

## Step 3 — Sensitive Items Audit

```bash
curl -s http://localhost:57822/sensitive
```

For each sensitive clip:
- Show a **truncated preview** (first 40 chars) — never show the full content
- Note the source app and timestamp
- Flag any that look like credentials, tokens, or payment info

---

## Step 4 — Pinned Items

From the Step 2 result, filter `pinned == true`. List each pinned clip with preview (first 80 chars) and source app.

---

## Step 5 — Synthesize

Present a structured summary:

```
ClipWatch Analysis — [date]

Health: [clip count] clips, [DB size] KB, port 57822 active

Recent Activity (last 100):
  • [count] clips · [date range]
  • [count] pinned · [count] sensitive
  • Top sources: [app1] (N clips), [app2] (N clips), ...

Sensitive Items: [count] flagged
  ⚠ [preview]... from [app] at [time]
  ...

Pinned: [count]
  📌 [preview]... from [app]
  ...

Recommendations:
  [Any items to review/delete/pin based on the data]
```

Do NOT show full content of sensitive items. Use truncated previews only.
