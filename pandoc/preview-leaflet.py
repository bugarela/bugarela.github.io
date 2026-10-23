#!/usr/bin/env python3
"""Preview a public Leaflet draft with the site's renderer, template and CSS.

Draft HTML is not a published AT Protocol record: this is a best-effort preview,
not a test of the publication/fetch pipeline. Footnote bodies aren't in the
server-rendered HTML; optionally supply them as an ID -> text JSON mapping.
"""
import argparse
import hashlib
import http.server
import importlib.util
import json
import math
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from html.parser import HTMLParser
from urllib.parse import urljoin, urlparse
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parent.parent


def download(url):
    with urlopen(Request(url, headers={"User-Agent": "bugarela.com draft preview"}), timeout=30) as response:
        return response.read()


class DraftParser(HTMLParser):
    """Extract visible blocks, preserving basic formatting and byte-range facets."""

    def __init__(self, notes=None):
        super().__init__()
        self.notes = notes or {}
        self.missing_notes = set()
        self.depth = 0
        self.block_depth = None
        self.current = None
        self.marks = []
        self.blocks = []
        self.title = ""
        self.description = ""
        self.in_title = False

    def position(self):
        return len(self.current["plaintext"].encode("utf-8"))

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "title":
            self.in_title = True
        if tag == "meta" and attrs.get("name") == "description":
            self.description = attrs.get("content", "")
        if tag == "div":
            self.depth += 1
            if attrs.get("id", "").startswith("block/"):
                self.block_depth = self.depth
        if self.block_depth is None:
            return
        kinds = {"p": "text", "blockquote": "blockquote", "h1": "header", "h2": "header", "h3": "header", "h4": "header"}
        if tag in kinds and self.current is None:
            self.current = {"$type": "pub.leaflet.blocks." + kinds[tag], "plaintext": "", "facets": []}
            self.text_tag = tag
            if tag.startswith("h"):
                self.current["level"] = int(tag[1])
        if self.current is not None:
            if tag == "br":
                self.current["plaintext"] += "\n"
            note_id = attrs.get("data-footnote-id")
            if note_id:
                text = self.notes.get(note_id)
                if text is None:
                    self.missing_notes.add(note_id)
                    text = "[Footnote body unavailable in draft HTML]"
                start = self.position()
                self.current["plaintext"] += "*"
                self.add_facet(start, self.position(), {"$type": "pub.leaflet.richtext.facet#footnote", "contentPlaintext": text})
            kind = {"strong": "bold", "b": "bold", "em": "italic", "i": "italic", "code": "code", "s": "strikethrough", "u": "underline", "mark": "highlight", "a": "link"}.get(tag)
            kinds = [kind] if kind else []
            if tag == "span":
                style = dict(part.strip().lower().split(":", 1) for part in attrs.get("style", "").split(";") if ":" in part)
                style = {key.strip(): value.strip() for key, value in style.items()}
                weight = style.get("font-weight", "")
                if weight in ("bold", "bolder") or (weight.isdigit() and int(weight) >= 600):
                    kinds.append("bold")
                if style.get("font-style") in ("italic", "oblique"):
                    kinds.append("italic")
            features = [{"$type": "pub.leaflet.richtext.facet#" + kind,
                         **({"uri": attrs.get("href", "")} if kind == "link" else {})}
                        for kind in kinds]
            # Include unstyled spans so their closing tags cannot close an
            # enclosing styled span prematurely.
            if features or tag == "span":
                self.marks.append((tag, self.position(), features))
        if tag == "img" and attrs.get("src"):
            self.blocks.append({"block": {"$type": "pub.leaflet.blocks.image", "source": attrs["src"], "alt": attrs.get("alt", ""), "aspectRatio": {k: int(attrs[k]) for k in ("width", "height") if attrs.get(k, "").isdigit()}}})

    def add_facet(self, start, end, feature):
        if end > start:
            self.current["facets"].append({"index": {"byteStart": start, "byteEnd": end}, "features": [feature]})

    def handle_data(self, data):
        if self.in_title:
            self.title += data
        if self.current is not None:
            self.current["plaintext"] += data

    def handle_endtag(self, tag):
        if tag == "title":
            self.in_title = False
        if self.current is not None:
            for i in range(len(self.marks) - 1, -1, -1):
                if self.marks[i][0] == tag:
                    _, start, features = self.marks.pop(i)
                    for feature in features:
                        self.add_facet(start, self.position(), feature)
                    break
            if tag == self.text_tag:
                self.blocks.append({"block": self.current})
                self.current = None
                self.marks = []
        if tag == "div":
            if self.depth == self.block_depth:
                self.block_depth = None
            self.depth -= 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("url", help="public Leaflet draft URL")
    parser.add_argument("--out", type=Path, help="preview directory (default: new temporary directory)")
    parser.add_argument("--footnotes", type=Path, help="JSON object mapping draft footnote IDs to plain text")
    parser.add_argument("--serve", action="store_true", help="serve the preview on localhost until Ctrl-C")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    if urlparse(args.url).scheme not in ("http", "https"):
        parser.error("URL must use http or https")
    if not shutil.which("pandoc"):
        parser.error("pandoc is required")
    notes = json.loads(args.footnotes.read_text()) if args.footnotes else {}
    draft = DraftParser(notes)
    draft.feed(download(args.url).decode("utf-8"))
    if not draft.blocks:
        parser.error("no draft blocks found; the page may be private or Leaflet's HTML may have changed")
    out = args.out.resolve() if args.out else Path(tempfile.mkdtemp(prefix="leaflet-preview-"))
    # Never overwrite the live site's assets or generated pages.
    if out == ROOT or ROOT in out.parents:
        parser.error("choose an output directory outside the repository")
    (out / "writing").mkdir(parents=True, exist_ok=True)
    for directory in ("css", "images"):
        shutil.copytree(ROOT / directory, out / directory, dirs_exist_ok=True)
        # Nix store assets are read-only; the local preview must accept images
        # and allow subsequent runs to refresh copied assets.
        for path in [out / directory, *(out / directory).rglob("*")]:
            path.chmod(path.stat().st_mode | (0o700 if path.is_dir() else 0o600))
    for wrapped in draft.blocks:
        block = wrapped["block"]
        if "source" in block:
            url = urljoin(args.url, block.pop("source"))
            cid = "preview-" + hashlib.sha256(url.encode()).hexdigest()[:16]
            (out / "images" / "writing").mkdir(exist_ok=True)
            (out / "images" / "writing" / (cid + ".jpg")).write_bytes(download(url))
            block["image"] = {"ref": {"$link": cid}}
    spec = importlib.util.spec_from_file_location("leaflet", ROOT / "pandoc" / "leaflet.py")
    leaflet = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(leaflet)
    body, count = leaflet.render_blocks(draft.blocks, args.url)
    md = out / "draft.md"
    leaflet.md_file(md, {"title": draft.title, "dek": draft.description, "year": "draft", "date-human": "draft preview", "read": f"{max(1, math.ceil(count / 200))} min read", "leaflet-url": args.url}, body)
    destination = out / "writing" / "draft.html"
    subprocess.run(["pandoc", str(md), "-f", "markdown", "-t", "html5", "-s", "--template", str(ROOT / "pandoc" / "template-writing.html"), "-V", "root=../", "-V", "nav-writing=true", "-V", "cssv=preview", "-o", str(destination)], check=True)
    print(f"Preview: {destination}")
    print("Best-effort draft preview; published-record fetching is not tested.")
    for note_id in sorted(draft.missing_notes):
        print(f"Warning: missing footnote {note_id}; supply its text using --footnotes", file=sys.stderr)
    if args.serve:
        from functools import partial
        handler = partial(http.server.SimpleHTTPRequestHandler, directory=str(out))
        with http.server.ThreadingHTTPServer(("127.0.0.1", args.port), handler) as server:
            print(f"Open http://127.0.0.1:{args.port}/writing/draft.html", flush=True)
            try:
                server.serve_forever()
            except KeyboardInterrupt:
                pass


if __name__ == "__main__":
    main()
