#!/usr/bin/env python3
"""Mirror Leaflet posts (standard.site documents) onto bugarela.com.

  leaflet.py fetch           pull posts + images from the PDS into the repo
  leaflet.py pages <dir>     write one pandoc-ready .md per post (+ index.md)

`fetch` stores a snapshot in writing/posts.json, writing/publications.json
and images/writing/, all committed, so a build without network still renders the last known posts.
`pages` turns Leaflet blocks into HTML and wraps it in a markdown file whose
YAML header feeds pandoc/template-writing.html.
"""
import html
import json
import math
import os
import re
import shutil
import subprocess
import sys
import unicodedata
import urllib.parse
import urllib.request
from datetime import datetime

HANDLE_DID = "did:plc:7dv3qlilrrooaptgmonjux32"  # bugarela.com
COLLECTION = "site.standard.document"
PUB_COLLECTION = "site.standard.publication"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SNAPSHOT = os.path.join(ROOT, "writing", "posts.json")
PUBS = os.path.join(ROOT, "writing", "publications.json")
IMG_DIR = os.path.join(ROOT, "images", "writing")
IMG_URL = "../images/writing/"  # relative to docs/writing/*.html
MONTHS = "jan feb mar apr may jun jul aug sep oct nov dec".split()


# ---------------------------------------------------------------- fetch ----
def get_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": "bugarela.com build"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.load(r)


def pds_for(did):
    doc = get_json(f"https://plc.directory/{did}")
    for s in doc["service"]:
        if s.get("type") == "AtprotoPersonalDataServer" or s["id"].endswith("atproto_pds"):
            return s["serviceEndpoint"].rstrip("/")
    raise RuntimeError("no PDS in DID document")


def list_records(pds, did, collection=COLLECTION):
    out, cursor = [], None
    while True:
        q = {"repo": did, "collection": collection, "limit": "100"}
        if cursor:
            q["cursor"] = cursor
        page = get_json(f"{pds}/xrpc/com.atproto.repo.listRecords?" + urllib.parse.urlencode(q))
        out += page["records"]
        cursor = page.get("cursor")
        if not cursor or not page["records"]:
            return out


def blob_cids(value):
    """Every blob CID referenced anywhere in a record."""
    found = []

    def walk(x):
        if isinstance(x, dict):
            if x.get("$type") == "blob" and "ref" in x:
                found.append(x["ref"]["$link"])
            for v in x.values():
                walk(v)
        elif isinstance(x, list):
            for v in x:
                walk(v)
    walk(value)
    return found


def save_image(pds, did, cid):
    dest = os.path.join(IMG_DIR, cid + ".jpg")
    if os.path.exists(dest):
        return
    url = f"{pds}/xrpc/com.atproto.sync.getBlob?did={did}&cid={cid}"
    tmp = dest + ".part"
    req = urllib.request.Request(url, headers={"User-Agent": "bugarela.com build"})
    with urllib.request.urlopen(req, timeout=60) as r, open(tmp, "wb") as f:
        shutil.copyfileobj(r, f)
    magick = shutil.which("magick") or shutil.which("convert")
    if magick:
        # web size, no metadata (drops GPS and camera data)
        subprocess.run([magick, tmp, "-auto-orient", "-resize", "1600x1600>",
                        "-strip", "-quality", "82", dest], check=True)
        os.remove(tmp)
    else:
        os.replace(tmp, dest)  # browsers sniff the real format
    print(f"   image {cid[:12]}…")


