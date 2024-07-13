local AISpline = require('AISpline')
local CubicInterpolatingLane = require('CubicInterpolatingLane')

local colLine = rgbm(0, 10, 0, 1)
local colEdge = rgbm(0, 10, 10, 1)
local sim = ac.getSim()
local uis = ac.getUI()

---@alias SelectedPoint {type: 'point'|'left'|'right', index: integer}

local rangeLimit = const(200)
local settings = ac.storage{rangeInv = 1 / 20, autosnap = false, fixEdges = false, resampleResize = false, resampleGap = 3, snapGap = 0.3, lastSelected = 'fast_lane.ai'}
local aiFolder = ac.getFolder(ac.FolderID.CurrentTrackLayout)..'/ai'
local splineFilename ---@type string
local spline ---@type AISpline

local availableSplines = {}
local function rescanSplines()
  availableSplines = io.scanDir(aiFolder, '*.ai')
  if not splineFilename then
    splineFilename = '%s/%s' % {aiFolder, table.contains(availableSplines, settings.lastSelected) and settings.lastSelected or availableSplines[1]}
    spline = AISpline(splineFilename)
  end
end

local selectedPoint = nil ---@type SelectedPoint?
local wasEditing = false
local undoStack = {}
local redoStack = {}
local savedUndoCounter = 0
local affectedNearby = {}
local positionHelper = render.PositioningHelper{skipAxis = {'y'}, alwaysAligned = true}

rescanSplines()
ac.onFolderChanged(aiFolder, '*.ai', false, rescanSplines)

---@param refTable table<integer, number>?
---@return string|table
local function recordState(refTable)
  return refTable and stringify.binary(table.map(refTable, function (_, k) return {spline.points[k].pos, spline.payloads[k].sideLeft, spline.payloads[k].sideRight}, k end)) or spline:encode()
end

local function restoreState(recordedState)
  if type(recordedState) == 'string' then
    return stringify.binary(table.map(stringify.binary.parse(recordedState), function (v, k, _) 
      local r = {spline.points[k].pos:clone(), spline.payloads[k].sideLeft, spline.payloads[k].sideRight}
      spline.points[k].pos:set(v[1])
      spline.payloads[k].sideLeft, spline.payloads[k].sideRight = v[2], v[3]
      return r, k
    end))
  end
  local ret = spline:encode()
  spline:decode(recordedState:read(0))
  return ret
end

