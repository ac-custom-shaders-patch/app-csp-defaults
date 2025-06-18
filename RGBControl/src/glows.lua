local registerGlow = require('src/glow').registerGlow
local sim = ac.getSim()
local data = require('src/data')
local Utils = require('src/utils')

local colorBlack = rgb(0.1, 0.1, 0.1)
registerGlow(
  {
    name = 'Race flags',
    description = 'Reacts to yellow (caution), blue (faster car behind) or black (penalty) race flags',
    condition = 'race flag'
  },
  { yellow = true, blue = true, black = true, start = true, finish = true }, function(cfg)
    if ui.checkbox('Starting lights', cfg.start) then cfg.start = not cfg.start end
    if ui.checkbox('Yellow flag (caution)', cfg.yellow) then cfg.yellow = not cfg.yellow end
    if ui.checkbox('Blue flag (faster car behind)', cfg.blue) then cfg.blue = not cfg.blue end
    if ui.checkbox('Black flag (penalty)', cfg.black) then cfg.black = not cfg.black end
    if ui.checkbox('Session is finished', cfg.finish) then cfg.finish = not cfg.finish end
  end, function(cfg, info)
    if cfg.yellow and sim.raceFlagType == ac.FlagType.Caution then return rgb.colors.yellow end
    if cfg.blue and sim.raceFlagType == ac.FlagType.FasterCar then return rgb.colors.blue end
    if cfg.black and sim.raceFlagType == ac.FlagType.Stop then return colorBlack end
    if cfg.start and sim.timeToSessionStart > -1e3 then
      if sim.timeToSessionStart > 0 then
        return sim.timeToSessionStart < 6.7e3 and rgb.colors.red or rgb.colors.black
      else
        return os.preciseClock() * 3 % 1 > 0.5 and rgb.colors.green or rgb.colors.black
      end
    end
    if cfg.finish and info.state.isRaceFinished then
      return info.state.racePosition == 1
          and hsv(os.preciseClock() % 1 * 360, 1, 1):rgb()
          or rgb.new(math.abs(1 - 2 * (os.preciseClock() % 1)))
    end
  end)

registerGlow({
    name = 'Car features',
    description = 'Shows rare car states, such as reverse lights or hazards',
    condition = 'reverse, hazards, turning lights, horn or flames'
  },
  { horn = true, flames = true }, function(cfg)
    if ui.checkbox('Horn', cfg.horn) then cfg.horn = not cfg.horn end
    if ui.checkbox('Flames', cfg.flames) then cfg.flames = not cfg.flames end
  end, function(cfg, info)
    if info.state.anyFlamesActive and cfg.flames then return rgb.colors.yellow end
    if info.state.hornActive and cfg.horn then return rgb(1, 0.5, 0.5) end
    local damaged = info.state.engineLifeLeft < 1
    if damaged or info.state.turningLeftLights or info.state.turningRightLights then
      if not info.state.turningLightsActivePhase then return rgb.colors.black end
      if info.state.hazardLights or damaged then return rgb.colors.orange end
      if info.state.turningLeftLights then return rgb.colors.black, rgb.colors.orange, rgb.colors.black end
      if info.state.turningRightLights then return rgb.colors.black, rgb.colors.black, rgb.colors.orange end
    end
    if info.state.gear < 0 then return rgb.colors.white end
  end)

registerGlow(
  { name = 'RPM', description = 'RPM lights', condition = 'RPM above downshift threshold' },
  { smooth = false }, function(cfg)
    if ui.checkbox('Smooth colors', cfg.smooth) then cfg.smooth = not cfg.smooth end
  end, function(cfg, info)
    local rpm = math.lerpInvSat(info.state.rpm, info.rpmDown, info.rpmUp)
    if rpm <= 0 then return nil end
    if rpm > 0.9 and (os.preciseClock() * 3 % 1 > 0.5) then return rgb.colors.black, nil, nil, 0 end
    local mix = math.saturateN(rpm * 2 + 1)
    if mix <= 0 then return nil end
    local colorShifting = cfg.smooth
        and hsv(90 * math.saturateN(1 - rpm), 1, 1):rgb()
        or (rpm > 0.6 and rgb.colors.red or rpm > 0.2 and rgb.colors.yellow or rgb.colors.lime)
    return colorShifting, nil, nil, rpm
  end)

local perfGradient = { rgb(1, 0, 0), rgb(1, 1, 1), rgb(0.5, 1, 0.5) }
registerGlow(
  {
    name = 'Performance meter',
    description = 'Greener if your lap time is better than before, redder if it’s worse',
    condition = 'previous lap to compare to'
  },
  { fullSaturation = 1 }, function(cfg)
    cfg.fullSaturation = ui.slider('##0', cfg.fullSaturation, 0, 5, 'Fully saturated at: %.1f s')
  end, function(cfg, info)
    return Utils.sampleGradient(perfGradient,
      math.lerpInvSat(info.state.performanceMeter / math.max(cfg.fullSaturation, 0.001), -1, 1))
  end)

