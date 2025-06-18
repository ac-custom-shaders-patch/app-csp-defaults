local App = require('src/App')
local Utils = require('src/Utils')
local Storage = require('src/Storage')
local Themes = require('src/Themes')

local hotkeyAlignment = vec2(1, 0)
local hotkeyTextColor = rgbm(1, 1, 1, 0.5)
local vec2Zero = vec2()

---@param label string
---@param hotkey string?
---@param flags integer?
---@return boolean
local function menuItem(label, hotkey, flags)
  flags = bit.bor(flags or 0, ui.SelectableFlags.SpanClipRect)
  if hotkey then
    local c = ui.getCursor()
    local r = ui.selectable(label, false, flags)
    ui.setCursorX(140)
    ui.setCursorX(c.x)
    ui.drawTextClipped(hotkey, c, c + vec2(ui.availableSpaceX(), 22), hotkeyTextColor, hotkeyAlignment)
    return r
  end
  return ui.selectable(label, false, flags)
end

---@param url string
---@param extraMenuItems fun()?
---@param selectionCallback fun()?
---@return boolean
local function nativeHyperlinkBehaviour(url, extraMenuItems, selectionCallback)
  if ui.itemHovered() then
    ui.setMouseCursor(ui.MouseCursor.Hand)
    App.nativeStatus = url
    if ui.itemClicked() then
      if ui.hotkeyCtrl() then
        App.addTab(url, nil, nil, App.selectedTab())
      elseif ui.hotkeyShift() or ac.getUI().ctrlDown and ac.getUI().shiftDown then
        App.addAndSelectTab(url, nil, nil, App.selectedTab())
      else
        return true
      end
    end
    if ui.itemClicked(ui.MouseButton.Middle) and App.canOpenMoreTabs() then
      App.addTab(url, nil, nil, App.selectedTab())
    end
    if url and ui.itemClicked(ui.MouseButton.Right, true) then
      local sb = selectionCallback or function () end
      Utils.popup(function ()
        local tab = App.selectedTab()
        local item = menuItem        
        if item('Open URL') then tab:navigate(url) sb() end
        if not App.canOpenMoreTabs() then ui.pushDisabled() end
        if item('Open in new tab') then App.addAndSelectTab(url, nil, nil, tab) sb() end
        if item('Open in background') then App.addTab(url, nil, nil, tab) sb() end
        if not App.canOpenMoreTabs() then ui.popDisabled() end
        if WebBrowser.knownProtocol(url) then
          if item('Open in system browser') then Utils.openURLInSystemBrowser(url) sb() end
        end
        ui.separator()
        if item('Copy URL') then ac.setClipboadText(url or '?') end
        if url:startsWith('http') then
          if item(Storage.settings.askForDownloadsDestination and 'Save link as…' or 'Download link') then tab:download(url) end
        end
        if extraMenuItems then extraMenuItems() end
      end)
    end
  end
  return false  
end

---@param url string
---@param tab WebBrowser?
---@param tryReuse boolean?
local function nativeHyperlinkNavigate(url, tab, tryReuse)
  local s = ac.getUI()
  if not s.ctrlDown and not s.altDown and not s.shiftDown then
    if tryReuse then
      App.selectOrOpen(url, tab)
    else
      (tab or App.selectedTab()):navigate(url)
    end
  end
end

local function nativeHyperlink(url, label, size)
  ui.pushStyleColor(ui.StyleColor.Text, rgbm(0, 0.5, 1, 1))
  ui.textAligned(label or url, vec2Zero, size, size ~= nil)
  ui.popStyleColor()
  ui.itemHyperlink()
  return nativeHyperlinkBehaviour(url)
end

