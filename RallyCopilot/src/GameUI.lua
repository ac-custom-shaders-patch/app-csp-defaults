local sim = ac.getSim()
local uis = ac.getUI()

local AppState = require('src/AppState')
local AppConfig = require('src/AppConfig')
local DrawCalls = require('src/DrawCalls')
local VoicesHolder = require('src/VoicesHolder')
local PaceNotesHolder = require('src/PaceNotesHolder')
local RouteItemType = require('src/RouteItemType')
local ExtraPhrases = require('src/ExtraPhrases')

local GameUI = {}

local lastPos = vec2(1e9)
local p0 = vec3()
local p1 = vec3()
local p2 = vec3()
local dirDown = vec3(0, -1, 0)
local dirOffsetY = vec3(0, 5, 0)

---@param v RouteItem
local function itemFits(v)
  return AppState.connection.raceState == 0 or v.pos > AppState.connection.hintsCutoffFrom and v.pos < AppState.connection.hintsCutoffTo
end

local function worldHintsRenderCallback()
  if AppState.editorActive then
    return
  end

  local visiblePos = ac.worldCoordinateToTrackProgress(sim.cameraPosition)
  local scale = AppConfig.worldHintsScale
  dirOffsetY.y = 5 * scale

  render.setBlendMode(render.BlendMode.AlphaBlend)
  local items = PaceNotesHolder.current().items
  for i = #items, 1, -1 do
    local e = items[i]
    if itemFits(e) then
      local g = e.pos - visiblePos
      if AppState.loopingSpline and g < -0.5 then
        g = g + 1
      end
      if g > 0 and g * sim.trackLengthM < AppConfig.worldHintsDistance then
        ac.trackProgressToWorldCoordinateTo(e.pos, p0)
        ac.trackProgressToWorldCoordinateTo(e.pos - 0.0001, p1)
        p2:setCrossNormalized(p1:sub(p0), dirDown):scale(scale * 2.5)

        local dc = DrawCalls.GamePointOnTrack
        dc.p4:set(p0):sub(p2)
        dc.p3:set(p0):add(p2)
        dc.p2:set(dc.p3):add(dirOffsetY)
        dc.p1:set(dc.p4):add(dirOffsetY)
        dc.textures.txIcon = e:iconTexture()
        dc.textures.txOverlay = e:iconOverlay()
        dc.values.gColor = e:color()
        dc.values.gAlpha = math.lerpInvSat(p0:distanceSquared(sim.cameraPosition),
          AppConfig.worldHintsFadeNearby ^ 2, (AppConfig.worldHintsFadeNearby * 1.2) ^ 2)
        render.shaderedQuad(dc)
      end
    end
  end
end

local worldHintsRelease

local function setWorldHintsCallback(active)
  if (not not active) ~= (worldHintsRelease ~= nil) then
    if worldHintsRelease then worldHintsRelease() worldHintsRelease = nil end
    if active then worldHintsRelease = render.on('main.track.transparent', worldHintsRenderCallback) end
  end
end

setWorldHintsCallback(AppConfig.worldHints)

