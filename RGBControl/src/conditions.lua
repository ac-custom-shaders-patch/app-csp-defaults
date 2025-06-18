local registerCondition = require('src/glow').registerCondition
local sim = ac.getSim()
local data = require('src/data')

local function combo(values, cfg, key)
  key = key or 'target'
  ui.combo('##'..key, values[cfg[key]], function ()
    local sorted = table.map(values, function (item, index) return {index, item} end)
    table.sort(sorted, function (a, b) return a[1] > b[1] end)
    for _, v in ipairs(sorted) do
      if ui.selectable(v[2], v[1] == cfg[key]) then
        cfg[key] = v[1]
      end
    end
  end)
end

local cmpE = {'<', '≤', '=', '≥', '>'}
local cmpV = {'<', '≤', '≈', '≥', '>'}

local function roughlySame(v1, v2)
  return math.floor(v1 + 0.5) == math.floor(v2 + 0.5)
end

---@generic T : {cmp: integer, value: number}
---@param attributes GlowAttributes
---@param slider {mult: number, add: number, min: number, max: number, label: string, format: string, formatMap: table<integer, string>, exact: boolean, settings: fun(cfg: T)}
---@param defaults T
---@param accessor fun(cfg: T, info: CarInfo): number, nil|boolean|number
local function registerNumerical(attributes, slider, defaults, accessor)
  attributes.description = '%s is above or below (configurable) of given threshold' % attributes.description
  local cmpT = slider.exact and cmpE or cmpV
  slider = table.assign({ mult = 1, add = 0, label = 'Value', format = '%.0f', min = 0, max = 100 }, slider)
  registerCondition(attributes, table.assign({ cmp = 4, value = 0 }, defaults),
  function (cfg)
    ui.setNextItemWidth(40)
    ui.combo('##a', cmpT[cfg.cmp], function ()
      for i = 1, #cmpT do
        if ui.selectable(cmpT[i], i == cfg.cmp) then cfg.cmp = i end
      end
    end)
    ui.sameLine(0, 0)
    ui.setNextItemWidth(120)
    local mapped = slider.formatMap and slider.formatMap[math.round(cfg.value)]
    cfg.value = ui.slider('##l', cfg.value or 0, slider.min, slider.max, mapped
      and string.format('%s: %s', slider.label, mapped)  
      or string.format('%s: %s', slider.label, slider.format))
    if slider.settings then
      slider.settings(cfg)
    end
  end,
  function (cfg, info)
    local c1, c2 = accessor(cfg, info)
    local actualV, targetV = c1 * slider.mult + slider.add, cfg.value or 0
    if c2 and slider.max == targetV and slider.formatMap[math.round(targetV)] then targetV = type(c2) == 'number' and c2 or actualV end
    if cfg.cmp == 1 then return actualV < targetV end
    if cfg.cmp == 2 then return actualV <= targetV or roughlySame(actualV, targetV) end
    if cfg.cmp == 4 then return actualV >= targetV or roughlySame(actualV, targetV) end
    if cfg.cmp == 5 then return actualV > targetV end
    return roughlySame(actualV, targetV)
  end,
  function (cfg)
    local mapped = slider.formatMap and slider.formatMap[math.round(cfg.value)]
    return string.format('%s %s', cmpT[cfg.cmp], mapped or slider.format % (cfg.value or 0))
  end)
end

-- Game switches

local inputMethods = {
  [ac.UserInputMode.Wheel] = 'wheel',
  [ac.UserInputMode.Gamepad] = 'gamepad',
  [ac.UserInputMode.Keyboard] = 'keyboard',
}
registerCondition({ key = 'online', group = 'Game', name = 'online race', description = 'Current session is an online race' },
  {}, nil, function () return sim.isOnlineRace end)
registerCondition({ key = 'replay', group = 'Game', name = 'replay is playing', description = 'Currently, playing replay' },
  {}, nil, function () return sim.isReplayActive end)
registerCondition({ key = 'mainMenu', group = 'Game', name = 'in main menu', description = 'Main menu is opened' },
  {}, nil, function () return sim.isInMainMenu end)
registerCondition({ key = 'paused', group = 'Game', name = 'paused', description = 'Game is paused' },
  {}, nil, function () return sim.isPaused end)
