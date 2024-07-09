---@ext:basic

local BTN_F0 = const(ui.ButtonFlags.PressedOnClick)
local BTN_FA = const(bit.bor(ui.ButtonFlags.Active, ui.ButtonFlags.PressedOnClick))
local BTN_FN = const(function (active) return active and BTN_FA or BTN_F0 end)

local car = ac.getCar(0) or error()
local sim = ac.getSim()

local weightShift = not sim.isVRConnected and ac.DriverWeightShift(0) or nil

local anyExtraHint = false
local extraHints = table.range(6, function (index)
  local r = ac.getExtraSwitchName(index - 1) or false
  if r then anyExtraHint = true end
  return r
end)

if not ac.getCarGearLabel then
  ac.getCarGearLabel = function (index)
    local gear = index == 0 and car.gear or ac.getCar(index).gear
    return gear < 0 and 'R' or gear == 0 and 'N' or tostring(gear)
  end
end

local controlsConfig = ac.INIConfig.controlsConfig()
local controlsBindings = {}

local function bindingInfoGen(section)
  local pieces = section:split(';')
  if #pieces > 1 then
    local r = {}
    for _, v in ipairs(pieces) do
      local p = string.split(v, ':', 2, true)
      local i = bindingInfoGen(p[2])
      if string.regfind(i, '^(?:Not |Keyboard:|Gamepad:)') then i = i:sub(1, 1):lower()..i:sub(2) end
      r[#r + 1] = p[1]..': '..i:replace('\n', '\n\t')
    end
    return table.concat(r, '\n')
  end

  local entries = {}
  local baseSection = section
  section = string.reggsub(section, '\\W+', '')

  if baseSection:endsWith('$') then
    return 'Keyboard: '..baseSection:sub(1, #baseSection - 1)
  end
  
  if section:startsWith('_') or sim.inputMode == ac.UserInputMode.Keyboard or controlsConfig:get('ADVANCED', 'COMBINE_WITH_KEYBOARD_CONTROL', true) then
    local k = controlsConfig:get(section, 'KEY', -1)
    if k > 0 then
      local modifiers = table.map(controlsConfig:get(section, 'KEY_MODIFICATOR', nil) or {}, function (v)
        if v == '' then return nil end
        if tonumber(v) == 16 then return 'Shift' end
        if tonumber(v) == 17 then return 'Ctrl' end
        if tonumber(v) == 18 then return 'Alt' end
        return '<'..v..'>'
      end)
      if #modifiers == 0 and baseSection:endsWith('!') then
        table.insert(modifiers, 'Ctrl')
      end

      local m
      for n, v in pairs(ac.KeyIndex) do
        if v == k then
          m = n
          break
        end
      end 

      table.insert(modifiers, m or string.char(k))
      entries[#entries + 1] = 'Keyboard: '..table.concat(modifiers, '+')
    end
  end

  if sim.inputMode == ac.UserInputMode.Gamepad then
    local x = controlsConfig:get(section, 'XBOXBUTTON', '')
    if x ~= '' and (tonumber(x) or 1) > 0 then
      entries[#entries + 1] = 'Gamepad: '..x
    end
  end

  local j = controlsConfig:get(section, 'JOY', -1)
  if j >= 0 then
    local n = controlsConfig:get('CONTROLLERS', 'CON'..j, 'Unknown device')
    local d = controlsConfig:get(section, 'BUTTON', -1)
    if d >= 0 and (tonumber(x) or 1) > 0 then
      -- if #n > 28 then n = n:sub(1, 27)..'…' end
      local m = controlsConfig:get(section, 'BUTTON_MODIFICATOR', -1)
      if m >= 0 then
        -- TODO: JOY_MODIFICATOR
        entries[#entries + 1] = n..': buttons #'..(m + 1)..'+'..(d + 1)
      else
        entries[#entries + 1] = n..': button #'..(d + 1)
      end
    else
      local p = controlsConfig:get(section, '__CM_POV', -1)
      if p >= 0 then
        local dir = {[0] = '←', [1] = '↑', [2] = '→', [3] = '↓'}
        entries[#entries + 1] = n..': D-pad #'..(p + 1)..(dir[controlsConfig:get(section, '__CM_POV_DIR', -1)] or '')
      end
    end
  end

  if #entries == 0 then
    return 'Not bound to anything'
  else
    return table.concat(entries, '\n')
  end
end

local function bindingInfo(section)
  return table.getOrCreate(controlsBindings, section, bindingInfoGen, section)
end

local function bindingInfoTooltip(section, prefix)
  if ui.itemHovered() then
    ui.tooltip(function ()
      if prefix then
        ui.pushFont(ui.Font.Main)
        ui.textWrapped(prefix, 500)
        ui.popFont()
        ui.offsetCursorY(4)
      end
      ui.pushFont(ui.Font.Small)
      ui.textWrapped(bindingInfo(section), 500)
      ui.popFont()
    end)
  end
end

local function isExtraPressed(i)
  if i == 1 then return car.extraA end
  if i == 2 then return car.extraB end
  if i == 3 then return car.extraC end
  if i == 4 then return car.extraD end
  if i == 5 then return car.extraE end
  if i == 6 then return car.extraF end
  return false
end

local steerApplied = 0
local steerLocked = 0
local shiftApplied = 0
local shiftLocked = 0
local controls = ac.overrideCarControls()
-- local controls = {}

local function releaseHeld()
  if weightShift and shiftApplied ~= 0 then
    weightShift.input = 0
  end
end

ac.onRelease(releaseHeld)

local colTurningLights = rgbm(0.5, 1, 0.5, 1)
local colHazards = rgbm(1, 0.5, 0.5, 1)

local function blockCarInstruments()
  local w2 = (ui.availableSpaceX() - 4) / 2
  local w3 = (ui.availableSpaceX() - 8) / 3
  local w6 = (ui.availableSpaceX() - 4 * 5) / 6

  -- Turning lights & hazards
  if car.hasTurningLights then
    if car.turningLightsActivePhase and car.turningLeftLights then ui.pushStyleColor(ui.StyleColor.Text, colTurningLights) end
    if ui.iconButton(ui.Icons.TurnSignalLeft, vec2(w3, 0), 4, true, BTN_FN(car.turningLeftOnly)) then ac.setTurningLights(car.turningLeftOnly and ac.TurningLights.None or ac.TurningLights.Left) end
    if car.turningLightsActivePhase and car.turningLeftLights then ui.popStyleColor() end
    bindingInfoTooltip('__EXT_TURNSIGNAL_LEFT', 'Left turning lights')
    ui.sameLine(0, 4)
    if car.turningLightsActivePhase and car.hazardLights then ui.pushStyleColor(ui.StyleColor.Text, colHazards) end
    if ui.iconButton(ui.Icons.Hazard, vec2(w3, 0), 4, true, BTN_FN(car.hazardLights)) then ac.setTurningLights(car.hazardLights and ac.TurningLights.None or ac.TurningLights.Hazards) end
    if car.turningLightsActivePhase and car.hazardLights then ui.popStyleColor() end
    bindingInfoTooltip('__EXT_HAZARDS', 'Hazards')
    ui.sameLine(0, 4)
    if car.turningLightsActivePhase and car.turningRightLights then ui.pushStyleColor(ui.StyleColor.Text, colTurningLights) end
    if ui.iconButton(ui.Icons.TurnSignalRight, vec2(w3, 0), 4, true, BTN_FN(car.turningRightOnly)) then ac.setTurningLights(car.turningRightOnly and ac.TurningLights.None or ac.TurningLights.Right) end
    if car.turningLightsActivePhase and car.turningRightLights then ui.popStyleColor() end
    bindingInfoTooltip('__EXT_TURNSIGNAL_RIGHT', 'Right turning lights')
  end

  -- Other functions
  local lightsW2 = car.hasHornAudioEvent or car.hasAnalogTelltale or car.hasFlashingLights
  if car.headlightsAreHeadlights and car.hasLowBeams then
    ui.setNextItemWidth(lightsW2 and w2 or -0.1)
    local value = ui.slider('##lights', not car.headlightsActive and 0 or car.lowBeams and 1 or 2, 0, 2, 
      not car.headlightsActive and 'No lights' or car.lowBeams and 'Low beams' or 'High beams')
    if ui.itemEdited() then
      value = math.round(value)
      ac.setHeadlights(value ~= 0)
      ac.setHighBeams(value == 2)
    end
    if lightsW2 then ui.sameLine(0, 4) end
    bindingInfoTooltip('Lights: ACTION_HEADLIGHTS; Low/high beams: __EXT_LOW_BEAM', 'Headlights can help in subpar lighting conditions')
  else
    ui.setNextItemWidth(lightsW2 and w2 or -0.1)
    if ui.checkbox('Lights', car.headlightsActive) then ac.setHeadlights(not car.headlightsActive) end
    bindingInfoTooltip('ACTION_HEADLIGHTS', car.headlightsAreHeadlights and 'Lights on this car act are used for a different role'
      or 'Headlights can help in subpar lighting conditions')
    if lightsW2 then ui.sameLine(0, 4) end
  end

  if car.hasFlashingLights then
    if ui.button('Flash', btnAutofill, BTN_FN(car.flashingLightsActive)) then controls.headlightsFlash = true end
    bindingInfoTooltip('ACTION_HEADLIGHTS_FLASH', 'Flash headlights')
  end
  if car.hasHornAudioEvent then
    local w = ui.getCursorX() < 40 and car.hasAnalogTelltale and w2 or -0.1
    if car.sirenHorn then
      ui.setNextItemWidth(w)
      if ui.checkbox('Siren', car.hornActive) then
        controls.horn = true
        setTimeout(function ()
          controls.horn = false
        end, 0.1)
      end
      bindingInfoTooltip('ACTION_HORN', 'Toggle siren (replaces horn on this car)')
    else
      ui.setNextItemIcon(ui.Icons.Speaker)
      ui.button('Horn', vec2(w, 0))
      controls.horn = ui.itemActive()
      bindingInfoTooltip('ACTION_HORN', 'Helps to alert other drivers')
    end
    if w > 0 then ui.sameLine(0, 4) end
  end

  if car.hasAnalogTelltale then
    local resetTelltaleNarrow = ui.availableSpaceX() < 100
    if resetTelltaleNarrow then
      ui.pushFont(ui.Font.Small)
      ui.pushStyleVar(ui.StyleVar.FramePadding, vec2(0, 5))
    end
    if ui.button('Reset telltale', btnAutofill, BTN_F0) then
      ac.simulateCustomHotkeyPress('__EXT_TELLTALE_RESET')
    end
    bindingInfoTooltip('__EXT_TELLTALE_RESET', 'Reset maximum RPM mark')
    if resetTelltaleNarrow then
      ui.popFont()
      ui.popStyleVar()
    end
  end

  if car.wiperModes > 1 then
    ui.setNextItemWidth(-0.1)
    local value = ui.slider('##wiper', car.wiperSelectedMode, 0, car.wiperModes - 1, car.wiperSelectedMode == 0 and 'Wipers: off' or 'Wipers: %d/%d' % {car.wiperMode, car.wiperModes - 1})
    if ui.itemEdited() then
      ac.setWiperMode(math.round(value))
    end
    bindingInfoTooltip('Next: __EXT_WIPERS_MORE; Previous: __EXT_WIPERS_LESS; Stop: __EXT_WIPERS_OFF', 'Current wipers mode')
  end

  ui.pushStyleVar(ui.StyleVar.FramePadding, vec2(0, 4))
  for i = 1, 6 do
    local t = extraHints[i]
    local a = ac.isExtraSwitchAvailable(i - 1, false)
    if not a then ui.pushDisabled() end
    local p = ac.accessExtraSwitchParams(i - 1)
    if anyExtraHint and not t then ui.pushStyleColor(ui.StyleColor.Text, rgbm.colors.gray) end
    if ui.button(string.char(('A'):byte(1) + i - 1), vec2(w6, 0), BTN_FN(isExtraPressed(i))) and not p.holdMode then
      ac.simulateCustomHotkeyPress('__EXT_LIGHT_'..string.char(('A'):byte(1) + i - 1))
    end
    if p and p.holdMode and ui.itemActive() then
      ac.simulateCustomHotkeyPress('__EXT_LIGHT_'..string.char(('A'):byte(1) + i - 1))
    end
    if anyExtraHint and not t then ui.popStyleColor() end
    if ui.itemHovered() then
      bindingInfoTooltip('__EXT_LIGHT_%c' % (('A'):byte(1) + i - 1), 'Extra switch %c%s' % {('A'):byte(1) + i - 1, t and '\nRole: '..t or ''})
    end
    if not a then ui.popDisabled() end
    if i < 6 then ui.sameLine(0, 4) end
  end  
  ui.popStyleVar()
end

local steerIcon, steerAngle = ui.ExtraCanvas(32), math.huge
local pedalLM, pedalLX, pedalNeutrals = vec2(), vec2(), {}
local btnAutofill = vec2(-0.1, 0)

ac.onSessionStart(function (sessionIndex, restarted)
  pedalNeutrals = {}
end)

local function pedalButton(title, size, color)
  ui.button('##'..title or title, size)
  local w = 0
  local rm = ui.itemRectMin()
  local rx = ui.itemRectMax()
  local rm2 = pedalLM:set(rm):sub(20)
  local rx2 = pedalLX:set(rx):add(20)
  if ui.itemActive() then
    w = math.lerpInvSat(ui.mouseLocalPos().y, rx.y, rm.y)
    if ui.mouseClicked(ui.MouseButton.Right) then
      pedalNeutrals[title] = w
    end
  else
    if ui.itemClicked(ui.MouseButton.Right) then
      if pedalNeutrals[title] and pedalNeutrals[title] > 0 then
        pedalNeutrals[title] = 0
      else
        w = math.lerpInvSat(ui.mouseLocalPos().y, rx.y, rm.y)
        pedalNeutrals[title] = w
      end
    end
    w = pedalNeutrals[title] or 0
    if ui.itemHovered() then
      ui.setTooltip('Click right mouse button while steering to set the new neutral value. Click the slider with right mouse button to reset the neutral value.')
    end
  end
  if w > 0 then
    rm.y = math.lerp(rx.y, rm.y, w)
    ui.drawRectFilled(rm, rx, color)
  end
  ui.beginRotation()
  ui.pushFont(ui.Font.Small)
  ui.drawTextClipped(title, rm2, rx2, rgbm.colors.white, 0.5)
  if w > 0 then
    ui.pushClipRect(rm, rx, false)
    ui.drawTextClipped(title, rm2, rx2, rgbm.colors.black, 0.5)
    ui.popClipRect()
  end
  ui.endRotation(180)
  ui.popFont()
  return w
end

local function blockCarDrive()
  local w4 = (ui.availableSpaceX() - 12) / 4

  if math.abs(steerAngle - car.steer) > 5 then
    steerAngle = car.steer
    steerIcon:clear(rgbm.colors.transparent):update(function (dt)
      ui.beginRotation()
      ui.setShadingOffset(1, 1, 1, 0)
      ui.image(ui.Icons.SteeringWheel, ui.windowSize())
      ui.resetShadingOffset()
      ui.endRotation(90 - car.steer)
    end)
  end

  ui.setNextItemWidth(-0.1)
  ui.setNextItemIcon(steerIcon)
  local value = ui.slider('##steer', car.steer, -car.steerLock, car.steerLock, 'Steer: %.0f°')
  if not ui.itemEdited() and not ui.itemActive() then
    if ui.itemClicked(ui.MouseButton.Right) then
      steerLocked = 0
    end
    value = steerLocked
    if ui.itemHovered() then
      ui.setTooltip('Hold Shift for more precise steering. Click right mouse button while steering to set the new neutral value. Click the slider with right mouse button to reset the neutral value.')
    end
  elseif ui.mouseClicked(ui.MouseButton.Right) then
    steerLocked = value
  end
  steerApplied = math.applyLag(steerApplied, value / car.steerLock, 0.8, ui.deltaTime())
  if steerApplied == 0 then
    controls.steer = math.huge
  elseif math.abs(steerApplied) < 0.001 then 
    steerApplied = 0
    controls.steer = 0
  else
    controls.steer = steerApplied
  end

  local ps = vec2(w4, 68)
  controls.clutch = 1 - pedalButton('Clutch', ps, rgbm.colors.cyan)
  ui.sameLine(0, 4)
  controls.brake = pedalButton('Brakes', ps, rgbm.colors.red)
  ui.sameLine(0, 4)
  controls.gas = pedalButton('Throttle', ps, rgbm.colors.lime)
  ui.sameLine(0, 4)
  controls.handbrake = pedalButton('Handbrake', ps, rgbm.colors.yellow)

  ui.pushFont(ui.Font.Title)
  local c = ui.getCursor()
  ui.textAligned(ac.getCarGearLabel(0), 0.5, vec2(56, 44))
  -- ui.pathLineTo(vec2(ui.itemRectMin().x, ui.itemRectMax().y))
  ui.pathArcTo(c + vec2(28, 23), 16, -2.4 - math.pi / 2, 2.4 - math.pi / 2, 20)
  ui.pathStroke(rgbm.colors.gray, false, 1)
  ui.pathArcTo(c + vec2(28, 23), 16, -2.4 - math.pi / 2, math.lerp(-2.4, 2.4, math.saturateN(car.rpm / math.max(1.2 * car.rpmLimiter, 4e3))) - math.pi / 2, 20)
  ui.pathStroke(car.rpm > car.rpmLimiter and rgbm.colors.red or rgbm.colors.white, false, 1)
  ui.popFont()
  ui.sameLine(80, 0)
  ui.beginGroup(-0.1)

  if w4 < 60 then
    if ui.iconButton(ui.Icons.Down, vec2(ui.availableSpaceX() / 2 - 2, 0), 6, true, BTN_F0) then controls.gearDown = true end
    bindingInfoTooltip('GEARDN', 'Previous gear')
    ui.sameLine(0, 4)
    if ui.iconButton(ui.Icons.Up, btnAutofill, 6, true, BTN_F0) then controls.gearUp = true end
    bindingInfoTooltip('GEARUP', 'Next gear')
  else
    if ui.button('Previous gear', vec2(ui.availableSpaceX() / 2 - 2, 0), BTN_F0) then controls.gearDown = true end
    bindingInfoTooltip('GEARDN', 'Previous gear')
    ui.sameLine(0, 4)
    if ui.button('Next gear', btnAutofill, BTN_F0) then controls.gearUp = true end
    bindingInfoTooltip('GEARUP', 'Next gear')
  end
  if ui.button('Neutral gear', btnAutofill, BTN_F0) then ac.switchToNeutralGear() end
  bindingInfoTooltip('__EXT_GEAR_NEUTRAL', 'Quickly reset to the neutral gear')
  ui.endGroup()
end

local targetTC2, targetFuelMap
local shiftIcon, shiftAngle = ui.ExtraCanvas(32), math.huge

local function blockCarTweaks()
  local w2 = (ui.availableSpaceX() - 4) / 2

  -- Car controls
  if car.absModes > 0 then
    ui.setNextItemWidth(car.tractionControlModes > 0 and w2 or -0.1)
    if car.absModes > 1 then
      local value = ui.slider('##abs', car.absMode, 0, car.absModes, 'ABS: %%.0f/%d' % car.absModes)
      if ui.itemEdited() then ac.setABS(math.round(value)) end
    elseif ui.checkbox('ABS', car.absMode == 1) then
      ac.setABS(1 - car.absMode)
    end
    if car.tractionControlModes > 0 then ui.sameLine(0, 4) end
    bindingInfoTooltip('Cycle: ABS!; Next: ABSUP; Previous: ABSDN', 'Change current ABS mode')
  end

  if car.tractionControlModes > 0 then
    ui.setNextItemWidth(car.absModes == 0 and car.tractionControl2Modes > 0 and w2 or -0.1)
    if car.tractionControlModes > 1 then
      local value = ui.slider('##tc', car.tractionControlMode, 0, car.tractionControlModes, 'TC: %%.0f/%d' % car.tractionControlModes)
      if ui.itemEdited() then ac.setTC(math.round(value)) end
    elseif ui.checkbox('TC', car.tractionControlMode == 1) then
      ac.setTC(1 - car.tractionControlMode)
    end
    if car.absModes == 0 and car.tractionControl2Modes > 0 then ui.sameLine(0, 4) end
    bindingInfoTooltip('Cycle: TRACTION_CONTROL!; Next: TCUP; Previous: TCDN', 'Change current traction control mode')
  end

  if car.tractionControl2Modes > 0 then
    ui.setNextItemWidth(-0.1)
    local tc2Value = targetTC2 or car.tractionControl2
    if car.tractionControl2Modes > 1 then
      local value = ui.slider('##tc2', tc2Value, 0, car.tractionControl2Modes, 'TC2: %%.0f/%d' % car.tractionControl2Modes)
      if ui.itemEdited() then targetTC2 = math.round(value) end
    elseif ui.checkbox('TC2', tc2Value == 1) then
      ac.setTC(1 - tc2Value)
    end
    bindingInfoTooltip('Next: __EXT_TC2_UP; Previous: __EXT_TC2_DOWN', 'Change secondary traction control mode')
    if targetTC2 and bit.band(sim.frame, 1) == 1 then
      if targetTC2 > car.tractionControl2 then
        ac.simulateCustomHotkeyPress('__EXT_TC2_UP', 1)
      elseif targetTC2 < car.tractionControl2 then
        ac.simulateCustomHotkeyPress('__EXT_TC2_DOWN', 1)
      else
        targetTC2 = nil
      end
    end
  end

  if car.fuelMaps > 0 then
    ui.setNextItemWidth(-0.1)
    local fuelMapValue = targetFuelMap or car.fuelMap
    local value = ui.slider('##fuelmap', fuelMapValue, 0, car.fuelMaps, 'Fuel map: %%.0f/%d' % car.fuelMaps)
    bindingInfoTooltip('__EXT_ENGINEMAP_UP', 'Change current fuel map (aka engine map)')
    if ui.itemEdited() then targetFuelMap = math.round(value) end
    if targetFuelMap and bit.band(sim.frame, 1) == 1 then
      if targetFuelMap ~= car.fuelMap then
        ac.simulateCustomHotkeyPress('__EXT_ENGINEMAP_UP', 1)
      else
        targetFuelMap = nil
      end
    end
  end

  if car.adjustableTurbo then
    ui.setNextItemWidth(-0.1)
    local value = ui.slider('##turbo', car.turboWastegates[0] * 10, 0, 10, 'Turbo: %.0f/10')
    if ui.itemEdited() then ac.setTurboWastegate(value / 10) end
    bindingInfoTooltip('Increase: TURBOUP; Reduce: TURBODN', 'Change turbo wastegate altering its efficiency')
  end

  if car.brakesCockpitBias then
    ui.setNextItemWidth(-0.1)    
    local value = ui.slider('##brakes', car.brakeBias * 100, car.brakesBiasLimitDown * 100, car.brakesBiasLimitUp * 100, 'Brakes: %.0f%%')
    if ui.itemEdited() then ac.setBrakeBias(value / 100) end
    bindingInfoTooltip('Move forward: BALANCEUP; Move back: BALANCEDN', 'Change brake bias')
  end

  if car.hasEngineBrakeSettings then
    ui.setNextItemWidth(-0.1)    
    local value = ui.slider('##ebrake', car.currentEngineBrakeSetting + 1, 1, car.engineBrakeSettingsCount, 'Engine brake: %%.0f/%d' % car.engineBrakeSettingsCount)
    if ui.itemEdited() then ac.setEngineBrakeSetting(value - 1) end
    bindingInfoTooltip('Increase: ENGINE_BRAKE_UP; Reduce: ENGINE_BRAKE_DN', 'Change engine braking intensity')
  end

  if car.hasCockpitSwitchForUserSpeedLimiter then
    ui.setNextItemWidth(-0.1)
    if ui.checkbox('Speed limiter', car.userSpeedLimiterEnabled) then ac.simulateCustomHotkeyPress('__EXT_SPEED_LIMITER') end
    bindingInfoTooltip('__EXT_SPEED_LIMITER', 'Click to toggle car’s speed limiter')
  end

  if not sim.isPitsSpeedLimiterForced then
    ui.setNextItemWidth(-0.1)
    if ui.checkbox('Pits limiter', car.manualPitsSpeedLimiterEnabled) then ac.simulateCustomHotkeyPress('__EXT_PIT_LIMITER') end
    bindingInfoTooltip('__EXT_PIT_LIMITER', 'Click to toggle pits limiter (in this session, limiter is not forced to activate)')
  end

  if car.drsPresent then
    ui.setNextItemWidth(car.kersPresent and w2 or -0.1)
    if not car.drsAvailable then ui.pushDisabled() end
    if ui.checkbox('DRS', car.drsActive) then controls.drs = true end
    bindingInfoTooltip('DRS', 'Click to toggle DRS')
    if not car.drsAvailable then ui.popDisabled() end
    if car.kersPresent then ui.sameLine(0, 4) end
  end

  if car.kersPresent then
    ui.button('KERS', btnAutofill)
    bindingInfoTooltip('KERS', 'Hold to activate KERS')
    local n, x = ui.itemRectMin(), ui.itemRectMax():sub(2)
    n.x, n.y = n.x + 2, x.y
    ui.drawLine(n, x, rgbm.colors.black)
    x.x = math.lerp(n.x, x.x, car.kersCharge)
    ui.drawLine(n, x, rgbm.colors.cyan)
    controls.kers = ui.itemActive() and ac.CarControlsInput.Flag.Enable or ac.CarControlsInput.Flag.Skip
  end

  if car.hasCockpitMGUHMode then
    if ui.checkbox('MGU-H charging', car.mguhChargingBatteries) then
      ac.setMGUHCharging(not car.mguhChargingBatteries)
    end
    bindingInfoTooltip('MGUH_MODE', 'Change between battery and motor modes')
    
    ui.pushFont(ui.Font.Small)
    ui.pushStyleVar(ui.StyleVar.FramePadding, vec2(0, 5))
    ui.setNextItemWidth(-0.1)    
    local value = ui.slider('##md', car.mgukDelivery + 1, 1, car.mgukDeliveryCount, 
      'MGU-K delivery: %s' % ac.getMGUKDeliveryName(0, car.mgukDelivery))
    if ui.itemEdited() then ac.setMGUKDelivery(value - 1) end
    bindingInfoTooltip('Next: MGUK_DELIVERY_UP; Previous: MGUK_DELIVERY_DN', 'Change MGU-K delivery mode')

    ui.setNextItemWidth(-0.1)    
    local value = ui.slider('##mr', car.mgukRecovery, 0, 10, 'MGU-K recovery: %.0f/10')
    if ui.itemEdited() then ac.setMGUKRecovery(value) end
    bindingInfoTooltip('Next: MGUK_RECOVERY_UP; Previous: MGUK_RECOVERY_DN', 'Change MGU-K recovery intensity')
    ui.popFont()
    ui.popStyleVar()
  end

  if weightShift then
    local current = -weightShift.input
    if math.abs(shiftAngle - current) > 0.01 then
      shiftAngle = current
      shiftIcon:clear(rgbm.colors.transparent):update(function (dt)
        ui.beginRotation()
        ui.setShadingOffset(1, 1, 1, 0)
        ui.image(ui.Icons.Driver, ui.windowSize())
        ui.resetShadingOffset()
        ui.endRotation(90 + shiftAngle * 60)
      end)
    end

    ui.setNextItemWidth(-0.1)
    ui.setNextItemIcon(shiftIcon)
    if math.abs(current) < 0.001 then current = 0 end
    local value = ui.slider('##weight', current * 1e3, -weightShift.range * 1e3, weightShift.range * 1e3, 'Shift: %.0f mm') / 1e3
    if not ui.itemEdited() and not ui.itemActive() then
      if ui.itemClicked(ui.MouseButton.Right) then
        shiftLocked = 0
      end
      value = shiftLocked
    elseif ui.mouseClicked(ui.MouseButton.Right) then
      shiftLocked = value
    end
    bindingInfoTooltip('Left: __EXT_DRIVER_SHIFT_LEFT; Right: __EXT_DRIVER_SHIFT_RIGHT', 'Shift driver weight left or right')
    shiftApplied = math.applyLag(shiftApplied, -value, 0.8, ui.deltaTime())
    if math.abs(shiftApplied) > 0.001 then
      weightShift.input = shiftApplied
    end
  end
end

local lastCarCamera = ac.CameraMode.Cockpit

local function selectNextDriveableCamera()
  if sim.cameraMode == ac.CameraMode.Cockpit then
    ac.setCurrentCamera(ac.CameraMode.Drivable)
    ac.setCurrentDrivableCamera(ac.DrivableCamera.Chase)
  elseif sim.cameraMode ~= ac.CameraMode.Drivable or sim.driveableCameraMode == ac.DrivableCamera.Dash then
    ac.setCurrentCamera(ac.CameraMode.Cockpit)
  else
    ac.setCurrentDrivableCamera((sim.driveableCameraMode + 1) % 5)
  end
end

local function blockView()
  ui.pushStyleVar(ui.StyleVar.FramePadding, vec2(0, 4))
  local w2 = (ui.availableSpaceX() - 4) / 2
  local w3 = (ui.availableSpaceX() - 8) / 3

  ui.setNextItemIcon(ui.Icons.VideoCamera)
  if ui.button('Camera', vec2(-22 * 3 - 4 * 3, 0), BTN_F0) then
    if controls:active() then
      controls.changeCamera = true
    else
      selectNextDriveableCamera()
    end
  end
  bindingInfoTooltip('F1$', 'Switch to the next driving camera')

  if sim.cameraMode == ac.CameraMode.Cockpit or sim.cameraMode == ac.CameraMode.Drivable then
    lastCarCamera = sim.cameraMode
  else
    ui.pushDisabled()
  end

  -- ui.popDisabled()

  if not controls:active() then ui.pushDisabled() end
  ui.sameLine(0, 4)
  ui.iconButton(ui.Icons.ArrowLeft, 22, 4, true)
  bindingInfoTooltip('GLANCELEFT', 'Hold to glance left')
  controls.lookLeft = ui.itemActive()
  ui.sameLine(0, 4)
  ui.iconButton(ui.Icons.ArrowDown, 22, 4, true)
  bindingInfoTooltip('GLANCEBACK', 'Hold to glance back')
  controls.lookBack = ui.itemActive()
  ui.sameLine(0, 4)
  ui.iconButton(ui.Icons.ArrowRight, 22, 4, true)
  bindingInfoTooltip('GLANCERIGHT', 'Hold to glance right')
  controls.lookRight = ui.itemActive()
  if not controls:active() then ui.popDisabled() end

  if sim.cameraMode ~= ac.CameraMode.Cockpit and sim.cameraMode ~= ac.CameraMode.Drivable then
    ui.popDisabled()
  end

  if ui.button('Free', vec2(w3, 0), BTN_FN(sim.cameraMode == ac.CameraMode.Free)) then 
    if sim.cameraMode == ac.CameraMode.Free then
      ac.setCurrentCamera(lastCarCamera) 
    else
      ac.setCurrentCamera(ac.CameraMode.Free) 
    end
  end
  bindingInfoTooltip('F7 (if enabled in AC system settings)$',
    'Enable free camera (use right mouse button to look around, arrows to move the camera, hold Control and Shift to alter camera speed)')
  ui.sameLine(0, 4)
  if ui.button(sim.orbitOnboardCamera and 'Orbit' or 'Onboard', vec2(w3, 0), BTN_FN(sim.cameraMode == ac.CameraMode.OnBoardFree)) then
    if sim.cameraMode == ac.CameraMode.OnBoardFree then
      ac.setOrbitOnboardCamera(not sim.orbitOnboardCamera)
    else
      ac.setCurrentCamera(ac.CameraMode.OnBoardFree)
    end
  end
  bindingInfoTooltip('F5$', 'Fixed camera moving relative to the car, either in orbit or free mode')
  ui.sameLine(0, 4)
  if ui.button('Car', vec2(w3, 0), BTN_FN(sim.cameraMode == ac.CameraMode.Car)) then 
    if sim.cameraMode == ac.CameraMode.Car then
      ac.setCurrentCarCamera((sim.carCameraIndex + 1) % 6)
    else
      ac.setCurrentCamera(ac.CameraMode.Car) 
    end
  end
  bindingInfoTooltip('F6$', 'A few custom preconfigured cameras positioned relative to the car')
  if sim.isVRConnected then
    ui.button('Reset VR', btnAutofill)
    if ui.itemActive() then ac.resetVRPose() end
    bindingInfoTooltip('Ctrl+Space$', 'Reset VR orientation')
  end
  ui.popStyleVar()
end

local function blockCars()
  local w3 = (ui.availableSpaceX() - 8) / 3
  ui.pushFont(ui.Font.Small)
  ui.pushStyleVar(ui.StyleVar.FramePadding, vec2(0, 4))
  if ui.button('Previous', vec2(w3, 0), BTN_F0) then
    ac.trySimKeyPressCommand('Previous Car')
  end
  bindingInfoTooltip('PREVIOUS_CAR!', 'Focus on the previous car in the list')
  ui.sameLine(0, 4)
  if ui.button('Own', vec2(w3, 0), BTN_F0) then
    ac.trySimKeyPressCommand('Player Car')
  end
  bindingInfoTooltip('PLAYER_CAR!', 'Focus on your car')
  ui.sameLine(0, 4)
  if ui.button('Next', vec2(w3, 0), BTN_F0) then
    ac.trySimKeyPressCommand('Next Car')
  end
  bindingInfoTooltip('NEXT_CAR!', 'Focus on the next car in the list')
  ui.popFont()
  ui.popStyleVar()
  ui.childWindow('cars', vec2(-0.1, 80), function ()
    for i = 0, sim.carsCount - 1 do
      ui.pushID(i)
      ui.pushStyleColor(ui.StyleColor.Text, ac.DriverTags(ac.getDriverName(i)).color)
      if ui.selectable(string.format(' %d. %s', i + 1, ac.getDriverName(i)), sim.focusedCar == i) then
        ac.focusCar(i)
      end
      ui.popID()
      ui.popStyleColor()
    end
  end)
end

local function blockReplay()
  if ui.button('Previous lap', btnAutofill, BTN_F0) then
    ac.trySimKeyPressCommand('Previous Lap')
  end
  bindingInfoTooltip('PREVIOUS_LAP!', 'Rewind to the previous lap')
  if ui.button('Next lap', btnAutofill, BTN_F0) then
    ac.trySimKeyPressCommand('Next Lap')
  end
  bindingInfoTooltip('NEXT_LAP!', 'Rewind to the next lap')
end

local autopilot = 0

local function blockMiscellaneous()
  local w2 = (ui.availableSpaceX() - 4) / 2
  if ui.button('Save clip', vec2(w2, 0), BTN_F0) then
    ac.simulateCustomHotkeyPress('__EXT_SAVE_CLIP')
  end
  bindingInfoTooltip('__EXT_SAVE_CLIP', 'Save last 30 seconds in a separate replay clip')
  ui.sameLine(0, 4)

  ui.setNextItemWidth(-0.1)
  local value = ui.slider('##ffb', car.ffbMultiplier * 100, 0, 200, 'FFB: %.0f%%') / 100
  if ui.itemEdited() then
    ac.setFFBMultiplier(value)
    ac.setMessage(string.format('User level for %s: %.0f%%', ac.getCarName(0, true), value * 100), 'Force Feedback')
  end
  bindingInfoTooltip('Increase: __EXT_FFB_INCREASE; Reduce: __EXT_FFB_DECREASE', 'Alter FFB intensity')

  ui.pushFont(ui.Font.Small)
  ui.setNextItemWidth(w2)
  if ui.checkbox('Damage', sim.damageDisplayerShown) then ac.trySimKeyPressCommand('Hide Damage') end
  bindingInfoTooltip('HIDE_DAMAGE!', 'Damage displayer showing state of the car')

  local boardParams = ac.accessOverlayLeaderboardParams()
  if boardParams then
    ui.sameLine(0, 4)
    ui.setNextItemWidth(-0.1)
    local boardOldValue = boardParams.displayMode + (boardParams.verticalLayout and 3 or 0)
    local boardValue = ui.slider('##leaderboard', boardOldValue, 0, 6, 'Board: %.0f/6')
    if boardValue ~= boardOldValue then
      boardParams.verticalLayout = boardValue > 3
      boardParams.displayMode = boardValue > 3 and boardValue - 3 or boardValue
      ac.setMessage('Overlay Leaderboard', ({'Off', 'Showing difference from first', 'Showing difference from previous', 'Alternate mode'})
        [boardParams.displayMode + 1])
    end
    bindingInfoTooltip('F9$', 'Current overlay leaderboard mode')
  end

  ui.setNextItemWidth(w2)
  if ui.checkbox('Names', sim.driverNamesShown) then ac.trySimKeyPressCommand('Driver Names') end
  bindingInfoTooltip('DRIVER_NAMES!', 'Show or hide driver names')
  ui.sameLine(0, 4)
  ui.setNextItemWidth(-0.1)
  if ui.checkbox('Ideal line', sim.idealLineShown) then ac.trySimKeyPressCommand('Ideal Line') end
  bindingInfoTooltip('IDEAL_LINE!', 'Show ideal trajectory')

  ui.setNextItemWidth(w2)
  if ui.checkbox('Auto shift', car.autoShift) then ac.trySimKeyPressCommand('Auto Shifter') end
  bindingInfoTooltip('AUTO_SHIFTER!', 'Shift gears automatically (won’t be as efficient as manual shifting)')
  if not sim.isOnlineRace then
    ui.sameLine(0, 4)
    ui.setNextItemWidth(-0.1)
    if ui.checkbox('AI', car.isAIControlled and autopilot == 0) then
      if autopilot ~= 0 then
        autopilot = 0
        physics.setAITopSpeed(0, math.huge)
      end
      ac.trySimKeyPressCommand('Activate AI') 
    end
    bindingInfoTooltip('ACTIVATE_AI!', 'Use AI to drive the car (deactivating stops any inputs, restart the session to get the control back)')
  end

  ui.popFont()
end

function script.windowMain(dt)
  local f = false
  local s = ui.getCursorY()
  local notAvailable = not car.isUserControlled and autopilot == 0 or sim.isReplayActive
  if notAvailable then
    ui.pushDisabled()
  end

  if not ui.windowFocused() then
    releaseHeld()
  end
  
  if ui.windowHeight() > 320 then
    ui.header('Car')
  end

  blockCarInstruments()
  if ui.windowHeight() > 240 then
    blockCarDrive()
  else
    ui.setExtraContentMark(true)
  end
  blockCarTweaks()

  if notAvailable then
    ui.popDisabled()
    ui.drawRectFilled(vec2(ui.getCursorX() + 4, s + 20), vec2(ui.getCursorX() + ui.availableSpaceX() - 4, ui.getCursorY() - 20), 
      rgbm(0.1, 0.1, 0.1, 0.8), 4)
    ui.drawTextClipped(sim.isReplayActive and 'Not available in replay' or 'Can’t control the car', vec2(ui.getCursorX() + 8, s + 8), vec2(ui.getCursorX() + ui.availableSpaceX() - 8, ui.getCursorY() - 8), rgbm.colors.white, 0.5)

    if not sim.isReplayActive and not sim.isOnlineRace then
      local c = ui.getCursor()
      ui.setCursor(vec2(c.x + ui.availableSpaceX() / 2 - 60, (c.y + s) / 2 + 20))
      ui.pushFont(ui.Font.Small)
      ui.setNextItemIcon(ui.Icons.Restart)
      if ui.button('Restart session', vec2(120, 0)) then
        ac.tryToRestartSession()
      end
      bindingInfoTooltip('__CM_RESET_SESSION', 'Restart session restoring car controls')
      ui.popFont()
      ui.setCursor(c)
    end
  end

  if ui.windowHeight() > 320 then
    ui.offsetCursorY(12)
    ui.header('Camera')
    blockView()
  
    if ui.availableSpaceY() > 20 then
      if sim.isReplayActive then
        ui.offsetCursorY(12)
        ui.header('Replay')
        blockReplay()
      else
        ui.offsetCursorY(12)
        ui.header('Race')
        blockMiscellaneous()
      end
  
      if sim.carsCount > 1 then
        if ui.availableSpaceY() > 20 then
          f = true
          ui.offsetCursorY(12)
          ui.header('Cars')
          blockCars()
        end
      else
        f = true
      end
    end
  end

  -- if ac.isCarResetAllowed() then
  --   ui.offsetCursorY(12)
  --   ui.header('Autopilot')
  --   ui.setNextItemWidth(-0.1  )
  --   autopilot = ui.slider('##ai', autopilot, 0, 300, 'Limit: %.0f km/h')
  --   if ui.itemEdited() then
  --     physics.setAITopSpeed(0, autopilot == 0 and math.huge or autopilot)
  --     physics.setCarAutopilot(autopilot > 0, false)
  --   elseif ui.itemActive() and autopilot == 0 then
  --     physics.forceUserBrakesFor(0.1, 1)
  --   elseif not car.isAIControlled then
  --     autopilot = 0
  --     physics.setAITopSpeed(0, math.huge)
  --   end
  -- end

  if not f then
    ui.setExtraContentMark(true)
  end

  if not ui.windowResizing() then
    local h = ui.getCursorY() + 16
    ac.setWindowSizeConstraints('main', vec2(200, h), vec2(200, h))
  else
    ac.setWindowSizeConstraints('main', vec2(200, 80), vec2(200, 2000))
  end
end
