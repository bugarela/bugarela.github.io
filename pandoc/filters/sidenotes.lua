-- sidenotes.lua
-- Org footnotes ([fn:x] / [fn::inline]) become side notes instead of a list
-- at the bottom: a numbered marker in the text plus the note itself, which
-- story.css floats beside the paragraph on wide screens. On narrow screens
-- the note is hidden until the marker is tapped (checkbox toggle, no JS).

local n = 0

local function html(inls)
  return (pandoc.write(pandoc.Pandoc({ pandoc.Plain(inls) }), "html"):gsub("\n$", ""))
end

function Note(el)
  n = n + 1
  local id = "sn-" .. n
  -- a note is a list of blocks; flatten paragraphs into one inline run
  local inls = pandoc.List()
  for i, b in ipairs(el.content) do
    if i > 1 then inls:insert(pandoc.Space()) end
    if b.content then inls:extend(b.content) end
  end
  return pandoc.RawInline("html",
    '<label for="' .. id .. '" class="sn-ref">' .. n .. '</label>' ..
    '<input type="checkbox" id="' .. id .. '" class="sn-toggle">' ..
    '<span class="sidenote"><span class="sn-num">' .. n .. '</span> ' .. html(inls) .. '</span>')
end
