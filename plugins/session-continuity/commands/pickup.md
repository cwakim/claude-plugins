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
2. The most recent entry in `~/.claude/handoff-index.md` (the pointer index `/handoff` maintains). Read the index, take the newest path, and confirm it still exists.
3. If neither resolves, say so and ask where the handoff lives.

If the resolved handoff lives **outside** the current working directory, say so explicitly and name its absolute path before acting on it — so a stale or wrong-repo pickup is obvious rather than silent.

## Step 1 — Read the most recent snapshot

The file may hold several snapshots separated by `---`, newest first. Read the **top** one as the active state. Note that older snapshots exist, but do not act on them unless asked.

## Step 2 — Verify before acting

A handoff is a point-in-time summary and may have drifted from reality since it was written. Before doing anything, cross-check its claims against ground truth:

- Run `git status` and `git log` to confirm the branch and recent commits match what the snapshot describes.
- Spot-check that the files it names still exist and look as described.

If anything has diverged, flag it to the user instead of trusting the snapshot blindly.

## Step 3 — Continue

Summarize the state back in 2-3 lines (goal, where things stand, the next step), then either proceed with that next step or wait for direction.
