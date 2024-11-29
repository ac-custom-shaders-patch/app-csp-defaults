local settings = ac.storage({
  showHidden = false,
  showDisclaimer = true,
  higherPrecision = false
})

local car = ac.getCar(0) or error()
local ignoreChangesUntil = 0
local onConfigChange

---@class MappedConfig
---@field filename string
---@field ini ac.INIConfig
---@field data table
---@field original table
---@field map table
local MappedConfig = class('MappedConfig', function(filename, map)
  local ini = ac.INIConfig.load(filename)
  local data = ini:mapConfig(map)
  local key = 'app.ControllerTweaks:'..filename
  -- local original = stringify.tryParse(ac.load(key))
  local original = nil -- TODO: REMOVE THIS LINE
  if not original then
    ac.store(key, stringify(data))
    original = stringify.parse(stringify(data))
  end
  return {filename = filename, ini = ini, map = map, data = data, original = original}
end, class.NoInitialize)

function MappedConfig:reload()
  self.ini = ac.INIConfig.load(self.filename) or self.ini
  self.data = self.ini:mapConfig(self.map)
end

---@param section string
---@param key string
---@param value number|boolean
---@param triggerControlReload boolean?
function MappedConfig:set(section, key, value, triggerControlReload, hexFormat)
  if not self.data[section] then self.data[section] = {} end
  if type(value) == 'number' and not (value > -1e9 and value < 1e9) then error('Sanity check failed: '..tostring(value)) end
  if self.data[section][key] == value then return end
  self.data[section][key] = value
  setTimeout(function ()
    ac.log('Saving updated value: '..tostring(value))
    if onConfigChange then onConfigChange() end
    self.ini:setAndSave(section, key, hexFormat and string.format('0x%x', self.data[section][key]) or self.data[section][key])
    if triggerControlReload ~= false then
      setTimeout(function ()
        ac.log('Reloading control settings now')
        ac.reloadControlSettings()
      end, 0.02, 'reload')
    end
    ignoreChangesUntil = ui.time() + 4
  end, 0.02, section..key)
end

-- Actual configs:

local cfgControls = MappedConfig(ac.getFolder(ac.FolderID.Cfg)..'/controls.ini', {
  HEADER = { INPUT_METHOD = ac.INIConfig.OptionalString },
  KEYBOARD = { 
    MOUSE_STEER = false, MOUSE_ACCELERATOR_BRAKE = false, STEERING_SPEED = 1.75, STEERING_OPPOSITE_DIRECTION_SPEED = 2.5, STEER_RESET_SPEED = 1.8, MOUSE_SPEED = 0.1,
    GAS = 0, BRAKE = 0, RIGHT = 0, LEFT = 0, GEAR_UP = 0, GEAR_DOWN = 0, HANDBRAKE = 0
  },
  __EXT_KEYBOARD = { SHIFT_WITH_WHEEL = false, SHIFT_WITH_XBUTTONS = false },
  __EXT_KEYBOARD_GAS_RAW = { OVERRIDE = 0, LAG_UP = 0.5, LAG_DOWN = 0.2, KEY_MODIFICATOR = -1, KEY = -1, MOUSE = 0, MOUSE_MODIFICATOR = 0 },
  X360 = {
    STEER_GAMMA = 2, STEER_FILTER = 0.7, SPEED_SENSITIVITY = 0.1, STEER_DEADZONE = 0, RUMBLE_INTENSITY = 0.5, STEER_SPEED = 0.2, STEER_THUMB = 'LEFT',
    JOYPAD_INDEX = 0, AXIS_REMAP_THROTTLE = 1, AXIS_REMAP_BRAKES = 0
  },
  STEER = { JOY = 0, AXLE = -1, LOCK = 1080, FF_GAIN = 0.8, FILTER_FF = 0, STEER_GAMMA = 1, SPEED_SENSITIVITY = 0, DEBOUNCING_MS = 50 },
  FF_TWEAKS = { MIN_FF = 0.03, CENTER_BOOST_GAIN = 0, CENTER_BOOST_RANGE = 0.1 },
  FF_ENHANCEMENT = { CURBS = 0.3, ROAD = 0.3, SLIPS = 0.15, ABS = 0.2 },
  FF_ENHANCEMENT_2 = { UNDERSTEER = 0 },
  FF_SKIP_STEPS = { VALUE = 1 },
  THROTTLE = { JOY = 0, AXLE = -1, MIN = -1, MAX = 1, GAMMA = 1 },
  BRAKES = { JOY = 0, AXLE = -1, MIN = 1, MAX = -1, GAMMA = 2.8 },
  CLUTCH = { JOY = 0, AXLE = -1, MIN = 1, MAX = -1, GAMMA = 1 },

  -- Gamepad buttons:
  ABS = { XBOXBUTTON = '' },
  ABSDN = { XBOXBUTTON = '' },
  ABSUP = { XBOXBUTTON = '' },
  ACTION_CELEBRATE = { XBOXBUTTON = '' },
  ACTION_CHANGE_CAMERA = { XBOXBUTTON = '' },
  ACTION_CLAIM = { XBOXBUTTON = '' },
  ACTION_HEADLIGHTS = { XBOXBUTTON = '' },
  ACTION_HEADLIGHTS_FLASH = { XBOXBUTTON = '' },
  ACTION_HORN = { XBOXBUTTON = '' },
  ACTIVATE_AI = { XBOXBUTTON = '' },
  AUTO_SHIFTER = { XBOXBUTTON = '' },
  BALANCEDN = { XBOXBUTTON = '' },
  BALANCEUP = { XBOXBUTTON = '' },
  DRIVER_NAMES = { XBOXBUTTON = '' },
  DRS = { XBOXBUTTON = '' },
  ENGINE_BRAKE_DN = { XBOXBUTTON = '' },
  ENGINE_BRAKE_UP = { XBOXBUTTON = '' },
  FFWD = { XBOXBUTTON = '' },
  GEARDN = { XBOXBUTTON = '' },
  GEARUP = { XBOXBUTTON = '' },
  GLANCEBACK = { XBOXBUTTON = '' },
  GLANCELEFT = { XBOXBUTTON = '' },
  GLANCERIGHT = { XBOXBUTTON = '' },
  HANDBRAKE = { XBOXBUTTON = '', JOY = 0, AXLE = -1, MIN = 1, MAX = -1, GAMMA = 1 },
  HIDE_APPS = { XBOXBUTTON = '' },
  HIDE_DAMAGE = { XBOXBUTTON = '' },
  IDEAL_LINE = { XBOXBUTTON = '' },
  KERS = { XBOXBUTTON = '' },
  MGUH_MODE = { XBOXBUTTON = '' },
  MGUK_DELIVERY_DN = { XBOXBUTTON = '' },
  MGUK_DELIVERY_UP = { XBOXBUTTON = '' },
  MGUK_RECOVERY_DN = { XBOXBUTTON = '' },
  MGUK_RECOVERY_UP = { XBOXBUTTON = '' },
  MOUSE_STEERING = { XBOXBUTTON = '' },
  NEXT_CAR = { XBOXBUTTON = '' },
  NEXT_LAP = { XBOXBUTTON = '' },
  PAUSE_REPLAY = { XBOXBUTTON = '' },
  PLAYER_CAR = { XBOXBUTTON = '' },
  PREVIOUS_CAR = { XBOXBUTTON = '' },
  PREVIOUS_LAP = { XBOXBUTTON = '' },
  RESET_RACE = { XBOXBUTTON = '' },
  REV = { XBOXBUTTON = '' },
  SHOW_DAMAGE = { XBOXBUTTON = '' },
  SLOWMO = { XBOXBUTTON = '' },
  STARTER = { XBOXBUTTON = '' },
  START_REPLAY = { XBOXBUTTON = '' },
  TCDN = { XBOXBUTTON = '' },
  TCUP = { XBOXBUTTON = '' },
  TRACTION_CONTROL = { XBOXBUTTON = '' },
  TURBODN = { XBOXBUTTON = '' },
  TURBOUP = { XBOXBUTTON = '' },
  __EXT_KEYBOARD_CLUTCH = { XBOXBUTTON = '' },
  __EXT_SIM_PAUSE = { XBOXBUTTON = '' },
  __CM_TO_PITS = { XBOXBUTTON = '' },
  __EXT_WIPERS_LESS = { XBOXBUTTON = '' },
  __EXT_WIPERS_MORE = { XBOXBUTTON = '' },
})

local cfgFFPostProcess = MappedConfig(ac.getFolder(ac.FolderID.Cfg)..'/ff_post_process.ini', {
  HEADER = { TYPE = ac.INIConfig.OptionalString, ENABLED = false },
  GAMMA = { VALUE = 1 },
  LUT = { CURVE = ac.INIConfig.OptionalString }
})