---@param tab WebBrowser
---@param onClose fun()?
local function showTabMenu(tab, onClose)
  Utils.popup(function ()
    if not App.canOpenMoreTabs() then ui.pushDisabled() end
    if menuItem('New tab to the right') then
      App.addAndSelectTab(nil, false, nil, tab)
    end
    if not App.canOpenMoreTabs() then ui.popDisabled() end
    if WebBrowser.knownProtocol(tab:url()) and menuItem('Move tab to system browser') then
      tab.attributes.onClose = function (browser)
        Utils.openURLInSystemBrowser(browser:url())
      end
      App.closeTab(tab)
    end
    ui.separator()
    if menuItem('Reload', 'Ctrl+R') then
      tab:reload(ui.hotkeyCtrl())
    end
    if not App.canOpenMoreTabs() then ui.pushDisabled() end
    if menuItem('Duplicate') then
      App.addAndSelectTab(tab:url(), false, tab:scroll().y, tab)
    end
    if not App.canOpenMoreTabs() then ui.popDisabled() end
    if menuItem(tab.attributes.pinned and 'Unpin' or 'Pin') then
      tab.attributes.pinned = not tab.attributes.pinned
      tab.attributes.tabOffset = tab.attributes.pinned and 20 or -20
      App.verifyTabPosition(tab)
      App.updatedSavedTabInformation(tab)
    end
    if menuItem(tab:muted() and 'Unmute tab' or 'Mute tab') then
      tab:mute(not tab:muted())
      App.saveTabs()
    end
    ui.separator()
    if menuItem('Close', 'Ctrl+W') then
      App.closeTab(tab)
    end
    if #App.tabs > 1 then
      if menuItem('Close other tabs') then
        table.forEach(App.tabs, function (t) if t ~= tab then setTimeout(App.closeTab ^ t) end end)
      end
    end
    if table.indexOf(App.tabs, tab) < #App.tabs then
      if menuItem('Close tabs to the right') then
        local j = table.indexOf(App.tabs, tab)
        table.forEach(App.tabs, function (t, i) if i > j then setTimeout(App.closeTab ^ t) end end)
      end
    end
  end, { onClose = onClose })
end

---@param text string
---@param filter string
---@return string
local function textHighlightFilter(text, filter)
  if filter ~= '' then
    local s, l = 1, #filter
    for _ = 1, 3 do
      local x = text:findIgnoreCase(filter, s)
      if not x then break end
      ui.setNextTextSpanStyle(x, x + l - 1, nil, true)
      s = x + l
    end
  end
  return text
end

---@param tab WebBrowser
local function tabTooltip(tab)
  ui.pushFont(ui.Font.Title)
  ui.textWrapped(tab:title(true), 360)
  ui.popFont()
  ui.text(tab:domain())
  -- if not tab:loading() and (tab:blank() or not tab:loadError()) then
  do -- drawing those previews always 
    ui.offsetCursorY(8)
    ui.offsetCursorX(-19)
    ui.pushClipRectFullScreen()
    ui.dummy(vec2(378, math.round(378 * tab:height() / tab:width())))
    tab:draw(ui.itemRect())
    ui.popClipRect()
    ui.setMaxCursorX(360)
    ui.setMaxCursorY(ui.getCursorY() - 11)
  end
  if tab:playingAudio() then
    ui.offsetCursorY(8)
    ui.text('This tab is playing audio')
    ui.setMaxCursorY(ui.getCursorY())
  end
end

local newSize = vec2()
local lastCanvas ---@type ui.ExtraCanvas
local lastStateFn, lastState

---A small wrapper that usually draws WebBrowser custom things as is, but if the thing is requested to be drawn with a very
---different size, it would use a separate canvas to draw things smaller.
---@param fn fun(p1: vec2, p2: vec2, tab: WebBrowser)
---@param state fun(tab: WebBrowser): any
---@return fun(p1: vec2, p2: vec2, tab: WebBrowser)
local function drawThumbnailHelper(fn, state)
  ---@type fun(p1: vec2, p2: vec2, tab: WebBrowser)
  return function (p1, p2, tab)
    local targetWidth = p2.x - p1.x
    local tabWidth = tab:width()
    if math.abs(targetWidth - tabWidth) > 1 then
      newSize:set(tabWidth, math.round(tabWidth * (p2.y - p1.y) / targetWidth))
      if not lastCanvas or lastCanvas:size() ~= newSize then
        if lastCanvas then lastCanvas:dispose() end
        lastCanvas, lastState = ui.ExtraCanvas(newSize, 4), nil
      end

      local curState = state(tab)
      if lastState ~= curState or lastStateFn ~= state then
        lastState, lastStateFn = curState, state
        lastCanvas:update(function ()
          local theme = Themes.accentOverride()
          if theme then ui.configureStyle(theme, false, false, 1) end
          fn(vec2Zero, newSize, tab)
        end)
      end
      ui.drawImage(lastCanvas, p1, p2)
    else
      fn(p1, p2, tab)
    end
  end