def fetch():
    pds = pds_for(HANDLE_DID)
    recs = list_records(pds, HANDLE_DID)
    os.makedirs(IMG_DIR, exist_ok=True)
    for r in recs:
        for cid in blob_cids(r["value"]):
            save_image(pds, HANDLE_DID, cid)
    recs.sort(key=lambda r: r["value"].get("publishedAt", ""), reverse=True)
    os.makedirs(os.path.dirname(SNAPSHOT), exist_ok=True)
    with open(SNAPSHOT, "w", encoding="utf-8") as f:
        json.dump(recs, f, ensure_ascii=False, indent=1)
    # publication records map a post's at:// `site` to the publication's web URL
    pubs = {p["uri"]: {"name": p["value"].get("name", ""), "url": p["value"].get("url", "")}
            for p in list_records(pds, HANDLE_DID, PUB_COLLECTION)}
    with open(PUBS, "w", encoding="utf-8") as f:
        json.dump(pubs, f, ensure_ascii=False, indent=1)
    print(f"   {len(recs)} posts, {len(pubs)} publications from {pds}")


# --------------------------------------------------------------- render ----
def esc(s):
    return html.escape(s, quote=True)


FACET_TAGS = {"italic": "em", "bold": "strong", "code": "code",
              "strikethrough": "s", "underline": "u", "highlight": "mark"}


_notes = [0]  # side-note counter, reset per post in render_blocks


def sidenote(feat):
    """Leaflet footnote facet -> the side-note markup of pandoc/filters/sidenotes.lua."""
    _notes[0] += 1
    n = _notes[0]
    body = richtext(feat.get("contentPlaintext", ""), feat.get("contentFacets"), paragraphs=False)
    return (f'<label for="sn-{n}" class="sn-ref">{n}</label>'
            f'<input type="checkbox" id="sn-{n}" class="sn-toggle">'
            f'<span class="sidenote"><span class="sn-num">{n}</span> {body}</span>')


def richtext(text, facets, paragraphs=True):
    """Leaflet plaintext + byte-range facets -> HTML.

    Returns a list of paragraph HTML strings (split on blank lines) or a
    single string when paragraphs=False."""
    data = text.encode("utf-8")
    cuts = {0, len(data)}
    for f in facets or []:
        cuts.add(max(0, min(len(data), f["index"]["byteStart"])))
        cuts.add(max(0, min(len(data), f["index"]["byteEnd"])))
    if paragraphs:
        for m in re.finditer(rb"\n{2,}", data):
            cuts.update((m.start(), m.end()))
    cuts = sorted(cuts)
    paras, cur = [], ""
    for a, b in zip(cuts, cuts[1:]):
        seg = data[a:b].decode("utf-8", "replace")
        if paragraphs and re.fullmatch(r"\n{2,}", seg):
            paras.append(cur)
            cur = ""
            continue
        piece = esc(seg).replace("\n", "<br>")
        for f in facets or []:
            i = f["index"]
            if i["byteStart"] <= a and b <= i["byteEnd"]:
                for feat in f["features"]:
                    kind = feat["$type"].split("#")[-1]
                    if kind == "footnote":
                        # the facet covers a "*" placeholder; the note replaces it
                        piece = sidenote(feat)
                    elif kind == "link":
                        piece = f'<a href="{esc(feat.get("uri", ""))}">{piece}</a>'
                    elif kind in FACET_TAGS:
                        t = FACET_TAGS[kind]
                        piece = f"<{t}>{piece}</{t}>"
        cur += piece
    paras.append(cur)
    paras = [p.strip() for p in paras if p.strip()]
    return paras if paragraphs else " ".join(paras)


BULLET = re.compile(r"^\s*[•\-\*–]\s+")
NUMBER = re.compile(r"^\s*\d+[.)]\s+")


def strip_prefix(block, rx):
    """Drop a typed list marker ("  • ", "1. ") from a text block, shifting facets."""
    text = block.get("plaintext", "")
    m = rx.match(text)
    cut = len(text[:m.end()].encode("utf-8"))
    facets = []
    for f in block.get("facets") or []:
        s, e = f["index"]["byteStart"] - cut, f["index"]["byteEnd"] - cut
        if e > 0:
            facets.append({**f, "index": {"byteStart": max(0, s), "byteEnd": e}})
    return text[m.end():], facets


