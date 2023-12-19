local App = require('src/App')
local Icons = require('src/Icons')
local Utils = require('src/Utils')
local ControlsBasic = require('src/ControlsBasic')
local ControlsAdvanced = require('src/ControlsAdvanced')
local Themes = require('src/Themes')

local function readableSize(bytes)
  if bytes < 1.2 * 1024 then return string.format('%.0f B', bytes) end
  if bytes < 1.2 * (1024 * 1024) then return string.format('%.1f KB', bytes / 1024) end
  return string.format('%.1f MB', bytes / (1024 * 1024))
end

local function readableSizeFraction(bytes, bytesTotal)
  if not bytesTotal or bytesTotal == 0 then
    return readableSize(bytes)
  end
  if bytesTotal < 1.2 * 1024 then return string.format('%.0f/%.0f B', bytes, bytesTotal) end
  if bytesTotal < 1.2 * (1024 * 1024) then return string.format('%.1f/%.1f KB', bytes / 1024, bytesTotal / 1024) end
  return string.format('%.1f/%.1f MB', bytes / (1024 * 1024), bytesTotal / (1024 * 1024))
end

---@param item WebBrowser.DownloadItem
local function findETA(item)
  local leftToDownload = item.totalBytes - item.receivedBytes
  if item.currentSpeed <= 1 then
    return math.huge
  end
  return leftToDownload / item.currentSpeed
end

---@param item WebBrowser.DownloadItem
local function estimateProgress(item)
  return item.totalBytes and item.totalBytes > 0 and item.receivedBytes / item.totalBytes 
    or (1024 * 1024 * item.receivedBytes / (1024 * 1024 + item.receivedBytes))
end

---@param item WebBrowser.DownloadItem
local function restartDownload(item)  
  if item.attributes.browser and item.attributes.browser.disposed and not item.attributes.browser:disposed() then
    item.attributes.browser.attributes.awaitDownload = {
      time = os.preciseClock(),
      url = item.downloadURL,
      destination = item.destination
    }
    item.attributes.browser:download(item.downloadURL)
  else
    App.selectedTab().attributes.awaitDownload = {
      time = os.preciseClock(),
      url = item.downloadURL,
      destination = item.destination,
    }
    App.selectedTab():download(item.originalURL)
  end
end

local ColBgHovered = rgbm(1, 1, 1, 0.1)
local ITEM_HEIGHT = const(44)

local r1 = vec2()
local r2 = vec2()
local itDummy = vec2(2, ITEM_HEIGHT)
local pbDummy = vec2(2, 2)

local removeItem
local menuOpened

---@param item WebBrowser.DownloadItem
local function tryOpenItem(item)
  if not io.fileExists(item.destination) then
    item.state = '__removed'
    App.storedDownloads:update(item)
  else
    os.openInExplorer(item.destination)
  end
end

---@param item WebBrowser.DownloadItem
local function tryOpenFolder(item)
  if not io.fileExists(item.destination) then
    item.state = '__removed'
    App.storedDownloads:update(item)
  else
    os.showInExplorer(item.destination)
  end
end

---@param item WebBrowser.DownloadItem
local function showItemMenu(item)
  menuOpened = item
  Utils.popup(function ()
    if ControlsBasic.menuItem('Open') then tryOpenItem(item) end
    if ControlsBasic.menuItem('Show in folder') then tryOpenFolder(item) end
    ui.separator()
    local d = item.state ~= 'loading' and item.state ~= 'paused'
    if d then ui.pushDisabled() end
    if ControlsBasic.menuItem('Cancel') then item:control('cancel') end
    if d then ui.popDisabled() end
  end, { onClose = function () menuOpened = nil end })  
end