registerCondition({ key = 'results', group = 'Game', name = 'viewing results', description = 'Session is finished, results are shown' },
  {}, nil, function () return sim.isLookingAtSessionResults end)
registerCondition({ key = 'input', group = 'Game', name = 'input method is…', description = 'Current input method' },
  { target = ac.UserInputMode.Wheel }, function (cfg) combo(inputMethods, cfg) end,
  function (cfg) print(sim.inputMode) return sim.inputMode == cfg.target end, function (cfg) return inputMethods[cfg.target] end)
registerCondition({ key = 'mouseSteering', group = 'Game', name = 'mouse steering', description = 'Mouse steering is active' },
  {}, nil, function () return sim.isMouseSteeringActive end)
registerNumerical({ key = 'ping', group = 'Game', name = 'ping…', description = 'Your ping' },
  { label = 'Ping', format = '%.0f ms', max = 100 }, {}, function (cfg, info) return info.state.ping end)
registerCondition({ key = 'chat', group = 'Game', name = 'unread chat messages', description = 'Triggers if there are any unread chat messages' },
  {}, nil, function () return ac.getUnreadChatMessages() > 0 end)

-- Session switches

local sessionTypes = {
  [ac.SessionType.Practice] = 'practice',
  [ac.SessionType.Qualify] = 'qualifying',
  [ac.SessionType.Race] = 'race',
  [ac.SessionType.Hotlap] = 'hotlap',
  [ac.SessionType.TimeAttack] = 'time attack',
  [ac.SessionType.Drift] = 'drift',
  [ac.SessionType.Drag] = 'drag',
  [ac.SessionType.Undefined] = 'unknown',
}
local flagTypes = {
  [ac.FlagType.None] = 'none',
  [ac.FlagType.Start] = 'start',
  [ac.FlagType.Caution] = 'caution',
  [ac.FlagType.Slippery] = 'slippery',
  [ac.FlagType.PitLaneClosed] = 'pitlane closed',
  [ac.FlagType.Stop] = 'stop',
  [ac.FlagType.SlowVehicle] = 'slow vehicle',
  [ac.FlagType.Ambulance] = 'ambulance',
  [ac.FlagType.ReturnToPits] = 'return-to-pits',
  [ac.FlagType.MechanicalFailure] = 'mechanical failure',
  [ac.FlagType.Unsportsmanlike] = 'unsportsmanlike',
  [ac.FlagType.StopCancel] = 'stop-cancel',
  [ac.FlagType.FasterCar] = 'faster car',
  [ac.FlagType.Finished] = 'finished',
  [ac.FlagType.OneLapLeft] = 'one-lap-left',
  [ac.FlagType.SessionSuspended] = 'session suspended',
  [ac.FlagType.Code60] = 'code 60',
}
registerCondition({ key = 'session', group = 'Session', name = 'session is…', description = 'Type of current session' },
  { target = ac.SessionType.Race }, function (cfg) combo(sessionTypes, cfg) end,
  function (cfg) return sim.raceSessionType == cfg.target end, function (cfg) return sessionTypes[cfg.target] end)
registerCondition({ key = 'started', group = 'Session', name = 'session is started', description = 'Current session has started' },
  {}, nil, function () return sim.isSessionStarted end)
registerCondition({ key = 'ended', group = 'Session', name = 'session is finished', description = 'Current session has ended' },
  {}, nil, function () return sim.isSessionFinished end)
registerCondition({ key = 'flag', group = 'Session', name = 'race flag is…', description = 'Type of current race flag' },
  { target = ac.FlagType.FasterCar }, function (cfg) combo(flagTypes, cfg) end,
  function (cfg) return sim.raceFlagType == cfg.target end, function (cfg) return flagTypes[cfg.target] end)
registerNumerical({ key = 'timeToStart', group = 'Session', name = 'time to start…', description = 'Time to session start' },
  { label = 'Time', format = '%.1f s', max = 60 }, { value = 5 }, function () return math.max(0, sim.timeToSessionStart / 1e3) end)
registerNumerical({ key = 'timeSinceStart', group = 'Session', name = 'time since start…', description = 'Time since session start' },
  { label = 'Time', format = '%.1f s', max = 60 }, { value = 5 }, function () return math.max(0, -sim.timeToSessionStart / 1e3) end)
