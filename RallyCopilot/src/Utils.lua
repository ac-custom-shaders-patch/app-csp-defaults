local function verticalSeparator()
  ui.sameLine(0, 4)
  ui.dummy(vec2(1, 22))
  local p1, p2 = ui.itemRect()
  ui.drawRectFilled(p1, p2, ui.styleColor(ui.StyleColor.Separator))
end

---@param str string
---@return number?
local function displayToTime(str)
  local h, m, s = str:numbers(3)
  if s then
    return (h * 60 + m) * 60 + s
  elseif m then
    return h * 60 + m
  else
    return h
  end
end

---@generic T
---@param table T[]
---@param item T
---@return integer?
local function lastIndexOf(table, item)
  for i = #table, 1, -1 do
    if table[i] == item then return i end
  end
  return nil
end

return {
  verticalSeparator = verticalSeparator,
  displayToTime = displayToTime,
  lastIndexOf = lastIndexOf,
}