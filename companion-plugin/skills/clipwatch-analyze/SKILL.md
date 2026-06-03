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

## Lock Detection (applies to all data requests)

When Secure Mode is active and ClipWatch is locked, any request to `/clips`,
`/search`, `/sensitive`, `/clip`, `/pin`, or `/delete` returns **HTTP 423**.

Use this pattern for every data call:

```bash
http_code=$(curl -s -o /tmp/cw_response.json -w '%{http_code}' 'http://localhost:57822/ENDPOINT')
body=$(cat /tmp/cw_response.json)
```

**If `http_code` is `423`:** stop immediately. Tell the user:

> **ClipWatch is locked — unlock from the menu bar to continue.**
>
> Click the ClipWatch icon in the menu bar and authenticate with Touch ID or
> your Mac password, then try again.

Do **not** fall back to the SQLite database — it does not bypass the lock.

---

## Step 1 — Health Check

```bash
curl -s http://localhost:57822/health
```

If this returns a connection error, ClipWatch is not running. Tell the user to open
ClipWatch from /Applications/ClipWatch.app and try again.

If it returns JSON with `running: true`, proceed. If the response contains
`"locked": true`, apply the Lock Detection rule above before continuing to Step 2.

---

## Step 2 — Recent Clips Summary

```bash
http_code=$(curl -s -o /tmp/cw_response.json -w '%{http_code}' 'http://localhost:57822/clips?limit=100')
body=$(cat /tmp/cw_response.json)
```

If `http_code` is `423`, apply Lock Detection above and stop.

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
http_code=$(curl -s -o /tmp/cw_response.json -w '%{http_code}' 'http://localhost:57822/sensitive')
body=$(cat /tmp/cw_response.json)
```

If `http_code` is `423`, apply Lock Detection above and stop.

For each sensitive clip:
- Show a **truncated preview** (first 40 chars) — never show the full content
- Note the source app and timestamp
- Flag any that look like credentials, tokens, or payment info

---

## Step 4 — Pinned Items

From the Step 2 result, filter `pinned == true`. List each pinned clip with preview
(first 80 chars) and source app.

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
