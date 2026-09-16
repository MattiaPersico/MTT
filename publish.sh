#!/bin/sh
# Publish: bring main up to DEV and push it.
#
# index.xml serves its <source> URLs from the main branch, so this script is
# what makes work downloadable. Everything before it happens on DEV.
#
#   ./publish.sh            fast-forward main to DEV (default)
#   ./publish.sh --no-ff    same, but leave one merge commit per release
#   ./publish.sh --dry-run  say what would happen, change nothing
#
# It refuses rather than repairs: a dirty tree, a diverged branch or an
# index.xml that disagrees with a script all stop it with a message.

set -eu

NOFF=""
DRY=""
for a in "$@"; do
  case "$a" in
    --no-ff)   NOFF="--no-ff" ;;
    --dry-run) DRY="yes" ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

die() { printf '\n%s\n\n' "$*" >&2; exit 1; }
run() { if [ -n "$DRY" ]; then printf '  would run: %s\n' "$*"; else printf '  %s\n' "$*"; "$@"; fi; }

ROOT=$(git rev-parse --show-toplevel) || die "not inside a git repository."
cd "$ROOT"

SOURCE=DEV
TARGET=main
REMOTE=origin

# --- preconditions -----------------------------------------------------------

[ -z "$(git status --porcelain)" ] || {
  git status --short >&2
  die "Working tree is not clean. Commit on $SOURCE first, or stash — publishing
  must ship exactly what is committed."
}

git show-ref --verify --quiet "refs/heads/$SOURCE" || die "no local $SOURCE branch."

printf '\nfetching %s\n' "$REMOTE"
git fetch --quiet "$REMOTE"

ahead=$(git rev-list --count "$REMOTE/$SOURCE..$SOURCE")
behind=$(git rev-list --count "$SOURCE..$REMOTE/$SOURCE")
[ "$behind" = "0" ] || die "$SOURCE is $behind commit(s) behind $REMOTE/$SOURCE.
  Someone else pushed, or you are on an old clone. Pull $SOURCE and re-run."

# --- what is about to be published -------------------------------------------

pending=$(git log --oneline "$REMOTE/$TARGET..$SOURCE")
[ -n "$pending" ] || die "$SOURCE has nothing that $REMOTE/$TARGET does not already have.
  Nothing to publish."

printf '\nabout to publish:\n'
printf '%s\n' "$pending" | sed 's/^/  /'

# --- the versions these commits declare --------------------------------------

LIB="$ROOT/.githooks/lib"
if [ -f "$LIB/reapack-common.sh" ] && [ -f "$ROOT/index.xml" ]; then
  . "$LIB/reapack-common.sh"
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  git show "$SOURCE:index.xml" > "$tmp/index.xml"
  awk -f "$LIB/reapack-index.awk" < "$tmp/index.xml" > "$tmp/records"
  : > "$tmp/bad"; : > "$tmp/list"
  grep '^P'"$TAB" "$tmp/records" | while IFS="$TAB" read -r _ pkg idxver mainpath; do
    [ -n "$mainpath" ] || continue
    sv=$(git show "$SOURCE:$mainpath" 2>/dev/null | rp_script_version) || true
    [ -n "$sv" ] || continue
    if [ "$sv" = "$idxver" ]; then
      printf '  %-58s %s\n' "$pkg" "$sv" >> "$tmp/list"
    else
      printf '  %s: script says %s, index.xml says %s\n' "$pkg" "$sv" "$idxver" >> "$tmp/bad"
    fi
  done
  if [ -s "$tmp/bad" ]; then
    printf '\nindex.xml is out of sync on %s:\n\n' "$SOURCE" >&2
    cat "$tmp/bad" >&2
    die "Run a commit on $SOURCE so the pre-commit hook rewrites index.xml, then
  publish again. (A commit made with --no-verify leaves exactly this.)"
  fi
  printf '\nversions going live:\n'
  cat "$tmp/list"
fi

# --- do it -------------------------------------------------------------------

printf '\n'
if [ "$ahead" != "0" ]; then
  printf 'pushing %s (%s commit(s) ahead)\n' "$SOURCE" "$ahead"
  run git push "$REMOTE" "$SOURCE"
else
  printf '%s already in sync with %s/%s\n' "$SOURCE" "$REMOTE" "$SOURCE"
fi

printf '\nmoving %s\n' "$TARGET"
run git switch "$TARGET"
run git merge --ff-only "$REMOTE/$TARGET"
if [ -n "$NOFF" ]; then
  run git merge --no-ff -m "Release: $SOURCE -> $TARGET" "$SOURCE"
else
  run git merge "$SOURCE"
fi
run git push "$REMOTE" "$TARGET"

printf '\nback to %s\n' "$SOURCE"
run git switch "$SOURCE"

if [ -n "$DRY" ]; then
  printf '\ndry run: nothing changed.\n\n'
else
  printf '\npublished. %s at %s, %s at %s\n\n' \
    "$SOURCE" "$(git rev-parse --short "$SOURCE")" \
    "$TARGET" "$(git rev-parse --short "$TARGET")"
fi