local function drawPopupItem(i)
  ui.pushID(i)
  local item = App.recentDownloads[i]

  r1.y = ui.getCursorY() - 6
  r2.y = r1.y + ITEM_HEIGHT

  local hovered = ui.rectHovered(r1, r2, true)
  if menuOpened then hovered = menuOpened == item end
  if hovered then ui.drawRectFilled(r1, r2, ColBgHovered) end

  ui.setCursorX(20)
  ui.offsetCursorY(4)
  ui.image(ui.FileIcon(item.destination, item.state == 'complete'):style(ui.FileIcon.Style.Small), 16)
  ui.sameLine(0, 8)
  ui.offsetCursorY(-4)
  ui.beginGroup()
  ui.textAligned(io.getFileName(item.destination), 0, vec2(218, 0), true)
  ui.pushFont(ui.Font.Small)
  if item.state == '__removed' then
    ui.text('Removed')
    ui.dummy(pbDummy)
  elseif item.state == 'cancelled' then
    ui.text('Cancelled')
    ui.dummy(pbDummy)
  elseif item.state == 'complete' then
    ui.text(string.format('%s • %s', readableSize(item.totalBytes), Utils.readableAge(item.attributes.finishedTime)))
    ui.dummy(pbDummy)
  else
    local eta = item.totalBytes and item.totalBytes > 0 and Utils.readableETA(findETA(item)) or 'some time left'
    ui.text(string.format('%s • %s', readableSizeFraction(item.receivedBytes, item.totalBytes), item.state == 'paused' and 'Paused' or eta))
    if item.state == 'paused' then ui.pushStyleColor(ui.StyleColor.PlotHistogram, rgbm.colors.yellow) end
    ui.progressBar(estimateProgress(item), vec2(ui.availableSpaceX() - 20, 2))
    if item.state == 'paused' then ui.popStyleColor() end
  end

  ui.offsetCursorY(4)
  if hovered then
    local c = ui.getCursor()
    ui.pushStyleColor(ui.StyleColor.Button, rgbm.colors.transparent)
    ui.setCursor(r2 - vec2(44 + 16, 40))

    local co = ColBgHovered
    local ct = rgbm.new(co.rgb, 0)
    ui.drawRectFilledMultiColor(r2 - vec2(44 + 24, 40), r2 - vec2(44 + 12, 18), ct, co, co, ct)
    ui.drawRectFilled(r2 - vec2(44 + 12, 40), r2 - vec2(0, 18), co)

    ui.beginGroup()
    if item.state == 'complete' then
      if ui.iconButton(ui.Icons.Folder, 22, 7) then tryOpenFolder(item) end
      if ui.itemHovered() then ui.setTooltip('Show in folder') end
      ui.sameLine(0, 0)
      if ui.iconButton(ui.Icons.Maximize, 22, 7) then
        if not io.fileExists(item.destination) then
          item.state = '__removed'
          App.storedDownloads:update(item)
        else
          tryOpenItem(item)
        end
      end
      if ui.itemHovered() then ui.setTooltip('Open file') end
    elseif item.state == 'loading' then
      if ui.iconButton(Icons.Pause, 22, 7) then item:control('pause') end
      if ui.itemHovered() then ui.setTooltip('Pause loading') end
        ui.sameLine(0, 0)
      if ui.iconButton(Icons.Cancel, 22, 7) then item:control('cancel') end
      if ui.itemHovered() then ui.setTooltip('Cancel loading') end
    elseif item.state == 'paused' then
      if ui.iconButton(Icons.Resume, 22, 7) then item:control('resume') end
      if ui.itemHovered() then ui.setTooltip('Resume loading') end
      ui.sameLine(0, 0)
      if ui.iconButton(Icons.Cancel, 22, 7) then item:control('cancel') end
      if ui.itemHovered() then ui.setTooltip('Cancel loading') end
    elseif item.state == '__removed' or item.state == 'cancelled' then
      if ui.iconButton(ui.Icons.Restart, 22, 7) then
        restartDownload(item)
      end
      if ui.itemHovered() then ui.setTooltip('Try to download again') end
      ui.sameLine(0, 0)
      if ui.iconButton(Icons.Cancel, 22, 7) then removeItem = item end
      if ui.itemHovered() then ui.setTooltip('Remove item from list') end
    end
    ui.endGroup()
    if not ui.itemClicked() then
      if item.state == 'complete' and ui.mouseDoubleClicked() then
        tryOpenItem(item)
      end
      if ui.mouseClicked(ui.MouseButton.Right) then
        showItemMenu(item)
      end
    end

    ui.popStyleColor()
    ui.setCursor(c)
  end

  ui.popFont()
  ui.endGroup()
  ui.popID()  
end

local LIST_ITEM_HEIGHT = const(72)
local itListDummy = vec2(2, LIST_ITEM_HEIGHT)