local lapsListenerSet = false
local lastLap, lastIllegal
local purple = rgb(1, 0.5, 1)
registerGlow(
  {
    name = 'Previous lap time color',
    description = 'Flashes green or purple if previous lap time is best, flashes red on lap invalidation',
    condition = 'recently completed lap'
  },
  { invalidation = true }, function(cfg)
    if ui.checkbox('Flash on invalidation', cfg.invalidation) then
      cfg.invalidation = not cfg.invalidation
    end
  end, function(cfg, info)
    if not lapsListenerSet then
      lapsListenerSet = true
      ac.onLapCompleted(0, function (carIndex, lapTime, valid)
        if valid then
          lastLap = {lapTime, os.preciseClock() + 1}
        else
          lastLap = nil
        end
      end)
      ac.onMessage(function (title, description, type, time)
        if type == 'illegal' then
          lastIllegal = os.preciseClock() + 1
        end
      end)
    end
    if lastLap and lastLap[2] > os.preciseClock() then
      if lastLap[1] == sim.bestLapTimeMs then
        return purple
      end
      if lastLap[1] == info.state.bestLapTimeMs then
        return rgb.colors.lime
      end
    end
    if lastIllegal and lastIllegal > os.preciseClock() then
      return rgb.colors.red
    end
  end)

local hitsListenerSet
local recentHit
registerGlow(
  {
    name = 'Collisions',
    description = 'Shortly flashes red on collisions',
    condition = 'recent collision'
  },
  {}, nil, function(cfg, info)
    if not hitsListenerSet then
      hitsListenerSet = true
      ac.onCarCollision(0, function ()
        recentHit = os.preciseClock() + 0.3
      end)
      ac.onMessage(function (title, description, type, time)
        if type == 'illegal' then
          lastIllegal = os.preciseClock() + 3
        end
      end)
    end
    if recentHit and recentHit > os.preciseClock() then
      return rgb.colors.red
    end
  end)

registerGlow(
  {
    name = 'Blind spot',
    description = 'Flash yellow color if there is a car in a blind spot',
    condition = 'car in blind spot'
  },
  { threshold = 20 }, function(cfg)
    cfg.threshold = ui.slider('##0', cfg.threshold, 1, 20, 'Threshold: %.0f m')
  end, function(cfg, info)
    local bl, br = ac.getCarBlindSpot(info.state.index)
    local min = math.min(bl or math.huge, br or math.huge)
    if min >= cfg.threshold then return nil end
    if os.preciseClock() * 3 % 1 > 0.5 then return rgb.colors.black end
    return rgb.colors.yellow,
        (bl or math.huge) == min and rgb.colors.orange or rgb.colors.yellow,
        (br or math.huge) == min and rgb.colors.orange or rgb.colors.yellow
  end)

registerGlow(
  {
    name = 'Conditional color',
    description = 'Color based on a single condition',
    condition = 'satisfied condition or set alternate color'
  },
  { color = rgb(1, 1, 1), color1 = nil, conds = Utils.emptyConds(), _name = 'Cond.: <not configured>' },
  function(cfg)
    Utils.colorSelector('Color', cfg.color)
    cfg.color1 = Utils.colorSelectorOpt('Alternate', cfg.color1)
    if ui.button('Condition: %s' % Utils.getConditionLabel(cfg.conds), vec2(200, 0)) then
      Utils.conditionPopupEditor(true, cfg, function (arg)
        Utils.assignCondition(cfg, arg)
        cfg._name = 'Cond.: ' .. Utils.getConditionLabel(arg.conds)
      end)
    end
    cfg.flashing = Utils.flashingOut('Flashing', cfg.flashing)
  end, function(cfg)
    if cfg.flashing and (os.preciseClock() / cfg.flashing.time % 1 > cfg.flashing.active) then
      return nil
    end
    if Utils.isConditionPassing(cfg.conds, cfg.hold, cfg.stop) then
      return cfg.color
    else
      return cfg.color1
    end
  end)

