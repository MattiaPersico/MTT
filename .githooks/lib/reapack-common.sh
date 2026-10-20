# Shared helpers for the ReaPack version hooks. Sourced, never executed.

TAB=$(printf '\t')
RP_AUTHOR="Mattia Persico"

rp_die() { printf '\n%s\n\n' "$*" >&2; exit 1; }

# Version declared inside a script, read from stdin. Lua: local major_version /
# minor_version; JSFX: a "// Version: X.Y" comment. Empty if absent.
rp_script_version() {
  awk '
    /local[ \t]+major_version[ \t]*=/ {
      if (match($0, /=[ \t]*[0-9]+/)) { s = substr($0, RSTART, RLENGTH); gsub(/[^0-9]/, "", s); maj = s }
    }
    /local[ \t]+minor_version[ \t]*=/ {
      if (match($0, /=[ \t]*[0-9]+/)) { s = substr($0, RSTART, RLENGTH); gsub(/[^0-9]/, "", s); min = s }
    }
    # JSFX effects declare "// Version: X.Y" in a comment near the top.
    jsver == "" && match($0, /\/\/[ \t]*Version:[ \t]*[0-9]+(\.[0-9]+)+/) {
      s = substr($0, RSTART, RLENGTH)
      sub(/^\/\/[ \t]*Version:[ \t]*/, "", s)
      jsver = s
    }
    END { if (maj != "" && min != "") print maj "." min; else if (jsver != "") print jsver }
  '
}

# rp_version_lt A B -> true when A is strictly older than B (numeric, M.m).
rp_version_lt() {
  awk -v a="$1" -v b="$2" '
    BEGIN {
      na = split(a, A, "."); nb = split(b, B, ".")
      n = (na > nb) ? na : nb
      for (i = 1; i <= n; i++) {
        x = (i <= na) ? A[i] + 0 : 0
        y = (i <= nb) ? B[i] + 0 : 0
        if (x < y) exit 0
        if (x > y) exit 1
      }
      exit 1
    }'
}
