local FaviconsProvider = require('src/FaviconsProvider')
local ControlsInputFeatures = require('src/ControlsInputFeatures')

local App = require('src/App')
local Icons = require('src/Icons')
local Utils = require('src/Utils')
local ControlsBasic = require('src/ControlsBasic')

local popup = Utils.uniquePopup()
local itSize = vec2(1, 46)
local menuShown

---@param i integer @Ordered index
---@param tab WebBrowser
---@param filter string
---@param enterPressed boolean
local function tabItem(i, tab, filter, enterPressed)
  ui.pushID(i)
  local icon = tab:loading() and ui.Icons.LoadingSpinner or FaviconsProvider.get(tab)
  local selected = tab == App.selectedTab()
  if ui.selectable(' \n\n ', selected or tab == menuShown) or enterPressed then
    App.selectTab(tab)
    ui.closePopup()
  end
  if ui.itemClicked(ui.MouseButton.Middle) then
    App.closeTab(tab)
  end
  if ui.itemClicked(ui.MouseButton.Right, true) then
    menuShown = tab
    ControlsBasic.showTabMenu(tab, function () menuShown = nil end)
  end

  local r1, r2 = ui.itemRectMin(), ui.itemRectMax()
  local showIcon = tab:playingAudio() or tab:muted()
  local showButton = selected or showIcon or ui.rectHovered(r1, r2)
  r1.x, r2.x = r1.x + 12, r2.x - (showButton and 38 or 8)

  ui.drawIcon(icon, r1 + vec2(8, 14), r1 + vec2(24, 30))
  r1.x = r1.x + 36

  if showIcon then
    r2.x = r2.x - 22
  end
  ui.drawTextClipped(ControlsBasic.textHighlightFilter(tab:title(true), filter), r1, r2, nil, vec2(0, 0.25), true)
  ui.pushFont(ui.Font.Small)
  local age = selected and 'active' or Utils.readableAge(tab.attributes.lastFocusTime)
  ui.drawTextClipped(ControlsBasic.textHighlightFilter(tab:domain(), filter)..' • '..age, r1, r2, nil, vec2(0, 0.75), true)
  ui.popFont()
  if showIcon then
    ui.backupCursor()
    ui.setCursor(r2 + vec2(6, 5 - 34))
    if tab:muted() then
      ui.image(Icons.Atlas.VolumeMuted, 12)
      if ui.itemHovered() then ui.setTooltip('Tab is muted') end
    else
      ui.image(Icons.talkingIcon(tab:audioPeak()), 12)
      if ui.itemHovered() then ui.setTooltip('This tab is playing audio') end
    end
    ui.restoreCursor()
    r2.x = r2.x + 22
  end
  if showButton then
    ui.backupCursor()
    ui.setCursor(r2 - vec2(0, 34))
    ui.setItemAllowOverlap()
    ui.pushStyleColor(ui.StyleColor.Button, rgbm.colors.transparent)
    if ui.iconButton(Icons.Cancel, 22, 7) then App.closeTab(tab) end
    ui.popStyleColor()
    ui.restoreCursor()
  end
  ui.popID()
end

local function tabClosedItem(i, filter, enterPressed)
  ui.pushID(i)
  local item = App.closedTabs:at(i)
  if (ui.selectable(' \n\n ', item == menuShown) or enterPressed) and App.canOpenMoreTabs() then
    App.restoreClosedTab(item)
    ui.closePopup()
  end
  if ui.itemClicked(ui.MouseButton.Middle) then
    App.dumpClosedTab(item)
  end
  if ui.itemClicked(ui.MouseButton.Right, true) then
    menuShown = item
    Utils.popup(function ()
      if not App.canOpenMoreTabs() then ui.pushDisabled() end
      if ControlsBasic.menuItem('Restore') then
        App.restoreClosedTab(item)
      end
      if ControlsBasic.menuItem('Restore in background') then
        App.restoreClosedTab(item, true)
      end
      if not App.canOpenMoreTabs() then ui.popDisabled() end
      if WebBrowser.knownProtocol(item.url) then
        if ControlsBasic.menuItem('Restore in system browser') then
          Utils.openURLInSystemBrowser(item.url)
        end
      end
      ui.separator()
      if ControlsBasic.menuItem('Remove from list') then
        App.dumpClosedTab(item)
      end
    end, { onClose = function () menuShown = nil end })
  end

  local r1, r2 = ui.itemRectMin(), ui.itemRectMax()
  local showButton = ui.rectHovered(r1, r2)
  r1.x, r2.x = r1.x + 12, r2.x - (showButton and 38 or 8)

  ui.drawIcon(item.favicon or FaviconsProvider.require(item.url), r1 + vec2(8, 14), r1 + vec2(24, 30))
  r1.x = r1.x + 36
  ui.drawTextClipped(ControlsBasic.textHighlightFilter(item.title == '' and WebBrowser.getDomainName(item.url) or item.title, filter), r1, r2, nil, vec2(0, 0.25), true)
  ui.pushFont(ui.Font.Small)
  ui.drawTextClipped(ControlsBasic.textHighlightFilter(WebBrowser.getDomainName(item.url), filter)..' • '..Utils.readableAge(item.closedTime), r1, r2, nil, vec2(0, 0.75), true)
  ui.popFont()
  if showButton then
    local c = ui.getCursor()
    ui.setCursor(r2 - vec2(0, 34))
    ui.setItemAllowOverlap()
    ui.pushStyleColor(ui.StyleColor.Button, rgbm.colors.transparent)
    if ui.iconButton(Icons.Cancel, 22, 7) then 
      App.dumpClosedTab(item)
    end
    ui.popStyleColor()
    ui.setCursor(c)
  end
  ui.popID()
