-- orglinks.lua
-- Rewrite intra-site links that point to .org sources so they point at the
-- generated .html, matching Emacs' file:foo.org -> foo.html behavior.
-- Leaves external (http/https/mailto) and non-.org targets untouched.

function Link(el)
  local t = el.target
  if t:match("^%a[%w+.-]*:") and not t:match("^file:") then
    return nil -- has a URI scheme (http:, mailto:, ...) that isn't file:
  end
  t = t:gsub("^file:", "")
  -- split off any ::search / #anchor suffix, rewrite the path part only
  local path, suffix = t:match("^(.-)([#].*)$")
  if not path then path, suffix = t, "" end
  path = path:gsub("%.org$", ".html")
  el.target = path .. suffix
  return el
end
