---
description: Audit the project's persistent memory for rot (stale claims, contradictions, duplicates, index drift), verify what the project itself can prove, and fix the rest through one confirmed docket.
---

# Memory Gardener

Audit this project's persistent memory directory and clean it up. Memory rots in
predictable ways: "not yet done" flags that got done, entries that contradict newer
ones, duplicates saved in different sessions, index lines drifting from file
contents, and facts the repo now records on its own. Most of that staleness is
verifiable from the project itself, so verify it yourself first and bring the user
only the residue that a human has to answer.

The contract: **housekeeping is silent, meaning changes are confirmed.** You may
fix a broken index line on your own, but you never rewrite, merge, or delete what
a memory *claims* without showing it in the docket and getting a yes.

## Arguments

`$ARGUMENTS` is optional and freeform:

- **A memory type** (`user`, `feedback`, `project`, `reference`) limits the audit
  to memories of that type. Multiple types may be given.
- **`--older-than <N>d`** only audits memory files whose last modification is more
  than N days ago (per `stat`/`git log` on the file).
- **`--dry-run`** stops after presenting the docket: no questions, no edits, no
  deletions. (It still writes the docket artifact; see State directory.)
- **`schedule`** sets up a local scheduled job (cron, or launchd on macOS)
  that runs the dry-run periodically; follow the **Schedule mode** section
  instead of steps 1-5.
- **`unschedule`** removes that job; see Schedule mode.

Examples: `/garden`, `/garden project`, `/garden feedback --older-than 60d`,
`/garden --dry-run`, `/garden schedule`, `/garden unschedule`.

## State directory

The gardener keeps its bookkeeping in `~/.claude/projects/<slug>/garden/`
(sibling of the `memory/` store, never inside it, so it can't pollute the
audit):

- `docket.md`: the docket from the most recent audit (written on every run,
  including dry-runs, so a scheduled headless dry-run leaves its findings
  behind for a human to read).
- `needs-real-run`: marker containing the count of open items (confirmed
  stale + suspected). Written when that count is > 0, deleted when it is 0.
- `last-real-run`: epoch timestamp of the last completed real run.
- `last-nudge`, `cron.log`: used by the SessionStart nudge hook and the cron
  job respectively.

The plugin's SessionStart hook reads this directory to nudge at session start:
with a fresh `docket.md` + `needs-real-run` it reports the actual finding count
(evidence nudge); otherwise it falls back to a rate-limited heuristic (how many
memory files changed since `last-real-run`). A real run clearing the artifacts
is what silences the nudge.

## Step 0: Locate the memory store

Use the memory directory declared in your system prompt's Memory section. If none
is declared, derive it from the working directory: Claude Code stores per-project
memory at `~/.claude/projects/<slug>/memory/` where `<slug>` is the absolute
project path with `/` replaced by `-`.

If the directory does not exist or has no memory files, say so and stop; there is
nothing to garden.

The expected shape is the current Claude Code convention: a `MEMORY.md` index
(one pointer line per memory) plus one file per fact with YAML frontmatter
(`name`, `description`, `metadata.type`) and `[[name]]` links between memories.
**Probe rather than assume.** If the store deviates (no index, different
frontmatter, extra files), adapt to what is actually there and note the deviation
in the report instead of "fixing" the user's format.

## Step 1: Mechanical audit (silent housekeeping)

Read `MEMORY.md` and every memory file. Collect:

- Index lines pointing at files that do not exist.
- Memory files missing from the index.
- `[[links]]` naming a memory that does not exist. (These are allowed by
  convention as "worth writing later" markers; flag them as FYI, do not remove.)
- Malformed or missing frontmatter (`name` mismatching the filename, missing
  `description` or `metadata.type`).
- Index descriptions that no longer match the file's actual content.

These are structural fixes that change no meaning: apply them without asking, and
list what was fixed in the final report under "housekeeping."

## Step 2: Evidence check (verify, do not ask)

For each memory in scope, test its claims against reality before considering a
question to the user:

