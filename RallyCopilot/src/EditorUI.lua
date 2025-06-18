local sim = ac.getSim()
local uis = ac.getUI()

local AppState = require('src/AppState')
local DrawCalls = require('src/DrawCalls')
local RouteItem = require('src/RouteItem')
local RouteItemType = require('src/RouteItemType')
local RouteItemHint = require('src/RouteItemHint')
local VoicesHolder = require('src/VoicesHolder')
local EditorConfig = require('src/EditorConfig')
local PaceNotesHolder = require('src/PaceNotesHolder')

local EditorUI = {}

---@type Editor
local mainEditor

local function syncEditor()
  local editedNotes = PaceNotesHolder.edited()
  if not mainEditor then
    PaceNotesHolder.edit(PaceNotesHolder.list()[2] or PaceNotesHolder.generated())
    editedNotes = PaceNotesHolder.edited()
  end
  mainEditor = editedNotes:editor()
end

local vecUp = vec3(0, 1, 0)
local vecDown = vec3(0, -1, 0)
local fromAbove = 0
local trackProgress = 0
local trackYOffset = 0
local trackPosActive = -1

local hoveredItem = nil ---@type RouteItem?
local draggingStartItem = nil ---@type RouteItem?
local draggingList = nil
local draggingRay = nil
local zoom = 0
local lastMx = 0
local targetScroll = 0
local draggingBtnClicked = false

local u2 = vec2(0, 80)
local u3 = vec2(0, 120)
local u4 = vec2(0, 120)
local colSelected = rgbm(0, 1, 1, 1)
local colBlueBar = rgbm(0, 0.75, 1, 1)

local testSpeed = 100
local testingActive = false
local testingLastStart = 0
local blueBarScrolling = false
local movingFreeCamera = false
local popupOpened = false
local hoveredFlipped = false
local baseBlueBarYOffset
local lastClickedItem
local dragAreaUIStart
local speedGuess

local dragArea3DStart
local dragArea3DEnd
local dragArea3DCache = {}

local function estimateDY(testTrackYOffset)
  local v = vec2(1, 0.5 + testTrackYOffset * 0.1):normalize()
  return v.y * (50 + math.max(0, testTrackYOffset) * 8)
end

local function rectsIntersect(a1, a2, b1, b2, mx, my)
  return b2.x > math.min(a1.x, a2.x) + mx and b1.x < math.max(a1.x, a2.x) - mx
    and b2.y > math.min(a1.y, a2.y) + my and b1.y < math.max(a1.y, a2.y) - my
end

local function updateTrackPos()
  local progressCur = trackProgress
  local progressNext = trackProgress + (25 + 1000 * fromAbove) / sim.trackLengthM
  if AppState.loopingSpline then
    progressNext = progressNext % 1
  elseif progressNext > 1 then
    progressCur = progressCur - (progressNext - 1) / 10
    progressNext = 1
  end
  local pos = ac.trackProgressToWorldCoordinate(progressCur)
  local yOffset = trackYOffset
  fromAbove = math.min(1, yOffset * 0.01)
  local dir = ac.trackProgressToWorldCoordinate(progressNext):sub(pos)
  if dir:lengthSquared() < 1 then
    dir = vec3(0, 0, 1)
  else
    dir.y = 0
    dir:normalize()
  end

  dir.y = -0.5 - yOffset * 0.03
  pos:addScaled(dir:normalize(), -(50 + math.max(0, yOffset) * 8))
  ac.setCurrentCamera(ac.CameraMode.Free)
  local lag = math.lagMult(0.5, uis.dt)
  ac.setCameraPosition(math.lerp(sim.cameraPosition, pos, lag))
  ac.setCameraDirection(math.lerp(sim.cameraLook, dir, lag), vecUp)
  table.clear(dragArea3DCache)
end

local function syncTrackPos()
  local adjustedPosition = sim.cameraPosition:clone()
  adjustedPosition.y = ac.trackProgressToWorldCoordinate(ac.worldCoordinateToTrackProgress(sim.cameraPosition)).y
  local progress = ac.worldCoordinateToTrackProgress(adjustedPosition)
  local dy = sim.cameraPosition.y - ac.trackProgressToWorldCoordinate(progress).y
  local offset = dy * 0.1
  for _ = 1, 5 do
    local actualDY = estimateDY(offset)
    offset = offset * (dy / actualDY)
  end
  fromAbove = math.min(1, offset * 0.01)
  local lag = math.lagMult(0.5, uis.dt)
  if AppState.loopingSpline and math.abs(trackProgress - progress) > 0.5 then
    trackProgress = trackProgress > progress and trackProgress - 1 or trackProgress + 1
    trackProgress, trackYOffset = math.lerp(trackProgress, progress, lag), math.lerp(trackYOffset, offset, lag)
    trackProgress = trackProgress % 1
  else
    trackProgress, trackYOffset = math.lerp(trackProgress, progress, lag), math.lerp(trackYOffset, offset, lag)
  end
  table.clear(dragArea3DCache)
end

---@param hoveredNewItem RouteItem?
local function registerHoveredItem(hoveredNewItem)  
  if uis.isMouseLeftKeyClicked then
    if not uis.ctrlDown and not uis.shiftDown and not table.contains(mainEditor.selected, hoveredNewItem) then
      table.clear(mainEditor.selected)
    end
    if hoveredNewItem then
      if ui.hotkeyCtrl() and table.contains(mainEditor.selected, hoveredNewItem) then
        table.removeItem(mainEditor.selected, hoveredNewItem)
      else
        if uis.shiftDown and #mainEditor.selected > 0 then
          if not table.contains(mainEditor.selected, lastClickedItem) then
            lastClickedItem = nil
          end
          if not uis.ctrlDown then
            table.clear(mainEditor.selected)
          end
          mainEditor:sort('selected')
          if lastClickedItem then
            local f = table.indexOf(mainEditor.items, lastClickedItem)
            local i = table.indexOf(mainEditor.items, hoveredNewItem)
            if f and i then
              for j = math.min(f, i), math.max(f, i) do
                if not table.contains(mainEditor.selected, mainEditor.items[j]) then
                  table.insert(mainEditor.selected, mainEditor.items[j])
                end
              end
            end
          end
        end
        if not table.contains(mainEditor.selected, hoveredNewItem) then
          table.insert(mainEditor.selected, hoveredNewItem)
        end
      end
      if #mainEditor.selected == 1 then
        lastClickedItem = hoveredNewItem
      end
      if uis.isMouseLeftKeyDoubleClicked then
        trackProgress = hoveredNewItem.pos
        trackPosActive = 0.1
      end
    end
  end
  hoveredItem = hoveredNewItem
