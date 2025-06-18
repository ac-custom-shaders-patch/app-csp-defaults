---@alias RouteItemHint 
---| `RouteItemHint.Cut`
---| `RouteItemHint.DoNotCut`
---| `RouteItemHint.Keep`
---| `RouteItemHint.Long`
---| `RouteItemHint.VeryLong`
---| `RouteItemHint.Tightens`
---| `RouteItemHint.Open`
---| `RouteItemHint.Caution`

local RouteItemHint = const({
  Cut = 1, ---@type RouteItemHint
  DoNotCut = 2, ---@type RouteItemHint
  Long = 3, ---@type RouteItemHint
  VeryLong = 4, ---@type RouteItemHint
  Tightens = 5, ---@type RouteItemHint
  Open = 6, ---@type RouteItemHint
  Caution = 7, ---@type RouteItemHint
  KeepLeft = 8, ---@type RouteItemHint
  KeepRight = 9, ---@type RouteItemHint
})

local hintNames = {
  'Cut',
  'Do not cut',
  'Long',
  'Very long',
  'Tightnens',
  'Open',
  'Caution',
  'Keep left',
  'Keep right',
}

local hintIcons = {
  'hint-cut',
  'hint-do-not-cut',
  'hint-long',
  'hint-very-long',
  'hint-tightnens',
  'hint-open',
  'hint-caution',
  'type-keep-left',
  'type-keep-right',
}

---@return table<RouteItemHint, string>
function RouteItemHint.names()
  return hintNames
end

---@param type RouteItemHint
---@return string
function RouteItemHint.name(type)
  return hintNames[type] or 'Unknown'
end

---@param type RouteItemHint
---@return string
function RouteItemHint.icon(type)
  return 'res/icons/%s.png' % (hintIcons[type] or 'caution')
end

---@param hints RouteItemHint[]
---@param hint RouteItemHint
function RouteItemHint.addHint(hints, hint)
  if table.contains(hints, hint) then
    return
  end
  if hint == RouteItemHint.Tightens then
    table.removeItem(hints, RouteItemHint.Open)
  end
  if hint == RouteItemHint.Open then
    table.removeItem(hints, RouteItemHint.Tightens)
  end
  if hint == RouteItemHint.Cut then
    table.removeItem(hints, RouteItemHint.DoNotCut)
  end
  if hint == RouteItemHint.DoNotCut then
    table.removeItem(hints, RouteItemHint.Cut)
  end
  if hint == RouteItemHint.Long then
    table.removeItem(hints, RouteItemHint.VeryLong)
  end
  if hint == RouteItemHint.VeryLong then
    table.removeItem(hints, RouteItemHint.Long)
  end
  if hint == RouteItemHint.KeepLeft then
    table.removeItem(hints, RouteItemHint.KeepRight)
  end
  if hint == RouteItemHint.KeepRight then
    table.removeItem(hints, RouteItemHint.KeepLeft)
  end
  table.insert(hints, hint)
  table.sort(hints, function (a, b) return a > b end)
end

return RouteItemHint