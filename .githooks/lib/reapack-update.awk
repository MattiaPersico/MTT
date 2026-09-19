# Rewrite index.xml on stdin, stamping AUTHOR / TIME on every <version> it
# rewrites. Two inputs:
#   MAP     pkg TAB new-version -> rewrite the package's <version name>
#   REMOVE  one pkg per line    -> delete the package's whole <reapack> block,
#                                  and its <category> if the deletion empties it
# Lines that survive are printed byte for byte, so a run with an empty REMOVE
# behaves exactly like the version rewrite alone.

BEGIN {
  while ((getline line < MAP) > 0) {
    n = index(line, "\t")
    if (n > 0) newver[substr(line, 1, n - 1)] = substr(line, n + 1)
  }
  close(MAP)
  nremove = 0
  while ((getline line < REMOVE) > 0)
    if (line != "") { remove[line] = 1; nremove++ }
  close(REMOVE)
}

function attr(line, key,   pat) {
  pat = key "=\"[^\"]*\""
  if (match(line, pat)) return substr(line, RSTART + length(key) + 2, RLENGTH - length(key) - 3)
  return ""
}

function flushcat() {
  # Drop the category only if this deletion actually emptied it; an
  # already-empty category (or a run without removals) is left byte-identical.
  if (nremove > 0 && !catcontent && catdropped) return
  printf "%s", catbuf
  catbuf = ""
  catcontent = 0
  catdropped = 0
}

{
  # Inside a dropped <reapack> block, whether in a category or not.
  if (dropping) {
    if ($0 ~ /<\/reapack>/) dropping = 0
    next
  }

  # Inside a buffered <category>: only reached when something is being
  # removed, and the decision (keep / drop) waits for </category>.
  if (incap) {
    if ($0 ~ /<reapack[ \t]+name="/) {
      pkg = attr($0, "name")
      if (pkg in remove) { dropping = 1; catdropped = 1 }
      else done = 0
    }
    if (dropping) { if ($0 ~ /<\/reapack>/) dropping = 0; next }
    t = $0
    gsub(/^[ \t]+/, "", t)
    gsub(/[ \t]+$/, "", t)
    if (t != "" && $0 !~ /<\/category>/) catcontent = 1
    if (pkg != "" && !done && $0 ~ /<version[ \t]+name="/ && (pkg in newver)) {
      sub(/<version[ \t]+name="[^"]*"/, "<version name=\"" newver[pkg] "\"")
      sub(/author="[^"]*"[ \t]+time="[^"]*"/, "author=\"" AUTHOR "\" time=\"" TIME "\"")
      done = 1
    }
    catbuf = catbuf $0 "\n"
    if ($0 ~ /<\/category>/) { flushcat(); incap = 0 }
    next
  }

  if (nremove > 0 && $0 ~ /<category[ \t]/) {
    incap = 1
    catbuf = $0 "\n"
    catcontent = 0
    catdropped = 0
    next
  }

  if ($0 ~ /<reapack[ \t]+name="/) {
    pkg = attr($0, "name")
    if (pkg in remove) { dropping = 1; next }
    done = 0
  }

  if (pkg != "" && !done && $0 ~ /<version[ \t]+name="/ && (pkg in newver)) {
    sub(/<version[ \t]+name="[^"]*"/, "<version name=\"" newver[pkg] "\"")
    sub(/author="[^"]*"[ \t]+time="[^"]*"/, "author=\"" AUTHOR "\" time=\"" TIME "\"")
    done = 1
  }

  print
}
