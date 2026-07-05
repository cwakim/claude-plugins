---
description: Save a portable, human-readable snapshot of this conversation to a markdown file, so a fresh Claude or a human can pick up the thread without replaying the whole chat.
---

# Handoff

Distill the current conversation into a compact, portable markdown snapshot and write it to a file.

This is **not** a context restore. Unlike resuming a session (which replays the whole raw transcript), a handoff is a deliberate, lossy summary: the substance, not the noise. The goal is that a fresh session, a different machine, or a human contributor can continue from a single readable page instead of rehydrating a long, messy thread.

It is also **not** a log of past sessions. A handoff is a *living current-state note* for an ongoing thread: what the thing is, where it stands right now, what shipped, what was deliberately held back and why. When you handoff again on the same thread, you **update that one page in place** to match reality — you do not stack a new dated entry on top. The file should always read as "here is the state now," roughly one screen, never a diary of everything that ever happened.

## Arguments (`$ARGUMENTS`)

Parse optional arguments, in any order:

- **A path** (anything containing `/` or ending in `.md`) → the destination file. Expand a leading `~`. Examples: `~/Desktop/auth-refactor.md`, `notes/that-chat.md`.
- **The word `ideas`** (or `capture`) → use the **idea-capture** template instead of the default work template.
- **The word `archive`** (optionally followed by a thread name) → retire a finished thread: move its note into an archive folder and clear it out of the active handoff. This follows the **Archive mode** section below instead of Steps 1-5.
- No path given → default to `.claude/handoff.md` in the current working directory (create `.claude/` if needed).
- No mode word given → use the **work** template.

## Step 1 — Choose the template

**Work template** (default, for resuming a task):

```markdown
# <thread name> — working state (updated YYYY-MM-DD)

## Goal
The overarching objective, 1-3 sentences.

## Status now
Where the thread stands right now: what's live, what's in progress, which
files / branches are in play. Cite ground truth (branch names, commit hashes,
file paths) rather than re-describing code that the repo already holds.

## Shipped, watch for
Things built and pushed that may still need fixes — name the change and the
suspected weak spot, so a follow-up knows where to look. Omit the heading if empty.

## Held back (and why)
Anything deliberately NOT done yet — not pushed to prod, parked on a branch,
deferred — each with the reason. This is the context that is easy to lose.
Omit the heading if empty.

## Decided (don't revisit)
Choices made and the one-line reason: "chose A over B because ...". This is
what stops a fresh session from relitigating settled questions. Omit the
heading if empty.

## Next / blocked
The immediate next step, or the exact thing we are stuck on. Be specific.

## Constraints
Session-specific gotchas still in effect (see the note below).

_As of branch `<branch>` @ `<short sha>`, <clean tree | dirty: N files>. Session `<session id>`._
```

**Fill the ground-truth footer from the repo, not from memory:** `git rev-parse --abbrev-ref HEAD` for the branch, `git rev-parse --short HEAD` for the sha, `git status --porcelain | wc -l` for dirtiness. This footer is what lets `/pickup` verify mechanically ("N commits have landed since") instead of guessing. Outside a git repo, drop the git part and keep just the session line.

**Session id (best effort):** the current session's transcript is the newest `*.jsonl` in `~/.claude/projects/<munged cwd>/`, where the munged name is the absolute working directory with `/` (and other non-alphanumerics) replaced by `-`. Its basename is the session id. Record it so the user can fall back to `claude --resume <id>` on this machine if the summary turns out too lossy. If the lookup fails, omit the session part silently; never guess an id.

This is the page you **revise in place** on the next handoff: move finished items out of `Shipped, watch for` once they're confirmed stable, clear resolved entries from `Held back`, update `Status now`. Date any fact whose freshness matters (`as of YYYY-MM-DD`).

If the file genuinely tracks **several parallel threads** (e.g. different repos or unrelated tasks), give each its own `## <thread name>` section with this structure nested under it, rather than flattening them into one list — but prefer a separate file per thread (see Step 2) so each stays a clean one-screen note.

**Keep durable rules out of the note.** Workflow rules and project constants that hold across every session (branch/push policy, prose conventions, tooling gotchas) belong in the project's `CLAUDE.md`, which loads every session anyway — repeating them in the note is a top cause of handoff bloat. The `## Constraints` section should carry only *session-specific* gotchas: a hash that will change, a change parked on a branch, a one-off caveat. When you spot a durable rule sitting in the note (or being carried forward every time), **proactively suggest** moving it to `CLAUDE.md`: name the specific rules and tell the user "I'd suggest putting these in `CLAUDE.md` so they stop getting repeated here." Then act on their answer — never edit `CLAUDE.md` without asking first.