local rgb1, rgb2, rgb3 = rgb(), rgb(), rgb()
registerGlow(
  { name = 'Scene', description = 'Approximation of a scene color around the camera using reflection cubemap' },
  { saturation = 2, direction = 1, gradient = true }, function(cfg)
    cfg.saturation = ui.slider('##s', cfg.saturation * 100, 0, 300, 'Saturation: %.0f%%') / 100
    cfg.direction = select(1, ui.combo('##d', cfg.direction, ui.ComboFlags.None,
      { 'Forward', 'Backwards', 'Left', 'Right', 'Up', 'Down', 'Up (world-space)', 'Down (world-space)' }))
    if cfg.direction < 5 and ui.checkbox('Gradient', cfg.gradient) then
      cfg.gradient = not cfg.gradient
    end
  end, function(cfg)
    local scene = data.getSceneColors()
    local cm = rgb1:set(scene.scene[cfg.direction].rgb):adjustSaturation(cfg.saturation)
    if cfg.direction < 5 and cfg.gradient then
      return cm,
          rgb2:set(scene.scene[5].rgb):adjustSaturation(cfg.saturation),
          rgb3:set(scene.scene[6].rgb):adjustSaturation(cfg.saturation)
    end
    return cm
  end)

registerGlow(
  {
    name = 'Mirror',
    description = 'Approximation of a mirror color using the mirror texture',
    condition = 'mirror texture is available'
  },
  { saturation = 2, side = 0, gradient = true }, function(cfg)
    cfg.saturation = ui.slider('##s', cfg.saturation * 100, 0, 300, 'Saturation: %.0f%%') / 100
    if ui.checkbox('Gradient', cfg.gradient) then
      cfg.gradient = not cfg.gradient
    end
    if not cfg.gradient then
      cfg.side = ui.slider('##2', cfg.side, -1, 1, 'Side: %.1f')
    end
  end, function(cfg)
    if ac.getSim().closelyFocusedCar == -1 then return nil end
    local scene = data.getSceneColors()
    local cm = rgb1:set(scene.mirror[2].rgb)
    if cfg.gradient then
      return cm,
          rgb2:set(scene.mirror[1].rgb):adjustSaturation(cfg.saturation),
          rgb3:set(scene.mirror[3].rgb):adjustSaturation(cfg.saturation)
    end
    if cfg.side < -0.05 then
      cm = rgb2:setLerp(cm, scene.mirror[1].rgb, -cfg.side)
    elseif cfg.side > 0.05 then
      cm = rgb2:setLerp(cm, scene.mirror[3].rgb, cfg.side)
    end
    return cm:adjustSaturation(cfg.saturation)
  end)

registerGlow(
  { name = 'Solid color', description = 'Static solid color', condition = 'configured flashing (always on by default)' },
  { color = rgb(1, 1, 1), color1 = nil, color2 = nil }, function(cfg)
    Utils.colorSelector('Color', cfg.color)
    cfg.color1 = Utils.colorSelectorOpt('Gradient A', cfg.color1, cfg.color)
    if cfg.color1 then
      cfg.color2 = Utils.colorSelectorOpt('Gradient B', cfg.color2, cfg.color1)
    end
    cfg.flashing = Utils.flashingOut('Flashing', cfg.flashing)
  end, function(cfg)
    if cfg.flashing and (os.preciseClock() / cfg.flashing.time % 1 > cfg.flashing.active) then
      return nil
    end
    return cfg.color, cfg.color1, cfg.color2
  end)

registerGlow(
  { name = 'Shifting color', description = 'Color changing over time', condition = 'configured flashing (always on by default)' },
  { colors = { rgb(1, 1, 1), rgb(1, 0.5, 0) }, period = 1 }, function(cfg)
    Utils.gradientEditor('Colors', cfg.colors)
    ui.setNextItemWidth(260)
    cfg.period = ui.slider('##0', cfg.period, 0.1, 30, 'Period: %.1f s')
    cfg.flashing = Utils.flashingOut('Flashing', cfg.flashing)
  end, function(cfg)
    if cfg.flashing and (os.preciseClock() / cfg.flashing.time % 1 > cfg.flashing.active) then
      return nil
    end
    return Utils.sampleGradient(cfg.colors, os.preciseClock() / math.max(cfg.period, 0.1) % 1, true)
  end)

registerGlow(
  { name = 'Session color', description = 'Different colors depending on the session type' },
  {
    practice = rgb.from0255(22, 198, 12),
    qualifying = rgb.from0255(136, 108, 228),
    race = rgb.from0255(232, 18, 36),
    other = rgb.from0255(255, 255, 255)
  }, function(cfg)
    Utils.colorSelector('Practice', cfg.practice)
    Utils.colorSelector('Qualifying', cfg.qualifying)
    Utils.colorSelector('Race', cfg.race)
    cfg.other = Utils.colorSelectorOpt('Other', cfg.other)
  end, function(cfg)
    local t = sim.raceSessionType
    if t == ac.SessionType.Practice then return cfg.practice end
    if t == ac.SessionType.Qualify then return cfg.qualifying end
    if t == ac.SessionType.Race then return cfg.race end
    return cfg.other
  end)

