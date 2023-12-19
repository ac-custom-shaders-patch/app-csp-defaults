local FaviconsProvider = require('src/FaviconsProvider')
local App = require('src/App')
local Icons = require('src/Icons')
local Utils = require('src/Utils')
local ControlsBasic = require('src/ControlsBasic')
local ControlsAdvanced = require('src/ControlsAdvanced')
local Themes = require('src/Themes')

local function removeEntry(item)
  App.storedHistory:remove(item)
  ui.toast(ui.Icons.Trash, 'Removed “%s”' % item.title, function ()
    App.storedHistory:restore(item)
  end)
end

local itSize = vec2(1, 20)
local itAlign = vec2(0, 0.5)

---@param i integer
---@param filter string
---@param compact boolean
local function historyItem(i, filter, compact)
  ui.pushID(i)
  local item = App.storedHistory:at(i)
  local icon = FaviconsProvider.get(item.url)

  if ui.invisibleButton('', itSize) then
    ControlsBasic.nativeHyperlinkNavigate(item.url)
  end
  ControlsBasic.nativeHyperlinkBehaviour(item.url, function ()
    ui.separator()
    if ControlsBasic.menuItem('Remove entry') then
      removeEntry(item)
    end
  end)

  ui.backupCursor()
  local r1, r2 = ui.itemRectMin(), ui.itemRectMax()
  r1.x, r2.x = r1.x + 12, r2.x - (compact and 20 or 33)

  ui.pushFont(ui.Font.Small)
  ui.drawTextClipped(os.date('%I:%M %p', item.time), r1, r2, rgbm.colors.gray, itAlign, true)
  ui.popFont()
  r1.x = r1.x + 54

  ui.drawIcon(icon, r1 + vec2(8, 4), r1 + vec2(20, 16))
  r1.x = r1.x + 28

  local title = item.title
  local domainName = WebBrowser.getDomainName(item.url)
  if title == '' then 
    title, domainName = domainName, nil
  end

  r1.x = 4 + ui.drawTextClipped(ControlsBasic.textHighlightFilter(title, filter), r1, r2, nil, itAlign, true)
  if domainName and r2.x - r1.x > 40 then
    ui.drawTextClipped(ControlsBasic.textHighlightFilter(domainName, filter), r1, r2, rgbm.colors.gray, itAlign, true)
  end

  ui.setCursor(r2 - vec2(0, 20))
  ui.setItemAllowOverlap()
  ui.pushStyleColor(ui.StyleColor.Button, rgbm.colors.transparent)
  if ui.iconButton(Icons.Cancel, 22, 7) then removeEntry(item) end
  if ui.itemHovered() then ui.setTooltip('Remove item from list') end
  ui.popStyleColor()
  ui.restoreCursor()

  ui.popID()
end

---@param p1 vec2
---@param p2 vec2
---@param tab WebBrowser
local function drawHistoryTab(p1, p2, tab)
  Themes.drawThemedBg(p1, p2, 0.5)
  Themes.beginColumnGroup(p1, p2, 400)

  tab.attributes.historyQuery = ControlsAdvanced.searchBar('Search history', tab.attributes.historyQuery, tab)
  ui.offsetCursorY(12)

  ui.childWindow('history', vec2(), false, bit.bor(ui.WindowFlags.NoScrollbar, ui.WindowFlags.NoBackground), function ()
    ui.thinScrollbarBegin(true)

    itSize.x = ui.availableSpaceX()
    local anyShown = false
    local filter = tab.attributes.historyQuery or ''
    local lastDay

    local compact = ui.windowWidth() < 400
    for i = #App.storedHistory, 1, -1 do
      local item = App.storedHistory:at(i)
      if filter == '' or item.title:findIgnoreCase(filter) or item.url:findIgnoreCase(filter) then

        local day = tostring(os.date('%Y-%m-%d', item.time))
        if day ~= lastDay then
          lastDay = day
          if i > 1 then ui.offsetCursorY(12) end
          ui.pushFont(ui.Font.Small)
          ui.text(Utils.readableDay(day, item.time))
          ui.popFont()
          ui.offsetCursorY(4)
        end

        if ui.areaVisibleY(itSize.y) then
          anyShown = true
          historyItem(i, filter, compact)
        else
          ui.dummy(itSize)
        end
      end
    end

    if not anyShown then
      ui.offsetCursorY(12)
      ui.text('Nothing to show.')
    end

    -- ui.setMaxCursorY(#App.storedHistory * itSize.y + 200)
    ui.offsetCursorY(20)
    ui.thinScrollbarEnd()
  end)
  ui.endGroup()

  if p2.x - p1.x > 800 then
    ui.setCursorX((p1.x + p2.x) / 2 + 200 + (p2.x - p1.x - 400) * 1 / 4 - 68)
    ui.setCursorY(p2.y - 40)
    ui.setNextItemIcon(ui.Icons.Trash)
    ui.pushStyleColor(ui.StyleColor.Button, rgbm.colors.transparent)
    if ui.button('Clear browsing data') then
      ControlsBasic.nativeHyperlinkNavigate('about:settings/privacy')
    end
    ControlsBasic.nativeHyperlinkBehaviour('about:settings/privacy')
    ui.popStyleColor()
  end

end

return {
  drawHistoryTab = drawHistoryTab,
}