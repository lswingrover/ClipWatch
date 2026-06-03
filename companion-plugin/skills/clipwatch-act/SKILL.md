---
name: clipwatch-act
description: "Take actions on ClipWatch clipboard history — pin important clips, delete sensitive items, or bulk-clear old entries. Always shows what it will do and asks for confirmation before writing. Trigger phrases: pin this clip, delete that clipboard item, remove sensitive clipboard entries, pin that thing I copied, clear clipboard history, clipwatch act, delete clip, unpin."
---

# ClipWatch Act

You are taking action on Louis's clipboard history via the ClipWatch API.

## Safety Rules (Non-Negotiable)

1. **Always show what you're about to do and ask for confirmation before executing.**
2. **Never delete pinned items without explicit "yes, delete pinned too" confirmation.**
3. **For bulk delete operations, show count + preview of what will be removed first.**
4. **Never call deleteAll without a two-step confirmation ("are you sure? this removes everything including pinned").**

---

## Available Actions

### Pin / Unpin a Clip

```bash
# Toggle pin (pinned → unpinned or unpinned → pinned)
curl -s 'http://localhost:57822/pin?id=N'
```

Returns `{"success": true, "id": N, "action": "pin_toggled"}`.

Before acting, fetch the clip to show what's being pinned:
```bash
curl -s 'http://localhost:57822/clip?id=N'
```

### Delete a Specific Clip

```bash
curl -s 'http://localhost:57822/delete?id=N'
```

Returns `{"success": true, "id": N, "action": "deleted"}`.

Always show the clip preview and ask for confirmation first.

### Delete All Sensitive Items

1. Fetch sensitive clips:
```bash
curl -s http://localhost:57822/sensitive
```

2. Show count + truncated previews (never full content).

3. Ask for confirmation: "Delete these N sensitive items?"

4. If confirmed, delete each by ID:
```bash
curl -s 'http://localhost:57822/delete?id=N'
```

### Find and Delete Clips Matching a Pattern

1. Search for the pattern:
```bash
curl -s 'http://localhost:57822/search?q=TERM&limit=200'
```

2. Show matches with previews, ask which to delete.

3. Delete confirmed items one by one.

---

## Step 0 — Confirm ClipWatch is Running

```bash
curl -s http://localhost:57822/ping
```

If no response, ClipWatch is not running — tell the user to open it first.

---

## Step 1 — Understand the Request

Map the user's intent to one of the actions above:
- "pin this" / "save this" → pin action
- "delete that" / "remove X" / "clear X" → delete action
- "clean up sensitive" / "remove credentials" → delete-sensitive flow
- "delete everything about X" → search + delete flow

If ambiguous, ask which clip or search term they mean.

---

## After Acting

Confirm what was done and offer to run `clipwatch-analyze` to show the updated state.
