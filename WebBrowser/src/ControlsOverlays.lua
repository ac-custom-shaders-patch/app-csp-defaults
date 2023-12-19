local App = require('src/App')
local Utils = require('src/Utils')
local ControlsBasic = require('src/ControlsBasic')
local ControlsInputFeatures = require('src/ControlsInputFeatures')

local ColOverlay = rgbm(0, 0, 0, 0.8)
local btnSize = vec2(22, 22)

---@param p1 vec2
---@param p2 vec2
---@param tab WebBrowser
---@return boolean
local function drawPageSearch(p1, p2, tab)  
  local c = ui.getCursor()
  ui.pushID('search')
  ui.setCursor(vec2(p2.x - 300, p1.y))
  ui.drawRectFilled(ui.getCursor(), ui.getCursor() + vec2(300, 30), ColOverlay, 4, ui.CornerFlags.BottomLeft)
  ui.offsetCursorX(10)
  ui.offsetCursorY(8)
  ui.icon(ui.Icons.Search, 12)
  ui.sameLine(0, 4)
  ui.offsetCursorY(-5)
  ui.setNextItemWidth(149)
  ui.setItemAllowOverlap()

  ui.pushStyleColor(ui.StyleColor.FrameBgHovered, rgbm.colors.transparent)
  ui.pushStyleColor(ui.StyleColor.FrameBg, rgbm.colors.transparent)
  local newValue, _, enter = ui.inputText('Search', tab.attributes.search.text, bit.bor(ui.InputTextFlags.Placeholder, ui.InputTextFlags.RetainSelection))
  ControlsInputFeatures.inputContextMenu(tab, function ()
    ui.separator()
    if ControlsBasic.menuItem(tab.attributes.search.case and 'Do not match case' or 'Match case') then
      tab.attributes.search.case = not tab.attributes.search.case
      if #newValue > 0 then
        tab:find(newValue, true, tab.attributes.search.case, true)
      end
    end
  end)
  local ret =  ui.itemActive()
  ui.popStyleColor(2)
  if App.focusNext == 'search' then
    App.focusNext = nil
    ui.activateItem(ui.getLastID())
  end

  ui.sameLine(0, 0)
  ui.textAligned(tab.attributes.search.found and string.format('%s/%s', tab.attributes.search.found.index, tab.attributes.search.found.count) or '0/0', vec2(1, 0.5), vec2(40, 22))
  ui.sameLine(0, 8)
  ui.offsetCursorY(1)
  ui.pushStyleColor(ui.StyleColor.Button, rgbm.colors.transparent)
  if ui.iconButton(ui.Icons.ArrowUp, btnSize, 7) then
    tab:find(newValue, false, tab.attributes.search.case, true)
    App.focusNext = 'search'
  end
  ui.sameLine(0, 4)
  if ui.iconButton(ui.Icons.ArrowDown, btnSize, 7) or enter then
    tab:find(newValue, true, tab.attributes.search.case, true)
    App.focusNext = 'search'
  end
  ui.sameLine(0, 4)
  ui.pushID(2)
  if ui.iconButton(ui.Icons.Cancel, btnSize, 7) then Utils.stopSearch(tab) end
  ui.popID()
  if newValue ~= tab.attributes.search.text then
    tab:find(newValue, true, tab.attributes.search.case, tab.attributes.search.found ~= nil)
    tab.attributes.search.text = newValue
  end
  ui.popStyleColor()
  ui.setCursor(c)
  ui.popID()
  return ret
end

local v1, v2 = vec2(), vec2()

---@param p1 vec2
---@param p2 vec2
---@param status string
local function drawPageStatus(p1, p2, status)
  local width = math.min(ui.measureText(status).x + 20, p2.x - p1.x - 80)
  ui.drawRectFilled(v1:set(p1.x, p2.y - 20), v2:set(p1.x + width, p2.y), ColOverlay, 4, ui.CornerFlags.TopRight)
  ui.drawTextClipped(status, v1:set(p1.x + 4, p2.y - 20), v2:set(p1.x + width - 8, p2.y), rgbm.colors.white, 0.5, true)
end

---@param p1 vec2
---@param p2 vec2
---@param tab WebBrowser
local function isMouseBlocked(p1, p2, tab)
  if tab.attributes.search.active then
    return ui.rectHovered(vec2(p2.x - 300, p1.y), vec2(p2.x, p1.y + 30))
  end
  return false
end

return {
  drawPageSearch = drawPageSearch,
  drawPageStatus = drawPageStatus,
  isMouseBlocked = isMouseBlocked,
}