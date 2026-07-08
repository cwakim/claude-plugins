# memory-gardener

One command for the hygiene of Claude Code's persistent per-project memory:
find what rotted, verify what the project itself can prove, and fix the rest
through one confirmed docket.

- **`/garden`** — audit the memory store, self-verify stale claims against the
  repo, ask only the questions a human has to answer, then apply the approved
  edits, merges, and deletions.

## Why

Anyone who uses Claude Code heavily with memory enabled accumulates the same rot:
"not yet done" flags that quietly got done, entries that contradict newer ones,
near-duplicates saved in different sessions, index lines drifting from file
contents, and facts the repo's own docs now record. Left alone, stale memories
get recalled as truth in future sessions.

Cleaning this by hand means rereading every file. `/garden` does the reading for
you, and it is built around two rules:

- **Verify before asking.** Most staleness is checkable from the project itself
  (does the file exist, did the branch merge, is the frontmatter there). The
  command checks evidence first, so the user only answers the genuinely
  unverifiable items — personal facts, intentions, off-repo state. A typical run
  is two or three questions, not a quiz over every memory.
- **Housekeeping is silent, meaning changes are confirmed.** Structural fixes
  (a broken index line, frontmatter drift) are applied automatically and listed.
  Anything that changes what a memory *claims* — an edit, a merge, a deletion —
  goes through a docket and an explicit yes. Deletions are applied last.

## Usage

```text
/garden                          # audit everything, docket, confirm, apply
/garden project                  # only memories of type "project"
/garden feedback --older-than 60d  # only feedback memories untouched for 60+ days
/garden --dry-run                # show the docket, change nothing, ask nothing
/garden schedule                 # set up a recurring dry-run audit (local cron)
/garden unschedule               # remove it
```

## The nudge (knowing *when* to garden)

Memory rots with usage, not time, so the plugin ships a SessionStart hook that
tells you when a run is worth it, instead of you remembering a cadence:

- **Heuristic nudge** (works out of the box): at session start, if enough
  memories changed since the last real run (5+ within two weeks, or any change
  after a month), one line suggests a run. Rate-limited to once a week, silent
  when there is nothing to say, and always exits 0.
- **Evidence nudge** (opt-in via `/garden schedule`): a local cron job runs
  `/garden --dry-run` headlessly on the cadence you pick and saves its docket
  to a state directory (`~/.claude/projects/<slug>/garden/`, outside the repo
  and outside the memory store). The nudge then reports actual findings
  ("the last audit found 7 open items") instead of a guess, and you read the
  docket before deciding. Detection is automatic; decisions stay yours.

It is local cron rather than a scheduled cloud routine on purpose: the memory
store lives on your machine, and a cloud agent cannot read it. The scheduled
run needs `claude` on the machine and consumes plan/API usage per run, so
monthly is a sensible default. A completed real run clears the docket and
silences the nudge.

## Notes

- Age alone never justifies deletion; only contradiction, obsolescence, or
  duplication does.
- Dangling `[[links]]` are kept: by convention they mark memories worth writing
  later, so they are reported as FYI, not removed.
- The command edits only the memory directory. It never touches the project's
  files, even when a fact arguably belongs in CLAUDE.md instead; it proposes
  that move and leaves it to you.
- The memory layout (a `MEMORY.md` index plus one file per fact) is a Claude
  Code convention that may evolve; the command probes the structure it finds
  and adapts rather than hard-assuming the format.
- Uninstalling the plugin does **not** remove a scheduled cron job (plugins
  have no uninstall hook) — run `/garden unschedule` first.

## Install

```text
/plugin marketplace add cwakim/claude-plugins
/plugin install memory-gardener@cwakim-plugins
```
