local sim = ac.getSim()
local car = ac.getCar(0) or error()
local mapButton = ac.ControlButton('__APP_DYNAMICRETURN_MAP')

-- local cars = require('shared/sim/cars')
local SectorRecord = require('SectorRecord')

local function runDataFactory(delta)
  return {
    deltas = {},
    startTime = os.preciseClock() + (delta or 0),
    currentPos = 0,
    currentTime = 0,
    posShift = 0,
    measure = {},
    result = nil
  }
end

-- Storage for previous sectors
local dir = '%s\\%s_%s' % {ac.getFolder(ac.FolderID.ScriptConfig), ac.getTrackFullID('_'), ac.getCarID(0)}
local prevSectors = {}
for _, v in ipairs(io.scanDir(dir, '*.lon')) do
  local s = SectorRecord(dir..'/'..v)
  if s.state then
    prevSectors[#prevSectors + 1] = s
  end
end

-- General state-ignoring state:
local popupOpened = false
local teleporting = false
local curSplinePosition = 0
local prevSplinePosition = math.huge

-- Configuration values (used until sectorData is ready):
local savedState
local startingPoint

-- Actual sector data:
---@type SectorRecord?
local sectorDataCand

---@type SectorRecord?
local sectorData = nil

-- State linked to current run:
local runData --= runDataFactory(0)

local function resetState()
  savedState = nil
  sectorDataCand = nil
  sectorData = nil
  teleporting = false
  runData = nil
  prevSplinePosition = math.huge
end

function script.update(dt)
  if sim.isReplayActive or sim.isPaused or sim.isInMainMenu then
    return
  end

  -- Already extrapolated (with extrapolation tweak active)
  local pos = car.position + car.look * (car.aabbSize.z / 2 - car.aabbCenter.z)
  curSplinePosition = ac.worldCoordinateToTrackProgress(pos)

  if car.justJumped or prevSplinePosition > 1e30 then
    prevSplinePosition = car.splinePosition
  end

  if runData then
    if not runData.result then
      if curSplinePosition < 0.1 and prevSplinePosition > 0.9 then
        runData.posShift = runData.posShift + 1
      elseif prevSplinePosition < 0.1 and curSplinePosition > 0.9 then
        runData.posShift = runData.posShift - 1
      end
      runData.currentTime = (os.preciseClock() - runData.startTime) * 1e3
      runData.currentPos = curSplinePosition + runData.posShift
      runData.measure[#runData.measure + 1] = {runData.currentPos, runData.currentTime}
      runData.deltas = sectorData and sectorData:deltas(runData.currentTime, runData.currentPos) or {}
    end
  end

  if mapButton:pressed() then
    if savedState == nil then
      savedState = false
      -- runStart()
      runData = runDataFactory()
      -- local pos = car.position:clone()
      -- local vel = car.velocity:clone()
      startingPoint = curSplinePosition
      ac.saveCarStateAsync(function (err, data)
        savedState = data
        ac.setSystemMessage('Dynamic Return', 'Starting point has been set')
        -- local driven = math.dot(cars.getCarStateTransform(data).position - pos, math.normalize(vel))
        -- local timeGap = driven / #vel
        -- print(timeGap)
      end)
    elseif savedState == false then
      ac.setSystemMessage('Dynamic Return', 'Setting starting point…')
    elseif not sectorData then
      sectorDataCand = SectorRecord('%s\\%s' % {dir, os.time()..'.lon'}, savedState, startingPoint, curSplinePosition)
      runData.result = sectorDataCand:register(runData.currentTime, runData.measure)
      ac.setSystemMessage('Dynamic Return', 'Finishing point has been set')
    end
  end
  
  teleporting = false
  if mapButton:down() then
    if sectorData then
      ac.loadCarState(sectorData.state, 30)
      runData = runDataFactory(30 / 333)
      teleporting = true
    end
  elseif sectorDataCand and not sectorData then
    sectorData = sectorDataCand
  end

  if sectorData and runData and not runData.result and prevSplinePosition <= sectorData.finishingPoint and curSplinePosition > sectorData.finishingPoint then
    local overshot = ((curSplinePosition - sectorData.finishingPoint) * sim.trackLengthM) / math.max(0.1, car.speedMs)
    runData.result = sectorData:register(runData.currentTime - overshot, runData.measure)
  end
 
  prevSplinePosition = curSplinePosition
end

function script.windowSettings(dt)
  ui.text('Map key:')
  mapButton:control(vec2(120, 0))
end

local drawCall = {
  p1 = vec3(), p2 = vec3(), p3 = vec3(), p4 = vec3(),
  directValuesExchange = true,
  cacheKey = 1,
  values = {gColor = rgbm(), gAlpha = 1, gWidthMul = 1},
  shader = [[
    float4 main(PS_IN pin) {
      float4 bg = float4(pow(max(0, gColor.rgb), USE_LINEAR_COLOR_SPACE ? 2.2 : 1), 1);
      // bg.rgb = lerp(bg.rgb, tx.rgb, tx.w) * (3 * gWhiteRefPoint);
      bg.w = gAlpha;// * saturate((3 - texRemL) * 5);
      bg.w *= max(
        saturate(((abs(pin.Tex.x * 2 - 1) - 1) * 200 * gWidthMul + 10)),
        saturate(abs(pin.Tex.y * 2 - 1) * 200 - 190));
      if (!bg.w) discard;
      return pin.ApplyFog(bg);
    }
  ]]
}

local p0, p1, p2 = vec3(), vec3(), vec3()
local dirDown = vec3(0, -1, 0)
local dirOffsetY = vec3(0, 4, 0)

local function drawGates(pos, color)
  ac.trackProgressToWorldCoordinateTo(pos, p0)
  ac.trackProgressToWorldCoordinateTo(pos - 0.0001, p1)
  p2:setCrossNormalized(p1:sub(p0), dirDown)

  local s = ac.getTrackAISplineSides(pos)
  p0:addScaled(p2, (s.x - s.y) / 2)

  local w = (s.x + s.y) / 2 + 0.2
  p2:scale(w)

  drawCall.p4:set(p0):sub(p2):sub(dirOffsetY)
  drawCall.p3:set(p0):add(p2):sub(dirOffsetY)
  drawCall.p2:set(drawCall.p3):addScaled(dirOffsetY, 2)
  drawCall.p1:set(drawCall.p4):addScaled(dirOffsetY, 2)
  drawCall.values.gColor = color
  drawCall.values.gWidthMul = w / 4
  ac.log(drawCall.values.gWidthMul)
  render.shaderedQuad(drawCall)
end

render.on('main.track.transparent', function ()
  render.setBlendMode(render.BlendMode.AlphaBlend)
  render.setCullMode(render.CullMode.None)
  render.setDepthMode(render.DepthMode.ReadOnly)
  if sectorData then
    drawGates(sectorData.startingPoint, rgbm.colors.lime)
    drawGates(sectorData.finishingPoint, rgbm.colors.white)
  elseif startingPoint then
    drawGates(startingPoint, rgbm.colors.lime)
  end
  -- drawGates(car.splinePosition, rgbm.colors.lime)
end)

function script.windowMain(dt)
  local windowFading = ac.windowFading()
  local outlineEnded = false
  ui.beginOutline()

  if popupOpened then
    ac.forceFadingIn()
  end

  if not ac.isCarResetAllowed() then
    ac.forceFadingIn()
    ui.textWrapped('Not available in this race. Try a single-car offline practice session.')
  elseif not mapButton:configured() then
    ac.forceFadingIn()
    ui.textWrapped('Map action is not configured. Open settings and assign some button to map the sector.')
  elseif not savedState and not sectorData and #prevSectors == 0 then
    ac.forceFadingIn()
    ui.textAligned('Press %s to save car state.' % mapButton:boundTo(), 0.5, -0.1)
  else
    ui.beginGroup(150)
    if runData then
      ui.text('Time: '..ac.lapTimeToString(runData.currentTime, false))
      if not runData.result then
        ui.backupCursor()
        if sectorData then
          local left = (sectorData.finishingPoint - curSplinePosition) % 1
          ui.sameLine(0, 3)
          ui.offsetCursorY(1)
          ui.pushFont(ui.Font.Small)
          ui.text(' (%.0f m)' % (left * sim.trackLengthM))
          ui.popFont()
        else
          local driven = (curSplinePosition - startingPoint) % 1
          ui.sameLine(0, 3)
          ui.offsetCursorY(1)
          ui.pushFont(ui.Font.Small)
          ui.text(' (%.0f m)' % (driven * sim.trackLengthM))
          ui.popFont()
        end
        ui.restoreCursor()
      end
      local sectorCur = sectorData or sectorDataCand
      if sectorCur then
        ui.text('Best: '..ac.lapTimeToString(sectorCur.bestTime.time, false))
        if runData.deltas.best then
          ui.sameLine()
          ui.textColored('%s%.03f' % {runData.deltas.best < 0 and '−' or '+', math.abs(runData.deltas.best) / 1e3}, runData.deltas.best < 0 and rgbm.colors.lime or rgbm.colors.red)
        end
        ui.text('Last: '..ac.lapTimeToString(sectorCur.prevTime.time, false))
        if runData.deltas.prev then
          ui.sameLine()
          ui.textColored('%s%.03f' % {runData.deltas.prev < 0 and '−' or '+', math.abs(runData.deltas.prev) / 1e3}, runData.deltas.prev < 0 and rgbm.colors.lime or rgbm.colors.red)
        end
        if ui.itemHovered() then
          ui.tooltip(function ()
            ui.header('Previous runs:')
            if #sectorCur.history == 0 then          
              ui.pushDisabled()
              ui.pushFont(ui.Font.Small)
              ui.text('<Nothing to show>')
              ui.popFont()
              ui.popDisabled()
            else
              for i = #sectorCur.history, math.max(1, #sectorCur.history - 20), -1 do
                if sectorCur.history[i] ~= sectorCur.bestTime.time then
                  local d = sectorCur.history[i] - sectorCur.bestTime.time
                  ui.text(ac.lapTimeToString(sectorCur.history[i], false))
                  ui.sameLine()
                  ui.textColored('%s%.03f' % {d < 0 and '−' or '+', math.abs(d) / 1e3}, d < 0 and rgbm.colors.lime or rgbm.colors.red)
                else
                  ui.textColored(ac.lapTimeToString(sectorCur.history[i], false), rgbm.colors.lime)
                end
              end
            end
          end)
        end
      end
    else
      ui.pushFont(ui.Font.Small)
      ui.pushTextWrapPosition(120)
      ui.textWrapped(sectorData 
        and 'Press %s to start a new run.' % mapButton:boundTo()
        or 'Press %s to save car state.' % mapButton:boundTo())
      ui.popTextWrapPosition()
      ui.popFont()
    end
    ui.endGroup()

    if windowFading < 0.99 then
      ui.endOutline(rgbm.colors.black, windowFading)
      outlineEnded = true

      ui.pushStyleVarAlpha(1 - windowFading)
      ui.sameLine(0, 0)
      ui.drawSimpleLine(ui.getCursor(), ui.getCursor() + vec2(0, ui.availableSpaceY()), ui.styleColor(ui.StyleColor.Separator))
      ui.offsetCursorX(8)
      
      ui.beginGroup(-0.1)
      ui.pushFont(ui.Font.Small)
      if teleporting then
        ui.text('Teleporting back…')
      else
        if not sectorData then
          ui.text('Press %s to set the end point.\nUse Reset button to restart.' % mapButton:boundTo())
        else
          ui.text('Hold %s to teleport back.\nUse Reset button to map a new sector.' % mapButton:boundTo())
        end
        if ui.button('Reset', vec2(ui.availableSpaceX() / 2 - 4, 0), savedState and 0 or ui.ButtonFlags.Disabled) then
          resetState()
        end
        ui.sameLine(0, 4)
        if ui.button('Sectors', vec2(-0.1, 0)) then
          local r1, r2 = ui.itemRect()
          popupOpened = true
          ui.popup(function ()
            ui.header('Previous sectors:')
            if #prevSectors == 0 then
              ui.pushDisabled()
              ui.pushFont(ui.Font.Small)
              ui.text('<No saved sectors for this car and track found>')
              ui.popFont()
              ui.popDisabled()
            else
              for i, v in ipairs(prevSectors) do
                ui.pushID(i)
                if ui.selectable(v.name, sectorData == v) then
                  resetState()
                  sectorData = v
                end
                if ui.itemHovered() then
                  ui.setTooltip('Best time: %s\nTotal runs: %s' % {ac.lapTimeToString(v.bestTime.time), v.totalRuns})
                end
                ui.popID()
              end
            end
            if sectorData then
              ui.offsetCursorY(12)
              ui.setNextItemIcon(ui.Icons.Save)
              if ui.button('Save sector', vec2(280, 0)) then
                sectorData:save()
                if not table.contains(prevSectors, sectorData) then
                  prevSectors[#prevSectors + 1] = sectorData
                end
              end
            end
          end, {
            position = vec2(r1.x, r2.y) + ui.windowPos(),
            onClose = function ()
              popupOpened = false
            end
          })
        end
      end
      ui.popFont()
      ui.endGroup()
      ui.popStyleVar()
    end
  end

  if not outlineEnded then
    ui.endOutline(rgbm.colors.black, windowFading)
  end
end