local function addUndoPoint(wholeSpline)
  undoStack[#undoStack + 1] = recordState(not wholeSpline and affectedNearby or nil)
  table.clear(redoStack)
end

local function computeFactor(i)
  local m = 0
  if selectedPoint then
    local a = affectedNearby[i]
    if a then
      m = math.smoothstep(math.max(0, 1 - a * settings.rangeInv))
    end
  end
  return m
end

---@param i integer
---@param p vec3
---@param ray ray?
---@param radius number
---@return {type: 'left'|'point'|'right', index: integer}?
local function drawPoint(i, p, ray, radius)
  local j = i % #spline.points + 1
  local hovered = nil ---@type SelectedPoint?
  local im, jm = computeFactor(i), computeFactor(j)
  if (im > 0 or jm > 0) and selectedPoint and selectedPoint.type == 'point' then
    render.debugArrow(spline.points[i].pos, spline.points[j].pos, 0.25, rgbm(10 * im, 10 * (1 - im), 0, 1), rgbm(10 * jm, 10 * (1 - jm), 0, 1))
    if selectedPoint.index == i then render.debugPoint(spline.points[i].pos, 1, rgbm.colors.white) end
  else
    render.debugArrow(spline.points[i].pos, spline.points[j].pos, 0.25, colLine)
  end
  if spline.hasSides then
    if (im > 0 or jm > 0) and selectedPoint and selectedPoint.type == 'left' then
      render.debugLine(spline.sideLeft[i], spline.sideLeft[j], rgbm(10 * im, 10 * (1 - im), 0, 1), rgbm(10 * jm, 10 * (1 - jm), 0, 1))
      if selectedPoint.index == i then render.debugPoint(spline.sideLeft[i], 1, rgbm.colors.white) end
    else
      render.debugLine(spline.sideLeft[i], spline.sideLeft[j], colEdge)
    end
    if (im > 0 or jm > 0) and selectedPoint and selectedPoint.type == 'right' then
      render.debugLine(spline.sideRight[i], spline.sideRight[j], rgbm(10 * im, 10 * (1 - im), 0, 1), rgbm(10 * jm, 10 * (1 - jm), 0, 1))  
      if selectedPoint.index == i then render.debugPoint(spline.sideRight[i], 1, rgbm.colors.white) end
    else
      render.debugLine(spline.sideRight[i], spline.sideRight[j], colEdge)
    end
    if ray and not hovered then
      if ray:sphere(spline.sideLeft[i], radius) > 0 then
        hovered = {type = 'left', index = i}
      end
      if ray:sphere(spline.sideRight[i], radius) > 0 then
        hovered = {type = 'right', index = i}
      end
    end
  end

  if ray and ray:sphere(spline.points[i].pos, radius) > 0 then
    hovered = {type = 'point', index = i}
  end
  return hovered
end

local prevFrom = -1

render.on('main.track.transparent', function ()
  spline:finalize()
  if #spline.points == 0 then return end
  local ray = not uis.wantCaptureMouse and not positionHelper:anyHighlight() and render.createMouseRay() or nil
  local radius = spline.points[#spline.points].length / (#spline.points * 2)
  render.setDepthMode(render.DepthMode.Off)
  local hovered = nil ---@type SelectedPoint?
  if sim.cameraJumped then
    prevFrom = 1
  end
  local anyHit = false
  do
    local i = math.max(1, prevFrom - 100)
    local e = spline.closed and #spline.points or #spline.points - 1
    while i <= e do
      local p = spline.points[i].pos
      if p:closerToThan(sim.cameraPosition, 600) then
        if not anyHit then
          anyHit = true
          prevFrom = i
        end
        hovered = drawPoint(i, p, ray, radius) or hovered
      elseif anyHit then
        i = i + 100
      end
      i = i + 1
    end
  end
  if hovered then
    if hovered.type == 'point' then
      render.debugPoint(spline.points[hovered.index].pos, 1, rgbm.colors.yellow)
      render.debugLine(spline.points[hovered.index].pos, spline.sideLeft[hovered.index], colEdge)
      render.debugLine(spline.points[hovered.index].pos, spline.sideRight[hovered.index], colEdge)
    elseif hovered.type == 'left' then
      render.debugPoint(spline.sideLeft[hovered.index], 1, rgbm.colors.yellow)
      render.debugLine(spline.points[hovered.index].pos, spline.sideLeft[hovered.index], colEdge)
    elseif hovered.type == 'right' then
      render.debugPoint(spline.sideRight[hovered.index], 1, rgbm.colors.yellow)
      render.debugLine(spline.points[hovered.index].pos, spline.sideRight[hovered.index], colEdge)
    end
  end
  if selectedPoint and not uis.wantCaptureMouse then 
    if selectedPoint.type == 'point' then
      local modifiedPos = spline.points[selectedPoint.index].pos:clone()
      if positionHelper:renderAligned(modifiedPos, spline.payloads[selectedPoint.index].forwardVector) then
        if not wasEditing and (uis.mouseDelta.x ~= 0 or uis.mouseDelta.y ~= 0) then
          addUndoPoint()
          wasEditing = true
        end
        if wasEditing then
          local diff = modifiedPos - spline.points[selectedPoint.index].pos
          diff.y = 0
          for k, v in pairs(affectedNearby) do
            if settings.fixEdges and spline.hasSides then
              if not spline.extras.orthogonalDirs then
                spline.extras.orthogonalDirs = table.map(affectedNearby, function (_, key)
                  return (spline.sideLeft[key] - spline.sideRight[key]):normalize(), key
                end)
              end
              local dir = spline.extras.orthogonalDirs[k]
              if dir then
                local offsetAmount = math.clamp(dir:dot(diff) * math.smoothstep(math.max(0, 1 - v * settings.rangeInv)), -spline.payloads[k].sideRight, spline.payloads[k].sideLeft)
                spline.points[k].pos:addScaled(dir, offsetAmount)
                spline.payloads[k].sideLeft = spline.payloads[k].sideLeft - offsetAmount
                spline.payloads[k].sideRight = spline.payloads[k].sideRight + offsetAmount
              end
            else
              spline.points[k].pos:addScaled(diff, math.smoothstep(math.max(0, 1 - v * settings.rangeInv)))
            end
          end
          spline.dirty = true
        end
        return
      elseif wasEditing then
        wasEditing = false
        spline.extras.orthogonalDirs = nil
        if settings.autosnap then
          for k, _ in pairs(affectedNearby) do
            spline:snapToTrackSurface(k, settings.snapGap)
          end
        end
      end
    end
    if selectedPoint.type == 'left' or selectedPoint.type == 'right' then
      local sideKey = selectedPoint.type == 'left' and 'sideLeft' or 'sideRight'
      local modifiedPos = spline[sideKey][selectedPoint.index]:clone()
      local direction = (spline[sideKey][selectedPoint.index % #spline[sideKey] + 1] - modifiedPos):normalize()
      if positionHelper:renderAligned(modifiedPos, direction) then
        if not wasEditing and (uis.mouseDelta.x ~= 0 or uis.mouseDelta.y ~= 0) then
          addUndoPoint()
          wasEditing = true
        end
        local diff = (modifiedPos - spline[sideKey][selectedPoint.index]):dot((spline[sideKey][selectedPoint.index] - spline.points[selectedPoint.index].pos):normalize())
        for k, v in pairs(affectedNearby) do
          spline.payloads[k][sideKey] = spline.payloads[k][sideKey] + diff * math.smoothstep(math.max(0, 1 - v * settings.rangeInv))
        end
        spline.dirty = true
        return
      elseif wasEditing then
        wasEditing = false
      end
    end
  end
  if uis.isMouseLeftKeyClicked and not uis.wantCaptureMouse then
    selectedPoint = hovered
    if selectedPoint then
      table.clear(affectedNearby)
      for i = 1, #spline.points do
        local d = spline:distanceBetween(i, selectedPoint.index)
        if d < rangeLimit then
          affectedNearby[i] = d
        end
      end
    else
      table.clear(affectedNearby)
    end
  end
end)

local function saveAs(destination)
  local mainSpline = false
  if destination == nil then
    mainSpline = true
    destination = splineFilename
    if not io.fileExists(destination..'_editor.bak') then
      io.copyFile(destination, destination..'_editor.bak')
    end
  end
  local hasBackup = io.fileExists(destination) and (io.deleteFile(destination..'_tmp.bak') or true) and io.move(destination, destination..'_tmp.bak')
  local s, err = pcall(spline.save, spline, destination)
  if s then
    if mainSpline then
      require('shared/sim/ai').spline.loadFast(destination)
    end
    ui.toast(ui.Icons.Confirm, 'AI spline saved', hasBackup and function ()
      if io.deleteFile(destination) and io.move(destination..'_tmp.bak', destination) and mainSpline then
        require('shared/sim/ai').spline.loadFast(destination)
      end
    end or nil)
  else
    ac.error(err)
    ui.toast(ui.Icons.Warning, 'Failed to save AI spline')
  end
end

local editedSplines = {}

local function loadAnotherSpline(fileName)
  if #undoStack > 0 then
    editedSplines[io.getFileName(splineFilename, false)] = {
      spline,
      selectedPoint,
      affectedNearby,
      undoStack,
      redoStack,
      savedUndoCounter,
      savedUndoCounter ~= #undoStack
    }
  end
  splineFilename = '%s/%s' % {aiFolder, fileName}
  local edited = editedSplines[fileName]
  if edited then
    spline = edited[1]
    selectedPoint = edited[2]
    affectedNearby = edited[3]
    undoStack = edited[4]
    redoStack = edited[5]
    savedUndoCounter = edited[6]
  else
    spline = AISpline(splineFilename)
    selectedPoint = nil
    affectedNearby = {}
    undoStack = {}
    redoStack = {}
    savedUndoCounter = 0
  end
  settings.lastSelected = fileName
end

local creatingNewSpline

function script.windowMain()
  ui.pushFont(ui.Font.Small)

  if creatingNewSpline then
    ui.setNextItemIcon(ui.Icons.ArrowLeft)
    if ui.button('Back') then
      creatingNewSpline = nil
    else
      creatingNewSpline()
      ui.popFont()
      return
    end
  end

  if #availableSplines > 1 then
    local selected, edited = io.getFileName(splineFilename, false), #undoStack ~= savedUndoCounter
    ui.setNextItemWidth(188)
    if edited then ui.pushFont(ui.Font.SmallItalic) end
    ui.combo('##', selected, function ()
      ui.pushFont(ui.Font.Small)
      for _, v in ipairs(availableSplines) do
        local vEdited = v ~= selected and editedSplines[v] and editedSplines[v][7] or v == selected and edited
        if vEdited then ui.pushFont(ui.Font.SmallItalic) end
        if ui.selectable(v, v == selected) then
          loadAnotherSpline(v)
        end
        if vEdited then ui.popFont() end
      end
      ui.popFont()
    end)
    if edited then ui.popFont() end
  end

  local shiftScale = ac.isKeyDown(ui.KeyIndex.SquareOpenBracket) and -1 or ac.isKeyDown(ui.KeyIndex.SquareCloseBracket) and 1 or 0
  if shiftScale ~= 0 then
    settings.rangeInv = 1 / math.clampN((1 / settings.rangeInv) * math.pow(2, shiftScale / 5), 1, rangeLimit)
  end

  if ui.button('Save', vec2(60, 0)) or uis.ctrlDown and ui.keyboardButtonPressed(ui.KeyIndex.S) then
    saveAs()
    savedUndoCounter = #undoStack
  end
  if ui.itemHovered() then
    ui.setTooltip('Save as %s (Ctrl+S)\nUse context menu to save a new spline\n\nYou can use Traffic Planner tool to quickly create a new spline by exporting lane as a spline' %io.getFileName(splineFilename, false) )
    if ui.itemClicked(ui.MouseButton.Right) then
      ui.popup(function ()
        ui.pushFont(ui.Font.Small)
        if ui.selectable('Save as…') then
          savedUndoCounter = #undoStack
          os.saveFileDialog({
            defaultFolder = ac.getFolder(ac.FolderID.CurrentTrackLayout)..'/ai', 
            fileTypes = {{name = 'AI splines', mask = '*.ai'}}, 
            fileName = io.getFileName(splineFilename, true),
            defaultExtension = '.ai',
            addAllFilesFileType = true, 
            flags = bit.bor(os.DialogFlags.PathMustExist, os.DialogFlags.OverwritePrompt, os.DialogFlags.NoReadonlyReturn)
          }, function (err, filename)
            if filename then
              saveAs(filename)
            end
          end)
        end
        ui.popFont()
      end)
    end
  end
  ui.sameLine(0, 4)
  if ui.button('Undo', vec2(60, 0), #undoStack == 0 and ui.ButtonFlags.Disabled or 0) or #undoStack > 0 and uis.ctrlDown and ui.keyboardButtonPressed(ui.KeyIndex.Z) then
    local b = table.remove(undoStack, #undoStack)
    redoStack[#redoStack + 1] = restoreState(b)
    spline.dirty = true
  end
  if ui.itemHovered() then
    ui.setTooltip('Ctrl+Z')
  end
  ui.sameLine(0, 4)
  if ui.button('Redo', vec2(60, 0), #redoStack == 0 and ui.ButtonFlags.Disabled or 0) or #redoStack > 0 and uis.ctrlDown and ui.keyboardButtonPressed(ui.KeyIndex.Y) then
    local b = table.remove(redoStack, #redoStack)
    undoStack[#undoStack + 1] = restoreState(b)
    spline.dirty = true
  end
  if ui.itemHovered() then
    ui.setTooltip('Ctrl+Y')
  end

  ui.setNextItemWidth(188)
  local rangeNew = ui.slider('##range', 1 / settings.rangeInv, 1, rangeLimit, 'Range: %.1f m', 2)
  if ui.itemHovered() then
    ui.setTooltip('Use buttons [ and ] to change range')
  end
  if ui.itemEdited() then
    settings.rangeInv = 1 / rangeNew 
  end

  if ui.checkbox('Snap to surfaces', settings.autosnap) then
    settings.autosnap = not settings.autosnap
  end
  if ui.itemHovered() then
    ui.setTooltip('Snap spline to physics surfaces after shifting')
  end

  if not spline.hasSides then ui.pushDisabled() end
  if ui.checkbox('Preserve sides', settings.fixEdges) then
    settings.fixEdges = not settings.fixEdges
  end
  if not spline.hasSides then ui.popDisabled() end
  if ui.itemHovered() then
    ui.setTooltip('Locks spline movement in othrogonal direction%s' % (spline.hasSides and '' or '\nThis spline doesn’t have sides'))
  end

  if ui.button('Resample', vec2(92, 0)) then
    addUndoPoint(true)
    local cubicPos = CubicInterpolatingLane(table.map(spline.points, function (p) return p.pos:clone() end), spline.closed)
    local cubicSides = CubicInterpolatingLane(table.map(spline.payloads, function (p) return vec2(p.sideLeft, p.sideRight) end), spline.closed, cubicPos)
    if settings.resampleResize then
      spline:resize(math.ceil(cubicPos.totalDistance / settings.resampleGap))
      selectedPoint = nil
      table.clear(affectedNearby)
    end
    for i = 1, #spline.points do
      local p = (i - 1) / (spline.closed and #spline.points or #spline.points - 1) * cubicPos.totalDistance
      cubicPos:interpolateDistanceInto(spline.points[i].pos, p, false)
      spline.payloads[i].sideLeft, spline.payloads[i].sideRight = cubicSides:interpolateDistanceInto(vec2.tmp(), p, false):unpack()
    end
    spline.dirty = true
  end
  if ui.itemHovered() then
    ui.setTooltip('Use context menu to adjust density')
    if ui.itemClicked(ui.MouseButton.Right) then
      ui.popup(function ()
        ui.pushFont(ui.Font.Small)
        if ui.checkbox('Resize on resample', settings.resampleResize) then
          settings.resampleResize = not settings.resampleResize
        end
        settings.resampleGap = ui.slider('##density', settings.resampleGap, 1, 20, 'Resample density: %.1f m', 2)
        ui.popFont()
      end)
    end
  end
  ui.sameLine(0, 4)
  if ui.button('Snap to ground', vec2(92, 0)) then
    addUndoPoint(true)
    for i = 1, #spline.points do
      spline:snapToTrackSurface(i, settings.snapGap)
    end
    spline.dirty = true
  end
  if ui.itemHovered() then
    ui.setTooltip('Use context menu to adjust density')
    if ui.itemClicked(ui.MouseButton.Right) then
      ui.popup(function ()
        ui.pushFont(ui.Font.Small)
        settings.snapGap = ui.slider('##gap', settings.snapGap, 0, 1, 'Hover above ground: %.2f m')
        ui.popFont()
      end)
    end
  end
  ui.button('Soften selected', vec2(-0.1, 0), selectedPoint and 0 or ui.ButtonFlags.Disabled)
  if selectedPoint and (ui.itemActive() or uis.ctrlDown and ui.keyboardButtonDown(ui.KeyIndex.Q)) then
    if ui.itemClicked(ui.MouseButton.Left) or uis.ctrlDown and ui.keyboardButtonPressed(ui.KeyIndex.Q, false) then
      addUndoPoint(true)
    end
    if selectedPoint.type == 'point' then
      for i = spline.closed and 1 or 2, spline.closed and #spline.points or #spline.points - 1 do
        local mult = computeFactor(i)
        if mult > 0 then
          local p1 = spline.points[i == 1 and #spline.points or i - 1].pos
          local p2 = spline.points[i % #spline.points + 1].pos
          spline.points[i].pos:addScaled((p1 + p2) / 2 - spline.points[i].pos, (uis.shiftDown and -uis.dt or uis.dt) * 5 * mult)
        end
      end
    else
      local side = selectedPoint.type == 'left' and 'sideLeft' or 'sideRight'
      for i = spline.closed and 1 or 2, spline.closed and #spline.points or #spline.points - 1 do
        local mult = computeFactor(i)
        if mult > 0 then
          local p1 = spline.payloads[i == 1 and #spline.payloads or i - 1]
          local p2 = spline.payloads[i % #spline.payloads + 1]
          spline.payloads[i][side] = math.lerp(spline.payloads[i][side], (p1[side] + p2[side]) / 2, (uis.shiftDown and -uis.dt or uis.dt) * 10 * mult)
        end
      end
    end
    spline.dirty = true
  end
  if ui.itemHovered() then
    ui.setTooltip('Ctrl+Q\nClick while holding Shift for a reverse operation')
  end
  -- ui.setNextItemIcon(ui.Icons.Plus)
  -- if ui.button('Create new spine', vec2(-0.1, 0)) then
  --   creatingNewSpline = require('AISplineCreator')
  -- end
  ui.popFont()
end