registerNumerical({ key = 'timeToEnd', group = 'Session', name = 'time to end…', description = 'Time to session end' },
  { label = 'Time', format = '%.1f s', max = 60 }, { value = 5 }, function () return math.max(0, sim.sessionTimeLeft / 1e3) end)

-- Condition switches

local weatherTypes = {
  [ac.WeatherType.LightThunderstorm] = 'thunderstorm (light)',
  [ac.WeatherType.Thunderstorm] = 'thunderstorm',
  [ac.WeatherType.HeavyThunderstorm] = 'thunderstorm (heavy)',
  [ac.WeatherType.LightDrizzle] = 'drizzle (light)',
  [ac.WeatherType.Drizzle] = 'drizzle',
  [ac.WeatherType.HeavyDrizzle] = 'drizzle (heavy)',
  [ac.WeatherType.LightRain] = 'rain (light)',
  [ac.WeatherType.Rain] = 'rain',
  [ac.WeatherType.HeavyRain] = 'rain (heavy)',
  [ac.WeatherType.LightSnow] = 'snow (light)',
  [ac.WeatherType.Snow] = 'snow',
  [ac.WeatherType.HeavySnow] = 'snow (heavy)',
  [ac.WeatherType.LightSleet] = 'sleet (light)',
  [ac.WeatherType.Sleet] = 'sleet',
  [ac.WeatherType.HeavySleet] = 'sleet (heavy)',
  [ac.WeatherType.Clear] = 'clear',
  [ac.WeatherType.FewClouds] = 'few clouds',
  [ac.WeatherType.ScatteredClouds] = 'scattered clouds',
  [ac.WeatherType.BrokenClouds] = 'broken clouds',
  [ac.WeatherType.OvercastClouds] = 'overcast clouds',
  [ac.WeatherType.Fog] = 'fog',
  [ac.WeatherType.Mist] = 'mist',
  [ac.WeatherType.Smoke] = 'smoke',
  [ac.WeatherType.Haze] = 'haze',
  [ac.WeatherType.Sand] = 'sand',
  [ac.WeatherType.Dust] = 'dust',
  [ac.WeatherType.Squalls] = 'squalls',
  [ac.WeatherType.Tornado] = 'tornado',
  [ac.WeatherType.Hurricane] = 'hurricane',
  [ac.WeatherType.Cold] = 'cold',
  [ac.WeatherType.Hot] = 'hot',
  [ac.WeatherType.Windy] = 'windy',
  [ac.WeatherType.Hail] = 'hail',
}
registerCondition({ key = 'weather', group = 'Conditions', name = 'weather is…', description = 'Type of current weather' },
  { target = ac.WeatherType.Clear }, function (cfg) combo(weatherTypes, cfg) end,
  function (cfg) return sim.weatherType == cfg.target end, function (cfg) return weatherTypes[cfg.target] end)
registerNumerical({ key = 'rain', group = 'Conditions', name = 'rain…', description = 'Rain intensity' },
  { label = 'Rain', format = '%.0f', mult = 100 }, {}, function () return sim.rainIntensity end)
registerNumerical({ key = 'wetness', group = 'Conditions', name = 'wetness…', description = 'Track wetness' },
  { label = 'Wetness', format = '%.0f', mult = 100 }, {}, function () return sim.rainWetness end)
registerNumerical({ key = 'water', group = 'Conditions', name = 'water…', description = 'Puddles on a track' },
  { label = 'Water', format = '%.0f', mult = 100 }, {}, function () return sim.rainWater end)

-- View switches

registerCondition({ key = 'vr', group = 'View', name = 'in VR', description = 'Using VR for rendering' },
  {}, nil, function () return sim.isVRMode end)
registerCondition({ key = 'interior', group = 'View', name = 'inside', description = 'Camera is currently inside the car' },
  {}, nil, function () return sim.isFocusedOnInterior end)
registerCondition({ key = 'focusedcar', group = 'View', name = 'focused car present', description = 'There is a focused car nearby, inactive with track cameras' },
  {}, nil, function () return sim.closelyFocusedCar ~= -1 end)