- **Repo-checkable claims.** A memory naming a file, directory, branch, command,
  flag, config key, or feature: check the working tree, `git branch`, and project
  config for it. A memory saying something is "not yet done" or "planned": look
  for evidence it since happened (the code exists, the frontmatter is there, the
  branch merged).
- **Cross-memory contradictions.** Two memories asserting incompatible facts.
  Newer file wins as the *suspected* truth, but the resolution still goes through
  the docket.
- **Duplication of the repo's own record.** Memory should not store what the
  project already records (CLAUDE.md, README, code structure, git history). A
  memory that is now fully covered by a checked-in doc is a delete candidate.
- **Near-duplicate memories.** Two files covering the same fact are a merge
  candidate: propose one merged file and which filename survives.
- **Time drift.** Relative dates ("last week", "currently") and claims tied to a
  date that has passed.

Label every finding **confirmed** (you have the evidence in hand; cite it) or
**suspected** (plausible but unverifiable from the machine: personal facts,
intentions, off-repo state like an external service or another machine).

## Step 3: The docket (one batched review, not a quiz)

Present a single compact docket grouped as:

1. **Housekeeping** (already fixed in step 1, listed for transparency).
2. **Confirmed stale**, each with the evidence and the proposed edit, merge, or
   deletion.
3. **Suspected**, phrased as questions only a human can answer.
4. **Merge proposals** for near-duplicates.

Then, **write the docket artifact** (both dry and real runs): save the docket to
`~/.claude/projects/<slug>/garden/docket.md`, and write the open-item count
(confirmed stale + suspected) to `needs-real-run` beside it, or delete that
marker if the count is 0.

Then:

- Under `--dry-run`, stop here.
- Otherwise ask the **suspected** items via `AskUserQuestion`, batched into as few
  calls as possible (it takes up to 4 questions per call). Never walk the list one
  memory at a time; in a healthy store this is 2 or 3 questions total.
- Ask one final confirmation for the whole set of proposed meaning changes
  (edits, merges, deletions). Proceed only on an explicit yes; honor partial
  approval if the user picks a subset.

## Step 4: Apply

On confirmation:

1. Apply edits and merges first. When merging, keep the richer file, fold in the
   unique content from the other, and update every `[[link]]` that pointed at the
   retired name.
2. Apply deletions last.
3. Rewrite the affected `MEMORY.md` index lines so the index matches the files
   exactly.
4. Record the run: `date +%s` into the state directory's `last-real-run`, and
   delete `docket.md` and `needs-real-run` there. This is what resets the
   SessionStart nudge.

## Step 5: Report

Summarize: memories audited, housekeeping fixes, confirmed-stale items updated,
merges, deletions, questions answered, and anything deliberately left alone
(including dangling `[[links]]` kept as future markers). If nothing was wrong,
say the store is clean and how many memories were checked.

Finally, if this project has no scheduled audit yet (both `crontab -l
2>/dev/null | grep "# memory-gardener:<slug>"` and `launchctl print
gui/$(id -u)/local.memory-gardener.<slug>` come up empty), mention once that
`/garden schedule` can run the dry-run automatically and leave a docket for
the session-start nudge. Just mention it; do not set anything up unasked.

## Schedule mode (`schedule` / `unschedule`)

Sets up (or removes) a **local scheduled job** that runs the dry-run headlessly
on a cadence and leaves its docket in the state directory, upgrading the
SessionStart nudge from heuristic to evidence-based. Local, not a cloud
routine: the memory store lives on this machine, so a cloud agent cannot read
it. Two schedulers are supported: **cron** (everywhere) and **launchd**
(macOS only). The difference that matters: cron silently skips a run if the
machine is asleep or off at the scheduled time; launchd runs a missed job as
soon as the machine wakes (though not if it was fully powered off).

**`unschedule`:** remove this project's job, whichever scheduler holds it
(check both), and confirm:
```bash
# cron entry, if present
crontab -l 2>/dev/null | grep -v "# memory-gardener:<slug>" | crontab -
# launchd agent, if present
launchctl bootout gui/$(id -u)/local.memory-gardener.<slug> 2>/dev/null
rm -f ~/Library/LaunchAgents/local.memory-gardener.<slug>.plist
```

**`schedule`:**

