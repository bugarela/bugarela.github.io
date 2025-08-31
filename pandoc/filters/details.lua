-- details.lua
-- Org "#+begin_details ... #+end_details" special blocks become a Div with
-- class "details". Emacs' ox-html renders these as native <details> elements
-- (with an inner <summary> supplied via #+html:). Reproduce that here.

function Div(el)
  if el.classes:includes("details") then
    local out = pandoc.List()
    out:insert(pandoc.RawBlock("html", "<details>"))
    out:extend(el.content)
    out:insert(pandoc.RawBlock("html", "</details>"))
    return out
  end
end