local cameraModes = {
  [ac.CameraMode.Cockpit] = 'first person view',
  [ac.CameraMode.Drivable] = 'drivable camera',
  [ac.CameraMode.OnBoardFree] = 'F5 camera',
  [ac.CameraMode.Car] = 'F6 camera',
  [ac.CameraMode.Track] = 'track camera',
  [ac.CameraMode.Free] = 'free camera',
  [ac.CameraMode.Start] = 'start camera',
}
registerCondition({ key = 'camera', group = 'View', name = 'camera is…', description = 'Current camera mode matches target mode' },
  { target = ac.CameraMode.Cockpit }, function (cfg) combo(cameraModes, cfg) end,
  function (cfg) return sim.cameraMode == cfg.target end, function (cfg) return cameraModes[cfg.target] end)

-- Car switches

local helperState = {
  [1] = 'present',
  [2] = 'enabled',
  [3] = 'present and disabled',
  [4] = 'working',
}
local drsState = {
  [1] = 'present',
  [2] = 'present and available',
  [3] = 'present and not available',
  [4] = 'active',
}
registerCondition({ key = 'pitstop', group = 'Car', name = 'in pits', description = 'Your car is currently in pits' },
  {}, nil, function (cfg, info) return info.state.isInPit end)
registerCondition({ key = 'pitlane', group = 'Car', name = 'in pitlane', description = 'Your car is currently in pitlane' },
  {}, nil, function (cfg, info) return info.state.isInPitlane end)
registerCondition({ key = 'ai', group = 'Car', name = 'controlled by AI', description = 'Your car is controlled by AI' },
  {}, nil, function (cfg, info) return info.state.isAIControlled end)
registerCondition({ key = 'lights', group = 'Car', name = 'lights are on', description = 'Headlights are active' },
  {}, nil, function (cfg, info) return info.state.headlightsActive end)
registerCondition({ key = 'horn', group = 'Car', name = 'horn is honking', description = 'Horn is being used' },
  {}, nil, function (cfg, info) return info.state.hornActive end)
registerCondition({ key = 'hazards', group = 'Car', name = 'hazard lights are active', description = 'Hazard lights are active' },
  {}, nil, function (cfg, info) return info.state.hazardLights end)
registerCondition({ key = 'limiter', group = 'Car', name = 'engine limiter is on', description = 'Engline limiter is on' },
  {}, nil, function (cfg, info) return info.state.isEngineLimiterOn end)
registerCondition({ key = 'gearGrinding', group = 'Car', name = 'gears grinding', description = 'Gears are grinding' },
  {}, nil, function (cfg, info) return info.state.isGearGrinding end)
registerCondition({ key = 'flames', group = 'Car', name = 'flames are active', description = 'Any of car flames are active' },
  {}, nil, function (cfg, info) return info.state.anyFlamesActive end)
registerCondition({ key = 'kersCharging', group = 'Car', name = 'KERS changing', description = 'KERS is currently charging' },
  {}, nil, function (cfg, info) return info.state.kersCharging end)
registerCondition({ key = 'kersButtonPressed', group = 'Car', name = 'KERS button is pressed', description = 'KERS button is currently pressed' },
  {}, nil, function (cfg, info) return info.state.kersButtonPressed end)
registerCondition({ key = 'collision', group = 'Car', name = 'colliding', description = 'Your car is colliding with something' },
  {}, nil, function (cfg, info) return info.state.collisionDepth > 0 end)
registerCondition({ key = 'abs', group = 'Car', name = 'ABS is…', description = 'ABS is in a certain state' },
  { target = 2 }, function (cfg) combo(helperState, cfg) end,
  function (cfg, info)
    if cfg.target == 1 then return info.state.absModes ~= 0 end
    if cfg.target == 2 then return info.state.absMode ~= 0 end
    if cfg.target == 3 then return info.state.absMode == 0 and info.state.absModes ~= 0 end
    if cfg.target == 4 then return info.state.absInAction end
    return false
  end, 
  function (cfg) return helperState[cfg.target] end)
registerCondition({ key = 'tc', group = 'Car', name = 'TC is…', description = 'Traction control is in a certain state' },
  { target = 2 }, function (cfg) combo(helperState, cfg) end,
  function (cfg, info)
    if cfg.target == 1 then return info.state.tractionControlModes ~= 0 end
    if cfg.target == 2 then return info.state.tractionControlMode ~= 0 end
    if cfg.target == 3 then return info.state.tractionControlMode == 0 and info.state.tractionControlModes ~= 0 end
    if cfg.target == 4 then return info.state.tractionControlInAction end
    return false
  end, 
  function (cfg) return helperState[cfg.target] end)