end

---@param tabSearch string
---@param tab WebBrowser
---@return boolean
local function searchTestTab(tabSearch, tab)
  if tabSearch == '' then return true end
  return string.findIgnoreCase(tab:title(), tabSearch) ~= nil or string.findIgnoreCase(tab:url(), tabSearch) ~= nil
end

local function searchTestClosedTab(tabSearch, i)
  if tabSearch == '' then return true end
  local tab = App.closedTabs:at(i)
  return string.findIgnoreCase(tab.title, tabSearch) or string.findIgnoreCase(tab.url, tabSearch)
end

local function listHeader(title)
  ui.offsetCursorY(8)
  ui.pushFont(ui.Font.Small)
  ui.offsetCursorX(8)
  ui.text(title)
  ui.popFont()
  ui.offsetCursorY(8)
end

local function showTabsMenu(toggle, position)
  local tabSearch = ''
  local tabsMenuLastHeight = 80
  popup(toggle, function ()
    ui.pushStyleColor(ui.StyleColor.FrameBg, rgbm.colors.transparent)
    if ui.isWindowAppearing() then ui.setKeyboardFocusHere() end
    local _, enterPressed

    ui.offsetCursorX(-2)
    ui.offsetCursorY(4)
    ui.icon(ui.Icons.Search, 12)
    ui.sameLine(0, 8)
    ui.offsetCursorY(-4)

    tabSearch, _, enterPressed = ui.inputText('Search', tabSearch, ui.InputTextFlags.Placeholder)
    ControlsInputFeatures.inputContextMenu()
    if tabSearch ~= '' then
      ui.backupCursor()
      ui.sameLine(0, 0)
      ui.offsetCursorX(-16)      
      ui.setItemAllowOverlap()
      ui.pushStyleColor(ui.StyleColor.Button, rgbm.colors.transparent)
      if ui.iconButton(Icons.Cancel, 22, 7) then tabSearch = '' ui.setKeyboardFocusHere(-2) end
      if ui.itemHovered() then ui.setMouseCursor(ui.MouseCursor.Arrow) end
      ui.popStyleColor()
      ui.restoreCursor()
    end
    ui.popStyleColor()
    ui.offsetCursorY(4)
    ui.separator()
    
    if #tabSearch == '' then enterPressed = false end
    local enterWasPressed = enterPressed

    ui.setCursorX(0)
    ui.childWindow('tabs', vec2(280, math.min(tabsMenuLastHeight, Utils.maxPopupHeight() - 60)), false, bit.bor(ui.WindowFlags.NoScrollbar, ui.WindowFlags.NoBackground), function ()
      local any = false
      local ordered = table.clone(App.tabs, false) ---@type WebBrowser[]
      local anyPlaying = false
      table.sort(ordered, function (a, b)
        if a:playingAudio() or b:playingAudio() then anyPlaying = true end
        return a.attributes.lastFocusTime > b.attributes.lastFocusTime
      end)

      if anyPlaying then
        listHeader('Audio')
        for i = 1, #ordered do
          if ordered[i]:playingAudio() and searchTestTab(tabSearch, ordered[i]) then
            any = true
            if not ui.areaVisibleY(itSize.y) then
              ui.dummy(itSize)
            else
              tabItem(i, ordered[i], tabSearch, enterPressed)
              enterPressed = false
            end
          end
        end
        if not any then
          ui.offsetCursorX(8)
          ui.textColored('Nothing to show.', rgbm.colors.gray)
        end
        ui.offsetCursorY(0)
        any = false
      end

      listHeader('Open tabs')
      for i = 1, #ordered do
        if not ordered[i]:playingAudio() and searchTestTab(tabSearch, ordered[i]) then
          any = true
          if not ui.areaVisibleY(itSize.y) then
            ui.dummy(itSize)
          else
            tabItem(i, ordered[i], tabSearch, enterPressed)
            enterPressed = false
          end
        end
      end
      if not any then
        ui.offsetCursorX(8)
        ui.textColored('Nothing to show.', rgbm.colors.gray)
      end
      ui.offsetCursorY(0)
  
      if enterWasPressed and not enterPressed then
        ui.closePopup()
      end
  
      if #App.closedTabs > 0 then
        listHeader('Recently closed')
  
        ui.pushID('closed')
        any = false
        for i = #App.closedTabs, 1, -1 do
          if searchTestClosedTab(tabSearch, i) then
            any = true
            if not ui.areaVisibleY(46) then
              ui.dummy(itSize)
            else
              tabClosedItem(i, tabSearch, enterPressed)
              enterPressed = false
            end
          end
        end
        if not any then
          ui.offsetCursorX(8)
          ui.textColored('Nothing to show.', rgbm.colors.gray)
        end
        ui.popID()
        ui.offsetCursorY(0)
      end
  
      ui.offsetCursorY(4)
      ui.thinScrollbarBegin(true)
      ui.thinScrollbarEnd()
      tabsMenuLastHeight = ui.getCursorY()
    end)
    ui.setMaxCursorX(260)
    ui.setMaxCursorY(ui.getCursorY() - 12)
  end, {position = position, pivot = vec2(1, 0)})
end

return {
  showTabsMenu = showTabsMenu
}