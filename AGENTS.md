# MTT — REAPER scripts published through ReaPack

## Branches and publishing
- Work and commit on `DEV`, always.
- `main` is what ReaPack users download (`index.xml` serves `raw.githubusercontent.com/MattiaPersico/MTT/main/...`). It moves only through `./publish.sh`: push DEV, move main onto it, push main (`--dry-run` shows the steps, `--no-ff` = one merge commit per release). Never do the sequence by hand.

## Versions
- A published script declares `local major_version` / `local minor_version` near the top. The `pre-commit` hook copies them into `index.xml` (`<version name="...">`): never edit that number by hand.
- A change to a published script bumps its `minor_version` in the same commit: ReaPack offers an update only when the number changes.

## Hooks
`.githooks/` (enable per clone: `git config core.hooksPath .githooks`). `pre-commit` refuses a commit on `main` and a changed published script without a bump; `pre-push` refuses a push to `main` whose versions disagree with `index.xml`. Never `--no-verify`.

## Script notes
Every script has three notes beside it — same folder, same base name, `.lua` swapped for the suffix. `Testing/mtt_Shelf.lua` →

    Testing/mtt_Shelf.md          what it is + ruled out
    Testing/mtt_Shelf.state.md    where the work left off
    Testing/mtt_Shelf.wanted.md   the user's list

Three files because each is replaced with `write_file`, whole, in one call: nothing to locate or match, so a rewrite cannot degrade into an append. Format and rules: `_NOTE_TEMPLATE.md` at the repo root — read it before your first note write in a thread. All three in English, impersonal third person.
- Before changing a script, read its `.state.md` and `.wanted.md` (and its `.md` if unfamiliar). A question about a script is not a change.
- A failed read is not proof the notes are missing: list the script's folder before concluding it. Really missing → create all three from the template in the same pass, filling "What it is" from the code and leaving "Ruled out" and the wanted list empty.
- Work done → in the same reply, `write_file` its whole `.state.md`, never `edit_file` it: Done = only what this session changed (the previous lines go), Not done = asked for and not delivered + why, Waiting on = still open, including an older change whose check has not come back. `updated:` = the date only, no git state.
- Its `.wanted.md` is the user's menu, not a queue: do only the entry asked for; when you implement one, remove it and renumber, rewriting that file whole. Never add, reword, reorder or prune an entry. Re-read it in the same turn before acting on "number 3".
- Commit the notes in the same commit as the change they describe.

## Scratch
`.scratch/` (gitignored, never committed) is only for running pure-Lua logic outside REAPER (see `reaper-lua`). Nothing in it is part of the work.