def list_items(children):
    items = []
    for c in children or []:
        content = c.get("content", {})
        inner = richtext(content.get("plaintext", ""), content.get("facets"), paragraphs=False)
        sub = c.get("children")
        if sub:
            inner += "<ul>" + list_items(sub) + "</ul>"
        items.append(f"<li>{inner}</li>")
    return "".join(items)


def words(s):
    return len(re.findall(r"\w+", s))


def render_blocks(blocks, leaflet_url):
    _notes[0] = 0
    out, wc, first_p, side = [], 0, True, 0
    i = 0
    while i < len(blocks):
        b = blocks[i]["block"]
        kind = b["$type"].split(".")[-1]
        text = b.get("plaintext", "")
        wc += words(text)

        # consecutive text blocks typed as "• item" / "1. item" become a real list
        if kind == "text" and (BULLET.match(text) or NUMBER.match(text)):
            rx = BULLET if BULLET.match(text) else NUMBER
            tag = "ul" if rx is BULLET else "ol"
            items = []
            while i < len(blocks):
                bb = blocks[i]["block"]
                t = bb.get("plaintext", "")
                if bb["$type"].split(".")[-1] != "text" or not rx.match(t):
                    break
                if items:  # the first item was already counted above
                    wc += words(t)
                body, facets = strip_prefix(bb, rx)
                items.append(f"<li>{richtext(body, facets, paragraphs=False)}</li>")
                i += 1
            out.append(f"<{tag}>" + "".join(items) + f"</{tag}>")
            continue

        if kind == "text":
            for p in richtext(text, b.get("facets")):
                cls = ' class="lead"' if first_p else ""
                first_p = False
                out.append(f"<p{cls}>{p}</p>")
        elif kind == "header":
            lvl = min(4, max(2, int(b.get("level", 1)) + 1))
            out.append(f"<h{lvl}>{richtext(text, b.get('facets'), paragraphs=False)}</h{lvl}>")
        elif kind == "blockquote":
            ps = "".join(f"<p>{p}</p>" for p in richtext(text, b.get("facets")))
            out.append(f"<blockquote>{ps}</blockquote>")
        elif kind == "image":
            cid = b["image"]["ref"]["$link"]
            ar = b.get("aspectRatio") or {}
            alt = b.get("alt", "")
            dims = ""
            if ar.get("width") and ar.get("height"):
                dims = f' width="{ar["width"]}" height="{ar["height"]}"'
            cap = f"<figcaption>{esc(alt)}</figcaption>" if alt else ""
            side += 1
            out.append(f'<figure class="side{" left" if side % 2 == 0 else ""}"><div class="pol">'
                       f'<img src="{IMG_URL}{cid}.jpg" alt="{esc(alt)}"{dims} loading="lazy">'
                       f"{cap}</div></figure>")
        elif kind in ("unorderedList", "orderedList"):
            tag = "ol" if kind == "orderedList" else "ul"
            out.append(f"<{tag}>" + list_items(b.get("children")) + f"</{tag}>")
        elif kind == "horizontalRule":
            out.append("<hr>")
        elif kind == "code":
            lang = esc(b.get("language", "") or "")
            out.append(f'<pre class="code" data-lang="{lang}"><code>{esc(text)}</code></pre>')
        elif kind == "math":
            out.append(f'<pre class="code"><code>{esc(b.get("tex", ""))}</code></pre>')
        elif kind == "website":
            src = b.get("src", "")
            title = b.get("title") or src
            desc = b.get("description", "")
            out.append(f'<p class="card"><a href="{esc(src)}">{esc(title)}</a>'
                       + (f"<br><span>{esc(desc)}</span>" if desc else "") + "</p>")
        elif kind == "bskyPost":
            uri = b.get("postRef", {}).get("uri", "")
            m = re.match(r"at://([^/]+)/app\.bsky\.feed\.post/(.+)", uri)
            href = f"https://bsky.app/profile/{m.group(1)}/post/{m.group(2)}" if m else leaflet_url
            out.append(f'<p class="card"><a href="{esc(href)}">a post on bluesky ↗</a></p>')
        else:
            out.append(f'<p class="card"><a href="{esc(leaflet_url)}">'
                       f"this part of the post is best seen on leaflet ↗</a></p>")
        i += 1
    return "\n".join(out), wc


