local FaviconsProvider = require('src/FaviconsProvider')

local App = require('src/App')
local Icons = require('src/Icons')
local Utils = require('src/Utils')
local ControlsBasic = require('src/ControlsBasic')
local ControlsAdvanced = require('src/ControlsAdvanced')
local ControlsInputFeatures = require('src/ControlsInputFeatures')
local Themes = require('src/Themes')

local removeItem
local popup = Utils.uniquePopup()

local function showBookmarksMenu(toggle, position)
  local tab = App.selectedTab()
  local entry = tab.attributes.bookmarked
  local newlyCreated = not entry
  if newlyCreated then
    entry = {title = tab:title(true), url = tab:url()}
    tab.attributes.bookmarked = entry
    App.storedBookmarks:add(entry)
  end
  popup(toggle, function ()
    ui.pushFont(ui.Font.Title)
    ui.text(newlyCreated and 'Bookmark added' or 'Edit bookmark')
    ui.popFont()
    ui.offsetCursorY(8)

    ui.pushFont(ui.Font.Small)
    ui.text('Name:')
    ui.popFont()
    
    ui.pushStyleColor(ui.StyleColor.FrameBg, rgbm(0, 0, 0, 0.4))
    ui.setNextItemWidth(-0.1)
    if ui.isWindowAppearing() then ui.setKeyboardFocusHere() end
    local _, enterPressed
    entry.title, _, enterPressed = ui.inputText('##title', entry.title)
    App.storedBookmarks:update(entry)
    ui.popStyleColor()
    ControlsInputFeatures.inputContextMenu(tab)
    ui.offsetCursorY(8)

    ui.setNextItemIcon(ui.Icons.Confirm)
    if ui.button('Done', vec2(120, 0)) or enterPressed then
      ui.closePopup()
    end
    ui.sameLine(0, 4)
    ui.setNextItemIcon(ui.Icons.Trash)
    if ui.button('Remove', vec2(120, 0)) then
      App.storedBookmarks:remove(entry)
      tab.attributes.bookmarked = nil
      ui.closePopup()
      ui.toast(ui.Icons.Trash, 'Removed “%s”' % entry.title, function ()
        App.storedBookmarks:restore(entry)
        tab.attributes.bookmarked = entry
      end)
    end
    ui.offsetCursorY(8)
  end, {position = position, pivot = vec2(1, 0)})
end

---@param entry {title: string, url: string}
local function editBookmark(entry)
  local copied = table.clone(entry, false) ---@type {title: string, url: string}
  ui.modalDialog('Edit bookmark', function ()
    copied.title = ui.inputText('Title', copied.title, ui.InputTextFlags.Placeholder)
    copied.url = ui.inputText('URL', copied.url, ui.InputTextFlags.Placeholder)
    ui.newLine()
    ui.offsetCursorY(4)
    local a = copied.title ~= '' and copied.url ~= ''
    if ui.modernButton('OK', vec2(ui.availableSpaceX() / 2 - 4, 40), a and ui.ButtonFlags.Confirm or ui.ButtonFlags.Disabled, ui.Icons.Confirm) 
        or ui.keyPressed(ui.Key.Enter) then
      entry.title, entry.url = copied.title, copied.url
      App.storedBookmarks:update(copied)
      return true
    end
    ui.sameLine(0, 8)
    return ui.modernButton('Cancel', vec2(-0.1, 40), ui.ButtonFlags.Cancel, ui.Icons.Cancel)
  end, true)
end

local itSize = vec2(1, 46)
local editingItem, draggingItem, draggingStart, draggingAnimationItem, draggingAnimationFade

