---
name: reapack-publish
description: "MTT repo git work: commit or push on DEV, publish DEV to main for ReaPack ('committa', 'pusha', 'pubblica', 'mergia DEV in main', 'porta DEV in main'), recover work done on main ('ero su main per sbaglio'). Any task on this repo's branches, index.xml versions or hooks."
license: MIT
---

# MTT: commit, publish, recover

The repo's `AGENTS.md` has the facts (DEV/main, versions, hooks). This skill is the procedures.

## Commit on DEV
1. `git status --short` + `git diff`: read what changed. Commit only what the user asked for.
2. `git rev-parse --abbrev-ref HEAD` — not DEV? Go to "Work ended up on main".
3. Message from `git diff` + the style of `git log --oneline -5` (`Subject: what`). Nothing else: no ancestry, no file history, no "which commit touched it". Two unrelated changes → two commits.
4. `git add <paths>`, `git commit -m "..."`, `git push`.

The hook refuses (a package changed without a bump)? Do not retry. Report the package; bump its `minor_version` only if the user asked for a change they consider released, otherwise hand it back — the number is theirs.

## Publish
`./publish.sh` is the whole procedure: pushes DEV, fast-forwards main onto it, pushes main; refuses on a dirty tree, a diverged branch, or an `index.xml` that disagrees with a script. `--dry-run` shows the steps; `--no-ff` leaves one merge commit per release.
- Never switch/merge/push by hand instead.
- Paste its "versions going live" block: that is what ReaPack will offer.
- It refuses? Report the reason verbatim and stop: each refusal names its fix.

## Work ended up on main
`git status --short` + `git log --oneline origin/main..main` decide the case:
- Nothing committed: `git stash`, `git switch DEV`, `git stash pop` (main untouched). A conflict → stop, hand it back.
- Committed, not pushed — in this order:
  ```
  git switch DEV
  git merge main
  git log --oneline DEV..main      # must be empty before the next command
  git branch -f main origin/main
  ```
  Moving main first strands the commits. Never `reset --hard`.
- Already pushed to main: it is live. No history rewrite, no force-push. `git switch DEV`, `git merge main`; tell the user it is published and let them decide on a follow-up release.

## Rules
- Never pre-flight the hooks (no reading `.githooks/*`, no `git lfs` checks, no grepping `index.xml`): run the command; the hook's message is the check.
- Verify once, at the end: one `git log --oneline -3` + one `git status --short`.
- Reply = what was committed and where it went, with the actual output ("Already up to date." included). Git internals only if they changed what you did, in one line.
- Never `reset --hard`, `checkout -- <file>`, `clean -f`, `push --force`, `--no-verify`. If one seems needed, stop and say why.
- A fast-forward is not a merge commit. Claim divergence only after reading `git branch -vv`.
