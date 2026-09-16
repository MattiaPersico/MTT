# Rewrite index.xml on stdin, applying the pkg -> version map in MAP
# (TAB-separated), and stamping AUTHOR / TIME on every package it touches.

BEGIN {
  while ((getline line < MAP) > 0) {
    n = index(line, "\t")
    if (n > 0) newver[substr(line, 1, n - 1)] = substr(line, n + 1)
  }
}

function attr(line, key,   pat) {
  pat = key "=\"[^\"]*\""
  if (match(line, pat)) return substr(line, RSTART + length(key) + 2, RLENGTH - length(key) - 3)
  return ""
}

/<reapack[ \t]+name="/ { pkg = attr($0, "name"); done = 0 }

/<version[ \t]+name="/ {
  if (!done && (pkg in newver)) {
    sub(/<version[ \t]+name="[^"]*"/, "<version name=\"" newver[pkg] "\"")
    sub(/author="[^"]*"[ \t]+time="[^"]*"/, "author=\"" AUTHOR "\" time=\"" TIME "\"")
    done = 1
  }
}

{ print }
