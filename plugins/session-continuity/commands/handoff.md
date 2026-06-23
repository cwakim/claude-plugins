---
description: Save a portable, human-readable snapshot of this conversation to a markdown file, so a fresh Claude or a human can pick up the thread without replaying the whole chat.
---

# Handoff

Distill the current conversation into a compact, portable markdown snapshot and write it to a file.

This is **not** a context restore. Unlike resuming a session (which replays the whole raw transcript), a handoff is a deliberate, lossy summary: the substance, not the noise. The goal is that a fresh session, a different machine, or a human contributor can continue from a single readable page instead of rehydrating a long, messy thread.

## Arguments (`$ARGUMENTS`)

Parse optional arguments, in any order:

- **A path** (anything containing `/` or ending in `.md`) → the destination file. Expand a leading `~`. Examples: `~/Desktop/auth-refactor.md`, `notes/that-chat.md`.
- **The word `ideas`** (or `capture`) → use the **idea-capture** template instead of the default work template.
- No path given → default to `.claude/handoff.md` in the current working directory (create `.claude/` if needed).
- No mode word given → use the **work** template.

## Step 1 — Choose the template

**Work template** (default, for resuming a task):

```markdown
# Handoff — YYYY-MM-DD

## Goal
The overarching objective, 1-3 sentences.

## Done
What is complete and verified. Cite ground truth (branch names, commit hashes,
file paths) rather than re-describing code that the repo already holds.

## In play
Files / branches currently being touched.

## Next / blocked
The immediate next step, or the exact thing we are stuck on. Be specific.

## Constraints
Workflow rules, preferences, and gotchas that must stay in effect.
```

If the session covered **several parallel threads** (e.g. different repos or unrelated tasks), repeat `## Goal` / `## Done` / `## Next` per thread under a `### <thread name>` heading rather than flattening them into one list. Date any fact whose freshness matters (`as of YYYY-MM-DD`), and flag anything you suspect has since drifted with a short `STALE?` note — a picker-up trusts a dated, hedged fact more than a confident stale one.

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

## Step 2 — Preserve history (never clobber)

If the destination file already exists, do **not** overwrite it. Read it first, then write the **new** snapshot at the top, separated from the existing content by a single blank line, followed by that existing content verbatim. Newest snapshot is always first. If the file has grown long with many old snapshots you may trim the oldest, but never drop the immediately preceding one.

Each snapshot is delimited by its own dated top-level heading (`# Handoff — YYYY-MM-DD` or `# Conversation snapshot — YYYY-MM-DD`), which is what `/pickup` splits on. Do **not** use a `---` rule as the separator: a snapshot body can legitimately contain one, which would split it mid-snapshot. The heading is the boundary.

## Step 3 — Gitignore awareness

If the destination is inside a git repository and the file is **not** gitignored, the snapshot will be committed with the project. Unless the user clearly wants that, warn them and offer to add the path to `.gitignore`. A snapshot written outside any repo (e.g. on the Desktop) needs no such check.

## Step 4 — Leave a pointer (discoverability)

So a fresh session in any directory can find this handoff, prepend one line to `~/.claude/handoff-index.md` (create the file and `~/.claude/` if needed):

```text
- YYYY-MM-DD HH:MM — <absolute path> — <work|ideas> — <one-line goal or title>
```

The template tag (`work` or `ideas`) and the goal let `/pickup` choose the right snapshot and pick the right verification without opening each file. Newest entry first. This is an append-only index of pointers, not a copy of the snapshot — never write snapshot content here. `/pickup` reads it to locate the latest handoff when the current repo has none. If the same path already appears, move it to the top with the new timestamp rather than duplicating it.

## Step 5 — Confirm

Report: the absolute path written, which template was used, whether a prior snapshot was preserved, and that the pointer index was updated. Keep it human-readable. A contributor with zero context should be able to read it and know what is going on and what to do next.
