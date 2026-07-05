# session-continuity

Two commands for carrying a conversation across the gap between sessions, machines, or people.

- **`/handoff`** — distill the current conversation into a compact, human-readable markdown snapshot and save it to a file.
- **`/pickup`** — read a snapshot back and continue from it, after checking it still matches reality.

## Why not just resume the session?

Restoring a session replays the entire raw transcript: every dead end, every correction, all the noise. A handoff is the opposite, a deliberate, lossy summary of just the substance. That makes it:

- **Portable** — it is a file, so it travels to another machine, repo, or person. It is not tied to a local session store.
- **Human-readable** — a contributor can read it. A session restore is for the model only.
- **Cheap** — a fresh session reads one page instead of burning its context window rehydrating a huge thread.
- **Durable** — it survives a cleared history, a new model, or a two-week vacation.

It is a baton pass, not a context restore.

## Usage

```text
/handoff                         # work snapshot → .claude/handoff.md in this repo
/handoff ~/Desktop/that-chat.md  # write somewhere else
/handoff ideas                   # capture an idea/discussion instead of task state
/handoff archive                 # retire a finished thread to handoff-archive/
/pickup                          # read .claude/handoff.md and continue
/pickup ~/Desktop/that-chat.md   # pick up from a specific file
/pickup auth refactor            # find a thread by name via the pointer index
/pickup list                     # show every live handoff across repos
```

`/handoff` keeps one **living current-state note** per thread: on a repeat handoff it revises that page in place — folding in new progress, retiring finished items, dropping what's obsolete — rather than stacking a dated entry, so the file stays roughly one screen instead of growing into a diary. It warns before writing an un-ignored file inside a git repo, and starts a separate file (or asks) for an unrelated thread. Each work note records what was **decided and why** (so a fresh session does not relitigate settled questions) and ends with a **ground-truth footer**: the branch, commit, tree state, and session id at the moment of handoff. When a thread is done, `/handoff archive` moves its note into a `handoff-archive/` folder and clears the active slot, so the live handoff only ever describes live work.

`/pickup` reports how old the note is and verifies it before acting: with a ground-truth footer it can diff mechanically (`git log <sha>..HEAD` shows exactly what landed since), otherwise it falls back to `git status` for a work note or the referenced resources for an idea capture, checking harder the staler the note is. If the summary proves too lossy, the recorded session id is a rip cord (`claude --resume <id>` on the original machine). `/pickup <thread name>` finds a thread by name via the pointer index, `/pickup list` shows everything in flight across repos, and picking up a file from `handoff-archive/` offers to revive the thread. When pickup walks the pointer index it prunes entries pointing at deleted files so the index stays clean.

The plugin also ships a **PreCompact hook**: when Claude Code is about to auto-compact the conversation (the moment context becomes lossy), it reminds you to `/handoff` first, noting how stale the current note is.

One caveat: the pointer index lives at `~/.claude/handoff-index.md`, so it does not travel between machines even though the notes themselves do. On a new machine, pass `/pickup` an explicit path once and the index picks up from there.

## Install

```text
/plugin marketplace add cwakim/claude-plugins
/plugin install session-continuity@cwakim-plugins
```
