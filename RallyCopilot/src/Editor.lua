local StateSaver = require('src/StateSaver')
local RouteItem = require('src/RouteItem')

---@class Editor
---@field pn PaceNotes
local Editor = class('Editor')

---@param pn PaceNotes
---@return Editor
function Editor.allocate(pn)
  return {pn = pn}
end

function Editor:initialize()
  self.items = self.pn.items ---@type RouteItem[]
  self.selected = {} ---@type RouteItem[]
  self.unsavedChanges = false
  self.state = StateSaver(function ()
    self.unsavedChanges = true
    return stringify{self.items, table.map(self.selected, function (item) return table.indexOf(self.items, item) end)}
  end, function (data)
    local p = stringify.parse(data, {RouteItem = RouteItem})
    if type(p) == 'table' then
      self.items = p[1]
      self.selected = table.map(p[2], function (i) return p[1][i] end)
    end
  end)
end

---@param mode nil|'selected'
function Editor:sort(mode)
  self.pn:sort()
  if mode == 'selected' then
    table.sort(self.selected, function (a, b)
      return a.pos < b.pos
    end)
  end
end

function Editor:save()
  self.pn:save()
  self.unsavedChanges = false
end

function Editor:cloneSelected()
  for _, v in ipairs(self.selected) do
    table.insert(self.items, v:clone())
  end
end

return class.emmy(Editor, Editor.allocate)