---@param i integer
---@param filter string
local function bookmarkItem(i, filter)
  ui.pushID(i)
  local item = App.storedBookmarks:at(i)
  local icon = FaviconsProvider.get(item.url, nil, true)

  local dragOffset = 0
  if draggingStart ~= nil then
    if not ui.mouseDown(ui.MouseButton.Left) then
      draggingStart, draggingItem = nil, nil
    elseif item == draggingItem then
      dragOffset = ui.mousePos().y - draggingStart
      if math.abs(dragOffset) > itSize.y * 0.7 and App.storedBookmarks:at(i + math.sign(dragOffset)) then
        setTimeout(function ()
          draggingStart = draggingStart + itSize.y * math.sign(dragOffset)
          App.storedBookmarks:swap(item, App.storedBookmarks:at(i + math.sign(dragOffset)))
          draggingAnimationItem, draggingAnimationFade = App.storedBookmarks:at(i), math.sign(dragOffset)
        end)
      end
      ui.captureMouse(true)
    end
  end

  if item == draggingAnimationItem then
    dragOffset = draggingAnimationFade * itSize.y
    draggingAnimationFade = math.applyLag(draggingAnimationFade, 0, 0.7, ui.deltaTime())
  end
  if math.abs(dragOffset) > 0.5 then
    ui.beginTransformMatrix()
  end

  if filter == '' then
    ui.invisibleButton('', itSize)
  else
    ui.dummy(itSize)
  end

  local h = ui.itemHovered()
  if not draggingStart and ui.itemActive() then
    draggingStart = ui.mousePos().y
    draggingItem = item
  elseif item == draggingItem and math.abs(dragOffset) > 4 then
    ui.drawRectFilled(ui.itemRectMin(), ui.itemRectMax(), rgbm.colors.black)    
  end

  local clicked = ControlsBasic.nativeHyperlinkBehaviour(item.url, function ()
    ui.separator()
    if ControlsBasic.menuItem('Edit bookmark') then
      editBookmark(item)
    end
    if ControlsBasic.menuItem('Remove bookmark') then
      removeItem = item
    end
  end) and ui.getLastID() or false
  if ui.itemClicked(ui.MouseButton.Left) then
    editingItem = item
    if ui.mouseDoubleClicked() then
      draggingStart, draggingItem = nil, nil
      ControlsBasic.nativeHyperlinkNavigate(item.url, nil, true)
    end
  end

  local c = ui.getCursor()
  local r1, r2 = ui.itemRectMin(), ui.itemRectMax()
  r1.x, r2.x = r1.x + 10, r2.x - 28

  ui.drawIcon(icon, r1 + vec2(8, 14), r1 + vec2(24, 30))
  r1.x = r1.x + 36

  if editingItem == item or ui.itemHovered() then
    local e1, e2 = false, false
    ui.pushStyleColor(ui.StyleColor.FrameBg, rgbm(0, 0, 0, 0))
    ui.setCursor(r1 + vec2(-8, 4))
    ui.setItemAllowOverlap()
    ui.setNextItemWidth(-40)
    item.title, e1 = ui.inputText('Title', item.title, ui.InputTextFlags.Placeholder)
    ControlsInputFeatures.inputContextMenu(App.selectedTab())

    ui.setCursor(r1 + vec2(-8, 21))
    ui.setItemAllowOverlap()
    ui.pushFont(ui.Font.Small)
    ui.setNextItemWidth(-40)
    item.url, e2 = ui.inputText('URL', item.url, ui.InputTextFlags.Placeholder)
    ControlsInputFeatures.inputContextMenu(App.selectedTab())
    ui.popFont()
    ui.popStyleColor()
    if e1 or e2 then
      App.storedBookmarks:update(item)
    end
  else
    ui.drawTextClipped(ControlsBasic.textHighlightFilter(item.title, filter), r1, r2, nil, vec2(0, 0.25), true)
    ui.pushFont(ui.Font.Small)
    ui.drawTextClipped(ControlsBasic.textHighlightFilter(item.url, filter), r1, r2, nil, vec2(0, 0.75), true)
    ui.popFont()
  end

  ui.setCursor(r2 - vec2(4, 34))
  ui.setItemAllowOverlap()
  ui.pushStyleColor(ui.StyleColor.Button, rgbm.colors.transparent)
  if ui.iconButton(Icons.Cancel, 22, 7) then removeItem = item end
  if ui.itemHovered() then ui.setTooltip('Remove item from list') end
  ui.popStyleColor()
  ui.setCursor(c)

  ui.popID()

  if math.abs(dragOffset) > 0.5 then
    local m = mat3x3:identity()
    m.row2.z = dragOffset
    ui.endTransformMatrix(m)
  elseif clicked and ui.getActiveID() == clicked then
    App.selectedTab():navigate(item.url)
  end

  return h
end

local function removeBookmark(item)
  local tab = App.selectedTab() ---@type WebBrowser?
  if tab and tab.attributes.bookmarked ~= item then tab = nil end
  if tab then tab.attributes.bookmarked = nil end
  App.storedBookmarks:remove(item)
  ui.toast(ui.Icons.Trash, 'Removed “%s”' % item.title, function ()
    App.storedBookmarks:restore(item)
    if tab then tab.attributes.bookmarked = item end
  end)
end

