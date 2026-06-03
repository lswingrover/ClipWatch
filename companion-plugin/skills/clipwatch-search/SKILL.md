---
name: clipwatch-search
description: "Search Louis's clipboard history using full-text search. Finds clips by content, source app, or date. Trigger phrases: search clipboard, find in clipboard, did I copy X, search my clipboard history, find that thing I copied, clipwatch search, what did I copy from Y."
---

# ClipWatch Search

You are searching Louis's clipboard history via the ClipWatch API.

## Data Source

ClipWatch API: `http://localhost:57822`
Fallback: `sqlite3 ~/Library/Application\ Support/ClipWatch/clips.db "<sql>"`

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
curl -s 'http://localhost:57822/search?q=ENCODED_QUERY&limit=50'
```

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
# Get all recent and filter client-side
curl -s 'http://localhost:57822/clips?limit=500'
```
Filter `.source` field for the bundle ID (e.g. `com.google.Chrome`, `com.apple.Terminal`).

If date filtering is needed, compare `.ts` (ISO8601) against the requested range.

---

## Step 4 — Direct Fetch by ID (if user references a specific item)

```bash
curl -s 'http://localhost:57822/clip?id=N'
```

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