end

local buttonSize = vec2(22, 22)

local function openContextMenu(items)
  local e = items
  popupOpened = true
  ui.popup(function ()
    hoveredItem = nil
    ui.image(e[1]:icon(), vec2(48, 48))
    ui.sameLine(0, 12)
    ui.pushStyleVar(ui.StyleVar.FrameRounding, 2)
    ui.offsetCursorY(4)
    if ui.iconButton(ui.Icons.Play, vec2(22, 22), nil, nil, 6) then
      VoicesHolder.current():enqueue(e[1].type, e[1].modifier, e[1].hints, {})
    end
    ui.popStyleVar()
    if #e > 1 then
      local p1, p2 = vec2(62, 39), vec2(62 + 16, 39 + 16)
      for i = 2, #e do
        ui.drawImage(e[i]:icon(), p1, p2)
        p1.x, p2.x = p1.x + 12, p2.x + 12
      end
    end
    ui.separator()
    
    ui.header('Type')
    ui.separator()
    for i, v in ipairs(RouteItemType.names()) do
      if ui.menuItem(v, e[1].type == i, ui.SelectableFlags.DontClosePopups) then
        mainEditor.state:store()
        table.forEach(e, function (item) item.type = i end)
      end
    end

    local types = table.distinct(table.map(e, function (v) return v.type end))
    table.sort(types, function (a, b) return a < b end)
    local added = {}
    for _, t in ipairs(types) do
      local l, v = RouteItemType.modifiers(e[1].type)
      if l and v and not added[l] then
        added[l] = true

        ui.separator()
        ui.header(l)
        ui.separator()
        for i, d in ipairs(v) do
          if ui.menuItem(d, e[1].modifier == i, ui.SelectableFlags.DontClosePopups) then
            mainEditor.state:store()
            table.forEach(e, function (item) if item.type == t then item.modifier = i end end)
          end
        end
      end
    end

    ui.separator()
    ui.header('Hints')
    ui.separator()
    for hintID, hintName in ipairs(RouteItemHint.names()) do
      if ui.menuItem(hintName, table.contains(e[1].hints, hintID), ui.SelectableFlags.DontClosePopups) then
        mainEditor.state:store()
        if table.contains(e[1].hints, hintID) then
          table.forEach(e, function (item) table.removeItem(item.hints, hintID) end)
        else
          table.forEach(e, function (item) RouteItemHint.addHint(item.hints, hintID) end)
        end
      end
    end
  end, {onClose = function ()
    popupOpened = false
  end})
end

function EditorUI.newPopup()
  if ui.selectable('Empty') then
    PaceNotesHolder.edit()
    ac.setWindowOpen('editor', true)
  end
  if ui.itemHovered() then
    ui.setTooltip('Alternatively, you can use Ctrl+A and Delete to clear out an existing file')
  end
  if ui.selectable('Automatically generated') then
    PaceNotesHolder.edit(PaceNotesHolder.generated())
    ac.setWindowOpen('editor', true)
  end
end

local function saveAs()
  local v = PaceNotesHolder.edited()
  ui.modalPrompt('Save as?', 'New name:', v.metadata.name, 'Save', 'Cancel', ui.Icons.Save, ui.Icons.Cancel, function (newName)
    if newName then
      local updated = PaceNotesHolder.clone(v, newName)
      PaceNotesHolder.edit(updated)
      updated:save()
      ui.toast(ui.Icons.Save, 'Pacenotes saved as “%s”' % newName)
    end
  end)
end

