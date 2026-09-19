# .githooks

Git hooks for this repository, tracked so they are visible in diffs and
survive a fresh clone. Git does not pick them up on its own — enable them
once per clone:

    git config core.hooksPath .githooks

`core.hooksPath` replaces `.git/hooks` wholesale, so the Git LFS hooks
(`post-commit`, `post-checkout`, `post-merge`) live here too, unchanged, and
`pre-push` ends by handing over to `git lfs pre-push`.

| hook | what it does |
|---|---|
| `pre-commit` | refuses a commit on `main`; refuses a commit that changes a published package without bumping its version; drops the `index.xml` entry of a package whose main script is deleted; otherwise syncs `<version>` in `index.xml` and stages it |
| `pre-push` | refuses a push to `main` whose commit has a package version disagreeing with `index.xml`, or an entry whose main script is missing from the commit, then runs the LFS hook |

Both derive everything from `index.xml`: each `<reapack>`, its version, and the
repo paths in its `<source>` URLs. Adding a package to `index.xml` is enough —
the hooks never need editing.

A version is `local major_version` `.` `local minor_version`, read from the
package's `main` source. Versions are read from the *staged* blob (or, in
`pre-push`, from the commit being pushed), never from the working copy.

Escape hatches, for when the rule is genuinely wrong:

    ALLOW_MAIN_COMMIT=1 git commit ...   # committing on main on purpose
    git commit --no-verify ...           # skip the checks entirely
