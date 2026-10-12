#!/usr/bin/env bash
# Full site build: replaces make.el. Renders every .org with pandoc, copies
# assets, then post-processes (og:image, search index, sitemap, CNAME).
#
# Incremental: a page is re-rendered only when the hash of its inputs (source,
# #+include'd files, template, partials, filters, bibliography, pandoc args,
# build.sh itself) differs from the last build. Hashes live in .cache/build/.
#
# Usage: pandoc/build.sh            # build what changed into docs/
#        pandoc/build.sh --fetch    # also pull new Leaflet posts from the PDS
#        pandoc/build.sh --full     # ignore the cache, rebuild everything
# Requires: pandoc, python3.
set -euo pipefail

FETCH=0 FULL=0
for a in "$@"; do
  case "$a" in
    --fetch) FETCH=1 ;;
    --full)  FULL=1 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
P="$ROOT/pandoc"
OUT="${OUT_DIR:-$ROOT/docs}"
SITE_URL="https://bugarela.com"
CSL="${CSL:-$P/associacao-brasileira-de-normas-tecnicas.csl}"

cd "$ROOT"

CACHE="$ROOT/.cache/build"
mkdir -p "$CACHE"
BUILT=0 SKIPPED=0

# cache-busting stamp for the stylesheets (changes whenever any of them does)
CSSV="$(cat css/layouts/*.css | sha1sum | cut -c1-8)"

# --- change detection -----------------------------------------------------
# Inputs every page depends on, hashed once.
GLOBAL_HASH="$(cat "$P/build.sh" "$P/head.html" "$P/nav.html" "$P/footer.html" | sha1sum | cut -c1-40)"

# input_hash <src> <template> [pandoc args...]: hash of everything the page reads
input_hash() {
  local src="$1" template="$2"; shift 2
  local src_dir a f inc
  src_dir="$(dirname "$src")"
  {
    echo "$GLOBAL_HASH"
    printf '%s\n' "$@"
    cat "$src" "$template"
    # #+include'd files (resolved like render's awk does)
    grep -iE '^[[:space:]]*#\+include:' "$src" | tr -d '\r"' \
      | sed -E 's/^[[:space:]]*#\+[Ii][Nn][Cc][Ll][Uu][Dd][Ee]:[[:space:]]*//; s/[[:space:]].*//' \
      | while read -r inc; do
          [[ "$inc" = /* ]] || inc="$src_dir/$inc"
          [ -f "$inc" ] && cat "$inc"
        done
    # any argument that names a file (filters, --bibliography=, --csl ...)
    for a in "$@"; do
      f="${a#*=}"
      if [ -f "$f" ]; then cat "$f"
      elif [ -f "$src_dir/$f" ]; then cat "$src_dir/$f"
      fi
    done
  } | sha1sum | cut -c1-40
}

# build <src> <out.html> <template> [pandoc args...]: render unless up to date
build() {
  local src="$1" out="$2" stamp hash
  stamp="$CACHE/$(printf '%s' "$out" | sha1sum | cut -c1-40)"
  hash="$(input_hash "$1" "$3" "${@:4}")"
  if [ "$FULL" = 0 ] && [ -f "$out" ] && [ "$(cat "$stamp" 2>/dev/null)" = "$hash" ]; then
    SKIPPED=$((SKIPPED + 1)); return
  fi
  echo "   ${out#"$OUT"/}"
  render "$@"
  echo "$hash" > "$stamp"
  BUILT=$((BUILT + 1))
}

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
  build "$src" "$OUT/mfo/$base.html" "$P/template-mfo.html" -V root="../" -V nav-mfo=true "${flags[@]}"
done

echo ">> mfo index"
build "mfo/index.org" "$OUT/mfo/index.html" "$P/template-mfo.html" \
  -V root="../" -V nav-mfo=true -V mfo-index=true --lua-filter "$P/filters/orglinks.lua"

echo ">> homepage (story layout) + sblp2024 (pages)"
build "index.org" "$OUT/index.html" "$P/template-story.html" \
  -V root="./" -V nav-story=true --lua-filter "$P/filters/orglinks.lua" --lua-filter "$P/filters/sidenotes.lua" --lua-filter "$P/filters/story.lua"
build "sblp2024/index.org" "$OUT/sblp2024/index.html" "$P/template-page.html" \
  -V root="../" --lua-filter "$P/filters/details.lua" --lua-filter "$P/filters/orglinks.lua"

echo ">> pi"
build "pi/index.org" "$OUT/pi/index.html" "$P/template-pi.html" -V root="../" -V nav-pi=true

echo ">> writing (Leaflet posts)"
if [ "$FETCH" = 1 ]; then
  # refresh the committed snapshot; offline builds keep the last one
  python3 "$P/leaflet.py" fetch || echo "   fetch failed, using the last snapshot in writing/posts.json"
else
  echo "   using the snapshot in writing/posts.json (--fetch to refresh from the PDS)"
fi
WTMP="$(mktemp -d)"
python3 "$P/leaflet.py" pages "$WTMP"
mkdir -p "$OUT/writing"
for md in "$WTMP"/*.md; do
  build "$md" "$OUT/writing/$(basename "$md" .md).html" "$P/template-writing.html" \
    -f markdown -V root="../" -V nav-writing=true
done
# drop pages of posts that no longer exist
for html in "$OUT/writing"/*.html; do
  [ -e "$html" ] || continue
  [ -f "$WTMP/$(basename "$html" .html).md" ] || { echo "   removed ${html#"$OUT"/}"; rm -f "$html"; }
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
      dest="$OUT/${f#./}"
      cmp -s "$f" "$dest" 2>/dev/null && continue
      mkdir -p "$(dirname "$dest")"; cp "$f" "$dest"; echo "   ${f#./}"
    done

echo ">> post-process (og:image, search index, sitemap, CNAME)"
python3 "$P/postprocess.py" "$OUT" "$SITE_URL"

echo "OK -> $OUT ($BUILT pages rendered, $SKIPPED up to date)"