---@param p1 vec2
---@param p2 vec2
---@param tab WebBrowser
local function drawBookmarksTab(p1, p2, tab)
  Themes.drawThemedBg(p1, p2, 0.5)
  Themes.beginColumnGroup(p1, p2, 400)

  tab.attributes.bookmarksQuery = ControlsAdvanced.searchBar('Search bookmarks', tab.attributes.bookmarksQuery, tab)
  ui.offsetCursorY(12)

  ui.childWindow('bookmarks', vec2(), false, bit.bor(ui.WindowFlags.NoScrollbar, ui.WindowFlags.NoBackground), function ()
    ui.thinScrollbarBegin(true)

    itSize.x = ui.availableSpaceX()
    local anyShown = false
    local anyHovered
    local filter = tab.attributes.bookmarksQuery or ''
    local draggingIndex, draggingPosition
    for i = 1, #App.storedBookmarks do
      local item = App.storedBookmarks:at(i)
      if filter == ''
          or item.title:findIgnoreCase(filter)
          or item.url:findIgnoreCase(filter) then
        if draggingItem == item then
          draggingIndex, draggingPosition = i, ui.getCursorY()
          ui.dummy(itSize)
        elseif ui.areaVisibleY(itSize.y) then
          anyShown = true
          if bookmarkItem(i, filter) then
            anyHovered = true
          end
          -- drawListItem(i, filter)
          -- ui.text(item.title)
          -- ui.text(item.url)
        else
          ui.dummy(itSize)
        end
      end
    end

    if draggingIndex then
      local c = ui.getCursorY()
      ui.setCursorY(draggingPosition)
      if bookmarkItem(draggingIndex, filter) then
        anyHovered = true
      end
      ui.setCursorY(c)
    end

    if ui.mouseClicked() and not anyHovered then
      editingItem = nil
    end

    if not anyShown then
      ui.offsetCursorY(12)
      ui.text('Nothing to show.')
    end

    ui.offsetCursorY(20)
    ui.thinScrollbarEnd()

    if removeItem then
      removeBookmark(removeItem)
      removeItem = nil
    end
  end)
  ui.endGroup()
end

local closeBookmarksPopup = false
local function drawBookmarksPopup(startingIndex)
  ui.thinScrollbarBegin(true)
  for i = startingIndex, #App.storedBookmarks do
    ui.pushID(i)
    local item = App.storedBookmarks:at(i)

    ui.setNextItemIcon(FaviconsProvider.get(item.url, nil, true))
    if ControlsBasic.menuItem(item.title) then
      ControlsBasic.nativeHyperlinkNavigate(item.url)
    end
    ControlsBasic.nativeHyperlinkBehaviour(item.url, function ()
      ui.separator()
      if ControlsBasic.menuItem('Edit bookmark') then
        editBookmark(item)
      end
      if ControlsBasic.menuItem('Remove bookmark') then
        removeBookmark(item)
      end
    end, function ()
      closeBookmarksPopup = true
    end)
    if closeBookmarksPopup then
      ui.closePopup()
    end

    ui.popID()
  end
  ui.thinScrollbarEnd()
end

local uis = ac.getUI()
local vecItemSize = vec2(80, 22)
local vecI1, vecI2 = vec2(), vec2()

local barLargeMove = false
local barDraggingItem, barDraggingStart
local barDraggingAnimationItem, barDraggingAnimationOffset

local function drawBookmarksBarItem(item, width)
  local dragOffset = 0
  if item == barDraggingItem and barDraggingStart ~= nil then
    if uis.isMouseLeftKeyDown then
      dragOffset = ui.mousePos().x - barDraggingStart
      ui.captureMouse(true)
    else
      barDraggingStart, barDraggingItem = nil, nil
    end
  elseif item == barDraggingAnimationItem then
    barDraggingAnimationOffset = math.applyLag(barDraggingAnimationOffset, 0, 0.8, uis.dt)
    dragOffset = barDraggingAnimationOffset * 40
    if math.abs(dragOffset) < 1 then
      barDraggingAnimationItem = nil
    end
  end

  if math.abs(dragOffset) > 0.5 then
    ui.beginTransformMatrix()
  end

  vecItemSize.x = width
  if barDraggingItem and barDraggingItem ~= item then
    ui.invisibleButton('', vecItemSize)
  elseif ui.button('###', vecItemSize) then
    ControlsBasic.nativeHyperlinkNavigate(item.url)
  end
  ControlsBasic.nativeHyperlinkBehaviour(item.url, function ()
    ui.separator()
    if ControlsBasic.menuItem('Edit bookmark') then
      editBookmark(item)
    end
    if ControlsBasic.menuItem('Remove bookmark') then
      removeBookmark(item)
    end
  end)

  local v1, v2 = ui.itemRect()
  if not barDraggingItem and ui.itemActive() then
    barDraggingStart = ui.mousePos().x
    barDraggingItem = item
  elseif item == barDraggingItem then
    if barLargeMove then
      ui.drawRectFilled(v1, v2, ControlsBasic.barBackgroundColor)    
    elseif math.abs(dragOffset) > 4 then
      barLargeMove = true
    end
  end

  ui.drawIcon(FaviconsProvider.get(item.url, nil, true), vecI1:set(5, 5):add(v1), vecI2:set(17, 17):add(v1))
  v1.x, v1.y = v1.x + 21, v1.y + 5
  ui.drawTextClipped(item.title, v1, v2, nil, 0, true)

  if math.abs(dragOffset) > 0.5 then
    local m = mat3x3:identity()
    m.row1.z = dragOffset
    ui.endTransformMatrix(m)
  end
  return dragOffset
