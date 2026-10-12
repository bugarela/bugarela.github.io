# pandoc build (elisp-free)

Replaces `make.el` / ox-thtml. Renders every `.org` to `docs/` with pandoc,
copies assets, and regenerates `search-index.json`, `sitemap.xml`, `CNAME`.

## Usage

```sh
bash pandoc/build.sh              # build into docs/
OUT_DIR=/tmp/preview bash pandoc/build.sh   # build somewhere else (for diffing)
```

Requires `pandoc` (>= 3) and `python3`. The bibliography style is read from
`$CSL` (defaults to the vendored `pandoc/associacao-brasileira-de-normas-tecnicas.csl`,
CC BY-SA 3.0).

## Layout

- `template-mfo.html` — lecture + MFO index pages (folder sidebar)
- `template-story.html` — homepage (nav bar + white sheet + polaroids; links `css/layouts/story.css`)
- `template-page.html` — sblp2024 (portrait sidebar)
- `head.html` — shared `<head>` partial (pandoc `$head.html()$`)
- `filters/`
  - `faicons.lua` — `\faTrafficLight` → `<i class="fa fa-traffic-light">`
  - `mermaid.lua` — mermaid `src` blocks → `<img>` at the committed PNG
  - `orglinks.lua` — `[[file:x.org]]` → `x.html`
  - `details.lua` — `#+begin_details` → `<details>`
  - `story.lua` — homepage only: hero before `-----`, then one chapter per
    captioned image (polaroid; placeholder when the file is missing)
- `postprocess.py` — og:image injection, search index, sitemap, CNAME
- `build.sh` — orchestration

## What pandoc handles natively

Citations (`[cite:@k]` + `#+bibliography` + `#+print_bibliography`) via
`--citeproc`, `#+EXCLUDE_TAGS`, `#+BEAMER:` directives (ignored), math (passed
through for MathJax), `#+OPTIONS: num:/toc:`.

## Known differences vs the old ox-thtml output

- Code highlighting uses pandoc/skylighting classes (`kw`, `co`, …) with an
  injected `<style>`, not htmlize's `org-*` classes. Colors differ; the
  `org-*` rules in `style.css` no longer apply to code.
- The old `docs/` had stray artifacts (`mfo/Aulas/…`, `mfo/trabalho_1/…`,
  `mfo/sitemap.html`, `README.html`); this build produces a clean 30-page set.
- Source files use CRLF line endings — handled in `build.sh`.