function EditorUI.windowEditor()
  syncEditor()

  if not uis.wantCaptureMouse and speedGuess then
    ui.setTooltip('Speed estimate: %.1f km/h' % speedGuess)
  end

  local windowSize = ui.windowSize()

  ui.pushClipRect(0, windowSize, false)
  ui.setCursor(vec2(160, 0))

  if ui.hotkeyCtrl() then
    if ui.keyboardButtonPressed(ui.KeyIndex.A) then
      mainEditor.selected = table.clone(mainEditor.items, false)
    end
    if ui.keyboardButtonPressed(ui.KeyIndex.N) then
      ui.popup(EditorUI.newPopup)
    end
    if ui.keyboardButtonPressed(ui.KeyIndex.S) then
      PaceNotesHolder.edited():save()
      ui.toast(ui.Icons.Save, 'Pacenotes saved')
    end
  elseif uis.ctrlDown and uis.shiftDown and not uis.altDown then
    if ui.keyboardButtonPressed(ui.KeyIndex.S) then
      saveAs()
    end
  end

  ui.setNextItemIcon(ui.Icons.Document)
  if ui.button('File') then
    ui.popup(function ()
      do
        local v = PaceNotesHolder.edited()
        if ui.menuItem('New…', false, ui.SelectableFlags.DontClosePopups, 'Ctrl+N') then
          ui.popup(EditorUI.newPopup, {position = ui.windowPos() + ui.itemRectMax() - vec2(8, 22)})
        end
        if ui.menuItem('Save', false, ui.SelectableFlags.None, 'Ctrl+S') then
          v:save()
          ui.toast(ui.Icons.Save, 'Pacenotes saved')
        end
        if ui.menuItem('Save as…', false, ui.SelectableFlags.None, 'Ctrl+Shift+S') then
          saveAs()
        end
        if ui.selectable('Rename…') then
          ui.modalPrompt('Rename pacenotes?', 'New name:', v.metadata.name, 'Rename', 'Cancel', ui.Icons.Edit, ui.Icons.Cancel, function (newName)
            if newName then
              v.metadata.name = newName
              v:save()
            end
          end)
        end
      end
      ui.separator()
      ui.header('Pacenotes:')
      for _, v in ipairs(PaceNotesHolder.list()) do
        if not v:generated() then
          ui.setNextTextSpanStyle(1, #v.metadata.name, nil, true)
          if ui.selectable('%s%s\n ' % {v.metadata.name, v:hasUnsavedChanges() and '*' or ''}, v == PaceNotesHolder:edited()) then
            PaceNotesHolder.edit(v)
          end
          local s1, s2 = ui.itemRect()
          ui.pushFont(ui.Font.Small)
          ui.drawTextClipped('Author: %s.' % v.metadata.author, s1 + vec2(24, 4), s2 - 2, rgbm.colors.white, vec2(0, 1))
          ui.popFont()
          if ui.itemHovered() then
            ui.setTooltip('%sLocation: %s' % {v.new and 'Hasn’t been saved yet\n' or v:hasUnsavedChanges() and 'Has unsaved changes\n' or '', v.filename})
          end
          if ui.itemClicked(ui.MouseButton.Right, true) then
            ui.popup(function ()
              if ui.selectable('Rename…') then
                ui.modalPrompt('Rename pacenotes?', 'New name:', v.metadata.name, 'Rename', 'Cancel', ui.Icons.Edit, ui.Icons.Cancel, function (newName)
                  if newName then
                    v.metadata.name = newName
                    v:save()
                  end
                end)
              end
              if v == PaceNotesHolder.edited() then
                ui.pushDisabled()
              end
              if ui.selectable('Delete') then
                PaceNotesHolder.delete(v)
              end
              if v == PaceNotesHolder.edited() then
                ui.popDisabled()
                ui.setTooltip('Can’t remove currently selected pacenotes')
              end
              if not v.new then
                ui.separator()
                if ui.selectable('View in File Explorer') then
                  os.showInExplorer(v.filename)
                end
              end
            end)
          end
        end
      end
      -- testSpeed = ui.slider('##speed', testSpeed, 50, 200, 'Speed: %.0f km/h')
      -- if ui.button('Revert', vec2(98, 0)) then
      --   testingActive = false
      --   trackProgress = testingLastStart
      --   ui.closePopup()
      -- end
      -- ui.sameLine(0, 4)
      -- if ui.button('Stop here', vec2(98, 0)) then
      --   testingActive = false
      --   ui.closePopup()
      -- end
    end, {
      position = ui.windowPos() + ui.itemRectMin() + vec2(0, 22)
    })
    -- io.createFileDir(mainEditor.currentFilename)
    -- mainEditor:save(mainEditor.currentFilename)
    -- ui.toast(ui.Icons.Save, 'Data saved')
  end
  -- ui.setNextItemIcon(ui.Icons.Save)
  -- if ui.button('Save') then
  --   io.createFileDir(mainEditor.currentFilename)
  --   mainEditor:save(mainEditor.currentFilename)
  --   ui.toast(ui.Icons.Save, 'Data saved')
  -- end
  ui.sameLine(0, 4)

  ui.setNextItemIcon(ui.Icons.Undo)
  if ui.button('Undo', mainEditor.state:canUndo() and ui.ButtonFlags.None or ui.ButtonFlags.Disabled)
      or ui.hotkeyCtrl() and ui.keyboardButtonPressed(ui.KeyIndex.Z) then
    mainEditor.state:undo()
  end
  if ui.itemHovered() then
    ui.setTooltip('Undo (Ctrl+Z)')
  end
  ui.sameLine(0, 4)
  ui.setNextItemIcon(ui.Icons.Redo)
  if ui.button('Redo', mainEditor.state:canRedo() and ui.ButtonFlags.None or ui.ButtonFlags.Disabled)
      or ui.hotkeyCtrl() and ui.keyboardButtonPressed(ui.KeyIndex.Y) then
    mainEditor.state:redo()
  end
  if ui.itemHovered() then
    ui.setTooltip('Redo (Ctrl+Y)')
  end
  if windowSize.x < 700 then
    ui.sameLine(0, 4)
    ui.setNextItemIcon(ui.Icons.Plus)
    if ui.button('Add') then
      local added = false
      ui.popup(function ()
        if added then
          ui.closePopup()
          return
        end
        for i, v in pairs(RouteItemType.names()) do
          ui.setNextItemIcon(RouteItemType.icon(i, -1, nil, true))
          local clicked = ui.selectable(v, false, ui.SelectableFlags.DontClosePopups)
          if ui.itemHovered() then
            ui.setTooltip('%s (Ctrl+%d)' % {v, i})
          end
          if clicked or ui.hotkeyCtrl() and ui.keyboardButtonPressed(ui.KeyIndex.D1 + (i - 1)) then
            local l, m = RouteItemType.modifiers(i)
            if l and m then
              local hints = {}
              ui.popup(function ()
                for j, d in ipairs(m) do
                  ui.setNextItemIcon(RouteItemType.icon(i, j))
                  if ui.selectable(d) then
                    mainEditor.state:store()             
                    table.insert(mainEditor.items, RouteItem(i, j, trackProgress, hints))
                    added = true
                  end
                end
      
                ui.separator()
                ui.header('Hints')
                ui.separator()
                for hintID, hintName in ipairs(RouteItemHint.names()) do
                  if ui.menuItem(hintName, table.contains(hints, hintID), ui.SelectableFlags.DontClosePopups) then
                    mainEditor.state:store()
                    if table.contains(hints, hintID) then
                      table.removeItem(hints, hintID)
                    else
                      RouteItemHint.addHint(hints, hintID)
                    end
                  end
                end
              end)
            else
              mainEditor.state:store()
              table.insert(mainEditor.items, RouteItem(i, 1, trackProgress, {}))
              ui.closePopup()
            end
          end
        end
      end)
    end
    ui.sameLine(0, 4)
  else
    for i, v in pairs(RouteItemType.names()) do
      ui.sameLine(0, i == 1 and 12 or 4)
      local clicked
      if i < -3 then
        ui.setNextItemIcon(RouteItemType.icon(i, -1, nil, true))
        clicked = ui.button(v)
      else
        clicked = ui.iconButton(RouteItemType.icon(i, -1, nil, true), buttonSize, nil, nil, 2)
      end
      if ui.itemHovered() then
        ui.setTooltip('%s (Ctrl+%d)' % {v, i})
      end
      if clicked or ui.hotkeyCtrl() and ui.keyboardButtonPressed(ui.KeyIndex.D1 + (i - 1)) then
        local l, m = RouteItemType.modifiers(i)
        if l and m then
          local hints = {}
          ui.popup(function ()
            for j, d in ipairs(m) do
              ui.setNextItemIcon(RouteItemType.icon(i, j))
              if ui.selectable(d) then
                mainEditor.state:store()             
                table.insert(mainEditor.items, RouteItem(i, j, trackProgress, hints))
              end
            end
  
            ui.separator()
            ui.header('Hints')
            ui.separator()
            for hintID, hintName in ipairs(RouteItemHint.names()) do
              if ui.menuItem(hintName, table.contains(hints, hintID), ui.SelectableFlags.DontClosePopups) then
                mainEditor.state:store()
                if table.contains(hints, hintID) then
                  table.removeItem(hints, hintID)
                else
                  RouteItemHint.addHint(hints, hintID)
                end
              end
            end
          end)
        else
          mainEditor.state:store()
          table.insert(mainEditor.items, RouteItem(i, 1, trackProgress, {}))
        end
      end
    end
    ui.sameLine(0, 12)
  end
  ui.setNextItemIcon(ui.Icons.Play)
  if ui.button('Play', testingActive and ui.ButtonFlags.Active or ui.ButtonFlags.Activable) then
    testingActive = not testingActive
    if trackProgress == 1 and testingActive then
      trackProgress = 0
    end
    if testingActive then
      testingLastStart = trackProgress
      ui.popup(function ()
        ui.setNextItemWidth(200)
        testSpeed = ui.slider('##speed', testSpeed, 50, 200, 'Speed: %.0f km/h')
        if ui.button('Revert', vec2(98, 0)) then
          testingActive = false
          trackProgress = testingLastStart
          ui.closePopup()
        end
        ui.sameLine(0, 4)
        if ui.button('Stop here', vec2(98, 0)) then
          testingActive = false
          ui.closePopup()
        end
      end, {
        onClose = function ()
          testingActive = false
        end,
        position = ui.windowPos() + ui.itemRectMin() + vec2(0, 22)
      })
    end
  end
  -- ui.sameLine(0, 4)
  -- ui.setNextItemWidth(116)
  if testingActive then
    trackPosActive = 0.1
    local oldProgress = trackProgress
    trackProgress = math.min(trackProgress + testSpeed / 3.6 * uis.dt / sim.trackLengthM, 1)
    if trackProgress == 1 then
      if AppState.loopingSpline then
        trackProgress = 0
      else
        testingActive = false
      end
    end
    VoicesHolder.enqueue(mainEditor.items, oldProgress, trackProgress)
  end
  ui.setCursorY(22)
  
  if hoveredItem and (not uis.wantCaptureMouse or ui.windowHovered(ui.HoveredFlags.RootAndChildWindows)) 
      and ui.mouseReleased(ui.MouseButton.Right) then
    openContextMenu(table.contains(mainEditor.selected, hoveredItem) and table.clone(mainEditor.selected, false) or {hoveredItem})
    hoveredItem = nil
  end

  local windowHovered = uis.wantCaptureMouse and ui.windowHovered(bit.bor(ui.HoveredFlags.RootAndChildWindows, ui.HoveredFlags.AllowWhenBlockedByActiveItem))
  if windowHovered then
    trackYOffset = math.clamp(trackYOffset + uis.mouseWheel * -10, 0, 200)
    if uis.mouseWheel ~= 0 then
      trackPosActive = 0.1
    end
  end

  zoom = math.clamp(4 - trackYOffset / 40, 0, 4)

  ui.childWindow('##scrolling', vec2(-0.1, -0.1), false, bit.bor(ui.WindowFlags.HorizontalScrollbar, ui.WindowFlags.NoScrollWithMouse), function ()
    local mx = ui.windowWidth() * math.pow(2, (zoom / 4) ^ 2 * 4)
    local w = mx - 16
    if targetScroll ~= -1 then
      ui.setScrollX(targetScroll, false, false)
      targetScroll = -1
    end

    local p = ui.windowWidth() / 4 / mx
    if lastMx ~= mx and not movingFreeCamera then
      if lastMx ~= 0 then
        w = lastMx - 16
        targetScroll = ui.getScrollX() + (mx - lastMx) * (trackProgress < p and 0 or trackProgress > 1 - p and 1 or trackProgress)
      end
      lastMx = mx
    elseif trackPosActive ~= 0 or movingFreeCamera then
      local lag = math.lagMult(0.5, uis.dt)
      targetScroll = math.lerp(ui.getScrollX(), ui.getScrollMaxX() * math.lerpInvSat(trackProgress, p, 1 - p), lag)
    end
    ui.dummy(vec2(mx, 1))
    local h = ui.windowHeight() - 10
    local z = 16 + 6 * math.min(4, zoom)
    local dc = DrawCalls.EditorIcon
    local u0, u1 = dc.p1, dc.p2
    -- u0.y, u1.y = h * 0.7 - z * 1.08, h * 0.7 + z * 0.92
    u0.y, u1.y = 20 + h * 0.4 - z * 1.08, 20 + h * 0.4 + z * 0.92
    u2.y = u1.y - 4
    u3.y, u4.y = h, h

    local mousePos = ui.mouseLocalPos()
    local hoveredNewDistance = math.huge
    local hoveredNewItem = nil

    ---@param e RouteItem
    local function drawItem(e)
      local x = 8 + w * e.pos
      u0.x, u1.x = x - z, x + z
      if ui.rectVisible(u0, u1) then
        local col = e:color()
        local isSelected = table.contains(mainEditor.selected, e)

        u4.x, u4.y = u1.x, h
        if dragAreaUIStart then
          local dragAreaCovered = rectsIntersect(dragAreaUIStart, mousePos, u0, u4, 12, 12)
          if isSelected ~= dragAreaCovered then
            if dragAreaCovered then
              table.insert(mainEditor.selected, e)
            else
              table.removeItem(mainEditor.selected, e)
            end
          end
        else
          if windowHovered and ui.rectHovered(u0, u4) then
            local distance = math.abs((u0.x + u4.x) / 2 - mousePos.x)
            if distance < hoveredNewDistance then
              hoveredNewDistance, hoveredNewItem = distance, e
            end
          end
        end

        dc.values.gColor = col
        dc.values.gHovered = hoveredItem == e and 2 or isSelected and 1 or 0
        dc.textures.txIcon = e:iconTexture()
        dc.textures.txOverlay = e:iconOverlay()
        ui.renderShader(dc)
        u2.x, u3.x = x, x
        if dc.values.gHovered ~= 0 then
          ui.drawLine(u2, u3, dc.values.gHovered == 2 and rgbm.colors.white or colSelected, 6)
        end
        ui.drawSimpleLine(u2, u3, rgbm.new(col, 1), 2)
      end
    end

    for i = 1, #mainEditor.items do
      local e = mainEditor.items[i]
      if not table.contains(mainEditor.selected, e) and hoveredItem ~= e then drawItem(e) end
    end
    for i = 1, #mainEditor.selected do
      drawItem(mainEditor.selected[i])
    end
    if hoveredItem and not table.contains(mainEditor.selected, hoveredItem) then
      drawItem(hoveredItem)
    end

    local x = math.round(8 + w * trackProgress)
    ui.drawSimpleLine(vec2(8, h), vec2(w + 8, h), colBlueBar, 4)
    ui.drawSimpleLine(vec2(x, h + 2), vec2(x, 20), rgbm.colors.white, 1)
    ui.beginScale()
    ui.drawCircle(vec2(x, h), 4, rgbm.colors.white, 20, 1)
    ui.drawCircle(vec2(x, h), 1, rgbm.colors.white, 20, 1)
    ui.endScale(vec2(2, 1))

    ui.backupCursor()
    ui.setCursor(vec2(8, 0))
    ui.invisibleButton('##1', vec2(w, h - 2))
    if not ui.itemActive() then
      if draggingBtnClicked then
        for _, v in ipairs(mainEditor.selected) do
          v.pos = AppState.loopingSpline and v.pos % 1 or math.saturateN(v.pos)
        end
      end
      draggingBtnClicked = false
      dragAreaUIStart = nil
    elseif not dragAreaUIStart then
      if math.abs(uis.mouseDelta.x) > 1 and not draggingBtnClicked then
        if #mainEditor.selected > 0 then
          draggingStartItem = uis.altDown and hoveredItem or nil
          hoveredItem = nil
          draggingBtnClicked = true
          mainEditor.state:store()
          if ui.hotkeyShift() then
            mainEditor:cloneSelected()
          end
        else
          dragAreaUIStart = mousePos - uis.mouseDelta
        end
      end
    end
    if (ui.itemActive() or ui.itemHovered()) and windowHovered and not draggingBtnClicked and not blueBarScrolling then
      registerHoveredItem(hoveredNewItem)
    end

    if draggingBtnClicked or dragAreaUIStart then
      local dx = uis.mouseDelta.x
      local mouseX = mousePos.x - ui.getScrollX()
      if targetScroll == -1 and (mouseX < 10 or mouseX > ui.windowWidth() - 10) then
        local maxOffset = dragAreaUIStart and 10 or 20
        local shift = mouseX < 10 and math.max(-maxOffset, -ui.getScrollX()) or math.min(maxOffset, ui.getScrollMaxX() - ui.getScrollX())
        dx = dx + shift
        targetScroll = ui.getScrollX() + shift
      end
      if not dragAreaUIStart then
        for _, v in ipairs(mainEditor.selected) do
          v.pos = draggingStartItem and draggingStartItem.pos + (v.pos - draggingStartItem.pos) * (1 + 10 * dx / w) or v.pos + dx / w
        end
      end
    end

    if dragAreaUIStart then
      ui.drawRectFilled(dragAreaUIStart, mousePos, rgbm(0, 1, 1, 0.1))
      ui.drawRect(dragAreaUIStart, mousePos, rgbm(0, 1, 1, 0.3))
    end

    ---@type RouteItem?, RouteItem?
    local itemNext, itemPrevious
    do
      local distNext, distPrev = math.huge, math.huge
      for i = 1, #mainEditor.items do
        local e = mainEditor.items[i]
        local g = math.saturateN(e.pos) - trackProgress
        if AppState.loopingSpline and math.abs(g) > 0.5 then g = g > 0.5 and g - 1 or g + 1 end
        if math.abs(g) > 1 / sim.trackLengthM then
          if g > 0 and g < distNext then
            itemNext, distNext = e, g
          elseif g < 0 and -g < distPrev then
            itemPrevious, distPrev = e, -g
          end
        end
      end
    end

    local scrollCandidate
    ui.setCursor(vec2(ui.getScrollX(), 4))
    ui.beginGroup(ui.windowWidth())
    ui.pushAlignment()
    ui.pushFont(ui.Font.Small)
    ui.setItemAllowOverlap()
    -- ui.setCursor(vec2(16 + ui.getScrollX(), 4))
    ui.beginMIPBias()
    ui.setNextItemIcon(ui.Icons.Previous, nil, 0.2)
    if ui.button('Start') then
      trackPosActive = 0.2
      trackProgress = 0
    end
    if ui.itemHovered() then
      scrollCandidate = 0
    end
    ui.sameLine(0, 4)
    ui.setNextItemIcon(itemPrevious and itemPrevious:icon() or ui.Icons.Glow, nil, itemPrevious and 0 or 0.2)
    if ui.button('Previous', itemPrevious and 0 or ui.ButtonFlags.Disabled) and itemPrevious then
      trackPosActive = 0.2
      trackProgress = itemPrevious.pos - 0.1 / sim.trackLengthM
    end
    if ui.itemHovered() and itemPrevious then
      scrollCandidate = itemPrevious.pos
    end
    ui.sameLine(0, 4)
    ui.setNextItemIcon(ui.Icons.ArrowDown, nil, 0.2)
    if ui.button('Cursor') then
      trackPosActive = -0.5
    end
    ui.sameLine(0, 4)
    ui.setNextItemIcon(itemNext and itemNext:icon() or ui.Icons.Glow, nil, itemNext and 0 or 0.2)
    if ui.button('Next', itemNext and 0 or ui.ButtonFlags.Disabled) and itemNext then
      trackPosActive = 0.2
      trackProgress = itemNext.pos + 0.1 / sim.trackLengthM
    end
    if ui.itemHovered() and itemNext then
      scrollCandidate = itemNext.pos
    end
    ui.sameLine(0, 4)
    ui.setNextItemIcon(ui.Icons.Next, nil, 0.2)
    if ui.button('End') then
      trackPosActive = 0.2
      trackProgress = 1
    end
    if ui.itemHovered() and itemNext then
      scrollCandidate = 1
    end
    ui.endMIPBias(-0.5)
    ui.popAlignment()
    ui.endGroup()
    ui.popFont()

    ui.setCursor(vec2(8, h - 2))
    ui.invisibleButton('##2', vec2(w, 8))
    blueBarScrolling = ui.itemActive() and not movingFreeCamera
    if blueBarScrolling then
      trackPosActive = 0.1
      trackProgress = math.saturateN((math.clampN(ui.mouseLocalPos().x, ui.getScrollX(), ui.getScrollX() + ui.windowWidth() - 1) - 8) / w)
      if not baseBlueBarYOffset then
        baseBlueBarYOffset = {trackYOffset, uis.mousePos.y}
      else
        trackYOffset = math.max(0, baseBlueBarYOffset[1] + (baseBlueBarYOffset[2] - uis.mousePos.y) / 2)
      end
      ui.setMouseCursor(ui.MouseCursor.ResizeEW)
    else
      baseBlueBarYOffset = nil

      local anyArrowsPressed = ac.isKeyDown(ui.KeyIndex.Left) or ac.isKeyDown(ui.KeyIndex.Right) or ac.isKeyDown(ui.KeyIndex.Up) or ac.isKeyDown(ui.KeyIndex.Down)
      local anyFreeCameraRelatedButtonsPressed = (anyArrowsPressed or uis.ctrlDown or uis.shiftDown) and not windowHovered and not popupOpened
      if sim.cameraMode == ac.CameraMode.Free and uis.isMouseRightKeyDown and not windowHovered and not popupOpened
          and (movingFreeCamera or ui.mouseDelta():lengthSquared() ~= 0) then
        movingFreeCamera = true
      elseif not anyFreeCameraRelatedButtonsPressed then
        movingFreeCamera = false
      end
 
      local needSyncing = trackPosActive < -0.5 or movingFreeCamera
      if needSyncing or anyArrowsPressed
        or ac.isKeyDown(ui.KeyIndex.W) or ac.isKeyDown(ui.KeyIndex.A) or ac.isKeyDown(ui.KeyIndex.S) or ac.isKeyDown(ui.KeyIndex.D) then
        if needSyncing then
          if trackPosActive > 0 then trackPosActive = 0 end
          syncTrackPos()
        else
          local s = 200 * (1 + fromAbove * 3)
          if uis.ctrlDown then s = s * 5 end 
          if uis.shiftDown then s = s * 0.2 end
          if ac.isKeyDown(ui.KeyIndex.Left) --[[or ac.isKeyDown(ui.KeyIndex.A)]] then trackProgress = trackProgress - s / sim.trackLengthM * uis.dt end
          if ac.isKeyDown(ui.KeyIndex.Right) --[[or ac.isKeyDown(ui.KeyIndex.D)]] then trackProgress = trackProgress + s / sim.trackLengthM * uis.dt end
          if ac.isKeyDown(ui.KeyIndex.Up) --[[or ac.isKeyDown(ui.KeyIndex.W)]] then trackYOffset = trackYOffset - s * 0.2 * uis.dt end
          if ac.isKeyDown(ui.KeyIndex.Down) --[[or ac.isKeyDown(ui.KeyIndex.S)]] then trackYOffset = trackYOffset + s * 0.2 * uis.dt end
          trackProgress = AppState.loopingSpline and trackProgress % 1 or math.saturateN(trackProgress)
          trackYOffset = math.clamp(trackYOffset, 0, 200)
          trackPosActive = 0.1
        end
      end
      if ui.itemHovered() then
        ui.setMouseCursor(ui.MouseCursor.Hand)
      end
    end
    ui.restoreCursor()

    if trackPosActive > 0 then
      trackPosActive = math.max(trackPosActive - uis.dt, 0)
      updateTrackPos()
    elseif trackPosActive < 0 then
      trackPosActive = math.min(trackPosActive + uis.dt, 0)
    end

    ui.pushClipRectFullScreen()
    do
      local wwAdj, sx = ui.windowWidth() - 16, ui.getScrollX()
      local p1, p2 = vec2(0, h + 2), vec2(0, h + 10)
      for i = 1, #mainEditor.items do
        p1.x = 8 + wwAdj * mainEditor.items[i].pos + sx
        p2.x = p1.x
        ui.drawSimpleLine(p1, p2, rgbm.colors.gray, 1)
      end
      if scrollCandidate then
        p1.x = 8 + wwAdj * scrollCandidate + sx
        p2.x = p1.x
        ui.drawSimpleLine(p1, p2, rgbm.colors.yellow, 1)
      end
      p1.x = 8 + wwAdj * trackProgress + sx
      p2.x = p1.x
      ui.drawSimpleLine(p1, p2, rgbm.colors.white, 1)
    end
    ui.popClipRect()
  end)

  ui.popClipRect()
end

local p1 = vec3()
local p2 = vec3()
local p3 = vec3()
local p4 = vec3()

local function renderCallback()
  local editActive = true

  render.setDepthMode(fromAbove > 0.1 and render.DepthMode.Off or render.DepthMode.Normal)
  -- render.setBlendMode(render.BlendMode.AlphaBlend)
  DrawCalls.TrackSpline.mesh = ac.SimpleMesh.trackLine(0, 1 + 5 * fromAbove)
  DrawCalls.TrackSpline.values.gColor = colBlueBar
  DrawCalls.TrackSpline.values.gWidth = math.round(1 + 5 * fromAbove)
  render.mesh(DrawCalls.TrackSpline)
  ac.setExtraTrackLODMultiplier(1 + 5 * fromAbove)

  local visiblePos = ac.worldCoordinateToTrackProgress(sim.cameraPosition)
  local visibleHalfRange = (1e3 + 10e3 * fromAbove) / sim.trackLengthM
  local dirUp = math.lerp(vecDown, -sim.cameraUp, fromAbove)
  local scale = 1 + fromAbove * 5
  local ray
  if editActive and not uis.wantCaptureMouse and not dragArea3DEnd then
    ray = render.createMouseRay()
  end

  render.shaderedQuad({
    pos = ac.trackProgressToWorldCoordinate(trackProgress),
    width = 0.25 + 2.5 * fromAbove,
    height = 80 * scale,
    up = dirUp,
    shader = 'float4 main(PS_IN pin) {clip(0.5 - pin.Tex.y);return float4((gWhiteRefPoint).xxx * 3, 1);}'
  })

  do
    ac.trackProgressToWorldCoordinateTo(trackProgress, p1)
    local s = 5 + 25 * fromAbove
    p1.y = p1.y + 0.1 + fromAbove
    p2.y, p3.y, p4.y = p1.y, p1.y, p1.y
    p1.x, p2.x, p3.x, p4.x = p1.x - s, p1.x + s, p1.x + s, p1.x - s
    p1.z, p2.z, p3.z, p4.z = p1.z + s, p1.z + s, p1.z - s, p1.z - s
    render.setBlendMode(render.BlendMode.AlphaBlend)
    render.shaderedQuad({
      p1 = p1,
      p2 = p2,
      p3 = p3,
      p4 = p4,
      shader = 'float4 main(PS_IN pin) {return float4((gWhiteRefPoint).xxx * 3, (length(pin.Tex * 2 - 1) < 1) * saturate(2 * (-3.2 + 4 * sin(-5.2 + length(pin.Tex * 2 - 1) * 12))));}'
    })
  end

  local mouseClicked = not uis.wantCaptureMouse and ac.isKeyPressed(ui.KeyIndex.LeftButton)
  local mouseDown = not uis.wantCaptureMouse and ac.isKeyDown(ui.KeyIndex.LeftButton)
  if draggingRay then
    if not mouseDown then
      draggingRay, draggingList = nil, nil
    else
      if not draggingList and uis.mouseDelta:lengthSquared() > 4 then
        mainEditor.state:store()
        if ui.hotkeyShift() then
          mainEditor:cloneSelected()
        end
        draggingList = table.map(mainEditor.selected, function (item, index)
          if index > 1 and mainEditor.selected == item then return nil end
          local pos = ac.trackProgressToWorldCoordinate(item.pos)
          return {item, pos, draggingRay.pos + draggingRay.dir * pos:distance(sim.cameraPosition), item.pos}
        end)
      end
      if draggingList and ray then
        local offset
        for _, v in ipairs(draggingList) do
          if not offset then
            local grabbedDistance = (ray.pos.y - v[3].y) / math.abs(ray.dir.y)
            local newPos = ray.pos:clone():addScaled(ray.dir, grabbedDistance)
            v[1].pos = ac.worldCoordinateToTrackProgress(v[2] + newPos - v[3])
            offset = v[1].pos - v[4]
          else
            v[1].pos = v[4] + offset
          end
        end
      end
    end
  elseif ac.isKeyPressed(ui.KeyIndex.Delete) then
    mainEditor.state:store()
    for _, v in ipairs(mainEditor.selected) do
      table.removeItem(mainEditor.items, v)
    end
    table.clear(mainEditor.selected)
  end

  speedGuess = nil
  if ray and EditorConfig.DebugMode and AppState.speedRec and #AppState.speedRec > 4 then
    local point = vec3()
    local hit = physics.raycastTrack(ray.pos, ray.dir, 1e3, point)
    if hit >= 0 then
      local progress = ac.worldCoordinateToTrackProgress(point)
      local find = table.findLeftOfIndex(AppState.speedRec, function (item)
        return item.pos > progress
      end)
      local i1, i2 = math.max(find, 1), math.min(find + 1, #AppState.speedRec)
      local mix = math.lerpInvSat(progress, AppState.speedRec[i1].pos, AppState.speedRec[i2].pos)
      speedGuess = math.lerp(AppState.speedRec[i1].speed, AppState.speedRec[i2].speed, mix)
    end
  end

  local hoveredNewDistance = math.huge
  local hoveredNewItem = nil
  hoveredFlipped = false
  for i = #mainEditor.items, 1, -1 do
    local e = mainEditor.items[i]
    local gap = e.pos - visiblePos
    if AppState.loopingSpline then
      if gap > 0.5 then
        gap = gap - 1
      elseif gap < -0.5 then
        gap = gap + 1
      end
    end
    if math.abs(gap) < visibleHalfRange then
      ac.trackProgressToWorldCoordinateTo(e.pos, p1)
      local isSelected = table.contains(mainEditor.selected, e)
      local alpha = isSelected and 1 or math.lerpInvSat(p1:distanceSquared(sim.cameraPosition), 100, 140)
      local posCam = ac.worldCoordinateToTrackProgress(p4:set(sim.cameraPosition):sub(p1):normalize():add(p1))
      if alpha > 0 then
        if ray then
          local hit = ray:line(p1, p4:set(p1):addScaled(dirUp, -8.5 * scale), 7 * scale)
          if hit >= 0 and hit < hoveredNewDistance then
            hoveredNewItem, hoveredNewDistance, hoveredFlipped = e, hit, posCam > e.pos
          end
        elseif dragArea3DEnd then
          local js = dragArea3DCache[e.pos]
          if not js then
            js = {ui.projectPoint(p1), ui.projectPoint(p4:set(p1):addScaled(dirUp, -8.5 * scale))}
            js[1].x, js[2].x = js[1].x - (js[2].y - js[1].y) / 2, js[1].x + (js[2].y - js[1].y) / 2
            dragArea3DCache[e.pos] = js
          end
          local dragAreaCovered = rectsIntersect(dragArea3DStart, dragArea3DEnd, js[2], js[1], 0, 0)
          if isSelected ~= dragAreaCovered then
            if dragAreaCovered then
              table.insert(mainEditor.selected, e)
            else
              table.removeItem(mainEditor.selected, e)
            end
          end
        end

        local dc = DrawCalls.EditorPointOnTrack
        dc.pos = p1
        dc.width = 10 * scale
        dc.height = 20 * scale
        dc.up = dirUp
        dc.textures.txIcon = e:iconTexture()
        dc.textures.txOverlay = e:iconOverlay()
        dc.values.gColor = e:color()
        dc.values.gAlpha = alpha * (posCam > e.pos and 0.6 or 1)
        -- dc.values.gFlipped = posCam > e.pos
        dc.values.gFlipped = false
        dc.values.gHovered = hoveredItem == e and 2 or isSelected and 1 or 0
        render.setBlendMode(render.BlendMode.AlphaBlend)
        render.shaderedQuad(dc)

        if EditorConfig.DebugMode and e.debugData and fromAbove <= 1 and math.abs(gap) < visibleHalfRange / 4 then
          ac.trackProgressToWorldCoordinateTo(e.debugData.posMax, p2)
          ac.trackProgressToWorldCoordinateTo(e.debugData.posEnd, p3)
          render.debugArrow(p1, p2)
          render.debugArrow(p2, p3, -1, rgbm(0, 3, 0, 1))
          render.debugText(p1, e.debugData.debugText)
          render.setDepthMode(render.DepthMode.Normal)
          render.setBlendMode(render.BlendMode.AlphaTest)
        end
      end
    end
  end

  if ray then
    registerHoveredItem(hoveredNewItem)
    if hoveredNewItem and mouseClicked then
      draggingRay = ray
    end
  end
end

local function hudCallback(mode)
  if uis.wantCaptureMouse or sim.cameraMode ~= ac.CameraMode.Free or mode ~= 'game' and mode ~= 'replay' then return end
  if draggingList then
    dragArea3DStart, dragArea3DEnd = nil, nil
    table.clear(dragArea3DCache)
  elseif uis.isMouseLeftKeyClicked then
    dragArea3DStart, dragArea3DEnd = uis.mousePos:clone(), nil
    table.clear(dragArea3DCache)
  elseif dragArea3DStart then
    if not uis.isMouseLeftKeyDown then
      dragArea3DStart, dragArea3DEnd = nil, nil
    elseif dragArea3DEnd or uis.mouseDelta:lengthSquared() > 1 then
      dragArea3DEnd = uis.mousePos:clone()
    end
  end
  if dragArea3DStart and dragArea3DEnd then    
    ui.drawRectFilled(dragArea3DStart, dragArea3DEnd, rgbm(0, 1, 1, 0.1))
    ui.drawRect(dragArea3DStart, dragArea3DEnd, rgbm(0, 1, 1, 0.3))
  end
  if hoveredFlipped then
    ui.setTooltip('Camera is looking from the wrong side')
  end
end

local renderCallbackSubscription
local hudCallbackSubscription
local cameraModeBackup

function EditorUI.onEditorOpened()
  if not AppState.editorActive and (sim.cameraMode == ac.CameraMode.Drivable or sim.cameraMode == ac.CameraMode.OnBoardFree or sim.cameraMode == ac.CameraMode.Cockpit) then
    cameraModeBackup = sim.cameraMode
    trackPosActive = 1
  end
  AppState.editorActive = true
  if not renderCallbackSubscription then
    renderCallbackSubscription = render.on('main.track.transparent', renderCallback)
    hudCallbackSubscription = ui.onExclusiveHUD(hudCallback)
  end
end

function EditorUI.onEditorClosed()
  if cameraModeBackup then
    if AppState.editorActive then
      ac.setCurrentCamera(cameraModeBackup)
    end
    cameraModeBackup = nil
  end
  AppState.editorActive = false
  if renderCallbackSubscription then
    renderCallbackSubscription()
    renderCallbackSubscription = nil
  end
  if hudCallbackSubscription then
    hudCallbackSubscription()
    hudCallbackSubscription = nil
  end
  fromAbove = 0
  draggingRay, draggingList = nil, nil
  table.clear(mainEditor.selected)
end

return EditorUI