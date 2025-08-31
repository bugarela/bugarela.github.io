-- faicons.lua
-- Translate FontAwesome LaTeX macros (\faTrafficLight, \faBulb, ...) that pandoc
-- would otherwise drop into <i class="fa fa-..."></i>, matching ox-thtml behavior.

-- Cases where the LaTeX macro name != the CSS icon name.
local overrides = {
  Bulb = "lightbulb",
}

local function camel_to_kebab(s)
  s = s:gsub("(%l)(%u)", "%1-%2")
  s = s:gsub("(%u)(%u%l)", "%1-%2")
  return s:lower()
end

function RawInline(el)
  if el.format ~= "latex" then return nil end
  -- match \faXxx, optionally followed by [] or [opts]
  local base = el.text:match("^\\fa(%a+)%s*%[?[^%]]*%]?$")
  if not base then return nil end
  local icon = overrides[base] or camel_to_kebab(base)
  return pandoc.RawInline("html", '<i class="fa fa-' .. icon .. '"></i>')
end
