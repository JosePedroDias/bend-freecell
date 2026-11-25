#!/bin/sh
# ===================================================================
# Build the browser game: one self-contained freecell.html.
# ===================================================================
# bend bundles the page — web.html, its inline UI and the bend code
# it imports (web.bend, freecell.bend, solver.bend, plays.bend) — into
# web-dist/ as one JavaScript chunk. This script then splices that
# chunk back into the page, in place of the inline module, so the
# result is a single file that opens with a double-click: no
# server, no network, no build left behind at run time.
#
#   ./build-web.sh          # writes freecell.html
#
# The chunk is an ES module with no imports or exports of its own,
# so it runs inlined. web-dist/ is kept too, for hosting the
# two-file version as-is.
set -e
cd "$(dirname "$0")"

BEND="$(command -v bend || true)"
[ -n "$BEND" ] || BEND="$HOME/.bend/bin/bend"

echo "bundling the page…"
rm -rf web-dist
"$BEND" web.html -o web-dist

chunk=$(ls web-dist/chunk-*.js | head -n 1)
if grep -q '</script' "$chunk"; then
  echo "build-web: the bundle contains '</script', which would cut the page short" >&2
  exit 1
fi

echo "splicing in $chunk"
awk -v chunk="$chunk" '
  !open && /<script type="module">/ { print; while ((getline line < chunk) > 0) print line; print "</script>"; open = 1; next }
  open && /<\/script>/ { open = 0; next }
  open { next }
  { print }
' web.html > freecell.html

echo "wrote freecell.html ($(wc -c < freecell.html | tr -d " ") bytes)"