end

---@param tab WebBrowser
---@param stateRef {[1]: number}
local function zoomEditableText(tab, stateRef)  
  if ui.isWindowAppearing() then
    stateRef[1] = 0
  end

  local curScale = tab:zoomScale()
  if stateRef[1] ~= 0 then
    ui.backupCursor()
    local textWidth = ui.measureText('%.0f' % (100 * curScale)).x
    ui.offsetCursorX((40 - (textWidth + 12)) / 2)
    ui.setNextItemWidth(textWidth)
    ui.pushStyleVar(ui.StyleVar.FramePadding, 0)
    local v = ui.inputText('##zoom', '%.0f' % (100 * curScale), bit.bor(ui.InputTextFlags.CharsDecimal, 
      ui.InputTextFlags.NoHorizontalScroll, ui.InputTextFlags.AutoSelectAll))
    if ui.itemEdited() then
      local newZoom = tonumber(v)
      if newZoom then tab:setZoomScale(newZoom / 100) end
    end
    if stateRef[1] == 1 then
      stateRef[1] = 2
      ui.setKeyboardFocusHere(-1)
    elseif not ui.itemActive() and not ui.itemFocused() then
      stateRef[1] = 0
    elseif ui.keyPressed(ui.Key.Up) or ui.keyPressed(ui.Key.Down) then
      ui.inputTextCommand('setText', (tonumber(v) or math.round(100 * curScale)) + (ui.keyPressed(ui.Key.Up) and 1 or -1) * (ui.hotkeyCtrl() and 10 or 1))
      ui.inputTextCommand('selectAll')
    end
    ui.popStyleVar()
    ui.sameLine(0, 0)
    ui.text('%')
    ui.restoreCursor()
    ui.dummy(vec2(40, 0))
  else
    ui.textAligned('%.0f%%' % (100 * curScale), 0.5, vec2(40, 0))
    if ui.itemHovered() then
      ui.setMouseCursor(ui.MouseCursor.TextInput)
      if ui.itemClicked() then stateRef[1] = 1 end
    end
  end
end

local function zoomMenuItem(tab, zoomState)
  local withFullscreen = not tab.attributes.windowTab
  local w = ui.availableSpaceX()
  local curScale = tab:zoomScale()
  ui.text('Zoom')
  ui.pushStyleColor(ui.StyleColor.Button, rgbm.colors.transparent)
  ui.sameLine(w - (withFullscreen and 86 or 66))
  ui.offsetCursorY(-4)
  if curScale <= 0.25 then ui.pushDisabled() end
  if ui.iconButton(ui.Icons.Minus) then tab:setZoom(tab:zoom() - 0.5 * (ui.hotkeyCtrl() and 5 or 1)) end
  if curScale <= 0.25 then ui.popDisabled() end
  ui.sameLine(0, 0)
  ui.offsetCursorY(4)
  zoomEditableText(tab, zoomState)
  ui.sameLine(0, 0)
  ui.offsetCursorY(-4)
  if curScale >= 5 then ui.pushDisabled() end
  if ui.iconButton(ui.Icons.Plus) then tab:setZoom(tab:zoom() + 0.5 * (ui.hotkeyCtrl() and 5 or 1)) end
  if curScale >= 5 then ui.popDisabled() end
  if withFullscreen then
    ui.sameLine(0, 0)
    if ui.iconButton(ui.Icons.Fullscreen) then Utils.toggleFullscreen(tab) end
  end
  ui.popStyleColor()
  ui.offsetCursorY(-4)  
end

return {
  menuItem = menuItem,
  nativeHyperlinkBehaviour = nativeHyperlinkBehaviour,
  nativeHyperlinkNavigate = nativeHyperlinkNavigate,
  nativeHyperlink = nativeHyperlink,
  showTabMenu = showTabMenu,
  textHighlightFilter = textHighlightFilter,
  tabTooltip = tabTooltip,
  drawThumbnailHelper = drawThumbnailHelper,
  zoomEditableText = zoomEditableText,
  zoomMenuItem = zoomMenuItem,
}