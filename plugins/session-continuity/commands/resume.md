---
description: Resume from a handoff snapshot — read a saved conversation state and continue from it, verifying against current ground truth before acting.
---

# Resume

Read a handoff snapshot written by `/handoff` and continue the work (or the conversation) from it.

## Arguments (`$ARGUMENTS`)

- **A path** → read that file. Expand a leading `~`.
- No argument → read `.claude/handoff.md` in the current working directory.
- If the file does not exist, say so and ask where the handoff lives.

## Step 1 — Read the most recent snapshot

The file may hold several snapshots separated by `---`, newest first. Read the **top** one as the active state. Note that older snapshots exist, but do not act on them unless asked.

## Step 2 — Verify before acting

A handoff is a point-in-time summary and may have drifted from reality since it was written. Before doing anything, cross-check its claims against ground truth:

- Run `git status` and `git log` to confirm the branch and recent commits match what the snapshot describes.
- Spot-check that the files it names still exist and look as described.

If anything has diverged, flag it to the user instead of trusting the snapshot blindly.

## Step 3 — Continue

Summarize the state back in 2-3 lines (goal, where things stand, the next step), then either proceed with that next step or wait for direction.