registerGlow(
  {
    name = 'Livery color',
    description = 'Color from car livery',
    condition = 'there is a focused car nearby, or it’s a track camera view (optionally)'
  },
  { trackCamera = false }, function(cfg)
    if ui.checkbox('Active with track camera', cfg.trackCamera) then
      cfg.trackCamera = not cfg.trackCamera
    end
  end, function(cfg, info)
    local i = sim.closelyFocusedCar
    if i == -1 and cfg.trackCamera and sim.cameraMode == ac.CameraMode.Track then
      i = sim.focusedCar
    end
    return data.getCarColor(i)
  end)

registerGlow({ name = 'Track progress', description = 'Changes between two or more colors based on track progress' },
  { colors = { rgb(0, 0, 0.5), rgb(1, 0.8, 0) }, max = 5 }, function(cfg)
    Utils.gradientEditor('Colors', cfg.colors)
  end, function(cfg, info)
    local normalized = info.state.splinePosition
    return Utils.sampleGradient(cfg.colors, normalized), nil, nil, normalized
  end)

registerGlow({ name = 'Lateral G-force', description = 'Changes between two or more colors based on lateral G-force' },
  { colors = { rgb(0, 0, 0.5), rgb(1, 0.8, 0) }, max = 5 }, function(cfg)
    Utils.gradientEditor('Colors', cfg.colors)
    cfg.max = ui.slider('##1', cfg.max, 1, 10, 'Maximum: %.0f G')
  end, function(cfg, info)
    local normalized = math.lerpInvSat(math.abs(info.state.acceleration.x), 0, cfg.max)
    return Utils.sampleGradient(cfg.colors, normalized), nil, nil, normalized
  end)

registerGlow(
  { name = 'Longitudinal G-force', description = 'Changes between two or more colors based on longitudinal G-force' },
  { colors = { rgb(0, 0, 0.5), rgb(1, 0.8, 0) }, max = 5 }, function(cfg)
    Utils.gradientEditor('Colors', cfg.colors)
    cfg.max = ui.slider('##1', cfg.max, 1, 10, 'Maximum: %.0f G')
  end, function(cfg, info)
    local normalized = math.lerpInvSat(math.abs(info.state.acceleration.z), 0, cfg.max)
    return Utils.sampleGradient(cfg.colors, normalized), nil, nil, normalized
  end)

local peakMaxAvg, peakUpdated = 0.5, -1
registerGlow({ name = 'Audio response', description = 'Changes between two or more colors based on audio peak' },
  { colors = { rgb(0, 0.5, 1), rgb(1, 0.5, 0) } }, function(cfg)
    Utils.gradientEditor('Colors', cfg.colors)
  end, function(cfg, info)
    local peak = ac.mediaCurrentPeak()
    local peakMax = math.max(peak.x, peak.y)
    if peakUpdated ~= sim.frame then
      peakUpdated = sim.frame
      peakMaxAvg = math.applyLag(peakMaxAvg, peakMax, peakMax > peakMaxAvg and 0.8 or 0.9995, ac.getDeltaT())
    end
    local normalized = math.lerpInvSat(peakMax, 0, peakMaxAvg)
    return Utils.sampleGradient(cfg.colors, normalized),
        Utils.sampleGradient(cfg.colors, math.lerpInvSat(peak.x, 0, peakMaxAvg)),
        Utils.sampleGradient(cfg.colors, math.lerpInvSat(peak.y, 0, peakMaxAvg)),
        normalized
  end)

registerGlow({ name = 'Sun height', description = 'Changes between two or more colors based on sun height' },
  { colors = { rgb(0, 0, 0.5), rgb(1, 0.8, 0) } }, function(cfg)
    Utils.gradientEditor('Colors', cfg.colors)
  end, function(cfg, info)
    local normalized = math.max(1 - ac.getSunAngle() / 90, 0)
    return Utils.sampleGradient(cfg.colors, normalized), nil, nil, normalized
  end)

registerGlow(
  { name = 'Ambient temperature', description = 'Changes between two or more colors based on ambient temperature' },
  { colors = { rgb(0, 0, 0.5), rgb(1, 0.8, 0) }, min = 0, max = 30 }, function(cfg)
    Utils.gradientEditor('Colors', cfg.colors)
    cfg.min = ui.slider('##0', cfg.min, 0, cfg.max, 'Minimum: %.0f °C')
    cfg.max = ui.slider('##1', cfg.max, cfg.min, 50, 'Maximum: %.0f °C')
  end, function(cfg, info)
    local normalized = math.lerpInvSat(sim.ambientTemperature, cfg.min, cfg.max)
    return Utils.sampleGradient(cfg.colors, normalized), nil, nil, normalized
  end)
