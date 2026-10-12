-- story.lua
-- Homepage layout (index.org, used with template-story.html).
--
--   * Blocks before the first horizontal rule (org "-----") form the hero
--     (or before the first Figure, if there is no rule): portrait polaroid on the
--     left, text on the right. A leading one-line paragraph ("Hello!")
--     becomes the big <h1 class="hello">.
--   * Each following run of blocks that ends in a Figure (an org image with
--     #+caption:) becomes
--       <article class="chap"><div class="txt">...</div>
--         <figure class="polaroid rN">img<figcaption class="cap">..</figcaption></figure>
--       </article>
--   * If the image file is missing on disk, a hatched placeholder showing the
--     caption is emitted instead of the <img>.
--   * Blocks after the last Figure are kept as a trailing text-only chapter.
--
-- Portrait path: metadata `portrait` (default images/me.jpeg).

local function esc(s)
  return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

local function raw(s) return pandoc.RawBlock("html", s) end

local function inlines_html(inls)
  return (pandoc.write(pandoc.Pandoc({ pandoc.Plain(inls) }), "html"):gsub("\n$", ""))
end

local function exists(path)
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end

-- first Image inside a Figure
local function figure_image(fig)
  local img
  fig:walk({ Image = function(i) img = img or i end })
  return img
end

local function caption_inlines(fig)
  local out = pandoc.List()
  for _, b in ipairs(fig.caption.long) do
    if b.content then out:extend(b.content) end
  end
  return out
end

local function polaroid(fig, rot)
  local img = figure_image(fig)
  local cap = caption_inlines(fig)
  local cap_txt = pandoc.utils.stringify(cap)
  local src = img and img.src or ""
  -- optional vertical nudge: #+attr_html: :shift -140px (negative moves the photo up)
  local shift = (img and img.attributes.shift) or fig.attributes.shift
  local style = ""
  if shift and shift:match("^%-?[%d%.]+%a*$") then
    style = string.format(' style="--shift:%s"', shift)
  end
  local inner
  if img and exists(src) then
    inner = string.format('<img src="%s" alt="%s" loading="lazy">', esc(src), esc(cap_txt))
  else
    inner = string.format('<div class="ph" role="img" aria-label="%s"><span>photo<br>%s</span></div>',
      esc(cap_txt), esc(cap_txt))
  end
  return raw(string.format('<figure class="polaroid r%d"%s>%s<figcaption class="cap">%s</figcaption></figure>',
    rot, style, inner, inlines_html(cap)))
end

function Pandoc(doc)
  local portrait = doc.meta.portrait and pandoc.utils.stringify(doc.meta.portrait) or "images/me.jpeg"
  local out = pandoc.List()
  local run = pandoc.List()
  local hero_done = false
  local chap = 0

  local function emit_hero()
    out:insert(raw('<header class="hero">'))
    out:insert(raw(string.format(
      '<div class="polaroid r1"><img src="%s" alt="Gabriela Moreira"><span class="cap">hello!</span></div>',
      esc(portrait))))
    out:insert(raw("<div>"))
    local first = run[1]
    if first and first.t == "Para" and #pandoc.utils.stringify(first) <= 40 then
      out:insert(raw('<h1 class="hello">' .. inlines_html(first.content) .. "</h1>"))
      run:remove(1)
    end
    out:extend(run)
    out:insert(raw("</div></header>"))
    run = pandoc.List()
    hero_done = true
  end

  for _, b in ipairs(doc.blocks) do
    if b.t == "HorizontalRule" and not hero_done then
      emit_hero()
    elseif b.t == "HorizontalRule" then
      -- a later rule ends a full-width, text-only row
      if #run > 0 then
        out:insert(raw('<article class="chap chap-text"><div class="txt">'))
        out:extend(run)
        out:insert(raw("</div></article>"))
        run = pandoc.List()
      end
    elseif b.t == "Figure" then
      if not hero_done then emit_hero() end
      out:insert(raw(string.format('<article class="chap %s"><div class="txt">',
        chap % 2 == 0 and "photo-right" or "photo-left")))
      out:extend(run)
      out:insert(raw("</div>"))
      out:insert(polaroid(b, chap % 3))
      out:insert(raw("</article>"))
      chap = chap + 1
      run = pandoc.List()
    elseif not (b.t == "RawBlock" and b.format == "org") then
      run:insert(b)
    end
  end

  if not hero_done then
    emit_hero()
  elseif #run > 0 then
    out:insert(raw('<article class="chap chap-text"><div class="txt">'))
    out:extend(run)
    out:insert(raw("</div></article>"))
  end

  doc.blocks = out
  return doc
end
