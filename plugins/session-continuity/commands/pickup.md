---
description: Pick up from a handoff snapshot — read a saved conversation state and continue from it, verifying against current ground truth before acting.
---

# Pickup

Read a handoff snapshot written by `/handoff` and continue the work (or the conversation) from it.

This is the other half of `/handoff`: a baton pass, not a session restore. It deliberately reads a distilled summary rather than replaying a transcript. (Named `pickup`, not `resume`, to avoid colliding with Claude Code's built-in `/resume`.)

## Arguments (`$ARGUMENTS`)

- **A path** (anything containing `/` or ending in `.md`) → read that file. Expand a leading `~`.
- **The word `list`** → don't pick anything up; show what's in flight instead. Follow the **List mode** section below.
- **Any other text** → treat it as a thread name: match it (case-insensitively, allowing partial matches) against the titles and goals in `~/.claude/handoff-index.md`. One live match → pick that up. Several → show them and ask. None → say so and fall back to the discovery order below.
- No argument → find the handoff via the discovery order below.

### Discovery order (no argument given)

A handoff does not always live in the current repo — it may have been written from a sibling repo, the Desktop, or elsewhere. Walk this order and stop at the first hit:

1. `.claude/handoff.md` in the current working directory.
2. The newest live entry in `~/.claude/handoff-index.md` (the pointer index `/handoff` maintains). Read the index and walk it top-down to the first path that still exists — entries can point at handoffs that were since deleted, so do not dead-end on a stale newest entry. **Prune as you go:** any entry whose path no longer exists is dead, so rewrite the index without those lines (keep the live ones in order) and tell the user which you removed. This keeps the index from accumulating pointers to deleted handoffs.
3. If neither resolves, say so and ask where the handoff lives.

If the resolved handoff lives **outside** the current working directory, say so explicitly and name its absolute path before acting on it — so a stale or wrong-repo pickup is obvious rather than silent.

If the resolved path sits inside a `handoff-archive/` folder, this thread was **retired** by `/handoff archive`. Say so, read the archived-on date from the filename suffix (`<slug>-YYYY-MM-DD.md`), and ask whether to revive it. To revive: move the note back to the active slot beside the archive folder (default `.claude/handoff.md`, or `.claude/handoff-<slug>.md` if that slot is taken by another thread), re-add its pointer line to `~/.claude/handoff-index.md`, then continue as a normal pickup.

## List mode (`list`)

Read `~/.claude/handoff-index.md` and report what's in flight, instead of picking a single note up:

1. Walk every entry. **Prune dead ones** exactly as in the discovery order: drop lines whose path no longer exists, rewrite the index, and say which were removed.
2. For each live entry, print one line: the thread title or goal, the template tag (`work` or `ideas`), the path, and the note's age (from the `updated YYYY-MM-DD` in its title, falling back to file modification time). Flag notes older than ~2 weeks as possibly stale.
3. If the index is missing or empty, check `.claude/handoff.md` in the current directory and report that, or say there is nothing in flight.
4. Stop there — do not read the notes' bodies or start work. The user picks what to pick up.

## Step 1 — Read the note

A handoff is normally a single living current-state note (one top-level `#` heading), so just read it. If the file holds more than one thread as side-by-side `## <thread>` sections, read the one that matches what you're picking up (ask if it's ambiguous). For an older-style file that stacked several dated snapshots, read the **top** one as the active state and ignore the rest unless asked. Split on top-level headings, not on `---`, since a body can contain a horizontal rule.

**Note how old the note is.** Parse the date from the title (`updated YYYY-MM-DD`, or the `— YYYY-MM-DD` on an idea capture); fall back to the file's modification time if there's no date. State the age when you summarize ("this note is 2 days old" vs "6 weeks old"), and let the gap calibrate how hard you verify in Step 2: a fresh note can be trusted lightly, a stale one warrants re-checking its claims before you act on them.

## Step 2 — Verify before acting

A handoff is a point-in-time summary and may have drifted from reality since it was written. Verify against ground truth before acting, but match the verification to what the snapshot is. Tell them apart by the title: a work note reads `# <thread name> — working state (updated YYYY-MM-DD)`, an idea capture reads `# Conversation snapshot — YYYY-MM-DD`; the `work|ideas` tag on the note's line in `~/.claude/handoff-index.md` is a second signal. (Older notes may use other titles; when unsure, a `## Goal` / `## Next / blocked` structure means work, `## Key ideas` means ideas.)

- **Work note with a ground-truth footer** (`_As of branch ... @ <sha> ..._`): verify mechanically. Run `git log --oneline <sha>..HEAD` to see exactly what has landed since the note was written; if the branch differs from the footer's, say so. Summarize the drift concretely ("7 commits since, touching the files this note cares about") and spot-check the files the note names. If the footer said the tree was dirty, check whether those changes were since committed or are still pending.
- **Work note without a footer, in a git repo**: run `git status` and `git log` to confirm the branch and recent commits match what it describes, and spot-check that the files it names still exist and look as described.
- **Idea capture**, or any note written outside a repo: there is no branch to check. Instead spot-check that any files, URLs, or resources it references still exist, and confirm the framing still holds before continuing.

If anything has diverged, flag it to the user instead of trusting the snapshot blindly. The older the note (see its age from Step 1), the harder you should look — most divergence is a function of elapsed time.

If the note turns out to be **too lossy** (it references decisions or details it doesn't contain) and its footer records a session id, tell the user they can recover the full transcript with `claude --resume <id>` on the machine the handoff was written on.

## Step 3 — Continue

Summarize the state back in 2-3 lines (goal, where things stand, the next step), then either proceed with that next step or wait for direction.
