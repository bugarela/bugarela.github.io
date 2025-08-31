-- mermaid.lua
-- Org mermaid src blocks look like:
--   #+begin_src mermaid :file semaforo.png ...
-- pandoc keeps them as a CodeBlock with class "mermaid" and attribute file=...
-- The current site commits the rendered PNGs, so we point an <img> at the file,
-- matching the existing output. (Alternative: drop this filter and load
-- mermaid.js client-side to render the diagrams live — see README.)

function CodeBlock(el)
  if el.classes:includes("mermaid") then
    local file = el.attributes["file"]
    if file then
      return pandoc.Para({ pandoc.Image({ pandoc.Str("diagram") }, file) })
    end
  end
end
