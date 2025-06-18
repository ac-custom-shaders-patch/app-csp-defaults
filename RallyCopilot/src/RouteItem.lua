local RouteItemType = require('src/RouteItemType')

---@class RouteItem
---@field type RouteItemType
---@field modifier integer
---@field pos number
---@field hints RouteItemHint[]
---@field debugData table?
local RouteItem = class('RouteItem')

---@param type RouteItemType
---@param modifier integer
---@param pos number
---@param hints RouteItemHint[]
---@return RouteItem
function RouteItem.allocate(type, modifier, pos, hints)
  return {
    type = type,
    modifier = RouteItemType.fitModifier(type, modifier),
    pos = pos,
    hints = hints,
  }
end

function RouteItem:color()
  return RouteItemType.color(self.type, self.modifier)
end

function RouteItem:icon()
  return RouteItemType.icon(self.type, self.modifier, self.hints)
end

function RouteItem:iconTexture()
  return RouteItemType.iconTexture(self.type, self.modifier, self.hints)
end

function RouteItem:iconOverlay()
  return RouteItemType.iconOverlay(self.type, self.modifier, self.hints)
end

---@return RouteItem
function RouteItem:clone()
  local r = RouteItem(self.type, self.modifier, self.pos, self.hints)
  if self.debugData then
    r.debugData = self.debugData
  end
  return r
end

---@return string
function RouteItem:__stringify()
  return 'RouteItem(%d,%d,%f,%s)' % {self.type, self.modifier, self.pos, stringify(self.hints, true)}
end

function RouteItem.upgrade(params, version)
  if version == 2 then
    if params[1] >= 8 then
      params[1] = params[1] + 1 -- making space for separate .Narrows
    end
    -- local j = #params[4]
    -- while j > 0 do
    --   if params[4][j] >= 4 then
    --     params[4][j] = params[4][j] - 1 -- removing old .Keep hint
    --   elseif params[4][j] == 3 then
    --     table.remove(params[4], j)
    --   end
    --   j = j - 1
    -- end
  end
end

return class.emmy(RouteItem, RouteItem.allocate)