def slugify(s):
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z0-9]+", "-", s).strip("-") or "post"


def human_date(iso):
    d = datetime.fromisoformat(iso.replace("Z", "+00:00"))
    return d, f"{d.day} {MONTHS[d.month - 1]} {d.year}"


def bsky_url(v):
    uri = (v.get("bskyPostRef") or {}).get("uri", "")
    m = re.match(r"at://([^/]+)/app\.bsky\.feed\.post/(.+)", uri)
    return f"https://bsky.app/profile/bugarela.com/post/{m.group(2)}" if m else ""


def md_file(path, meta, body):
    with open(path, "w", encoding="utf-8") as f:
        f.write("---\n")
        for k, val in meta.items():
            f.write(f"{k}: {json.dumps(val, ensure_ascii=False)}\n")
        f.write("lang: en\n---\n\n```{=html}\n" + body + "\n```\n")


def pages(outdir):
    os.makedirs(outdir, exist_ok=True)
    try:
        recs = json.load(open(SNAPSHOT, encoding="utf-8"))
    except FileNotFoundError:
        recs = []
    try:
        pubs = json.load(open(PUBS, encoding="utf-8"))
    except FileNotFoundError:
        pubs = {}
    seen, entries = set(), []
    for r in recs:
        v = r["value"]
        pages_ = (v.get("content") or {}).get("pages") or [{}]
        # looseleafs have an https `site`; publication posts point at the
        # publication record and live under its URL
        site = v.get("site", "")
        if site.startswith("at://"):
            site = pubs.get(site, {}).get("url", "")
            if not site:
                print(f"   warning: unknown publication for {r['uri']}, run with --fetch")
        leaflet_url = site.rstrip("/") + v.get("path", "") if site else ""
        body, wc = render_blocks(pages_[0].get("blocks", []), leaflet_url)
        slug = slugify(v.get("title", ""))
        if slug in seen:
            slug += "-" + r["uri"].rsplit("/", 1)[-1]
        seen.add(slug)
        d, when = human_date(v["publishedAt"])
        meta = {
            "title": v.get("title", ""),
            "dek": v.get("description", ""),
            "date-human": when,
            "year": str(d.year),
            "read": f"{max(1, math.ceil(wc / 200))} min read",
            "leaflet-url": leaflet_url,
            "bsky-url": bsky_url(v),
            "at-uri": r["uri"],
        }
        md_file(os.path.join(outdir, slug + ".md"), meta, body)
        entries.append((d, slug, meta))

    # index: one flat list, newest first (no year groups until there are more posts)
    items = [
        f'<li><a href="{slug}.html">'
        f'<span class="when"><time datetime="{d.date().isoformat()}">{d.day} {MONTHS[d.month - 1]}</time>'
        f'<span>{m["read"]}</span></span>'
        f'<div class="txt"><h3>{esc(m["title"])}</h3><p>{esc(m["dek"])}</p></div></a></li>'
        for d, slug, m in entries]
    body = (f'<ul class="entries">{"".join(items)}</ul>' if items
            else '<p class="intro">nothing here yet.</p>')
    md_file(os.path.join(outdir, "index.md"),
            {"title": "writing", "writing-index": True,
             "dek": "Lightweight posts I write on Leaflet and render here for maxxing style control.",
             # only one publication for now; no button until it exists
             "subscribe-url": next((p["url"] for p in pubs.values() if p["url"]), "")},
            body)
    print(f"   {len(entries)} posts rendered")


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "fetch":
        fetch()
    elif len(sys.argv) >= 3 and sys.argv[1] == "pages":
        pages(sys.argv[2])
    else:
        sys.exit(__doc__)