local cfgSystem = MappedConfig(ac.getFolder(ac.FolderID.Root)..'/system/cfg/assetto_corsa.ini', {
  FF_EXPERIMENTAL = { ENABLE_GYRO = false, DAMPER_MIN_LEVEL = 0, DAMPER_GAIN = 1 },
  LOW_SPEED_FF = { SPEED_KMH = 3, MIN_VALUE = 0.01 }
})

local cfgCSPGeneral = MappedConfig(ac.getFolder(ac.FolderID.ExtCfgUser)..'/general.ini', {
  CONTROL = { NO_MOUSE_STEERING_FOR_INACTIVE = false }
})

local cfgFFBTweaks = MappedConfig(ac.getFolder(ac.FolderID.ExtCfgUser)..'/ffb_tweaks.ini', {
  BASIC = { ENABLED = true },
  GYRO2 = { ENABLED = false, STRENGTH = 0.25 },
  POSTPROCESSING = { RANGE_COMPRESSION = 1, RANGE_COMPRESSION_ASSIST = false },
})

-- Listen to changes in files:

local curves = {}
local curvesCache = {}

local function reloadCurves()
  curves = io.scanDir(ac.getFolder(ac.FolderID.Cfg), '*.lut')
  if cfgFFPostProcess.data.LUT.CURVE and not table.indexOf(curves, cfgFFPostProcess.data.LUT.CURVE) then
    table.insert(curves, cfgFFPostProcess.data.LUT.CURVE)
  end
  if cfgFFPostProcess.original.LUT.CURVE and not table.indexOf(curves, cfgFFPostProcess.original.LUT.CURVE) then
    table.insert(curves, cfgFFPostProcess.original.LUT.CURVE)
  end
  table.sort(curves, function (a, b) return a < b end)
  table.clear(curvesCache)
end
reloadCurves()

-- ac.onCSPConfigChanged(ac.CSPModuleID.FFBTweaks, function ()
--   ac.log('FFB tweaks module changed!')
-- end)

ac.onFolderChanged(ac.getFolder(ac.FolderID.ACDocuments)..'/cfg', '{ ?controls.ini | ?ff_post_process.ini | ?.lut }', false, function (files)
  if ui.time() < ignoreChangesUntil then return end
  if table.some(files, function (file) return string.lower(file):match('%.lut') end) then
    reloadCurves()
  elseif table.some(files, function (file) return file:match('controls%.ini') or file:match('ff_post_process%.ini') end) then
    ac.log('Reload controls settings')
    cfgControls:reload()
    cfgFFPostProcess:reload()
    ac.reloadControlSettings()
  end
end)

ac.onFolderChanged(ac.getFolder(ac.FolderID.Root)..'/system/config', '?assetto_corsa.ini`', false, function ()
  if ui.time() < ignoreChangesUntil then return end
  ac.log('Reload system controls settings')
  cfgSystem:reload()
  ac.reloadControlSettings()
end)

ac.onFolderChanged(ac.getFolder(ac.FolderID.ExtCfgUser), '{ ?ffb_tweaks.ini | ?general.ini }', false, function ()
  if ui.time() < ignoreChangesUntil then return end
  ac.log('Reload CSP controls settings')
  cfgFFBTweaks:reload()
  cfgCSPGeneral:reload()
end)

-- Drawing curves:

---@param size vec2
---@return vec2
---@return vec2
local function drawCurveBase(size)
  ui.offsetCursorY(4)
  local from, range = ui.getCursor(), size:clone()
  ui.dummy(range)
  ui.pushFont(ui.Font.Tiny)
  ui.offsetCursorX(4)
  ui.text('0%')
  ui.sameLine(0, (range.x - 20) / 2 - 10)
  ui.text('Input')
  ui.sameLine(0, (range.x - 20) / 2 - 24)
  ui.text('100%')
  local c = ui.getCursor()
  from.x = from.x + 20
  range.x = range.x - 20
  ui.drawRectFilled(from, from + range, rgbm(0, 0, 0, 0.5))
  ui.setCursor(from + vec2(-20, range.y / 2))
  ui.beginRotation()
  ui.text('Output')
  ui.endRotation(180)
  ui.setCursor(from + vec2(-21, 0))
  ui.text('100%')
  ui.popFont()
  from.y, range.y = from.y + range.y, -range.y
  ui.setCursor(c)
  ui.offsetCursorY(8)
  return from, range
end

local function loadCurve(curve)
  local r = {}
  local c = io.load(ac.getFolder(ac.FolderID.Cfg)..'/'..curve)
  if not c then return {} end
  for _, line in ipairs(io.load(ac.getFolder(ac.FolderID.Cfg)..'/'..curve):split('\n')) do
    local m = line:match('^[^;#/]+')
    if m then
      local p = m:split('|')
      local k, v = tonumber(p[1]), tonumber(p[2])
      if k and v then
        table.insert(r, vec2(k, v))
      end
    end
  end
  return r
end

local function drawCurve(curve, label, size)
  local c = table.getOrCreate(curvesCache, curve, loadCurve, curve)
  ui.text(label or 'Curve:')
  if not c or #c < 2 then
    ui.text('Curve is missing or damaged')
    return
  end
  local f, s = drawCurveBase(size or vec2(300, 120))
  for i = 1, #c do
    ui.pathLineTo(f + c[i] * s)
  end
  ui.pathStroke(ac.getUI().accentColor)
end

local function drawGammaCurve(value, label)
  ui.textWrapped(label or 'Curve:', 300)
  value = value or cfgFFPostProcess.data.GAMMA.VALUE
  local f, s = drawCurveBase(vec2(300, 120))
  for i = 0, 30 do
    local x = (i / 30) ^ 2
    ui.pathLineTo(f + vec2(x, x ^ value) * s)
  end
  ui.pathStroke(ac.getUI().accentColor)
end

-- Few helper functions:

---@param key string
local function axleValue(key)
  local s = cfgControls.data[key]
  if not s.MIN then return ac.getJoystickAxisValue(s.JOY, s.AXLE) end
  return math.abs(math.lerpInvSat(ac.getJoystickAxisValue(s.JOY, s.AXLE), s.MIN, s.MAX))
end