1. Compute the project slug (as in Step 0) and check for an existing job
   under **both** schedulers (the crontab marker and the launchd agent, as in
   the Step 5 nudge check). If one exists, show it and ask whether to replace
   or keep it; replacing may also mean switching scheduler, in which case
   remove the old job as in `unschedule`.
2. On macOS (`uname` is `Darwin`), ask which scheduler via `AskUserQuestion`,
   recommending launchd: a laptop asleep at the scheduled time misses cron
   runs entirely, while launchd catches up on wake. Offer cron for users who
   prefer keeping everything in one crontab. On other platforms, use cron
   without asking.
3. Ask the cadence via `AskUserQuestion` (e.g. weekly Monday 09:00, every two
   weeks, monthly on the 1st; monthly is the sensible default for one
   actively-used project).
4. Resolve the absolute `claude` binary path (`command -v claude`): neither
   scheduler loads the user's shell profile, so a bare `claude` will not be
   found.
5. Install the job. The command is identical under both schedulers; only the
   wrapper differs. The `mkdir -p` matters either way: shell redirection does
   not create directories, so without it the job fails silently on a machine
   where the state dir does not exist yet.

   **cron**: append the entry (never overwrite other lines):
   ```bash
   (crontab -l 2>/dev/null; echo '<min> <hour> <dom> * <dow> cd <abs-project-dir> && mkdir -p <state-dir> && <abs-claude> -p "/memory-gardener:garden --dry-run" --allowedTools "Read,Glob,Grep,Write,Bash" >> <state-dir>/cron.log 2>&1 # memory-gardener:<slug>') | crontab -
   ```

   **launchd**: write
   `~/Library/LaunchAgents/local.memory-gardener.<slug>.plist`:
   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
     <key>Label</key>
     <string>local.memory-gardener.<slug></string>
     <key>ProgramArguments</key>
     <array>
       <string>/bin/zsh</string>
       <string>-lc</string>
       <string>cd <abs-project-dir> &amp;&amp; mkdir -p <state-dir> &amp;&amp; <abs-claude> -p "/memory-gardener:garden --dry-run" --allowedTools "Read,Glob,Grep,Write,Bash" &gt;&gt; <state-dir>/cron.log 2&gt;&amp;1</string>
     </array>
     <key>StartCalendarInterval</key>
     <dict>
       <!-- weekly: Weekday (0=Sun) + Hour + Minute; monthly: Day + Hour +
            Minute -->
     </dict>
   </dict>
   </plist>
   ```
   then validate and load it:
   ```bash
   plutil -lint ~/Library/LaunchAgents/local.memory-gardener.<slug>.plist
   launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/local.memory-gardener.<slug>.plist
   ```

   Either way the `--allowedTools` list is what lets the headless run work
   without a human approving tool calls: reads for the audit, Bash for the
   evidence checks, Write for the docket artifact. Warn the user this grants
   those tools unattended for that run. Both schedulers log to the same
   `<state-dir>/cron.log`.
6. Offer a smoke test: run the exact command once in the foreground and confirm
   it exits cleanly and `docket.md` appears in the state directory. (For
   launchd, `launchctl kickstart gui/$(id -u)/local.memory-gardener.<slug>`
   fires the real job on demand.) Headless runs consume plan/API usage; say
   so when the user picks an aggressive cadence (weekly or tighter).
7. Report what was installed (the crontab line, or the plist path and label)
   and how to remove it (`/garden unschedule`). Note: uninstalling the plugin
   does **not** remove the scheduled job (plugins have no uninstall hook);
   unschedule first.

## Notes

- **Never delete or rewrite a memory's meaning without it appearing in the docket
  and being approved.** The silent lane is strictly structural.
- A memory being old is not evidence it is wrong. Age alone never justifies
  deletion; only contradiction, obsolescence, or duplication does.
- When the user's answer contradicts a memory, update the memory to the answer
  (converting relative dates to absolute) rather than deleting it, unless it is
  genuinely obsolete.
- This command edits only the memory directory. It never modifies the project's
  files, CLAUDE.md included, even when a memory belongs there instead; propose
  that move in the report and let the user do it.