**Idea-capture template** (`ideas`, for a conversation worth keeping):

```markdown
# Conversation snapshot — YYYY-MM-DD

## What this was about
One paragraph of framing.

## Key ideas
The insights, framings, and arguments that landed. Bullet them.

## Decisions / conclusions
What was concluded or decided, and the reasoning.

## Open threads
Questions left unresolved, things to explore next.
```

## Step 2 — Revise the living note in place (don't stack)

If the destination file does **not** exist yet, just write a fresh note from the template.

If it **does** exist, read it first and decide whether this conversation continues the *same thread* that note describes:

- **Same thread (the common case)** → **rewrite the note in place** so it reflects reality now. Carry forward what's still true, fold this session's progress into `Status now`, move newly-shipped work into `Shipped, watch for` (and retire items there once they're confirmed stable), update `Held back (and why)`, keep `Decided (don't revisit)` cumulative (drop an entry only when the decision is genuinely reopened), and **delete whatever is now obsolete**. The result is one current-state page that replaces the old one — not a new entry added above it. Bump the `updated: YYYY-MM-DD` in the title and **refresh the ground-truth footer** (branch, sha, dirtiness, session id) to this session's values. Do not preserve the previous version inside the file; this is a living note, not a changelog (git already has the history when the file is tracked).

- **Different / unrelated thread** → don't graft it onto an unrelated note. Prefer a **separate file** (e.g. `.claude/handoff-<thread>.md`) so each thread stays a clean one-screen page. If the user wants to reuse the same file, **ask** whether to replace the existing note or keep both as side-by-side `## <thread>` sections — never silently overwrite an unrelated note.

When in doubt about whether it's the same thread, ask rather than guess — overwriting the wrong note loses real context.

The note's title is a single top-level heading (`# <thread name> — working state …`), which is what `/pickup` reads. Do **not** use a `---` rule inside the note as a structural separator: keep the section `##` headings as the structure.

## Step 3 — Gitignore awareness

If the destination is inside a git repository and the file is **not** gitignored, the snapshot will be committed with the project. Unless the user clearly wants that, warn them and offer to add the path to `.gitignore`. A snapshot written outside any repo (e.g. on the Desktop) needs no such check.

## Step 4 — Leave a pointer (discoverability)

So a fresh session in any directory can find this handoff, prepend one line to `~/.claude/handoff-index.md` (create the file and `~/.claude/` if needed):

```text
- YYYY-MM-DD HH:MM — <absolute path> — <work|ideas> — <one-line goal or title>
```

The template tag (`work` or `ideas`) and the goal let `/pickup` choose the right snapshot and pick the right verification without opening each file. Newest entry first. This is an append-only index of pointers, not a copy of the snapshot — never write snapshot content here. `/pickup` reads it to locate the latest handoff when the current repo has none. If the same path already appears, move it to the top with the new timestamp rather than duplicating it.

## Step 5 — Confirm

Report: the absolute path written, which template was used, whether you revised an existing note in place or started a fresh one, and that the pointer index was updated. If any durable rules ended up in the note, name them here and suggest moving them to `CLAUDE.md` (see the note in Step 1). Keep it human-readable. A contributor with zero context should be able to read it and know what is going on and what to do next.

## Archive mode (`archive`)

Invoked as `/handoff archive` (optionally `/handoff archive <thread name>` or with a path). Use it when a thread is **done** — shipped, closed, nothing left to pick up — so the active handoff always describes *live* work, not finished work. This replaces the normal Steps 1-5.

1. **Resolve the note.** Same as a normal handoff: the path argument if given, else `.claude/handoff.md` in the current working directory. If it does not exist, say so and stop. If the file holds several `## <thread>` sections and the user named one, operate on just that section; otherwise on the whole note.

2. **Check it is actually finished.** If `Next / blocked` or `Held back (and why)` still lists open items, point them out and confirm the user really wants to archive — archiving a thread with live work buries context. When in doubt, ask.

3. **Move it to the archive.** Write the note (or the single section) to `handoff-archive/<slug>-YYYY-MM-DD.md` beside the source file, creating `handoff-archive/` if needed. `<slug>` is the kebab-cased thread name from the title (fallback `handoff`). The archive folder sits next to the source, so it inherits the same gitignore status; if the active handoff was gitignored, confirm the archive folder is too.

4. **Clear the active slot.** Remove the archived content from the active file: if it was the whole note, delete the active file; if it was one section of a multi-thread file, drop just that section and leave the rest intact.

5. **Update the index.** Remove the now-dead active-path entry from `~/.claude/handoff-index.md` (if the active file is gone). Do **not** add the archived path — archives are retired, not routine `/pickup` targets.

6. **Confirm.** Report the archive path, what was cleared from the active file, and the index update.
