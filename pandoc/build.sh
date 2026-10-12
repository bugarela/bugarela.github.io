#!/usr/bin/env bash
# Full site build: replaces make.el. Renders every .org with pandoc, copies
# assets, then post-processes (og:image, search index, sitemap, CNAME).
#
# Usage: pandoc/build.sh          # build everything into docs/
# Requires: pandoc, python3.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
P="$ROOT/pandoc"
OUT="${OUT_DIR:-$ROOT/docs}"
SITE_URL="https://bugarela.com"
CSL="${CSL:-$P/associacao-brasileira-de-normas-tecnicas.csl}"

cd "$ROOT"

# cache-busting stamp for the stylesheets (changes whenever any of them does)
CSSV="$(cat css/layouts/*.css | sha1sum | cut -c1-8)"

# --- render one .org -> .html --------------------------------------------
# render <src.org> <out.html> <template> [extra pandoc args...]
render() {
  local src="$1" out="$2" template="$3"; shift 3
  local src_dir src_base tmp lang
  src_dir="$(cd "$(dirname "$src")" && pwd)"
  lang="$(file_lang "$src")"
  mkdir -p "$(dirname "$out")"

  # Expand simple `#+include: file` lines (pandoc's org reader ignores them).
  tmp="$(mktemp --suffix=.org)"
  awk -v dir="$src_dir" '
    /^[[:space:]]*#\+[Ii][Nn][Cc][Ll][Uu][Dd][Ee]:/ {
      s=$0; sub(/^[[:space:]]*#\+[Ii][Nn][Cc][Ll][Uu][Dd][Ee]:[[:space:]]*/,"",s)
      gsub(/[\r"]/,"",s); split(s,a," "); f=a[1]
      path=(f ~ /^\//)?f:dir"/"f
      while ((getline l < path) > 0) print l
      close(path); next
    }
    { print }
  ' "$src" > "$tmp"

  ( cd "$src_dir" && pandoc "$tmp" \
      -f org -t html5 -s \
      --template "$template" \
      --mathjax --section-divs \
      -M lang="$lang" \
      -M description="Personal homepage exported with pandoc" \
      -M site-url="$SITE_URL" \
      -M twitter="bugarela" \
      -V cssv="$CSSV" \
      "$@" \
      -o "$out" )
  rm -f "$tmp"
}

# crude language pick: pt-BR unless the file declares english
file_lang() { grep -qiE '^(#\+LANGUAGE:|lang:)\s*en' "$1" && echo "en" || echo "pt-BR"; }

echo ">> lectures (mfo/*.org)"
for src in mfo/*.org; do
  base="$(basename "$src" .org)"
  [ "$base" = "index" ] && continue

  flags=(--lua-filter "$P/filters/faicons.lua"
         --lua-filter "$P/filters/mermaid.lua"
         --lua-filter "$P/filters/orglinks.lua"
         --citeproc --bibliography=references.bib --csl "$CSL")
  # section numbers only when the file asks for them (#+OPTIONS: num:t)
  grep -q 'num:t' "$src" && flags+=(--number-sections)
  # TOC unless toc:nil and no inline #+TOC:
  if ! grep -q 'toc:nil' "$src" || grep -qi '^#+TOC:' "$src"; then
    flags+=(--toc --toc-depth=3)
  fi
  render "$src" "$OUT/mfo/$base.html" "$P/template-mfo.html" -V root="../" -V nav-mfo=true "${flags[@]}"
done

echo ">> mfo index"
render "mfo/index.org" "$OUT/mfo/index.html" "$P/template-mfo.html" \
  -V root="../" -V nav-mfo=true -V mfo-index=true --lua-filter "$P/filters/orglinks.lua"

echo ">> homepage (story layout) + sblp2024 (pages)"
render "index.org" "$OUT/index.html" "$P/template-story.html" \
  -V root="./" -V nav-story=true --lua-filter "$P/filters/orglinks.lua" --lua-filter "$P/filters/story.lua"
render "sblp2024/index.org" "$OUT/sblp2024/index.html" "$P/template-page.html" \
  -V root="../" --lua-filter "$P/filters/details.lua" --lua-filter "$P/filters/orglinks.lua"

echo ">> pi"
render "pi/index.org" "$OUT/pi/index.html" "$P/template-pi.html" -V root="../" -V nav-pi=true

echo ">> writing (Leaflet posts from the PDS)"
# refresh the committed snapshot; offline builds keep the last one
python3 "$P/leaflet.py" fetch || echo "   fetch failed, using the last snapshot in writing/posts.json"
WTMP="$(mktemp -d)"
python3 "$P/leaflet.py" pages "$WTMP"
rm -rf "$OUT/writing"
for md in "$WTMP"/*.md; do
  render "$md" "$OUT/writing/$(basename "$md" .md).html" "$P/template-writing.html" \
    -f markdown -V root="../" -V nav-writing=true
done
rm -rf "$WTMP"

echo ">> assets"
# Copy binary/static assets, preserving paths, matching make.el's extension set.
find . -type f \( \
     -name '*.ico' -o -name '*.jpg' -o -name '*.jpeg' -o -name '*.gif' \
  -o -name '*.png' -o -name '*.svg' -o -name '*.css' -o -name '*.js'  -o -name '*.pdf' \
  -o -name '*.xml' -o -name '*.zip' -o -name '*.ttf' -o -name '*.woff2' \) \
  -not -path './docs/*' -not -path './templates/*' -not -path './pandoc/*' \
  -not -path './.git/*' -not -path './.jj/*' -print0 \
  | while IFS= read -r -d '' f; do
      dest="$OUT/${f#./}"; mkdir -p "$(dirname "$dest")"; cp "$f" "$dest"
    done

echo ">> post-process (og:image, search index, sitemap, CNAME)"
python3 "$P/postprocess.py" "$OUT" "$SITE_URL"

echo "OK -> $OUT"