registerCondition({ key = 'drs', group = 'Car', name = 'DRS is…', description = 'DRS is in a certain state' },
  { target = 2 }, function (cfg) combo(drsState, cfg) end,
  function (cfg, info)
    if cfg.target == 1 then return info.state.drsPresent end
    if cfg.target == 2 then return info.state.drsPresent and info.state.drsAvailable end
    if cfg.target == 3 then return info.state.drsPresent and not info.state.drsAvailable end
    if cfg.target == 4 then return info.state.drsActive end
    return false
  end, 
  function (cfg) return drsState[cfg.target] end)
registerNumerical({ key = 'engineLife', group = 'Car', name = 'engine damage…', description = 'Engine damage' },
  { mult = -0.1, add = 100, label = 'Damage', format = '%.0f%%' }, {}, function (cfg, info) return info.state.engineLifeLeft end)
registerNumerical({ key = 'speed', group = 'Car', name = 'speed…', description = 'Car speed' },
  { label = 'Speed', format = '%.0f km/h', max = 300 }, {}, function (cfg, info) return info.state.speedKmh end)
registerNumerical({ key = 'gear', group = 'Car', name = 'gear…', description = 'Car gear' },
  { label = 'Gear', format = '%.0f', formatMap = {[-1] = 'R', [0] = 'N', [9] = 'top gear'}, min = -1, max = 9, exact = true }, {}, function (cfg, info) return info.state.gear, info.state.gear == info.state.gearCount end)
registerNumerical({ key = 'fuel', group = 'Car', name = 'fuel…', description = 'Fuel' },
  { label = 'Fuel', format = '%.0f L', max = 100, formatMap = {[100] = 'warning'} }, {}, function (cfg, info) return info.state.fuel, info.fuelWarning end)
registerNumerical({ key = 'plankWear', group = 'Car', name = 'plank wear…', description = 'Relative plank wear' },
  { label = 'Wear', format = '%.0f%%', mult = 100 }, {}, function (cfg, info) return info.state.maxRelativePlankWear end)
registerNumerical({ key = 'tyreWear', group = 'Car', name = 'tyre wear…', description = 'Tyre wear of the most worn out tyre' },
  { label = 'Wear', format = '%.0f%%', mult = 100 }, {},
  function (cfg, info)
    local w = info.state.wheels
    return math.max(w[0].tyreWear, w[1].tyreWear, w[2].tyreWear, w[3].tyreWear)
  end)
registerNumerical({ key = 'brakeTemperature', group = 'Car', name = 'brake temperature…', description = 'Hottest brake temperature' },
  { label = 'Temperature', format = '%.0f°', mult = 999 }, {},
  function (cfg, info) 
    local w = info.state.wheels 
    return math.max(w[0].brakeTemperature, w[1].brakeTemperature, w[2].brakeTemperature, w[3].brakeTemperature) 
  end)
registerNumerical({ key = 'wheelsBlown', group = 'Car', name = 'wheels blown…', description = 'Number of wheels blown entirely' },
  { label = 'Wheels', format = '%.0f', formatMap = {[0] = 'none'}, min = 0, max = 4, exact = true }, {}, 
  function (cfg, info)
    return (info.state.wheels[0].isBlown and 1 or 0) + (info.state.wheels[1].isBlown and 1 or 0) 
      + (info.state.wheels[2].isBlown and 1 or 0) + (info.state.wheels[3].isBlown and 1 or 0)
  end)
registerNumerical({ key = 'wheelsLocked', group = 'Car', name = 'wheels locked…', description = 'Number of wheels locked while moving' },
  { label = 'Wheels', format = '%.0f', formatMap = {[0] = 'none'}, min = 0, max = 4, exact = true }, {}, 
  function (cfg, info)
    local r = 0
    for i = 0, 3 do
      if math.abs(info.state.wheels[i].angularSpeed) < 0.1 and math.abs(info.state.wheels[i].speedDifference) > 50 then
        r = r + 1
      end
    end
    return r
  end)
