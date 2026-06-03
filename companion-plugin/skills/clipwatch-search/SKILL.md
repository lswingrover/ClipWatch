---
name: clipwatch-search
description: "Search your clipboard history using full-text search. Finds clips by content, source app, or date. Trigger phrases: search clipboard, find in clipboard, did I copy X, search my clipboard history, find that thing I copied, clipwatch search, what did I copy from Y."
---

# ClipWatch Search

You are searching your clipboard history via the ClipWatch API.

## Data Source

ClipWatch API: `http://localhost:57822`
Fallback: `sqlite3 ~/Library/Application\ Support/ClipWatch/clips.db "<sql>"`

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

## Step 1 — Parse the Query

The user wants to find something they copied. Extract:
- **Search terms** (what to search for in content)
- **Source filter** (app they copied from, if mentioned)
- **Date filter** (time range, if mentioned)
- **Type filter** (URLs, code, text, sensitive — if mentioned)

---

## Step 2 — Full-Text Search

```bash
http_code=$(curl -s -o /tmp/cw_response.json -w '%{http_code}' 'http://localhost:57822/search?q=ENCODED_QUERY&limit=50')
body=$(cat /tmp/cw_response.json)
```

If `http_code` is `423`, apply Lock Detection above and stop.

URL-encode the search query (spaces → %20, quotes → %22, etc.).
The API uses FTS5 — supports quoted phrases, prefix search (word*), and AND/OR operators.

Examples:
- Simple: `?q=github%20token`
- Phrase: `?q=%22bearer%20token%22`
- Prefix: `?q=https%3A%2F%2Fgithub*`

---

## Step 3 — Filter Results (if needed)

If the user specified a source app filter:

```bash
http_code=$(curl -s -o /tmp/cw_response.json -w '%{http_code}' 'http://localhost:57822/clips?limit=500')
body=$(cat /tmp/cw_response.json)
```

If `http_code` is `423`, apply Lock Detection above and stop.

Filter `.source` field for the bundle ID (e.g. `com.google.Chrome`, `com.apple.Terminal`).
If date filtering is needed, compare `.ts` (ISO8601) against the requested range.

---

## Step 4 — Direct Fetch by ID (if user references a specific item)

```bash
http_code=$(curl -s -o /tmp/cw_response.json -w '%{http_code}' 'http://localhost:57822/clip?id=N')
body=$(cat /tmp/cw_response.json)
```

If `http_code` is `423`, apply Lock Detection above and stop.

---

## Step 5 — Present Results

For each result, show:
- Preview: first 120 chars (never full content for sensitive items)
- Source app (if known)
- Timestamp
- Pinned/sensitive flags

If zero results:
- Suggest alternative search terms
- Offer to search with broader terms
- Note if ClipWatch's retention window might have pruned it

Maximum results to show: 20. If more found, say "N results — showing top 20. Refine your search to narrow down."