local function drawListItem(i, filter)
  ui.pushID(i)
  local item = App.storedDownloads:at(i)

  local yStart = ui.getCursorY()  
  ui.dummy(vec2(ui.availableSpaceX(), LIST_ITEM_HEIGHT))
  if ui.itemClicked(ui.MouseButton.Right, true) then
    showItemMenu(item)
  end
  local yFinal = ui.getCursorY()  
  ui.setCursorY(yStart)

  ui.offsetCursorY(8)
  ui.offsetCursorX(16)
  if item.state == '__removed' or item.state == 'cancelled' then
    ui.beginTextureSaturationAdjustment()
    ui.image(ui.FileIcon(item.destination, item.state == 'complete'):style(ui.FileIcon.Style.Small), 24)
    ui.endTextureSaturationAdjustment(0)
  else
    ui.image(ui.FileIcon(item.destination, item.state == 'complete'):style(ui.FileIcon.Style.Small), 24)
  end
  ui.sameLine(0, 12)
  ui.offsetCursorY(-8)
  local deleteButton = item.state ~= 'loading' and item.state ~= 'paused'
  ui.beginGroup(ui.availableSpaceX() - (deleteButton and 22 or 44) - 20)
  local w = ui.availableSpaceX()

  local name = ControlsBasic.textHighlightFilter(io.getFileName(item.destination), filter)
  if item.state == '__removed' or item.state == 'cancelled' then
    ui.pushStyleColor(ui.StyleColor.Text, rgbm.colors.gray)
    ui.text(name)
    local b1, b2 = ui.itemRectMin(), ui.itemRectMax()
    ui.popStyleColor()
    b1.y = (b1.y + b2.y) / 2
    b2.y = b1.y
    b1.x, b2.x = b1.x - 2, b2.x + 2
    ui.drawLine(b1, b2, rgbm.colors.gray)
  else
    ui.textAligned(name, 0, vec2(w, 0), true)
  end

  if ui.itemHovered() and item.state == 'complete' then
    ui.setMouseCursor(ui.MouseCursor.Hand)
    if ui.itemClicked() then
      tryOpenItem(item)
    end
  end

  ui.pushStyleColor(ui.StyleColor.Text, rgbm.colors.gray)
  ui.textAligned(ControlsBasic.textHighlightFilter(item.originalURL, filter), 0, vec2(w, 0), true)
  ui.popStyleColor()
  if ControlsBasic.nativeHyperlinkBehaviour(item.originalURL) then
    ControlsBasic.nativeHyperlinkNavigate(item.originalURL, nil, true)
  end
  if item.state == 'complete' then
    if ControlsBasic.nativeHyperlink(nil, 'View in folder', nil) then
      tryOpenFolder(item)
    end
  elseif item.state == 'cancelled' then
    if ControlsBasic.nativeHyperlink(nil, 'Retry download', nil) then
      removeItem = item
      restartDownload(item)
    end
  elseif item.state == '__removed' then
    ui.textColored('File is deleted', rgbm.colors.gray)
  elseif item.state == 'loading' or item.state == 'paused' then
    local eta = item.totalBytes and item.totalBytes > 0 and Utils.readableETA(findETA(item)) or 'some time left'
    if item.totalBytes and item.totalBytes > 0 then
      ui.text(string.format('%s/s, %s of %s, %s', readableSize(item.currentSpeed), readableSize(item.receivedBytes), readableSize(item.totalBytes) or '?', item.state == 'paused' and 'paused' or eta))
    else
      ui.text(string.format('%s/s, %s, %s', readableSize(item.currentSpeed), readableSize(item.receivedBytes), item.state == 'paused' and 'paused' or eta))
    end
    if item.state == 'paused' then ui.pushStyleColor(ui.StyleColor.PlotHistogram, rgbm.colors.yellow) end
    ui.progressBar(estimateProgress(item), vec2(ui.availableSpaceX() - 20, 2))
    if item.state == 'paused' then ui.popStyleColor() end
  end

  ui.endGroup()
  ui.sameLine(0, 12)
  ui.pushStyleColor(ui.StyleColor.Button, rgbm.colors.transparent)
  ui.offsetCursorY(-4)
  if deleteButton then
    if ui.iconButton(Icons.Cancel, 22, 7) then removeItem = item end
    if ui.itemHovered() then ui.setTooltip('Remove from list') end
  else
    if ui.iconButton(item.state == 'paused' and Icons.Resume or Icons.Pause, 22, 7) then item:control(item.state == 'paused' and 'resume' or 'pause') end
    if ui.itemHovered() then ui.setTooltip(item.state == 'paused' and 'Resume' or 'Pause') end
    ui.sameLine(0, 0)
    if ui.iconButton(Icons.Stop, 22, 7) then item:control('cancel') end
    if ui.itemHovered() then ui.setTooltip('Cancel') end
  end
  ui.popStyleColor()

  ui.setCursorY(yFinal)
  ui.popID()  
end

local popup = Utils.uniquePopup()

