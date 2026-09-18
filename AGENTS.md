# MTT — REAPER scripts published through ReaPack

## Branches

- **`DEV` is where work happens.** Commit here, always.
- **`main` is the distribution branch, not a milestone.** `index.xml` serves its
  `<source>` URLs from `raw.githubusercontent.com/MattiaPersico/MTT/main/...`, so
  whatever sits on `main` is what users download. It moves only by publishing.

## Publishing

`./publish.sh` is the whole procedure: push DEV, move main onto it, push main.
`--dry-run` prints the steps without doing them, `--no-ff` leaves one merge
commit per release. Never assemble the sequence by hand.

## Versions

A published script declares `local major_version` / `local minor_version` near
the top. `index.xml` carries the same number in `<version name="...">`, and the
`pre-commit` hook copies it there — that number is never edited by hand.

**A change to a published script needs its `minor_version` bumped in the same
commit.** ReaPack offers an update only when the number changes: new code under
an old number reaches nobody.

## Hooks

Enabled per clone with `git config core.hooksPath .githooks` (see
`.githooks/README.md`).

- `pre-commit` refuses a commit on `main`, and refuses a commit that changes a
  published package without a bump.
- `pre-push` refuses a push to `main` whose versions disagree with `index.xml`.

**Never pass `--no-verify`.** It skips exactly the checks that keep `index.xml`
honest, and what it leaves behind is a repo publishing new code under an old
version number.

## Script notes

Every script has a note at `.notes/<its path>.md` — `Testing/mtt_Shelf.lua` becomes
`.notes/Testing/mtt_Shelf.md`. The format and every rule for writing one live in
`.notes/_TEMPLATE.md`: read that file before writing to a note for the first time in a
thread, and do not restate its rules anywhere else.

- **Before changing a script, read its note.** It carries what has already been ruled out,
  where the last session stopped, and what the user still wants. Answering a question
  about a script is not changing it.
- **If the note does not exist, create it from the template in the same pass.** `mkdir -p`
  its folder first — `write_file` does not create directories. Fill "What it is" from the
  code; leave "Ruled out" and "Wanted" empty: you were not there for the first, and the
  second is not yours to write.
- **When the work would be reported as done, rewrite "Where we left off" in full**, in that
  same reply — not a turn later. Rewriting means the previous Done lines are gone, not
  pushed down: anything still open moves to "Waiting on". No git state goes in the note —
  `updated:` is the date and nothing else.
- **The note is committed with the change it describes**, in the same commit: a note that
  lands a commit later describes a tree that no longer exists.
- **"Wanted" is the user's list.** Implementing an entry and leaving it in the list is a
  failed pass: delete it in the same reply and renumber what remains. Never add, reword,
  reorder or prune one.

## Scratch

`.scratch/` at the repo root is this project's scratch directory: disposable, gitignored,
never committed. Pure Lua logic that can be tried outside REAPER is extracted and run
there (see the `reaper-lua` skill); nothing else belongs in it, and nothing in it is ever
part of the work.
