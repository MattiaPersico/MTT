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