local function showDownloadsMenu(toggle, position)
  popup(toggle, function ()
    ui.pushFont(ui.Font.Title)
    ui.text('Recent downloads')
    ui.popFont()
    ui.offsetCursorY(8)

    if #App.recentDownloads == 0 then
      ui.textColored('Nothing to show.', rgbm.colors.gray)
      ui.offsetCursorY(8)
    else
      r2.x = ui.windowSize().x
      ColBgHovered:set(ui.styleColor(ui.StyleColor.Header))
      ColBgHovered.mult = 1

      ui.setCursorX(0)
      ui.childWindow('list', vec2(280, 16 + math.min(#App.recentDownloads, 6) * ITEM_HEIGHT), false, bit.bor(ui.WindowFlags.NoScrollbar, ui.WindowFlags.NoBackground), function ()
        ui.thinScrollbarBegin(true)
        removeItem = nil
        ui.offsetCursorY(8)
        for i = #App.recentDownloads, math.max(1, #App.recentDownloads - 49), -1 do
          if ui.areaVisibleY(ITEM_HEIGHT) then
            drawPopupItem(i)
          else
            ui.dummy(itDummy)
          end
        end    
        ui.thinScrollbarEnd()
        if removeItem then
          table.removeItem(App.recentDownloads, removeItem)
          if removeItem.state == 'loading' or removeItem.state == 'paused' then
            removeItem:control('cancel')
          end
        end
      end)
    end

    ui.separator()

    if ControlsBasic.menuItem('Show all downloads', 'Ctrl+Shift+J') then
      App.selectOrOpen('about:downloads')
    end

    ui.setMaxCursorX(260)
  end, {position = position, pivot = vec2(1, 0)})
end

---@param p1 vec2
---@param p2 vec2
---@param tab WebBrowser
local function drawDownloadsTab(p1, p2, tab)
  Themes.drawThemedBg(p1, p2, 0.5)
  Themes.beginColumnGroup(p1, p2, 400)

  tab.attributes.downloadsQuery = ControlsAdvanced.searchBar('Search downloads', tab.attributes.downloadsQuery, tab)
  ui.offsetCursorY(12)

  ui.childWindow('list', vec2(), false, bit.bor(ui.WindowFlags.NoScrollbar, ui.WindowFlags.NoBackground), function ()
    ui.thinScrollbarBegin(true)
    removeItem = nil

    local anyShown = false
    local filter = tab.attributes.downloadsQuery or ''
    local lastDay
    for i = #App.storedDownloads, 1, -1 do
      local item = App.storedDownloads:at(i)
      if filter == '' 
          or io.getFileName(item.destination):findIgnoreCase(filter)
          or item.originalURL:findIgnoreCase(filter) then
        anyShown = true
        local day = tostring(os.date('%Y-%m-%d', item.attributes.startedTime))
        if day ~= lastDay then
          lastDay = day
          if i > 1 then ui.offsetCursorY(12) end
          ui.pushFont(ui.Font.Small)
          ui.text(Utils.readableDay(day, item.attributes.startedTime))
          ui.popFont()
          ui.offsetCursorY(4)
        end    
        if ui.areaVisibleY(LIST_ITEM_HEIGHT) then
          drawListItem(i, filter)
        else
          ui.dummy(itListDummy)
        end
      end
    end

    -- for i = #App.storedDownloads, 1, -1 do
    --   if ui.areaVisibleY(LIST_ITEM_HEIGHT) then
    --     drawListItem(#App.recentDownloads + i, filter)
    --   else
    --     ui.dummy(itListDummy)
    --   end
    -- end

    if not anyShown then
      ui.offsetCursorY(12)
      ui.text('Nothing to show.')
    end

    ui.offsetCursorY(20)
    ui.thinScrollbarEnd()

    if removeItem then
      local removed = removeItem
      table.removeItem(App.recentDownloads, removeItem)
      App.storedDownloads:remove(removed)
      if removeItem.state == 'loading' or removeItem.state == 'paused' then
        removeItem:control('cancel')
      end
      ui.toast(ui.Icons.Trash, 'Removed “%s” from list' % io.getFileName(removeItem.destination), function ()
        App.storedDownloads:restore(removed)
        table.insert(App.recentDownloads, removed)
        table.sort(App.recentDownloads, function (a, b)
          return a.attributes.startedTime < b.attributes.startedTime
        end)
      end)
    end
  end)
  ui.endGroup()
end

return {
  showDownloadsMenu = showDownloadsMenu,
  estimateProgress = estimateProgress,
  drawDownloadsTab = drawDownloadsTab,
}