registerNumerical({ key = 'bodyDirt', group = 'Car', name = 'body dirt…', description = 'Exterior dirt level' },
  { label = 'Dirt', format = '%.0f%%', mult = 100 }, {}, function (cfg, info) return info.state.dirt end)
registerNumerical({ key = 'splinePosition', group = 'Car', name = 'track progress…', description = 'Position along track spline' },
  { label = 'Progress', format = '%.0f%%', mult = 100 }, {}, function (cfg, info) return info.state.splinePosition end)
registerNumerical({ key = 'gas', group = 'Car', name = 'gas…', description = 'Throttle pedal amount' },
  { label = 'Value', format = '%.0f%%', mult = 100 }, {}, function (cfg, info) return info.state.gas end)
registerNumerical({ key = 'brake', group = 'Car', name = 'brake…', description = 'Brakes pedal amount' },
  { label = 'Value', format = '%.0f%%', mult = 100 }, {}, function (cfg, info) return info.state.brake end)
registerNumerical({ key = 'handbrake', group = 'Car', name = 'handbrake…', description = 'Handbrake amount' },
  { label = 'Value', format = '%.0f%%', mult = 100 }, {}, function (cfg, info) return info.state.handbrake end)
registerNumerical({ key = 'blindSpot', group = 'Car', name = 'blind spot…', description = 'Distance to the nearest car in a blind spot' },
  { label = 'Distance', format = '%.1f m', min = 1, max = 20, settings = function (cfg)
    cfg.side = ui.combo('##side', cfg.side, ui.ComboFlags.None, {'Both', 'Left', 'Right'})
  end }, { side = 1 }, function (cfg, info) 
    local bl, br = ac.getCarBlindSpot(info.state.index)
    if cfg.side == 1 then bl = math.min(bl or math.huge, br or math.huge) end
    if cfg.side == 3 then bl = br end
    return bl or math.huge
  end)

-- Timing switches

registerNumerical({ key = 'wheelsOutside', group = 'Timing', name = 'wheels outside…', description = 'Number of wheels outside of allowed zones' },
  { label = 'Wheels', format = '%.0f', formatMap = {[0] = 'none'}, min = 0, max = 4, exact = true }, {}, function (cfg, info) return info.state.wheelsOutside end)
registerNumerical({ key = 'racePlace', group = 'Timing', name = 'race position…', description = 'Place in the leaderboard in the current session' },
  { label = 'Place', format = '%.0f', formatMap = {[1] = 'first', [100] = 'last'}, min = 1, max = 100, exact = true }, {}, function (cfg, info) return info.state.racePosition, info.state.racePosition == sim.carsCount end)
registerCondition({ key = 'lapvalid', group = 'Timing', name = 'lap is valid', description = 'Current lap is valid' },
  {}, nil, function (cfg, info) return info.state.isLapValid end)
registerCondition({ key = 'lastlapvalid', group = 'Timing', name = 'last lap is valid', description = 'Previous lap is valid' },
  {}, nil, function (cfg, info) return info.state.isLastLapValid end)
registerCondition({ key = 'lastlapbest', group = 'Timing', name = 'last lap is personal best', description = 'Previous lap is best (personally)' },
  {}, nil, function (cfg, info) return info.state.previousLapTimeMs > 0 and info.state.bestLapTimeMs == info.state.previousLapTimeMs end)
registerCondition({ key = 'lastlapbestest', group = 'Timing', name = 'last lap is best', description = 'Previous lap is best (globally)' },
  {}, nil, function (cfg, info) return info.state.previousLapTimeMs > 0 and sim.bestLapTimeMs == info.state.previousLapTimeMs end)
registerCondition({ key = 'personalbest', group = 'Timing', name = 'personal best is global best', description = 'Personal best is global best' },
  {}, nil, function (cfg, info) return info.state.bestLapTimeMs > 0 and info.state.bestLapTimeMs == sim.bestLapTimeMs end)
registerCondition({ key = 'lastlap', group = 'Timing', name = 'last lap of the session', description = 'Current lap is the last lap of the session' },
  {}, nil, function (cfg, info) 
    local s = ac.getSession(sim.currentSessionIndex)
    if not s then return false end
    if s.type == ac.SessionType.Race then
      if s.isTimedRace then
        return s.isOver
      else
        return info.state.lapCount >= s.laps - 1
      end
    else
      return s.isOver
    end
  end)