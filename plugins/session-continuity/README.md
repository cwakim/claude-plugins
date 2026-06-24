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
/pickup                          # read .claude/handoff.md and continue
/pickup ~/Desktop/that-chat.md   # pick up from a specific file
```

`/handoff` keeps one **living current-state note** per thread: on a repeat handoff it revises that page in place — folding in new progress, retiring finished items, dropping what's obsolete — rather than stacking a dated entry, so the file stays roughly one screen instead of growing into a diary. It warns before writing an un-ignored file inside a git repo, and starts a separate file (or asks) for an unrelated thread. `/pickup` verifies the note before acting on it — against `git status` for a work note, or against the resources it references for an idea capture.

## Install

```text
/plugin marketplace add cwakim/claude-plugins
/plugin install session-continuity@cwakim-plugins
```
