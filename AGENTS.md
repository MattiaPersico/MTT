# MTT — REAPER scripts published through ReaPack

## Branches, versions, hooks
- Work and commit on `DEV`, always. `main` is what ReaPack users download (through `index.xml`); it moves only through `./publish.sh`, never by hand.
- Published script = it declares `local major_version` / `local minor_version` near the top. A change to it bumps `minor_version` in the same commit: ReaPack offers an update only when the number changes. The `pre-commit` hook copies the versions into `index.xml`: never edit that number by hand.
- `.githooks/` (per clone: `git config core.hooksPath .githooks`) refuse a commit on `main`, a changed published script without a bump, and a push to `main` whose versions disagree with `index.xml` or whose entry lists a deleted script; the `pre-commit` hook drops the `index.xml` entry of a deleted script. Never `--no-verify`.

## Script notes
Every script has three notes in its folder:

    <dir>/<name>.lua          e.g. Testing/mtt_Shelf/mtt_Shelf.lua
    <dir>/<name>.md           what it is + ruled out
    <dir>/<name>.state.md     where the work left off
    <dir>/<name>.wanted.md    the user's list

English, impersonal third person ("the user"; never "I" or a name). A note that disagrees with the code is wrong: fix the note.
- Before changing a script, read its `.state.md` and `.wanted.md` (its `.md` too if unfamiliar), once per thread: after a compaction the summary is newer than the notes. A question about a script is not a change.
- A failed read is not proof a note is missing: list the folder first. Really missing → create all three from `_NOTE_TEMPLATE.md` (repo root) in the same pass: "What it is" from the code, the rest empty.
- Work done, or a change ready for the user's test → before replying, rewrite the whole `.state.md` with `write_file`, never `edit_file` (a partial edit ends up appending):

      # <name> — where we left off

      updated: YYYY-MM-DD
      - Done:
      - Not done:
      - Waiting on:

  Done = only what this session changed (older lines go). Not done = asked for, not delivered, and why. Waiting on = still open, incl. an older change whose check has not come back — a check comes back only in the user's words: quote them. `updated:` = the date only: no commit, branch or "to commit".
- `.wanted.md` is the user's menu, not a queue: do only the entry asked for. Implemented → remove it and renumber, rewriting the file whole. Never add, reword, reorder or prune an entry. Re-read it in the same turn before acting on "number 3".
- `.md`: "What it is" = purpose in one short paragraph, not implementation. "Ruled out" = only a wrong diagnosis with no code line to comment on, one line each: `- YYYY-MM-DD — <symptom>: NOT <wrong cause>. <real cause>`. Any other decision is a comment on its code line.
- Commit the notes in the same commit as the change they describe.

## Scratch
`.scratch/` (gitignored, never committed) is only for running pure-Lua logic outside REAPER (see `reaper-lua`). Nothing in it is part of the work; never clean it up.
