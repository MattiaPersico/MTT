# Parse a ReaPack index.xml on stdin, emit TAB-separated records:
#   P <pkg> <index-version> <main-path>
#   S <pkg> <source-path>
# Paths are repo-relative and URL-decoded, and come last so spaces are safe.

function hexval(h,   d, j, c, v) {
  d = 0
  for (j = 1; j <= length(h); j++) {
    c = tolower(substr(h, j, 1))
    v = index("0123456789abcdef", c) - 1
    if (v < 0) return -1
    d = d * 16 + v
  }
  return d
}

function urldecode(s,   out, i, c, h, v) {
  out = ""
  i = 1
  while (i <= length(s)) {
    c = substr(s, i, 1)
    if (c == "%" && i + 2 <= length(s)) {
      h = substr(s, i + 1, 2)
      v = hexval(h)
      if (v >= 0) { out = out sprintf("%c", v); i += 3; continue }
    }
    out = out c
    i++
  }
  return out
}

# https://raw.githubusercontent.com/<user>/<repo>/<branch>/<path>
function strip_repo(u) {
  if (match(u, /githubusercontent\.com\/[^\/]+\/[^\/]+\/[^\/]+\//))
    return substr(u, RSTART + RLENGTH)
  return ""
}

function attr(line, key,   pat) {
  pat = key "=\"[^\"]*\""
  if (match(line, pat)) return substr(line, RSTART + length(key) + 2, RLENGTH - length(key) - 3)
  return ""
}

/<reapack[ \t]+name="/ { pkg = attr($0, "name"); ver = ""; mainpath = "" }

/<version[ \t]+name="/ { if (pkg != "" && ver == "") ver = attr($0, "name") }

/<source/ {
  if (pkg != "" && match($0, />[^<]*<\/source>/)) {
    url = substr($0, RSTART + 1, RLENGTH - 10)
    p = strip_repo(url)
    if (p != "") {
      p = urldecode(p)
      printf "S\t%s\t%s\n", pkg, p
      if ($0 ~ /main="/ && mainpath == "") mainpath = p
    }
  }
}

/<\/reapack>/ {
  if (pkg != "") printf "P\t%s\t%s\t%s\n", pkg, ver, mainpath
  pkg = ""; ver = ""; mainpath = ""
}
