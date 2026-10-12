#!/usr/bin/env python3
"""Post-build steps that used to live in make.el's elisp tail:

  1. inject an <meta property="og:image"> (first image on the page, made
     absolute) when one isn't already present,
  2. generate docs/search-index.json for lunr (from docs/mfo/*.html),
  3. generate docs/sitemap.xml,
  4. write docs/CNAME.

Standard library only.
"""
import json
import os
import re
import sys
from html.parser import HTMLParser
from urllib.parse import urljoin

OUT = sys.argv[1]
SITE_URL = sys.argv[2].rstrip("/")


def rel_url(path):
    return os.path.relpath(path, OUT).replace(os.sep, "/")


def page_url(path):
    return f"{SITE_URL}/{rel_url(path)}"


class Extractor(HTMLParser):
    """Pull out <title>, visible text, and the first <img src>."""

    def __init__(self):
        super().__init__()
        self.title_parts, self.text_parts = [], []
        self.first_img = None
        self._in_title = False
        self._skip = 0

    def handle_starttag(self, tag, attrs):
        if tag == "title":
            self._in_title = True
        elif tag in ("script", "style", "nav", "footer"):
            self._skip += 1
        elif tag == "img" and self.first_img is None:
            self.first_img = dict(attrs).get("src")

    def handle_endtag(self, tag):
        if tag == "title":
            self._in_title = False
        elif tag in ("script", "style", "nav", "footer") and self._skip:
            self._skip -= 1

    def handle_data(self, data):
        if self._in_title:
            self.title_parts.append(data)
        elif not self._skip:
            self.text_parts.append(data)

    @property
    def title(self):
        return " ".join("".join(self.title_parts).split())

    @property
    def text(self):
        return " ".join("".join(self.text_parts).split())


def all_html():
    for dirpath, _, files in os.walk(OUT):
        for name in sorted(files):
            if name.endswith(".html"):
                yield os.path.join(dirpath, name)


def inject_og_image(path, html, ex):
    if 'property="og:image"' in html or not ex.first_img:
        return html
    img_abs = urljoin(page_url(path), ex.first_img)
    tag = f'    <meta property="og:image" content="{img_abs}" />\n'
    # place right after og:title if present, else after <title>, else in <head>
    for anchor in (r'(<meta property="og:title"[^>]*>\n)',
                   r'(</title>\n)',
                   r'(<head>\n)'):
        new, n = re.subn(anchor, r"\1" + tag, html, count=1)
        if n:
            return new
    return html


def main():
    index = []
    for path in all_html():
        html = open(path, encoding="utf-8").read()
        ex = Extractor()
        ex.feed(html)

        new = inject_og_image(path, html, ex)
        if new != html:
            open(path, "w", encoding="utf-8").write(new)

        # search index covers the lecture pages, like make.el did for docs/mfo
        if os.path.dirname(path) == os.path.join(OUT, "mfo"):
            index.append({"title": ex.title,
                          "content": ex.text,
                          "url": os.path.basename(path)})

    with open(os.path.join(OUT, "search-index.json"), "w", encoding="utf-8") as f:
        json.dump(index, f, ensure_ascii=False)

    urls = [page_url(p) for p in all_html()]
    with open(os.path.join(OUT, "sitemap.xml"), "w", encoding="utf-8") as f:
        f.write('<?xml version="1.0" encoding="UTF-8"?>\n')
        f.write('<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n')
        for u in sorted(urls):
            f.write(f" <url>\n  <loc>{u}</loc>\n  <priority>0.5</priority>\n </url>\n")
        f.write("</urlset>\n")

    with open(os.path.join(OUT, "CNAME"), "w", encoding="utf-8") as f:
        f.write("bugarela.com\n")

    print(f"   {len(index)} lecture pages indexed, {len(urls)} urls in sitemap")


if __name__ == "__main__":
    main()