function GameUI.windowSettings()
  ui.header('Voice')
  ui.combo('##voice', VoicesHolder.current():metadata().NAME, function ()
    ui.header('Installed voices:')
    ui.pushFont(ui.Font.Small)
    local m = 0
    for _, v in ipairs(VoicesHolder.list()) do
      m = math.max(m, ui.measureText(v:metadata().DESCRIPTION or '<No description>').x)
    end
    ui.setMaxCursorX(m + 8)
    ui.popFont()
    for i, v in ipairs(VoicesHolder.list()) do
      ui.pushID(i)
      ui.setNextTextSpanStyle(1, #v:metadata().NAME, nil, true)
      if ui.selectable(v:metadata().NAME..'\n ', v == VoicesHolder.current()) then
        VoicesHolder.select(v)
      end
      local r1, r2 = ui.itemRect()
      ui.pushFont(ui.Font.Small)
      ui.drawTextClipped(v:metadata().DESCRIPTION or '<No description>', r1 + vec2(12, 4), r2 - 2, rgbm.colors.white, vec2(0, 1))
      ui.popFont()
      if ui.itemHovered() then
        ui.setTooltip('Author: %s\nVersion: %s\nLocation: %s' % {v:metadata().AUTHOR or '?', v:metadata().VERSION or '?', v:location():sub(#__dirname + 2)})
      end
      ui.popID()
    end
    ui.separator()
    ui.setNextItemIcon(ui.Icons.Edit)
    if ui.selectable('Editor', ac.isWindowOpen('voices')) then
      ac.setWindowOpen('voices', not ac.isWindowOpen('voices'))
    end
  end)
  local newValue = ui.slider('##callVolume', ac.getAudioVolume(AppState.volumeKey, nil, 1) * 100, 0, 200, 'Volume: %.0f%%')
  if ui.itemEdited() then
    ac.setAudioVolume(AppState.volumeKey, newValue / 100)
  end
  AppConfig.callAhead = ui.slider('##callAhead', AppConfig.callAhead, 0, 10, 'Call ahead: %.1f s', 2)
  if VoicesHolder.current().editor and ui.checkbox('Distortion', AppConfig.useDSP) then
    AppConfig.useDSP = not AppConfig.useDSP
    for _, v in ipairs(VoicesHolder.loaded()) do
      v:recreateAudioSamples()
    end
  end

  ui.offsetCursorY(12)
  ui.header('HUD hints')
  if ui.checkbox('Enable', AppConfig.uiHints) then
    AppConfig.uiHints = not AppConfig.uiHints
  end
  if AppConfig.uiHints then
    AppConfig.uiHintsTime = ui.slider('##uiHintsTime', AppConfig.uiHintsTime, 0, 10, 'Show for: %.1f s', 2)
    if ui.checkbox('Align in the center', AppConfig.centerHints) then
      AppConfig.centerHints = not AppConfig.centerHints
    end
  end

  ui.offsetCursorY(12)
  ui.header('3D hints')
  if ui.checkbox('Enable##3D', AppConfig.worldHints) then
    AppConfig.worldHints = not AppConfig.worldHints
    setWorldHintsCallback(AppConfig.worldHints)
  end
  if AppConfig.worldHints then
    AppConfig.worldHintsFadeNearby = ui.slider('##worldHintsFadeNearby', AppConfig.worldHintsFadeNearby, 15, 50, 'Fade nearby: %.0f m')
  end

  ui.offsetCursorY(12)
  ui.pushFont(ui.Font.SmallItalic)
  ui.pushTextWrapPosition(200)
  ui.textWrapped('Camera position is used for hints with free camera mode.')
  ui.popTextWrapPosition()
  ui.popFont()
end

local prevPos = -1
local marksToDisplay = {} ---@type {[1]: number, [2]: RouteItem}[]

local function currentPosition()
  if sim.cameraMode == ac.CameraMode.Free then
    return ac.worldCoordinateToTrackProgress(sim.cameraPosition), false
  end

  local car = ac.getCar(0)
  if not car or sim.trackLengthM < 1 then
    return 0, false
  end
  return car.splinePosition + AppConfig.callAhead * (car.speedKmh / 3.6) / sim.trackLengthM, car.justJumped
end

-- VoicesHolder.current():enqueue(RouteItemType.TurnLeft, 2, {}, {})
-- VoicesHolder.current():enqueue(RouteItemType.TurnLeft, 2, {}, {}) 
-- VoicesHolder.current():enqueue(RouteItemType.TurnLeft, 2, {}, {})
-- VoicesHolder.current():enqueue(RouteItemType.TurnLeft, 2, {}, {})
-- VoicesHolder.current():enqueue(RouteItemType.Extra, 2)

ac.onSharedEvent('app.RallyCopilot', function (data)
  if type(data) ~= 'table' then return end
  if type(data.extraPhraseID) == 'string' and ExtraPhrases[data.extraPhraseID] then
    VoicesHolder.current():enqueue(RouteItemType.Extra, ExtraPhrases[data.extraPhraseID])
  end
end)

function GameUI.update()
  if not AppState.editorActive then
    local curPos, invalidPos = currentPosition()
    if AppState.connection.raceState % 2 == 1 then
      prevPos = curPos
      AppState.connection.distanceToNextHint = sim.trackLengthM
      return
    end
    if not invalidPos and prevPos ~= -1 and curPos > prevPos and curPos < prevPos + 0.05 then
      local items = PaceNotesHolder.current().items
      local rangeFrom = prevPos % 1
      local rangeTo = curPos % 1
      local minGap = 1
      for _, v in ipairs(items) do
        if itemFits(v) then
          local fits = v.pos > rangeFrom
          if rangeFrom <= rangeTo then
            fits = fits and v.pos <= rangeTo
          else
            fits = fits or v.pos < rangeTo
          end
          if not fits then
            local d = v.pos - rangeFrom
            if d > 0 and d < minGap then
              minGap = d
            end
          elseif VoicesHolder.current():enqueue(v.type, v.modifier, v.hints, {}) then
            marksToDisplay[#marksToDisplay + 1] = {0, v}
          end
        end
      end
      AppState.connection.distanceToNextHint = minGap * sim.trackLengthM
      if AppState.connection.raceState == 0 and prevPos < 1 and curPos > 1 and ac.getSession(sim.currentSessionIndex).laps == ac.getCar(0).lapCount + 1 then
        VoicesHolder.current():enqueue(RouteItemType.Extra, ExtraPhrases['finish'])
      end
    end
    if invalidPos or curPos > prevPos or curPos < prevPos - 0.05 or sim.cameraMode == ac.CameraMode.Free or ac.getCar(0).justJumped then
      prevPos = curPos
    end
  end
end

local paceNotesSelectorOpened = false

local function getNotesExchangeCount()
  if AppState.notesExchangeCount == nil then
    AppState.notesExchangeCount = false
    web.get(AppState.exchangeEndpoint..'/count?trackID='..string.urlEncode(AppState.exchangeTrackID), function (err, response)
      AppState.notesExchangeCount = true
      if response then
        AppState.notesExchangeCount = JSON.parse(response.body).count
      end
    end)
  end
  return tonumber(AppState.notesExchangeCount)
end

function GameUI.windowMain()
  local windowFading = ac.windowFading()
  local itemSize = ui.windowHeight()
  local windowWidth, totalWidth = ui.windowWidth() - 20, 0
  local empty = true
  ui.pushClipRect(0, ui.windowSize())

  if AppState.connection.raceState == 1 or AppState.connection.raceState == 3 then
    local msg
    if AppState.connection.raceState == 3 then
      -- Not sure what to do here
    elseif AppState.connection.countdownState ~= 0 then
      -- Not sure what to do here
    elseif AppState.connection.distanceToStart > 2 then
      msg = 'Drive %.2f m closer to the starting line' % (AppState.connection.distanceToStart - 2)
    elseif AppState.connection.distanceToStart < 0 then
      msg = AppState.connection.distanceToStart > -5 and 'Drive %.2f m back' % -AppState.connection.distanceToStart or 'Consider restarting the session'
    else
      -- msg = 'Hold handbrake for a bit'
    end
    if msg then
      ui.beginOutline()
      ui.drawTextClipped(msg, vec2(0, 20), ui.windowSize(), rgbm.colors.white, 0.5)
      ui.endOutline(rgbm.colors.black, 1)
      empty = false
    end
  elseif AppConfig.uiHints then
    local fadeMult = math.max(1, AppConfig.uiHintsTime) / 0.2
    for i = #marksToDisplay, 1, -1 do
      local v = marksToDisplay[i]
      v[1] = v[1] + ac.getDeltaT() / AppConfig.uiHintsTime
      if v[1] > 1 then
        table.remove(marksToDisplay, i)
      else
        local f = math.min(1, v[1] * fadeMult) * math.saturateN((1 - v[1]) * fadeMult)
        totalWidth = totalWidth + math.smoothstep(f)
      end
    end

    totalWidth = math.max(1, totalWidth)

    local dc = DrawCalls.HUDIcon
    local r1, r2 = dc.p1, dc.p2
    r1.x = AppConfig.centerHints and 10 + math.round(math.max(0, windowWidth / 2 - totalWidth * (itemSize / 2))) or 10
    r2.x, r2.y = r1.x + itemSize, itemSize
    dc.values.gFadeAt = (#marksToDisplay + 1) * itemSize > windowWidth and ui.windowPos().x + windowWidth - 10 or 1e9
    for i = 1, #marksToDisplay do
      local e = marksToDisplay[i]
      local v = e[2]
      local fadeFront = math.saturateN((1 - e[1]) * fadeMult)
      local fade = fadeFront * math.min(1, e[1] * fadeMult)
      dc.values.gColor = v:color()
      dc.values.gAlpha = fade
      dc.values.gFadeFront = fadeFront
      dc.textures.txIcon = v:iconTexture()
      dc.textures.txOverlay = v:iconOverlay()
      ui.renderShader(dc)
      r1.x, r2.x = r1.x + itemSize * fade, r2.x + itemSize * fade
      empty = false
    end
  end

  ui.popClipRect()

  if paceNotesSelectorOpened then
    ac.forceFadingIn()
  end
  
  if windowFading > 0.99 then return end
  
  local c = ui.getCursor()
  local s = ui.availableSpace()
  local cur = ui.windowPos()
  if not lastPos:closerToThan(cur, 1) then
    if lastPos.x ~= 1e9 then
      AppConfig.introduction = false
    end
    lastPos:set(cur)
  end
  ui.pushStyleVarAlpha(1 - windowFading)
  ui.beginOutline()
  for x = 0, 1 do
    for y = 0, 1 do
      local p = vec2(c.x + x * s.x, c.y + s.y * y)
      ui.pathLineTo(p + vec2(x == 0 and 20 or -20, 0))
      ui.pathLineTo(p)
      ui.pathLineTo(p + vec2(0, y == 0 and 20 or -20))
      ui.pathStroke(rgbm.colors.white, false, 1)
    end
  end

  if sim.trackLengthM >= 1 then
    ui.backupCursor()
    ui.setCursor(vec2(12, 12))
    ui.pushFont(ui.Font.Small)
    ui.pushStyleColor(ui.StyleColor.Button, paceNotesSelectorOpened and rgbm(1, 1, 1, 0.05) or rgbm.colors.transparent)
    ui.pushStyleColor(ui.StyleColor.ButtonHovered, rgbm(1, 1, 1, 0.05))
    ui.pushStyleColor(ui.StyleColor.ButtonActive, rgbm(1, 1, 1, 0.05))
    local began = ui.button(PaceNotesHolder.current().metadata.name, vec2(ui.windowWidth() - 24, 20))
    ui.popStyleColor(3)
    ui.popFont()
    local r1, r2 = ui.itemRect()
    ui.drawRect(r1, r2, rgbm.colors.white)
    ui.drawIcon(ui.Icons.Down, vec2(r2.x - 20, r1.y) + 6, r2 - 6)
    if began then
      paceNotesSelectorOpened = true
      ui.popup(function ()
        ui.header('Available pacenotes:')
        for i, v in ipairs(PaceNotesHolder.list()) do
          ui.setNextTextSpanStyle(1, #v.metadata.name, nil, true)
          ui.pushID(i)
          if ui.selectable('%s\n ' % v.metadata.name,
              v == PaceNotesHolder:current()) then
            PaceNotesHolder.select(v)
          end
          local s1, s2 = ui.itemRect()
          ui.pushFont(ui.Font.Small)
          ui.drawTextClipped(v.metadata.author and 'Author: %s.' % v.metadata.author or 'Arranged based on AI spline.', s1 + vec2(24, 4), s2 - 2, rgbm.colors.white, vec2(0, 1))
          ui.popFont()
          if ui.itemClicked(ui.MouseButton.Right, true) then
            ui.popup(function ()
              ui.setNextItemIcon(ui.Icons.Font)
              if v:generated() then
                ui.pushDisabled()
              end
              if ui.selectable('Rename…') then
                ui.modalPrompt('Rename pacenotes?', 'New name:', v.metadata.name, 'Rename', 'Cancel', ui.Icons.Edit, ui.Icons.Cancel, function (newName)
                  if newName then
                    v.metadata.name = newName
                    v:save()
                  end
                end)
              end
              if v:generated() then
                ui.popDisabled()
              end
              ui.setNextItemIcon(ui.Icons.Edit)
              if ui.selectable('Edit…') then
                PaceNotesHolder.edit(v)
                ac.setWindowOpen('editor', true)
              end
              if v:generated() then
                ui.pushDisabled()
              end
              ui.setNextItemIcon(ui.Icons.Trash)
              if ui.selectable('Delete') then
                PaceNotesHolder.delete(v)
              end
              if v:generated() then
                ui.popDisabled()
              end
            end)
          end
          ui.popID()
        end
        ui.separator()
        ui.setNextItemIcon(ui.Icons.Plus)
        if ui.selectable('Create new…', ac.isWindowOpen('editor'), ui.SelectableFlags.DontClosePopups) then
          ui.popup(require('src/EditorUI').newPopup, {position = ui.windowPos() + ui.itemRectMax() - vec2(8, 22)})
        end
        local count = getNotesExchangeCount()
        ui.setNextItemIcon(ui.Icons.Earth)
        if ui.selectable(count and 'Pacenotes Exchange (%d entr%s)' % {count, count == 1 and 'y' or 'ies'} or 'Pacenotes Exchanges', ac.isWindowOpen('notesExchange')) then
          ac.setWindowOpen('notesExchange', not ac.isWindowOpen('notesExchange'))
        end
      end, {
        position = ui.windowPos() + vec2(r1.x, r2.y),
        size = vec2(ui.windowWidth() - 24, 0),
        onClose = function ()
          setInterval(function ()
            if not uis.isMouseLeftKeyDown then
              paceNotesSelectorOpened = false
              return clearInterval
            end
          end)
        end
      })
    end
    ui.restoreCursor()
    c.y = c.y + 32
    s.y = s.y - 32
  end

  if sim.trackLengthM < 1 then
    ui.drawTextClipped('Not available without AI spline', c, c + s, rgbm.colors.white, 0.5)
  elseif AppConfig.introduction then
    ui.drawTextClipped('\tPosition and size this window to\nthe place you’d like rally hints to be', c, c + s, rgbm.colors.white, 0.5)
  elseif AppState.editorActive then
    ui.drawTextClipped('Currently in editing mode', c, c + s, rgbm.colors.white, 0.5)
  elseif not AppConfig.uiHints then
    ui.drawTextClipped('HUD hints are disabled', c, c + s, rgbm.colors.white, 0.5)
  elseif empty then
    ui.drawTextClipped('Nothing to show', c, c + s, rgbm.colors.white, 0.5)
  end
  ui.endOutline(rgbm.colors.black, 1 - windowFading)
  ui.popStyleVar()
end

return GameUI