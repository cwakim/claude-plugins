---
description: Pick up from a handoff snapshot — read a saved conversation state and continue from it, verifying against current ground truth before acting.
---

# Pickup

Read a handoff snapshot written by `/handoff` and continue the work (or the conversation) from it.

This is the other half of `/handoff`: a baton pass, not a session restore. It deliberately reads a distilled summary rather than replaying a transcript. (Named `pickup`, not `resume`, to avoid colliding with Claude Code's built-in `/resume`.)

## Arguments (`$ARGUMENTS`)

- **A path** → read that file. Expand a leading `~`.
- No argument → find the handoff via the discovery order below.

### Discovery order (no argument given)

A handoff does not always live in the current repo — it may have been written from a sibling repo, the Desktop, or elsewhere. Walk this order and stop at the first hit:

1. `.claude/handoff.md` in the current working directory.
2. The newest live entry in `~/.claude/handoff-index.md` (the pointer index `/handoff` maintains). Read the index and walk it top-down to the first path that still exists — entries can point at handoffs that were since deleted, so do not dead-end on a stale newest entry. Mention any dead entries you skipped (they can be pruned).
3. If neither resolves, say so and ask where the handoff lives.

If the resolved handoff lives **outside** the current working directory, say so explicitly and name its absolute path before acting on it — so a stale or wrong-repo pickup is obvious rather than silent.

## Step 1 — Read the note

A handoff is normally a single living current-state note (one top-level `#` heading), so just read it. If the file holds more than one thread as side-by-side `## <thread>` sections, read the one that matches what you're picking up (ask if it's ambiguous). For an older-style file that stacked several dated snapshots, read the **top** one as the active state and ignore the rest unless asked. Split on top-level headings, not on `---`, since a body can contain a horizontal rule.

## Step 2 — Verify before acting

A handoff is a point-in-time summary and may have drifted from reality since it was written. Verify against ground truth before acting, but match the verification to what the snapshot is:

- **Work snapshot in a git repo** (`# Handoff — …`): run `git status` and `git log` to confirm the branch and recent commits match what it describes, and spot-check that the files it names still exist and look as described.
- **Idea capture** (`# Conversation snapshot — …`), or any snapshot written outside a repo: there is no branch to check. Instead spot-check that any files, URLs, or resources it references still exist, and confirm the framing still holds before continuing.

If anything has diverged, flag it to the user instead of trusting the snapshot blindly.

## Step 3 — Continue

Summarize the state back in 2-3 lines (goal, where things stand, the next step), then either proceed with that next step or wait for direction.
