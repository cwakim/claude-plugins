# memory-gardener

Hygiene for Claude Code's persistent per-project memory. One command, `/garden`,
audits the memory store, verifies what the project itself can prove, asks you
only what a human has to answer, and applies fixes through a single confirmed
docket. A session-start nudge tells you *when* a run is worth it, so you never
have to remember a cadence.

## Why

Anyone who uses Claude Code heavily with memory enabled accumulates the same
rot: "not yet done" flags that quietly got done, entries that contradict newer
ones, near-duplicates saved in different sessions, index lines drifting from
file contents, and facts the repo's own docs now record. Left alone, stale
memories get recalled as truth in future sessions.

Cleaning this by hand means rereading every file. `/garden` does the reading
for you, built around two rules:

- **Verify before asking.** Most staleness is checkable from the project itself
  (does the file exist, did the branch merge, is the frontmatter there). The
  command checks evidence first, so you only answer the genuinely unverifiable
  items: personal facts, intentions, off-repo state. A typical run is two or
  three questions, not a quiz over every memory.
- **Housekeeping is silent, meaning changes are confirmed.** Structural fixes
  (a broken index line, malformed frontmatter) are applied automatically and
  listed. Anything that changes what a memory *claims* (an edit, a merge, a
  deletion) goes through a docket and an explicit yes. Deletions are applied
  last.

## How a run works

Every run walks the same four passes:

1. **Mechanical audit.** Read the index and every memory file. Fix structural
   drift silently: index lines pointing nowhere, files missing from the index,
   malformed frontmatter. Nothing here changes what a memory means.
2. **Evidence check.** Test each memory's claims against reality: files,
   branches, config, and "not yet done" flags are checked against the working
   tree and git; memories are checked against each other for contradictions
   and near-duplicates, and against the repo's own docs for redundancy. Every
   finding is labeled **confirmed** (evidence in hand) or **suspected**
   (only a human can know).
3. **The docket.** One compact review: housekeeping done, confirmed-stale items
   with their evidence and proposed fix, suspected items as questions, merge
   proposals. The suspected questions are batched into as few prompts as
   possible. You approve the set (or a subset).
4. **Apply.** Edits and merges first, deletions last, index resynced. The run
   records itself, which is what resets the nudge.

With `--dry-run` the flow stops after pass 3: the docket is presented and saved,
nothing is asked, nothing is changed.

## The nudge lifecycle

Memory rots with usage, not time, so instead of a fixed schedule the plugin
ships a SessionStart hook that watches the store and speaks up at most once a
week, in one line, only when there is something to say. It has two modes:

```text
                       every /garden run
                      (real or --dry-run)
                              |
                     writes docket.md (+ item count)
                              v
   session start ----> pending docket? ----yes----> EVIDENCE NUDGE
        |                     |                     "last audit found N open
        |                     no                     items, docket at <path>"
        v                     v
   heuristic: how many memories changed        a real /garden run clears
   since the last real run?                    the docket and the counter,
        |                                      silencing both nudges
        v
   5+ changes in 14+ days, or any
   change after 30+ days ----> HEURISTIC NUDGE
                               "N memories changed since the
                                last garden K days ago"
```

The heuristic mode works out of the box with zero setup and zero cost: it only
compares file timestamps. The evidence mode activates whenever a dry-run has
left findings behind, which happens naturally if you run `--dry-run` yourself,
or automatically if you schedule it (next section).

The hook is deliberately boring: silent when there is nothing to say, capped at
one heuristic nudge per 7 days, never blocks anything, always exits 0.

## Workflows

### First run on a project

```text
/garden --dry-run     # see the docket, change nothing, get a feel for it
/garden               # the real thing: housekeeping, questions, apply
```

On a store that has never been gardened expect the biggest docket you will ever
see from it (weeks of accumulated drift at once). After that first real run the
baseline is recorded and subsequent runs are small.

### The routine loop (no setup)

Do nothing until nudged. When a session starts with

```text
memory-gardener: 6 of 23 memories changed since the last garden run 31 days ago.
```

finish what you came to do, then run `/garden`. The run takes a few minutes,
asks two or three questions, resets the counter, and the nudge goes quiet
again. This loop alone keeps a store healthy.

### Automated detection (opt-in)

```text
/garden schedule      # pick a cadence; installs a local cron job
```

The cron job runs `/garden --dry-run` headlessly on your cadence and saves the
docket it finds. From then on the session-start nudge is evidence-based:

```text
memory-gardener: the last dry-run audit found 4 open docket item(s)
(docket: ~/.claude/projects/<slug>/garden/docket.md).
```

You read the docket at your leisure and run the real `/garden` only when it
looks worth it. Detection is automatic, decisions stay yours. `/garden
unschedule` removes the job.

Three things to know before scheduling:

- It is **local cron, not a cloud routine**, on purpose: the memory store lives
  on your machine and a scheduled cloud agent cannot read it.
- Each scheduled run is a real headless Claude Code session and **consumes
  plan/API usage**. Monthly is a sensible default for one active project.
- The headless run needs tools pre-approved (`--allowedTools "Read,Glob,Grep,
  Write,Bash"` in the cron line), because nobody is there to click through
  permission prompts. The schedule step shows you the exact line and offers a
  foreground smoke test before trusting it to cron.

### Scoped and filtered runs

```text
/garden project                    # only memories of type "project"
/garden feedback --older-than 60d  # only feedback memories untouched 60+ days
```

Useful once a store is large: scope keeps the docket short and the run fast.

## Command reference

```text
/garden                          # full audit, docket, confirm, apply
/garden --dry-run                # audit + docket only; asks and changes nothing
/garden <type> [...]             # limit to user | feedback | project | reference
/garden --older-than <N>d        # limit to files untouched for N+ days
/garden schedule                 # install the recurring dry-run (local cron)
/garden unschedule               # remove it
```

## State directory

Bookkeeping lives in `~/.claude/projects/<slug>/garden/`, a sibling of the
`memory/` store (never inside it, so it cannot pollute the audit), where
`<slug>` is the project path with `/` replaced by `-`:

| File | Purpose |
|------|---------|
| `docket.md` | Findings from the most recent audit (every run writes it) |
| `needs-real-run` | Open-item count; present only when the docket has substance |
| `last-real-run` | Epoch timestamp of the last completed real run |
| `last-nudge` | Rate-limiter for the heuristic nudge |
| `cron.log` | Output of scheduled headless runs |

Deleting the directory is safe: the plugin regenerates it. Deleting
`last-real-run` just makes the nudge treat the store as never gardened.

## Safety guarantees

- Nothing that changes a memory's **meaning** (edit, merge, deletion) is ever
  applied without appearing in the docket and being approved. The silent lane
  is strictly structural.
- Age alone never justifies deletion; only contradiction, obsolescence, or
  duplication does.
- Dangling `[[links]]` are kept: by convention they mark memories worth writing
  later, so they are reported as FYI, not removed.
- The command edits only the memory directory. It never touches project files,
  even when a fact arguably belongs in CLAUDE.md instead; it proposes that move
  and leaves it to you.

## Install

```text
/plugin marketplace add cwakim/claude-plugins
/plugin install memory-gardener@cwakim-plugins
```

## Notes

- The memory layout (a `MEMORY.md` index plus one file per fact) is a Claude
  Code convention that may evolve; the command probes the structure it finds
  and adapts rather than hard-assuming the format.
- Uninstalling the plugin does **not** remove a scheduled cron job (plugins
  have no uninstall hook). Run `/garden unschedule` first.