---Converts CSV file from WheelCheck to a LUT file.
---@param csvFile string|string[] @Filename.
---@return vec2[]
local function convertCurveFromCSV(csvFile, smoothingSteps, intensity)
  local t = table.map(io.load(type(csvFile) == 'string' and csvFile or csvFile[1]):split('\n'), function (l)
    local k, v = l:match('([-%d.]+), [-%d.]+, [-%d.]+, ([-%d.]+)') 
    k, v = tonumber(k), tonumber(v)
    return k and v and { tonumber(v), 1 }, tonumber(k)
  end)
  if type(csvFile) == 'table' then
    for i = 2, #csvFile do
      for _, l in ipairs(io.load(csvFile[i]):split('\n')) do
        local k, v = l:match('([-%d.]+), [-%d.]+, [-%d.]+, ([-%d.]+)')
        k, v = tonumber(k), tonumber(v)
        if t[k] then t[k][1], t[k][2] = t[k][1] + v, t[k][2] + 1 end
      end
    end
  end
  t = table.map(t, function (v, k) return {k, v[1] / v[2]} end)
  table.sort(t, function (a, b) return a[1] < b[1] end)
  local mf = table.maxEntry(t, function (i) return i[1] end)[1]
  local mo = table.maxEntry(t, function (i) return i[2] end)[2]
  local r = table.map(t, function (v) return #v > 0 and vec2(v[2] / mo, v[1] / mf) or nil end) ---@type vec2
  for _ = 1, smoothingSteps do
    for i = 2, #r do r[i - 1].x, r[i].x = math.lerp(r[i - 1].x, r[i].x, 0.4), math.lerp(r[i - 1].x, r[i].x, 0.6) end
    r[1].x, r[#r].x = 0, 1
  end
  table.sort(r, function (a, b) return a.x < b.x end)
  if intensity then
    for i = 1, #r do r[i].y = math.lerp(r[i].x, r[i].y, intensity) end
  end
  return r
end

---@param curve vec2[]
---@return string
local function curveToLUT(curve)
  return table.join(curve, '\n', function (i) return i.x..'|'..i.y end)
end

local function importNewCurve()
  os.openFileDialog({
    defaultFolder = ac.getFolder(ac.FolderID.Cfg),
    fileTypes = { { name = 'LUT files', mask = '*.lut' }, { name = 'WheelCheck CSV tables', mask = '*.csv' } },
  }, function (err, filename)
    if not err and filename and io.exists(filename) then
      local contents, fileName = io.load(filename)
      if not contents or #contents == 0 then
        ui.toast(ui.Icons.Warning, 'Failed to set a curve, file is empty')
        return
      end

      fileName = filename:gsub('.*[/\\\\]', '')
      if fileName:lower():match('%.csv$') then
        fileName = fileName:gsub('%.csv$', '.lut')
        contents = curveToLUT(convertCurveFromCSV(filename, 10))
        if not contents or #contents == 0 then
          ui.toast(ui.Icons.Warning, 'Failed to convert a curve to LUT format')
          return
        end
      end

      local newDestination = ac.getFolder(ac.FolderID.Cfg)..'/'..fileName
      if io.exists(newDestination) then
        if contents == io.load(newDestination) then
          cfgFFPostProcess:set('LUT', 'CURVE', fileName)
          ui.toast(ui.Icons.Confirm, 'File with the same name and contents has been selected')
          return
        end
        newDestination = nil
        for i = 1, 1000 do
          local candidate = string.format('%s/%s-%d.lut', ac.getFolder(ac.FolderID.Cfg), fileName:gsub('%.lut$', ''), i)
          if not io.exists(candidate) then
            newDestination = candidate
            break
          end
        end
        if not newDestination then
          ui.toast(ui.Icons.Warning, 'Failed to find a new file name for a curve')
          return
        end
      end
      ignoreChangesUntil = ui.time() + 5
      if io.save(newDestination, contents) then
        cfgFFPostProcess:set('LUT', 'CURVE', fileName)
        ui.toast(ui.Icons.Confirm, 'Curve file has been copied to AC configs folder')
        reloadCurves()
      else
        ui.toast(ui.Icons.Warning, 'Failed to copy curve file to AC configs folder')
      end
    end
  end)
end

local createLUTData ---@type {csv: string[], selected: table, smoothingSteps: integer, intensity: number, demoApplied: boolean}

local function resetCreateLUTDataTest(withControlReload)
  if createLUTData and createLUTData.demoApplied then    
    local cfg = ac.INIConfig.load(ac.getFolder(ac.FolderID.Cfg)..'/ff_post_process.ini')
    cfg:setAndSave('HEADER', 'ENABLED', cfgFFPostProcess.data.HEADER.ENABLED)
    cfg:setAndSave('HEADER', 'TYPE', cfgFFPostProcess.data.HEADER.TYPE)
    cfg:setAndSave('LUT', 'CURVE', cfgFFPostProcess.data.LUT.CURVE)
    if withControlReload then ac.reloadControlSettings() end
    createLUTData.demoApplied = false
  end
end

onConfigChange = function()
  resetCreateLUTDataTest()
end

function script.windowEndLUTCreation()
  resetCreateLUTDataTest(true)
end

function script.windowCreateLUT()
  if not createLUTData then
    createLUTData = {
      csv = io.scanDir(ac.getFolder(ac.FolderID.Documents), 'log2 *.csv'),
      selected = {},
      smoothingSteps = 10,
      intensity = 1,
      demoApplied = false
    }
    table.sort(createLUTData.csv, function (a, b) return a > b end)
  end

  ui.pushFont(ui.Font.Small)
  ui.header('Found tables (newest first):')
  local selected = {}
  ui.childWindow('tablesList', vec2(0, 120), function ()
    for _, v in ipairs(createLUTData.csv) do
      if ui.checkbox(v, createLUTData.selected[v] or false) then
        createLUTData.selected[v] = not createLUTData.selected[v]
        createLUTData.generatedCurve = nil
      end
      if createLUTData.selected[v] then
        selected[#selected + 1] = v
      end
    end
  end)

  ui.setNextItemWidth(ui.availableSpaceX())
  createLUTData.smoothingSteps = ui.slider('##smoothing', createLUTData.smoothingSteps, 1, 20, 'Smoothing steps: %.0f')
  if ui.itemEdited() then
    createLUTData.generatedCurve = nil
  end

  ui.setNextItemWidth(ui.availableSpaceX())
  createLUTData.intensity = ui.slider('##intensity', createLUTData.intensity * 100, 0, 200, 'Intensity: %.0f%%') / 100
  if ui.itemEdited() then
    createLUTData.generatedCurve = nil
  end

  local updateTest
  if createLUTData.generatedCurve == nil then
    updateTest = createLUTData.demoApplied
    if #selected == 0 then
      createLUTData.generatedCurve = false
    else
      createLUTData.generatedCurve = convertCurveFromCSV(table.map(selected, function (item)
        return ac.getFolder(ac.FolderID.Documents)..'/'..item
      end), createLUTData.smoothingSteps, createLUTData.intensity)
    end
  end

  local c = createLUTData.generatedCurve or error() -- to stop Lua extension from complaining about possible nil
  if createLUTData.generatedCurve then
    local f, s = drawCurveBase(vec2(300, 280))
    for i = 1, #c do
      ui.pathLineTo(f + c[i] * s)
    end
    ui.pathStroke(ac.getUI().accentColor)
    if ui.button('Test current curve', vec2(ui.availableSpaceX() / 2 - 2, 0), createLUTData.demoApplied and ui.ButtonFlags.Active or 0) then
      createLUTData.demoApplied = not createLUTData.demoApplied
      updateTest = true
    end
    ui.sameLine(0, 4)
    ui.button('Save and apply the curve', vec2(ui.availableSpaceX(), 0))
  else
    ui.textWrapped('• Select some generated tables. If several tables are selected, they will be averaged;')
    ui.textWrapped('• To generate a table, you can use WheelCheck:')
    ui.offsetCursorX(20)
    if ui.button('Find WheelCheck') then
      os.openURL('https://www.racedepartment.com/downloads/lut-generator-for-ac.9740/')
    end
    ui.textWrapped('• Simply launch it and select “Step Log 2” in “Spring Force” dropdown, and wait for a bit until your wheel would stop moving, new table should appear in this list;')
    ui.textWrapped('• If WheelCheck doesn’t work, close Content Manager (when AC is running, it minimizes itself to Windows tray);')
    ui.textWrapped('• Or, you can use LUT Generator for AC from RaceDepartment, it might produce more accurate results.')
  end

  if updateTest then
    setTimeout(function ()
      ignoreChangesUntil = ui.time() + 5
      local cfg = ac.INIConfig.load(ac.getFolder(ac.FolderID.Cfg)..'/ff_post_process.ini')
      if not createLUTData.demoApplied then
        io.deleteFile(ac.getFolder(ac.FolderID.Cfg)..'/_curve_tmp.lut')
        cfg:setAndSave('HEADER', 'ENABLED', cfgFFPostProcess.data.HEADER.ENABLED)
        cfg:setAndSave('HEADER', 'TYPE', cfgFFPostProcess.data.HEADER.TYPE)
        cfg:setAndSave('LUT', 'CURVE', cfgFFPostProcess.data.LUT.CURVE)
      else
        if c then
          io.save(ac.getFolder(ac.FolderID.Cfg)..'/_curve_tmp.lut', curveToLUT(c))
        else
          io.deleteFile(ac.getFolder(ac.FolderID.Cfg)..'/_curve_tmp.lut')
        end
        cfg:setAndSave('HEADER', 'ENABLED', not not c)
        cfg:setAndSave('HEADER', 'TYPE', 'LUT')
        cfg:setAndSave('LUT', 'CURVE', c and '_curve_tmp.lut' or '')
      end
      ac.reloadControlSettings()
    end, 0.04, 'curveTest')
  end

  ui.popFont()
end

-- Editing controls:

---@param cfg MappedConfig
---@param section string
---@param key string
---@param from number
---@param to number
---@param mult number
---@param format string
---@param tooltip string|function|nil
local function slider(cfg, section, key, from, to, mult, format, tooltip, preprocess)
  if not cfg.data[section] then error('No such section: '..section, 2) end
  if not cfg.data[section][key] then error('No such key: '..key, 2) end
  if settings.higherPrecision then format = format:gsub('%.0f%%', '%.1f%%') end
  local curValue = ui.slider('##'..section..key, mult < 0 and -mult / cfg.data[section][key] or cfg.data[section][key] * mult, from, to, format)
  if tooltip and (ui.itemHovered() or ui.itemActive()) then
    (type(tooltip) == 'function' and ui.tooltip or ui.setTooltip)(tooltip)
  end
  if preprocess then
    curValue = preprocess(curValue)
  end
  ui.sameLine(0, 4)
  local changed = math.abs(cfg.original[section][key] - (mult < 0 and -mult / curValue or curValue / mult)) > 0.0001
  if ui.button('##r'..section..key, vec2(20, 20), changed and ui.ButtonFlags.None or ui.ButtonFlags.Disabled) then
    curValue = mult < 0 and -mult / cfg.original[section][key] or cfg.original[section][key] * mult
  end
  ui.addIcon(ui.Icons.Restart, 10, 0.5, nil, 0)
  if ui.itemHovered() then
    local v = string.format(format:match('%%.+'), mult < 0 and -mult / cfg.original[section][key] or cfg.original[section][key] * mult)
    ui.setTooltip(string.format(changed and 'Click to restore original value: %s' or 'Original value: %s', v))
  end
  local rounded = settings.higherPrecision and math.floor(curValue * 10) / 10 or math.floor(curValue)
  cfg:set(section, key, mult < 0 and -mult / curValue or rounded / mult, true)
end

---@param cfg MappedConfig
---@param section string
---@param key string
---@param label string
---@param tooltip string?
local function checkbox(cfg, section, key, label, tooltip)
  if cfg.data[section] == nil then error('No such section: '..section, 2) end
  if cfg.data[section][key] == nil then error('No such key: '..key, 2) end
  local curValue = cfg.data[section][key]
  if ui.checkbox(label, curValue) then curValue = not curValue end
  if tooltip and ui.itemHovered() then
    (type(tooltip) == 'function' and ui.tooltip or ui.setTooltip)(tooltip)
  end
  ui.sameLine(0, 0)
  ui.offsetCursorX(ui.availableSpaceX() - 20)
  local changed = cfg.original[section][key] ~= curValue
  if ui.button('##r'..section..key, vec2(20, 20), changed and ui.ButtonFlags.None or ui.ButtonFlags.Disabled) then
    curValue = cfg.original[section][key]
  end
  ui.addIcon(ui.Icons.Restart, 10, 0.5, nil, 0)
  if ui.itemHovered() then
    ui.setTooltip(string.format(changed and 'Click to restore original value: %s' or 'Original value: %s', cfg.original[section][key] and 'yes' or 'no'))
  end
  cfg:set(section, key, curValue, true)
end

local function combo(cfg, section, key, label, previewCallback, contentCallback, tooltip, widthOpt)
  ui.alignTextToFramePadding()
  ui.text(label..':')
  ui.sameLine(widthOpt or 68, 0)
  local current = cfgControls.data[section][key]
  local id = section..'/'..key
  ui.setNextItemWidth(ui.availableSpaceX() - 24)
  ui.combo('##r'..section..key, previewCallback(current), ui.ComboFlags.None, contentCallback)
  if tooltip and ui.itemHovered() then
    (type(tooltip) == 'function' and ui.tooltip or ui.setTooltip)(tooltip)
  end
  ui.sameLine(0, 4)
  local changed = cfgControls.original[section][key] ~= current
  if ui.button('##r'..id, vec2(20, 20), changed and ui.ButtonFlags.None or ui.ButtonFlags.Disabled) then
    cfgControls:set(section, key, cfgControls.original[section][key], true, true)
  end
  ui.addIcon(ui.Icons.Restart, 10, 0.5, nil, 0)
  if ui.itemHovered() then
    ui.setTooltip(string.format(changed and 'Click to restore original value: %s' or 'Original value: %s', previewCallback(cfgControls.original[section][key])))
  end
end

local keyNames = require('keys')
local keyWaiting

local function keyboardButton(section, key, label, tooltip)
  ui.alignTextToFramePadding()
  ui.text(label..':')
  ui.sameLine(120, 0)
  local current = cfgControls.data[section][key]
  local id = section..'/'..key
  if ui.button(string.format('%s###%s', keyNames[current] or current < 1 and 'None' or current, id), vec2(ui.availableSpaceX() - 24, 0), keyWaiting == id and ui.ButtonFlags.Active or 0) then
    keyWaiting = keyWaiting ~= id and id or nil
  end
  if tooltip and ui.itemHovered() then
    (type(tooltip) == 'function' and ui.tooltip or ui.setTooltip)(tooltip)
  end
  ui.sameLine(0, 4)
  local changed = cfgControls.original[section][key] ~= current
  if ui.button('##r'..id, vec2(20, 20), changed and ui.ButtonFlags.None or ui.ButtonFlags.Disabled) then
    cfgControls:set(section, key, cfgControls.original[section][key], true, true)
    keyWaiting = nil
  end
  ui.addIcon(ui.Icons.Restart, 10, 0.5, nil, 0)
  if ui.itemHovered() then
    local v = keyNames[cfgControls.original[section][key]] or cfgControls.original[section][key] < 1 and 'None' or current
    ui.setTooltip(string.format(changed and 'Click to restore original value: %s' or 'Original value: %s', v))
  end
  if keyWaiting == id then
    if ui.keyboardButtonDown(ui.KeyIndex.Escape) or ui.keyboardButtonDown(ui.KeyIndex.Back) then
      keyWaiting = nil
    else
      for k, _ in pairs(keyNames) do
        if ui.keyboardButtonDown(k) then
          cfgControls:set(section, key, k, true, true)
          keyWaiting = nil
        end
      end
    end
  end
end

local gamepadNames = { 
  ['DPAD_LEFT'] = { ac.GamepadButton.DPadLeft, 'D-Pad Left' },
  ['DPAD_RIGHT'] = { ac.GamepadButton.DPadRight, 'D-Pad Right' },
  ['DPAD_UP'] = { ac.GamepadButton.DPadUp, 'D-Pad Up' },
  ['DPAD_DOWN'] = { ac.GamepadButton.DpadLeft, 'D-Pad Down' },
  ['A'] = { ac.GamepadButton.A, 'A' },
  ['B'] = { ac.GamepadButton.B, 'B' },
  ['X'] = { ac.GamepadButton.X, 'X' },
  ['Y'] = { ac.GamepadButton.Y, 'Y' },
  ['LSHOULDER'] = { ac.GamepadButton.LeftShoulder, 'Left Shoulder' },
  ['RSHOULDER'] = { ac.GamepadButton.RightShoulder, 'Right Shoulder' },
  ['LTHUMB_PRESS'] = { ac.GamepadButton.LeftThumb, 'Left Thumb' },
  ['RTHUMB_PRESS'] = { ac.GamepadButton.RightThumb, 'Right Thumb' },
  ['START'] = { ac.GamepadButton.Start, 'Start' },
  ['BACK'] = { ac.GamepadButton.Back, 'Back' },
}
local gamepadWaiting

local function gamepadButton(section, label, tooltip)
  ui.alignTextToFramePadding()
  ui.text(label..':')
  ui.sameLine(120, 0)
  local key = 'XBOXBUTTON'
  local current = cfgControls.data[section][key]
  local id = section..'/'..key
  if ui.button(string.format('%s###%s', gamepadNames[current] and gamepadNames[current][2] or 'None', id), vec2(ui.availableSpaceX() - 24, 0), gamepadWaiting == id and ui.ButtonFlags.Active or 0) then
    gamepadWaiting = gamepadWaiting ~= id and id or nil
  end
  if tooltip and ui.itemHovered() then
    (type(tooltip) == 'function' and ui.tooltip or ui.setTooltip)(tooltip)
  end
  ui.sameLine(0, 4)
  local changed = cfgControls.original[section][key] ~= current
  if ui.button('##r'..id, vec2(20, 20), changed and ui.ButtonFlags.None or ui.ButtonFlags.Disabled) then
    cfgControls:set(section, key, cfgControls.original[section][key], true)
    gamepadWaiting = nil
  end
  ui.addIcon(ui.Icons.Restart, 10, 0.5, nil, 0)
  if ui.itemHovered() then
    local v = gamepadNames[cfgControls.original[section][key]] and gamepadNames[cfgControls.original[section][key]][2] or 'None'
    ui.setTooltip(string.format(changed and 'Click to restore original value: %s' or 'Original value: %s', v))
  end
  if gamepadWaiting == id then
    if ac.blockEscapeButton then ac.blockEscapeButton() end
    if ui.keyboardButtonDown(ui.KeyIndex.Escape) or ui.keyboardButtonDown(ui.KeyIndex.Back) then
      gamepadWaiting = nil
    elseif ui.keyboardButtonDown(ui.KeyIndex.Delete) then
      cfgControls:set(section, key, '', true)
      gamepadWaiting = nil
    else
      for k, _ in pairs(gamepadNames) do
        if ac.isGamepadButtonPressed(cfgControls.data.X360.JOYPAD_INDEX, _[1]) then
          cfgControls:set(section, key, k, true)
          gamepadWaiting = nil
        end
      end
    end
  end
end

local function mouseButton(section, key, label, tooltip)
  ui.alignTextToFramePadding()
  ui.text(label..':')
  ui.sameLine(120, 0)
  local current = cfgControls.data[section][key]
  local keys = { [0] = 'None', 'Left', 'Right', 'Middle', 'Fourth', 'Fifth' }
  local id = section..'/'..key
  ui.setNextItemWidth(ui.availableSpaceX() - 24)
  ui.combo(string.format('##%s', id), keys[current] or 'None', ui.ComboFlags.None, function ()
    for i = 0, #keys do
      local v = keys[i]
      if ui.selectable(v, i == 0 and current < 1 or i == current) then
        cfgControls:set(section, key, i == 0 and -1 or i, true)
      end
    end
  end)
  if tooltip and ui.itemHovered() then
    (type(tooltip) == 'function' and ui.tooltip or ui.setTooltip)(tooltip)
  end
  ui.sameLine(0, 4)
  local changed = cfgControls.original[section][key] ~= current
  if ui.button('##r'..id, vec2(20, 20), changed and ui.ButtonFlags.None or ui.ButtonFlags.Disabled) then
    cfgControls:set(section, key, cfgControls.original[section][key], true, true)
    keyWaiting = nil
  end
  ui.addIcon(ui.Icons.Restart, 10, 0.5, nil, 0)
  if ui.itemHovered() then
    ui.setTooltip(string.format(changed and 'Click to restore original value: %s' or 'Original value: %s', keys[cfgControls.original[section][key]] or 'None'))
  end
end

-- Specialized controls:

local originalFFBGain = tonumber(ac.load('app.ControllerTweaks:originalFFBGain')) or car.ffbMultiplier
ac.store('app.ControllerTweaks:originalFFBGain', originalFFBGain)

local function userFFBGainSlider()
  ui.setNextItemWidth(ui.availableSpaceX() - 48)
  local curValue = ui.slider('##ffb', car.ffbMultiplier * 100, 0, 200, 'Car FFB gain: %.0f%%') / 100
  ui.sameLine(0, 4)
  local changed = 1 ~= curValue
  if ui.button('##ffbResetTo100', vec2(20, 20), changed and ui.ButtonFlags.None or ui.ButtonFlags.Disabled) then curValue = 1 end
  ui.addIcon(ui.Icons.Cancel, 10, 0.5, nil, 0)
  if ui.itemHovered() then ui.setTooltip(changed and 'Click to set FFB gain to 100%' or 'Base value: 100%') end
  ui.sameLine(0, 4)
  changed = originalFFBGain ~= curValue
  if ui.button('##ffbReset', vec2(20, 20), changed and ui.ButtonFlags.None or ui.ButtonFlags.Disabled) then curValue = originalFFBGain end
  ui.addIcon(ui.Icons.Restart, 10, 0.5, nil, 0)
  if ui.itemHovered() then ui.setTooltip(string.format(changed and 'Click to restore original FFB gain: %.0f%%' or 'Original value: %.0f%%', originalFFBGain * 100)) end
  if curValue ~= car.ffbMultiplier then
    ac.setFFBMultiplier(curValue)
  end
end

local function getGyroMode()
  return cfgFFBTweaks.data.BASIC.ENABLED and cfgFFBTweaks.data.GYRO2.ENABLED and 3 or cfgSystem.data.FF_EXPERIMENTAL.ENABLE_GYRO and 2 or 1
end

local originalGyroMode = tonumber(ac.load('app.ControllerTweaks:originalGyroMode')) or getGyroMode()
ac.store('app.ControllerTweaks:originalGyroMode', originalGyroMode)

local function gyroModeCombo()
  ui.alignTextToFramePadding()
  ui.text('Mode:')
  ui.sameLine(68)
  ui.setNextItemWidth(ui.availableSpaceX() - 24)
  local currentGyroMode, changed = getGyroMode(), nil
  currentGyroMode, changed = ui.combo('##gyro', currentGyroMode, ui.ComboFlags.None, cfgFFBTweaks.data.BASIC.ENABLED and { 'None', 'Standard', 'FFB Tweaks' } or { 'None', 'Standard' })
  ui.sameLine(0, 4)
  local changedFromOriginal = originalGyroMode ~= currentGyroMode
  if ui.button('##gyroReset', vec2(20, 20), changedFromOriginal and ui.ButtonFlags.None or ui.ButtonFlags.Disabled) then
    currentGyroMode, changed = originalGyroMode, true
  end
  ui.addIcon(ui.Icons.Restart, 10, 0.5, nil, 0)
  if ui.itemHovered() then
    ui.setTooltip(string.format(changedFromOriginal and 'Click to restore original gyro mode setting: %s' or 'Original gyro mode setting: %s', 
      originalGyroMode == 3 and 'FFB Tweaks' or originalGyroMode == 2 and 'standard' or 'none'))
  end

  if changed then
    cfgSystem:set('FF_EXPERIMENTAL', 'ENABLE_GYRO', currentGyroMode == 2)
    cfgFFBTweaks:set('GYRO2', 'ENABLED', currentGyroMode == 3, false)
  end
  -- if currentGyroMode == 3 then
  --   slider(cfgFFBTweaks, 'GYRO2', 'STRENGTH', 0, 100, 100, 'Gyro strength: %.0f%%', 'Effect strength')
  -- end
end

local function getPPMode()
  return cfgFFPostProcess.data.HEADER.ENABLED and (cfgFFPostProcess.data.HEADER.TYPE == 'GAMMA' and 2 or 3) or 1
end

local originalPPMode = tonumber(ac.load('app.ControllerTweaks:originalPPMode')) or getPPMode()
ac.store('app.ControllerTweaks:originalPPMode', originalPPMode)

local originalCurve = tonumber(ac.load('app.ControllerTweaks:originalCurve')) or cfgFFPostProcess.original.LUT.CURVE
ac.store('app.ControllerTweaks:originalCurve', originalCurve)

local function ppModeCombo()
  ui.alignTextToFramePadding()
  ui.text('Mode:')
  ui.sameLine(68)
  ui.setNextItemWidth(ui.availableSpaceX() - 24)
  local currentPPMode, changed = getPPMode(), false
  ui.combo('##pp', currentPPMode == 3 and 'LUT' or currentPPMode == 2 and 'Gamma' or 'Disabled', ui.ComboFlags.None, function ()
    if ui.selectable('Disabled') then currentPPMode, changed = 1, true end
    if ui.itemHovered() then ui.tooltip(function () drawGammaCurve(1) end) end
    if ui.selectable('Gamma') then currentPPMode, changed = 2, true end
    if ui.itemHovered() then ui.tooltip(function () drawGammaCurve() end) end
    if ui.selectable('LUT') then currentPPMode, changed = 3, true end
    if ui.itemHovered() then ui.tooltip(function () drawCurve(cfgFFPostProcess.data.LUT.CURVE) end) end
  end)
  ui.sameLine(0, 4)
  local changedFromOriginal = originalPPMode ~= currentPPMode
  if ui.button('##ppReset', vec2(20, 20), changedFromOriginal and ui.ButtonFlags.None or ui.ButtonFlags.Disabled) then
    currentPPMode, changed = originalPPMode, true
  end
  ui.addIcon(ui.Icons.Restart, 10, 0.5, nil, 0)
  if ui.itemHovered() then
    ui.setTooltip(string.format(changedFromOriginal and 'Click to restore original post-processing mode setting: %s' or 'Original post-processing mode setting: %s', 
      originalPPMode == 3 and 'LUT' or originalPPMode == 2 and 'gamma' or 'none'))
  end
  if changed then
    cfgFFPostProcess:set('HEADER', 'ENABLED', currentPPMode ~= 1)
    if currentPPMode ~= 1 then cfgFFPostProcess:set('HEADER', 'TYPE', currentPPMode == 2 and 'GAMMA' or 'LUT') end
  end
  if currentPPMode == 2 then
    slider(cfgFFPostProcess, 'GAMMA', 'VALUE', 30, 300, 100, 'Gamma value: %.0f%%', 
      function () ui.tooltip(function () drawGammaCurve(nil, 'Decrease above 100% to boost smaller forces, increase above 100% to attenuate smaller forces:') end) end,
      function (v) return math.max(v, 30) end)
  elseif currentPPMode == 3 then
    ui.alignTextToFramePadding()
    ui.text('Curve:')
    ui.sameLine(68)
    ui.setNextItemWidth(ui.availableSpaceX() - 24)
    ui.combo('##ppFile', cfgFFPostProcess.data.LUT.CURVE or 'None', function ()
      for i = 1, #curves do
        if ui.selectable(curves[i], curves[i] == cfgFFPostProcess.data.LUT.CURVE) then
          cfgFFPostProcess:set('LUT', 'CURVE', curves[i])
        end
        if ui.itemHovered() then
          ui.tooltip(function () drawCurve(curves[i]) end)
        end
      end
      ui.separator()
      if ui.selectable('Add new curve from LUT…') then
        importNewCurve()
      end
      if ui.itemHovered() then
        ui.setTooltip('Select a LUT file and it will be copied to “Documents/Assetto Corsa/cfg” and selected')
      end
      if ui.selectable('Create new curve using WheelCheck…') then
        ac.setWindowOpen('createLUT', true)
      end
      if ui.itemHovered() then
        ui.setTooltip('Create new curve for your steering wheel using WheelCheck')
      end
    end)
    if ui.itemHovered() and cfgFFPostProcess.data.LUT.CURVE then
      ui.tooltip(function () drawCurve(cfgFFPostProcess.data.LUT.CURVE) end)
    end

    ui.sameLine(0, 4)
    if ui.button('##curveReset', vec2(20, 20), originalCurve ~= cfgFFPostProcess.data.LUT.CURVE and ui.ButtonFlags.None or ui.ButtonFlags.Disabled) then
      cfgFFPostProcess:set('LUT', 'CURVE', originalCurve)
    end
    ui.addIcon(ui.Icons.Restart, 10, 0.5, nil, 0)
    if ui.itemHovered() then
      ui.setTooltip(string.format(originalCurve ~= cfgFFPostProcess.data.LUT.CURVE and 'Click to restore original curve: %s' or 'Original curve: %s', originalCurve))
    end
  end
end

-- UI for different input modes:

local configurators = {}

function configurators.KEYBOARD()
  ui.header('Keyboard steering:')
  slider(cfgControls, 'KEYBOARD', 'STEERING_SPEED', 0, 400, 100, 'Speed: %.0f%%')
  slider(cfgControls, 'KEYBOARD', 'STEERING_OPPOSITE_DIRECTION_SPEED', 0, 400, 100, 'Opposite direction speed: %.0f%%', 'Speed of steering when steering back to zero')
  slider(cfgControls, 'KEYBOARD', 'STEER_RESET_SPEED', 0, 400, 100, 'Reset speed: %.0f%%', 'Speed of automatic return to zero')

  ui.offsetCursorY(16)
  ui.header('Mouse steering:')
  checkbox(cfgControls, 'KEYBOARD', 'MOUSE_STEER', 'Mouse steering', 'Use Ctrl+M to get cursor pointer back')
  checkbox(cfgControls, 'KEYBOARD', 'MOUSE_ACCELERATOR_BRAKE', 'Mouse acceleration and braking', 'Use mouse buttons to accelerate and brake')
  checkbox(cfgCSPGeneral, 'CONTROL', 'NO_MOUSE_STEERING_FOR_INACTIVE', 'No mouse steering in background', 'Stops mouse steering (including mouse capture) if Assetto Corsa is not in foreground')
  slider(cfgControls, 'KEYBOARD', 'MOUSE_SPEED', 0, 300, -10, 'Speed: %.0f%%', nil, function (v) return math.max(v, 0.01) end)

  checkbox(cfgControls, '__EXT_KEYBOARD', 'SHIFT_WITH_WHEEL', 'Shift gears with mouse wheel', 'Use mouse wheel to change gears')
  checkbox(cfgControls, '__EXT_KEYBOARD', 'SHIFT_WITH_XBUTTONS', 'Shift with 4th and 5th buttons', 'Use additional mouse buttons to change gears')

  ui.offsetCursorY(16)
  ui.header('Buttons:')
  keyboardButton('KEYBOARD', 'GAS', 'Gas')
  keyboardButton('KEYBOARD', 'BRAKE', 'Brake')
  keyboardButton('KEYBOARD', 'RIGHT', 'Right')
  keyboardButton('KEYBOARD', 'LEFT', 'Left')
  keyboardButton('KEYBOARD', 'GEAR_UP', 'Gear up')
  keyboardButton('KEYBOARD', 'GEAR_DOWN', 'Gear down')
  keyboardButton('KEYBOARD', 'HANDBRAKE', 'Handbrake')

  ui.offsetCursorY(16)
  ui.header('Forced throttle:')
  checkbox(cfgControls, '__EXT_KEYBOARD_GAS_RAW', 'OVERRIDE', 'Enable forced throttle', 'A CSP feature allowing to bind alternative throttle buttons overriding built-in traction control')
  keyboardButton('__EXT_KEYBOARD_GAS_RAW', 'KEY', 'Full throttle', 'If button is pressed, full throttle is applied')
  keyboardButton('__EXT_KEYBOARD_GAS_RAW', 'KEY_MODIFICATOR', 'Throttle modifier', 'If gas button and this button both are pressed, full throttle is applied')
  mouseButton('__EXT_KEYBOARD_GAS_RAW', 'MOUSE', 'Full throttle', 'If mouse button is pressed, full throttle is applied')
  mouseButton('__EXT_KEYBOARD_GAS_RAW', 'MOUSE_MODIFICATOR', 'Throttle modifier', 'If gas button and this mouse button both are pressed, full throttle is applied')
  slider(cfgControls, '__EXT_KEYBOARD_GAS_RAW', 'LAG_UP', 0, 99, 100, 'Filter (up): %.0f%%', 'Filter for forced throttle to kick in')
  slider(cfgControls, '__EXT_KEYBOARD_GAS_RAW', 'LAG_DOWN', 0, 99, 100, 'Filter (down): %.0f%%', 'Filter for forced throttle to turn off')

  ui.offsetCursorY(16)
  ui.header('Pedals state:')
  ui.pushStyleColor(ui.StyleColor.PlotHistogram, rgbm(0, 0.4, 0, 1))
  ui.progressBar(car.gas, vec2(ui.availableSpaceX(), 0), 'Gas')
  ui.popStyleColor()
  ui.pushStyleColor(ui.StyleColor.PlotHistogram, rgbm(0.4, 0, 0, 1))
  ui.progressBar(car.brake, vec2(ui.availableSpaceX(), 0), 'Brake')
  ui.popStyleColor()
end

local gamepadButtonsOrdered = {
  { 'GEARUP', 'Next gear' },
  { 'GEARDN', 'Previous gear' },
  { 'HANDBRAKE', 'Handbrake' },
  { '__EXT_KEYBOARD_CLUTCH', 'Clutch' },
  { 'ACTION_HEADLIGHTS', 'Headlights' },

  'Additional',
  { 'ACTION_HORN', 'Horn' },  
  { 'GLANCEBACK', 'Look back' },
  { 'GLANCELEFT', 'Look left' },
  { 'GLANCERIGHT', 'Look right' },
  { 'ACTION_CHANGE_CAMERA', 'Change camera' },
  { 'DRIVER_NAMES', 'Driver names' },
  { '__EXT_SIM_PAUSE', 'Pause' },
  { '__CM_TO_PITS', 'Teleport to pits' },

  'Car control',
  { 'ABSDN', 'ABS (reduce)' },
  { 'ABSUP', 'ABS (increase)' },
  { 'TCDN', 'TC (reduce)' },
  { 'TCUP', 'TC (increase)' },
  { 'TURBODN', 'Turbo (reduce)' },
  { 'TURBOUP', 'Turbo (increase)' },
  { 'KERS', 'KERS' },
  { 'DRS', 'DRS' },

  'Car extras',
  { '__EXT_WIPERS_LESS', 'Wipers (reduce)' },
  { '__EXT_WIPERS_MORE', 'Wipers (increase)' },

  -- { 'ABS', 'ABS' },
  -- { 'TRACTION_CONTROL', 'Traction control' },
  -- { 'ACTION_HEADLIGHTS_FLASH', 'Headlights (flash)' },
  -- { 'BALANCEDN', 'BALANCEDN' },
  -- { 'BALANCEUP', 'BALANCEUP' },
  -- { 'ENGINE_BRAKE_DN', 'ENGINE_BRAKE_DN' },
  -- { 'ENGINE_BRAKE_UP', 'ENGINE_BRAKE_UP' },
  -- { 'MGUH_MODE', 'MGUH_MODE' },
  -- { 'MGUK_DELIVERY_DN', 'MGUK_DELIVERY_DN' },
  -- { 'MGUK_DELIVERY_UP', 'MGUK_DELIVERY_UP' },
  -- { 'MGUK_RECOVERY_DN', 'MGUK_RECOVERY_DN' },
  -- { 'MGUK_RECOVERY_UP', 'MGUK_RECOVERY_UP' },
  
  -- { 'ACTION_CELEBRATE', 'ACTION_CELEBRATE' },
  -- { 'ACTION_CLAIM', 'ACTION_CLAIM' },

  -- { 'ACTIVATE_AI', 'ACTIVATE_AI' },
  -- { 'AUTO_SHIFTER', 'AUTO_SHIFTER' },

  -- { 'HIDE_APPS', 'HIDE_APPS' },
  -- { 'HIDE_DAMAGE', 'HIDE_DAMAGE' },
  -- { 'SHOW_DAMAGE', 'SHOW_DAMAGE' },
  -- { 'IDEAL_LINE', 'IDEAL_LINE' },
  -- { 'MOUSE_STEERING', 'MOUSE_STEERING' },
  -- { 'FFWD', 'Fast forward' },
  -- { 'NEXT_CAR', 'NEXT_CAR' },
  -- { 'NEXT_LAP', 'NEXT_LAP' },
  -- { 'PAUSE_REPLAY', 'PAUSE_REPLAY' },
  -- { 'PLAYER_CAR', 'PLAYER_CAR' },
  -- { 'PREVIOUS_CAR', 'PREVIOUS_CAR' },
  -- { 'PREVIOUS_LAP', 'PREVIOUS_LAP' },
  -- { 'SLOWMO', 'SLOWMO' },
  -- { 'STARTER', 'STARTER' },
  -- { 'START_REPLAY', 'START_REPLAY' },
  -- { 'REV', 'REV' },
  -- { 'RESET_RACE', 'RESET_RACE' },
}

local gamepadAxisList = {
  [0] = 'L2',
  [1] = 'R2',
  [2] = 'Left stick (Y+)',
  [3] = 'Left stick (Y−)',
  [4] = 'Right stick (Y+)',
  [5] = 'Right stick (Y−)',
  [6] = 'Left stick (X+)',
  [7] = 'Left stick (X−)',
  [8] = 'Right stick (X+)',
  [9] = 'Right stick (X−)',
}

local function comboGamepadAxis(key, label)
  combo(cfgControls, 'X360', key, label, function (v)
    return gamepadAxisList[v] or '?'
  end, function ()
    for k, v in pairs(gamepadAxisList) do
      if ui.selectable(v) then cfgControls:set('X360', key, k, true) end
    end
  end)
end

function configurators.X360()
  --[[ local index = cfgControls.data.X360.JOYPAD_INDEX % 4
  local useDualSense = cfgControls.data.X360.JOYPAD_INDEX > 3
  index = ui.slider('##gamepad', index + 1, 1, 4, 'Gamepad: %.0f') - 1
  local changed = ui.itemEdited()
  if ui.checkbox('Use PS 5 DualSense gamepad', useDualSense) then useDualSense, changed = not useDualSense, true end
  if changed then
    cfgControls:set('X360', 'JOYPAD_INDEX', index + (useDualSense and 4 or 0), true)
  end
  ui.offsetCursorY(16) ]]

  ui.header('Steering:')
  combo(cfgControls, 'X360', 'STEER_THUMB', 'Thumb', function (v) return v == 'LEFT' and 'Left' or 'Right' end, function ()
    if ui.selectable('Left') then cfgControls:set('X360', 'STEER_THUMB', 'LEFT', true) end
    if ui.selectable('Right') then cfgControls:set('X360', 'STEER_THUMB', 'RIGHT', true) end
  end, 'If you are using Neck FX, you might need to change thumb used for glancing around in its settings too')
  slider(cfgControls, 'X360', 'STEER_SPEED', 0, 200, 100, 'Speed: %.0f%%', 'Base speed of turning the steering wheel')
  slider(cfgControls, 'X360', 'STEER_GAMMA', 100, 500, 100, 'Gamma: %.0f%%', function ()
    ui.text('Curve (use steering thumb to see it in action):')
    local f, s = drawCurveBase(vec2(300, 120))
    local b = ac.getGamepadAxisValue(0, cfgControls.data.X360.STEER_THUMB == 'LEFT' and ac.GamepadAxis.LeftThumbX or ac.GamepadAxis.RightThumbX)
    if math.abs(b) > 0.01 then
      local relSteer = car.steer / 396
      ui.drawLine(f + vec2(0, (0.5 + 0.5 * relSteer) * s.y), f + vec2(s.x, (0.5 + 0.5 * relSteer) * s.y), rgbm.colors.gray)
      ui.drawLine(f + vec2((0.5 + 0.5 * b) * s.x, 0), f + vec2((0.5 + 0.5 * b) * s.x, s.y), rgbm.colors.gray)
    end
    local v = cfgControls.data.X360.STEER_GAMMA
    if v == 0 then v = 1 end
    for i0 = 0, 1 do
      for i = 0, 30 do
        local x = (i / 30) ^ 2
        if i0 == 1 then ui.pathLineTo(f + vec2(0.5 + 0.5 * x, 0.5 + 0.5 * x ^ v) * s)
        else ui.pathLineTo(f + vec2(0.5 - 0.5 * x, 0.5 - 0.5 * x ^ v) * s) end
      end
      ui.pathStroke(ac.getUI().accentColor)
    end
  end)
  slider(cfgControls, 'X360', 'STEER_FILTER', 0, 100, 100, 'Filter: %.0f%%', 'Smooths out steering angle')
  slider(cfgControls, 'X360', 'SPEED_SENSITIVITY', 0, 100, 100, 'Speed sensitivity: %.0f%%', 'Increase to reduce steering range with high speeds')
  slider(cfgControls, 'X360', 'STEER_DEADZONE', 0, 100, 100, 'Deadzone: %.0f%%', 'Ignore steering inputs within that range')
  slider(cfgControls, 'X360', 'RUMBLE_INTENSITY', 0, 100, 100, 'Rumble intensity: %.0f%%', 'How much gamepad would shake (if supported)')

  ui.offsetCursorY(16)
  ui.header('Buttons:')
  for i = 1, #gamepadButtonsOrdered do
    local v = gamepadButtonsOrdered[i]
    if type(v) == 'string' then
      ui.offsetCursorY(16)
      ui.header(v..':')
    else
      gamepadButton(v[1], v[2])
    end
  end

  ui.offsetCursorY(16)
  ui.header('Tweaks:')
  comboGamepadAxis('AXIS_REMAP_THROTTLE', 'Throttle')
  comboGamepadAxis('AXIS_REMAP_BRAKES', 'Brakes')
end

local function axisGammaSlider(section, format, tooltip)
  slider(cfgControls, section, 'GAMMA', 1, 500, 100, format, function ()
    ui.text(string.format('Curve (use %s to see it in action):', tooltip))
    local f, s = drawCurveBase(vec2(300, 120))
    local b = axleValue(section)
    if b > 0.001 then
      ui.drawLine(f + vec2(0, car.brake * s.y), f + vec2(s.x, car.brake * s.y), rgbm.colors.gray)
      ui.drawLine(f + vec2(b * s.x, 0), f + vec2(b * s.x, s.y), rgbm.colors.gray)
    end
    local v = cfgControls.data[section].GAMMA
    if v == 0 then v = 1 end
    for i = 0, 30 do
      local x = (i / 30) ^ 2
      ui.pathLineTo(f + vec2(x, x ^ v) * s)
    end
    ui.pathStroke(ac.getUI().accentColor)
  end)
end

function configurators.WHEEL()
  userFFBGainSlider()

  ui.offsetCursorY(16)
  ui.header('Steering:')
  slider(cfgControls, 'STEER', 'STEER_GAMMA', 20, 400, 100, 'Gamma: %.0f%%', function ()
    ui.text('Curve (steer to see it in action):')
    local f, s = drawCurveBase(vec2(300, 120))
    local b = axleValue('STEER')
    ui.pushClipRect(f + vec2(0, s.y), f + vec2(s.x, 0))
    if math.abs(b) > 0.003 then
      local relSteer = car.steer / (cfgControls.data.STEER.LOCK / 2)
      ui.drawLine(f + vec2(0, (0.5 + 0.5 * relSteer) * s.y), f + vec2(s.x, (0.5 + 0.5 * relSteer) * s.y), rgbm.colors.gray)
      ui.drawLine(f + vec2((0.5 + 0.5 * b) * s.x, 0), f + vec2((0.5 + 0.5 * b) * s.x, s.y), rgbm.colors.gray)
    end
    local v = cfgControls.data.STEER.STEER_GAMMA
    if v == 0 then v = 1 end
    for i0 = 0, 1 do
      for i = 0, 30 do
        local x = (i / 30) ^ 2
        if i0 == 1 then ui.pathLineTo(f + vec2(0.5 + 0.5 * x, 0.5 + 0.5 * x ^ v) * s)
        else ui.pathLineTo(f + vec2(0.5 - 0.5 * x, 0.5 - 0.5 * x ^ v) * s) end
      end
      ui.pathStroke(ac.getUI().accentColor)
    end
    ui.popClipRect()
  end)
  slider(cfgControls, 'STEER', 'SPEED_SENSITIVITY', 0, 100, 100, 'Speed sensitivity: %.0f%%', 'Reduces sensitivity when car accelerates')
  
  ui.offsetCursorY(16)
  ui.header('Others:')
  slider(cfgControls, 'STEER', 'DEBOUNCING_MS', 0, 200, 1, 'Debouncing: %.0f ms', 'Minimum delay between gear shifts with sequential gearbox')
  if ac.getPatchVersionCode() > 2554 then
    axisGammaSlider('THROTTLE', 'Gas gamma: %.0f%%', 'gas pedal')
  end
  axisGammaSlider('BRAKES', 'Brakes gamma: %.0f%%', 'brake pedal')
  if ac.getPatchVersionCode() > 2554 then
    axisGammaSlider('CLUTCH', 'Clutch gamma: %.0f%%', 'clutch pedal')
    axisGammaSlider('HANDBRAKE', 'Handbrake gamma: %.0f%%', 'handbrake')
  end

  ui.offsetCursorY(16)
  ui.header('FFB:')
  slider(cfgControls, 'STEER', 'FF_GAIN', 0, 200, 100, 'Gain: %.0f%%', 'Overall FFB intensity')
  slider(cfgControls, 'STEER', 'FILTER_FF', 0, 100, 100, 'Filter: %.0f%%', 'Increase to smooth out FFB')
  slider(cfgControls, 'FF_SKIP_STEPS', 'VALUE', 0, 10, 1, 'Skip steps: %.0f', 
    string.format('Resulting FFB refresh rate: %.0f Hz', 333 / (1 + math.max(0, cfgControls.data.FF_SKIP_STEPS.VALUE))))

  ui.offsetCursorY(16)
  ui.header('FFB tweaks:')
  slider(cfgControls, 'FF_TWEAKS', 'MIN_FF', 0, 100, 100, 'Minimum force: %.0f%%', 
    'Minimum force to be sent to the wheel (high values might introduce rattling at high speeds)')
  slider(cfgControls, 'FF_TWEAKS', 'CENTER_BOOST_GAIN', 0, 1000, 100, 'Center boost gain: %.0f%%',
    'Specifies amount of optional FFB increase in the center of steering range')
  slider(cfgControls, 'FF_TWEAKS', 'CENTER_BOOST_RANGE', 0, 100, 100, 'Center boost range: %.0f%%',
    'Specifies width of what constitutes a middle of that optional FFB increase in the center of steering range')

  ui.offsetCursorY(16)
  ui.header('FFB enhancements:')
  slider(cfgControls, 'FF_ENHANCEMENT', 'CURBS', 0, 200, 100, 'Curbs: %.0f%%', 'Adds vibrations when driving over curbs')
  slider(cfgControls, 'FF_ENHANCEMENT', 'ROAD', 0, 200, 100, 'Road: %.0f%%', 'Adds more vibrations for bumps in road surface')
  slider(cfgControls, 'FF_ENHANCEMENT', 'SLIPS', 0, 200, 100, 'Slips: %.0f%%', 'Adds vibrations when car is slipping')
  slider(cfgControls, 'FF_ENHANCEMENT', 'ABS', 0, 200, 100, 'ABS: %.0f%%', 'Adds vibrations when ABS is in action')
  if settings.showHidden then
    slider(cfgControls, 'FF_ENHANCEMENT_2', 'UNDERSTEER', 0, 200, 100, 'Understeer: %.0f%%', 'Fake effect reducing FFB when car is understeering')
  end
  
  ui.offsetCursorY(16)
  ui.header('FFB gyro:')
  gyroModeCombo()

  if settings.showHidden then
    ui.offsetCursorY(16)
    ui.header('Low speed FFB reduction:')
    slider(cfgSystem, 'LOW_SPEED_FF', 'SPEED_KMH', 0, 30, 1, 'Speed threshold: %.0f km/h', 'When driving slower than this, FFB will be lowered to prevent unnatural vibrations')
    slider(cfgSystem, 'LOW_SPEED_FF', 'MIN_VALUE', 0, 100, 100, 'Force multiplier: %.0f%%', 'Multiplier applied to FFB when driving slower than threshold')

    ui.offsetCursorY(16)
    ui.header('FFB damper:')
    slider(cfgSystem, 'FF_EXPERIMENTAL', 'DAMPER_GAIN', 0, 200, 100, 'Gain: %.0f%%', 'Adds stiffness to wheel when car is not moving fast (when car is stationary, gets cancelled out by low speed FFB reduction)')
    slider(cfgSystem, 'FF_EXPERIMENTAL', 'DAMPER_MIN_LEVEL', 0, 200, 100, 'Min level: %.0f%%', 'Amount of damping remaining for cars driving faster')
  end

  ui.offsetCursorY(16)
  ui.header('FFB post-processing:')
  if cfgFFBTweaks.data.BASIC.ENABLED then
    slider(cfgFFBTweaks, 'POSTPROCESSING', 'RANGE_COMPRESSION', 50, 400, 100, 'Range compression: %.0f%%', 'Set higher to compress force and make small forces easier to feel')
    if cfgFFBTweaks.data.POSTPROCESSING.RANGE_COMPRESSION ~= 1 then
      checkbox(cfgFFBTweaks, 'POSTPROCESSING', 'RANGE_COMPRESSION_ASSIST', 'Use car steer assist', 'Automatically convert STEER_ASSIST into range compression on cars that use STEER_ASSIST')
    end
  end
  ppModeCombo()
end

local vr = ac.getVR()

function script.windowMain(dt)
  ui.pushFont(ui.Font.Small)
  ui.pushItemWidth(ui.availableSpaceX() - 24)

  if vr ~= nil and ac.getSim().isOpenVRMode then
    ui.header('OpenVR controller axis:')
    local w = (ui.availableSpaceX() - 16) / 4
    for j = 0, 4 do
      ui.progressBar(0.5 + 0.5 * vr.hands[0].openVRAxis[j].x, vec2(w, 2), '')
      ui.sameLine(0, 4)
      ui.progressBar(0.5 + 0.5 * vr.hands[0].openVRAxis[j].y, vec2(w, 2), '')
      ui.sameLine(0, 8)
      ui.progressBar(0.5 + 0.5 * vr.hands[1].openVRAxis[j].x, vec2(w, 2), '')
      ui.sameLine(0, 4)
      ui.progressBar(0.5 + 0.5 * vr.hands[1].openVRAxis[j].y, vec2(w, 2), '')
    end
    ac.debug('0', vr.hands[1].openVRAxis[0].x)
    ui.offsetCursorY(20)
  end

  if configurators[cfgControls.data.HEADER.INPUT_METHOD] then
    configurators[cfgControls.data.HEADER.INPUT_METHOD]()
  else
    ui.textWrapped('Unknown input method: '..tostring(cfgControls.data.HEADER.INPUT_METHOD))
    return
  end

  ui.popItemWidth()

  if settings.showDisclaimer then
    ui.offsetCursorY(16)
    if cfgControls.data.HEADER.INPUT_METHOD == 'WHEEL' and not cfgFFBTweaks.data.BASIC.ENABLED then
      ui.textWrapped('FFB Tweaks module is disabled. Click here to enable it and get more options:')
      if ui.button('Enable FFB Tweaks') then
        cfgFFBTweaks:set('BASIC', 'ENABLED', true)
      end
    elseif cfgControls.data.HEADER.INPUT_METHOD == 'WHEEL'then
      ui.textWrapped('Hold Shift when moving slider for more precision. Hold Ctrl and click on a slider to edit it. Please be careful if you are using a direct drive wheel, do not input crazy values.')
    elseif cfgControls.data.HEADER.INPUT_METHOD == 'KEYBOARD' then 
      ui.textWrapped('Hold Shift when moving slider for more precision. Hold Ctrl and click on a slider to edit it. To toggle mouse steering during the race, use Ctrl+M.')
    else
      ui.textWrapped('Hold Shift when moving slider for more precision. Hold Ctrl and click on a slider to edit it.')
    end
  end

  ui.popFont()
end

function script.windowMainSettings(dt)
  ui.pushFont(ui.Font.Small)
  
  if ui.checkbox('Show hidden options', settings.showHidden) then settings.showHidden = not settings.showHidden end
  if ui.itemHovered() then ui.setTooltip('Hidden options are experimental and are not meant to be changed for most cases') end

  if ui.checkbox('Show disclaimer', settings.showDisclaimer) then settings.showDisclaimer = not settings.showDisclaimer end
  if ui.itemHovered() then ui.setTooltip('Please be careful when setting up direct drive wheel even if disclaimer is hidden') end
  
  if ui.checkbox('Higher precision', settings.higherPrecision) then settings.higherPrecision = not settings.higherPrecision end
  if ui.itemHovered() then ui.setTooltip('For some really fine tuning') end

  ui.offsetCursorY(16)
  ui.header('A few tips:')
  ui.textWrapped('• When app is opened, FFB settings reload automatically when configuration files change. You can use this app, but you can also use original launcher or Content Manager to edit FFB;', 400)
  ui.textWrapped('• Use “Create new curve…” in curve lists to generate new LUT curve using WheelCheck.', 400)

  ui.popFont()
end

-- function script.windowMain(dt)
--   for i = 1, ac.getJoystickCount() do
--     ui.header(ac.getJoystickName(i - 1))
--     ui.text(ac.getJoystickAxisCount(i - 1))
--     for j = 1, ac.getJoystickAxisCount(i - 1) do
--       ui.text(ac.getJoystickAxisValue(i - 1, j - 1))
--     end
--     for j = 1, ac.getJoystickButtonsCount(i - 1) do
--       ui.text(ac.isJoystickButtonPressed(i - 1, j - 1) and '1' or '0')
--       ui.sameLine(0, 0)
--     end
--     ui.newLine()
--   end
-- end