end

local widthCache = setmetatable({}, {__mode = 'kv'})

local function getWidth(title)
  local r = widthCache[title]
  if r then return r end
  r = math.min(ui.measureText(title).x, 80) + 28
  widthCache[title] = r
  return r
end

local vecFramePadding = vec2(5, 5)
local vecMoreSize = vec2(12, 0)

local function drawBookmarksBar()
  if not uis.isMouseLeftKeyDown then
    barDraggingItem, barLargeMove = nil, false
  end

  ui.pushFont(ui.Font.Small)
  ui.pushStyleVar(ui.StyleVar.FramePadding, vecFramePadding)
  local draggingIndex, draggingWidth, draggingPreviousWidth, draggingNextWidth, lastWidth
  for i = 1, #App.storedBookmarks do
    local item = App.storedBookmarks:at(i)
    local width = getWidth(item.title)
    if ui.availableSpaceX() < width + 8 then
      ui.offsetCursorX(ui.availableSpaceX() - 12)
      if ui.iconButton(ui.Icons.SquaresVertical, vecMoreSize, 2, true) then
        Utils.popup(function ()
          drawBookmarksPopup(i)
        end, { position = ui.windowPos() + ui.itemRectMax(), pivot = vec2(1, 0), flags = ui.WindowFlags.NoScrollbar })
      end
      break
    end
    if draggingIndex and draggingNextWidth == nil then
      draggingNextWidth = width
    end
    if item == barDraggingItem then
      draggingPreviousWidth = lastWidth
      draggingIndex, draggingWidth = i, width
      ui.backupCursor()
      ui.offsetCursorX(width + 4)
    else
      ui.pushID(i)
      drawBookmarksBarItem(item, width)
      if ui.itemHovered() then
        ui.tooltip(function ()
          ui.text(item.title)
          ui.textAligned(item.url, 0, vec2(math.min(ui.measureText(item.url).x + 6, 160), 0), true)
        end)
      end
      ui.popID()
      ui.sameLine(0, 4)
    end
    lastWidth = width
  end
  if draggingIndex and barDraggingItem then
    ui.restoreCursor()
    ui.pushID(draggingIndex)
    local offset = drawBookmarksBarItem(barDraggingItem, draggingWidth)
    ui.popID()
    if draggingPreviousWidth and offset < -draggingPreviousWidth * 0.7 then
      local another = App.storedBookmarks:at(draggingIndex - 1)
      if another then
        barDraggingStart = barDraggingStart - draggingPreviousWidth
        App.storedBookmarks:swap(barDraggingItem, another)
        barDraggingAnimationItem = another
        barDraggingAnimationOffset = -1
      end
    elseif draggingNextWidth and offset > draggingNextWidth * 0.7 then
      local another = App.storedBookmarks:at(draggingIndex + 1)
      if another then
        barDraggingStart = barDraggingStart + draggingNextWidth
        App.storedBookmarks:swap(barDraggingItem, another)
        barDraggingAnimationItem = another
        barDraggingAnimationOffset = 1
      end
    end
  end
  ui.popFont()
  ui.popStyleVar()
end

local bookmarksBarVisible = false

return {
  showBookmarksMenu = showBookmarksMenu,
  drawBookmarksTab = drawBookmarksTab,
  drawBookmarksBar = drawBookmarksBar,
  setBookmarksBarVisible = function (visible)
    bookmarksBarVisible = visible
  end,
  isBookmarksBarVisible = function ()
    return bookmarksBarVisible
  end
}