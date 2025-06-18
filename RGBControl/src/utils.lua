local Glow = require('src/glow')
local Saving = require('src/saving')

---@param gradient rgb[]
---@param pos number
local function sampleGradient(gradient, pos, looped)
  pos = math.saturateN(pos)
  local v = (looped and #gradient or #gradient - 1) * pos
  local i = math.floor(v)
  local x = v - i
  local g1 = gradient[i + 1]
  local g2 = gradient[looped and i + 1 == #gradient and 1 or math.min(i + 2, #gradient)]
  local s = math.lerp(g1:saturation(), g2:saturation(), x)
  local r = rgb():setLerp(g1, g2, x)
  r:adjustSaturation(s / math.max(0.1, r:saturation()))
  return r
end

---@return App.Conditions
local function emptyConds()
  return {{ invert = false }}
end

---@alias App.Condition {invert: boolean, op: 'and'|'or'|nil, cond: App.Cfg.Entry}
---@alias App.Conditions App.Condition[]

local stops = setmetatable({}, { __mode = 'kv' })
local held = setmetatable({}, { __mode = 'kv' })

---@param conds App.Conditions
local function isConditionPassing(conds, hold, stop)
  local ret
  for i = 1, #conds do
    local cond = conds[i]
    local r
    local c = cond.cond and Glow.getConditionByKey(cond.cond.key)
    local r = not not (c and c.condition(cond.cond))
    if cond.invert then r = not r end
    if ret == nil then
      ret = r
    elseif cond.op == 'and' then
      ret = ret and r
    else
      ret = ret or r
    end
  end
  if stop or hold then
    local now = os.preciseClock()
    if stop then
      if not ret then
        stops[conds] = nil
      elseif not stops[conds] then
        stops[conds] = now
      elseif stops[conds] + stop < now then
        ret = false
      end
    end
    if hold then
      if ret then
        held[conds] = now
      else
        local cur = held[conds]
        if cur and now < cur + hold then
          return true
        end
      end
    end
  end
  return ret
end

---@param conds App.Conditions
local function getConditionLabel(conds)
  local ret
  for i = 1, #conds do
    local cond = conds[i]
    local c = cond.cond and Glow.getConditionByKey(cond.cond.key).resolveName(cond.cond) or '?'
    if cond.invert then c = 'not ' .. c end
    if ret == nil then
      ret = c
    elseif cond.op == 'and' then
      ret = ret .. ' and ' .. c
    else
      ret = ret .. ' or ' .. c
    end
  end
  return ret
end

local _conditionsStepperStack = {}
local _conditionsStepperStackSize = 0
local _conditionsStepperState = true
local _conditionsStepperCallback = function(gcfg)
  if gcfg and gcfg.branch then
    local passing
    if gcfg.branch == 'if' then
      passing = gcfg.conds and isConditionPassing(gcfg.conds, gcfg.hold, gcfg.stop)
      _conditionsStepperStackSize = _conditionsStepperStackSize + 1
      _conditionsStepperStack[_conditionsStepperStackSize] = passing and 1 or 0
    elseif gcfg.branch == 'elseif' then
      if _conditionsStepperStackSize > 0 and _conditionsStepperStack[_conditionsStepperStackSize] <= 1 then
        passing = _conditionsStepperStack[_conditionsStepperStackSize] == 0 and gcfg.conds and
            isConditionPassing(gcfg.conds, gcfg.hold, gcfg.stop)
        _conditionsStepperStack[_conditionsStepperStackSize] = passing and 1 or 0
      else
        passing = 0
      end
    elseif gcfg.branch == 'else' then
      if _conditionsStepperStackSize > 0 and _conditionsStepperStack[_conditionsStepperStackSize] <= 1 then
        passing = _conditionsStepperStack[_conditionsStepperStackSize] == 0
        _conditionsStepperStack[_conditionsStepperStackSize] = passing and 3 or 2
      else
        passing = 0
      end
    elseif gcfg.branch == 'end' then
      if _conditionsStepperStackSize > 0 then
        _conditionsStepperStackSize = _conditionsStepperStackSize - 1
      else
        passing = 0
      end
    end
    _conditionsStepperState = true
    for i = 1, _conditionsStepperStackSize do
      if _conditionsStepperStack[i] % 2 ~= 1 then
        _conditionsStepperState = false
        break
      end
    end
    return passing
  else
    return _conditionsStepperState
  end
end

local function conditionsStepper()
  _conditionsStepperState, _conditionsStepperStackSize = true, 0
  return _conditionsStepperCallback
end

local function glowSettings(title, glow, gcfg)
  ui.pushFont(ui.Font.Small)
  ui.header(title)
  ui.beginGroup()
  glow.settings(gcfg)
  ui.endGroup()
  Saving.item()
  ui.popFont()
end

---@param conds App.Conditions
local function conditionEditor(prefix, conds)
  local ix = 0
  local function conditionCombo(cond)
    ui.pushID(ix)
    ui.setNextItemWidth(ui.measureText(cond.invert and 'not' or '').x + 36)
    ui.combo('##1', cond.invert and 'not' or '', function()
      if ui.selectable('') then cond.invert = false end
      if ui.selectable('not') then cond.invert = true end
    end)
    if ui.itemHovered() then
      ui.setTooltip('Inverse condition if needed')
    end
    ui.sameLine(0, 0)
    local c = cond.cond and Glow.getConditionByKey(cond.cond.key)
    local n = '(select one)'
    if c then
      n = c.resolveName(cond.cond)
    end
    ui.setNextItemWidth(ui.measureText(n).x + 36)
    ui.combo('##2', n, function()
      local drawnGroups = {}
      for _, glow in ipairs(Glow.conditions) do
        if glow.group then
          if not drawnGroups[glow.group] then
            drawnGroups[glow.group] = true
            if ui.beginMenu(glow.group) then
              for _, glow2 in ipairs(Glow.conditions) do
                if glow2.group == glow.group then
                  if ui.selectable(glow2.name, glow2 == c) then
                    cond.cond = Glow.instatiate(glow2)
                  end
                  if ui.itemHovered() then
                    ui.setTooltip(glow2.description)
                  end
                end
              end
              ui.endMenu()
            end
          end
        else
          if ui.selectable(glow.name, glow == c) then
            cond.cond = Glow.instatiate(glow)
          end
          if ui.itemHovered() then
            ui.setTooltip(glow.description)
          end
        end
      end
    end)
    if c and ui.itemHovered() then
      ui.setTooltip(c.description)
    end
    if c and c.settings then
      ui.sameLine(0, 0)
      if ui.iconButton(ui.Icons.Settings, vec2(32, 0), 5, true, 0) then
        TiedPopup(function()
          glowSettings('Condition settings:', c, cond.cond)
        end)
      end
      if ui.itemHovered() then
        ui.setTooltip('Configure the condition')
      end
    end
    ui.popID()
    ix = ix + 1
  end
  local function operandCombo(cond, allowed)
    ui.setNextItemWidth(ui.measureText(cond.op or 'then').x + 36)
    if not allowed then ui.pushDisabled() end
    ui.pushID(ix)
    ui.combo('##3', cond.op or 'then', function()
      for _, label in ipairs({ 'then', 'and', 'or' }) do
        if ui.selectable(label) then
          cond.op = label ~= 'then' and label or nil
        end
        -- 1 or 0 and 0
        if _ > 1 and ui.itemHovered() then
          ui.setTooltip(
            'Note: here, “and” doesn’t have a priority over “or”, meaning “TRUE or FALSE and FALSE” would result in ”FALSE”.')
        end
      end
    end)
    if ui.itemHovered() then
      ui.setTooltip('Set to “then” to stop (or remove the next term), or to something else to add another term')
    end
    if not allowed then ui.popDisabled() end
    ui.popID()
    ix = ix + 1
    if cond.op then
      ui.offsetCursorX(ui.measureText(prefix).x)
      conditionCombo(cond)
    end
  end
  ui.alignTextToFramePadding()
  ui.text(prefix)
  ui.sameLine(0, 0)
  for i = 1, #conds + 1 do
    if i == 1 then
      conditionCombo(conds[i])
    else
      local arg = conds[i] or {}
      ui.sameLine(0, 0)
      operandCombo(arg, conds[i - 1].cond)
      if arg.op == nil then
        table.remove(conds, i)
      elseif not conds[i] then
        conds[i] = arg
      end
    end
  end
  local passing = isConditionPassing(conds)
  local col = not conds[#conds].cond and rgbm.colors.red or passing and rgbm.colors.lime or rgbm.colors.yellow
  ui.icon(not conds[#conds].cond and ui.Icons.Warning or passing and ui.Icons.Confirm or ui.Icons.Ban, 14, col)
  ui.sameLine(0, 4)
  ui.textColored(not conds[#conds].cond and 'Condition is not complete'
    or passing and 'Condition is passing' or 'Condition is not passing', col)
  ui.offsetCursorY(12)
  return conds[#conds].cond
end

local function conditionFullEditor(modeIf, created, edit)
  local ret
  local valid = conditionEditor(modeIf and 'If ' or '… else if ', created.conds)

  ui.setNextItemWidth(324)
  created.stop = ui.slider('##s', created.stop or 0, 0, 5,
    (created.stop or 0) <= 0.01 and 'Stop after: never' or 'Stop after: %.1f s')
  if ui.itemHovered() then
    ui.setTooltip('Exit active state after this time (resets once trigger stops)')
  end

  ui.setNextItemWidth(324)
  created.hold = ui.slider('##h', created.hold or 0, 0, 5, 'Hold for: %.1f s')
  if ui.itemHovered() then
    ui.setTooltip('Once triggered, hold in active state for this time')
  end

  ui.setNextItemIcon(ui.Icons.Confirm)
  if ui.button(edit and 'Apply' or 'Add', vec2(160, 0), valid and 0 or ui.ButtonFlags.Disabled) then
    if created.hold <= 0.01 then created.hold = nil end
    if created.stop <= 0.01 then created.stop = nil end
    ui.closePopup()
    ret = true
  end
  ui.sameLine(0, 4)
  ui.setNextItemIcon(ui.Icons.Cancel)
  if ui.button('Cancel', vec2(160, 0)) then
    ui.closePopup()
    ret = false
  end
  return ret
end

local function assignCondition(dst, src)
  dst.conds = src.conds
  dst.hold = src.hold
  dst.stop = src.stop
  Saving.save()
end

---@param colors rgb[]
local function gradientEditor(label, colors)
  ui.alignTextToFramePadding()
  ui.text(label .. ':')
  ui.sameLine(0, 8)
  local r
  for i = 1, #colors do
    ui.colorButton('##%s' % i, colors[i], ui.ColorPickerFlags.PickerHueWheel)
    Saving.item()
    ui.sameLine(0, 2)
    if #colors > 2 and ui.itemClicked(ui.MouseButton.Middle) then
      r = i
    end
  end
  if ui.iconButton(ui.Icons.Plus, vec2(20, 20), 5) then
    colors[#colors + 1] = table.random(rgb.colors):clone()
    Saving.save()
  end
  if #colors > 2 then
    ui.sameLine(0, 2)
    if ui.iconButton(ui.Icons.Minus, vec2(20, 20), 5) then
      r = #colors
    end
    if ui.itemHovered() then
      ui.setTooltip('Click a color with middle mouse button to remove it')
    end
  end
  if r then
    table.remove(colors, r)
    Saving.save()
  end
end

local function colorSelector(label, color)
  ui.alignTextToFramePadding()
  ui.text('%s:' % label)
  ui.sameLine(100)
  ui.colorButton('##%s' % label, color, ui.ColorPickerFlags.PickerHueWheel)
  Saving.item()
end

local function colorSelectorOpt(label, color, colorRef)
  if ui.checkbox(color and '%s:' % label or label, color ~= nil) then
    color = not color and (colorRef or rgb.colors.white):clone() or nil
    Saving.save()
  end
  if color then
    ui.sameLine(100)
    ui.colorButton('##b%s' % label, color, ui.ColorPickerFlags.PickerHueWheel)
    Saving.item()
  end
  return color
end

local function flashingOut(label, flashing)
  if ui.checkbox(flashing and '%s:' % label or label, flashing ~= nil) then
    flashing = not flashing and { time = 1, active = 0.5 } or nil
    Saving.save()
  end
  if flashing then
    ui.sameLine(100)
    ui.setNextItemWidth(80)
    flashing.time = ui.slider('##0%s' % label, flashing.time, 0.1, 5, 'Period: %.1f s')
    Saving.item()
    ui.sameLine(0, 0)
    ui.setNextItemWidth(80)
    flashing.active = ui.slider('##1%s' % label, flashing.active * 100, 0, 100, 'Active: %.0f%%') / 100
    Saving.item()
  end
  return flashing
end

---@param id string
---@param value number
---@param min number
---@param max number
---@param default number
---@param label string
---@param power number?
---@return number
local function sliderWithReset(id, value, min, max, default, label, power)
  ui.pushID(id)
  ui.setNextItemWidth(248 - 24)
  value = ui.slider('##0', value or default, min, max, label, power)
  Saving.item()
  ui.sameLine(0, 4)
  if ui.iconButton(ui.Icons.Reset, 20, 5, true, math.abs(value - default) < 1e-6 and ui.ButtonFlags.Disabled or 0) then
    value = default
    Saving.save()
  end
  ui.popID()
  return value
end

---@type table<OpenRGB.TweakKey, string[]>
local propNames = {
  singleColor = {'Single color', 'Single c.'},
  partialCoverage = {'Partial coverage', 'Partial cov.'},
  backgroundColor = {'Background color', 'Bg.'},
  flipX = {'Flip direction', 'Flip'},
  delay = {'Delay', 'Del.'},
  delay2 = {'Delay (alt.)', 'Del./A.'},
  smoothing = {'Smoothness', 'Smo.'},
  smoothing2 = {'Smoothness (alt.)', 'Smo./A.'},
  saturation = {'Saturation', 'Sat.'},
  brightness = {'Brightness', 'Bri.'},
  gamma = {'Gamma', 'Gam.'},
}

---@param prop OpenRGB.TweakKey
---@param value number|boolean|rgb
---@param short boolean?
local function getPropLabel(prop, value, short)
  if propNames[prop] then
    if type(value) == 'boolean' then
      return short 
        and string.format('%s = %s', propNames[prop][2], value and 'yes' or 'no')
        or string.format('Set %s to %s', propNames[prop][1]:lower(), value and 'yes' or 'no')
    elseif rgb.isrgb(value) then
      ---@cast value rgb
      return short
        and string.format('%s = %s', propNames[prop][2], value:hex())
        or string.format('Set %s to %s', propNames[prop][1]:lower(), value:hex())
    elseif prop == 'delay' or prop == 'delay2' then
      return short 
        and string.format('%s = %.2f s', propNames[prop][2], value)
        or string.format('Set %s to %.2f s', propNames[prop][1]:lower(), value)
    elseif prop == 'smoothing' or prop == 'smoothing2' then
      return short 
        and string.format('%s = %.0f%%', propNames[prop][2], 100 - value * 100)
        or string.format('Set %s to %.0f%%', propNames[prop][1]:lower(), 100 - value * 100)
    else
      return short 
        and string.format('%s = %.0f%%', propNames[prop][2], value * 100)
        or string.format('Set %s to %.0f%%', propNames[prop][1]:lower(), value * 100)
    end
  end
  return string.format(short and '%s = %s' or 'Set %s to %s', prop, value)
end

---@generic T : number|boolean|rgb
---@param prop OpenRGB.TweakKey
---@param value T
---@return T
local function getPropEditor(title, prop, value)
  if propNames[prop] then
    ui.header('%s/%s:' % {title, propNames[prop][1]})
    if type(value) == 'boolean' then
      if ui.checkbox(propNames[prop][1], value) then
        value = not value
      end
    elseif rgb.isrgb(value) then
      colorSelector('Color', value)
    elseif prop == 'delay' or prop == 'delay2' then
      value = ui.slider('##0', value or 0, 0, 3, 'Delay: %.2f s')
    elseif prop == 'smoothing' or prop == 'smoothing2' then
      value = 1 - ui.slider('##0', 100 - (value or 1) * 100, 0, 100, 'Smoothing: %.0f%%', 0.5) / 100
    else
      value = ui.slider('##0', (value or 1) * 100, 0, 300, propNames[prop][1]..': %.0f%%') / 100
    end
    Saving.item()
    return value
  end
  return value
end

local function conditionPopupEditor(modeIf, existing, callback)
  if existing then
    local cloned = table.clone(existing, 'full')
    local closed = false
    TiedPopup(function()
      local ret = conditionFullEditor(modeIf, cloned, true)
      if ret then
        callback(cloned)
      end
      if ret ~= nil then
        closed = true
      end
    end, {
      onClose = function()
        if not closed and not table.same(cloned.conds, existing) then
          ui.toast(ui.Icons.Cancel, 'Edits cancelled'):button(ui.Icons.Backspace, 'Apply edits', function()
            callback(cloned)
          end)
        end
      end
    })
  else
    local created = {conds = emptyConds()}
    TiedPopup(function ()
      if conditionFullEditor(modeIf, created, false) then
        callback(created)
      end
    end)
  end
end

return {
  sampleGradient = sampleGradient,
  emptyConds = emptyConds,
  isConditionPassing = isConditionPassing,
  getConditionLabel = getConditionLabel,
  glowSettings = glowSettings,
  conditionEditor = conditionEditor,
  conditionFullEditor = conditionFullEditor,
  conditionsStepper = conditionsStepper,
  conditionsStepperDepth = function() return _conditionsStepperStackSize end,
  gradientEditor = gradientEditor,
  colorSelector = colorSelector,
  colorSelectorOpt = colorSelectorOpt,
  flashingOut = flashingOut,
  assignCondition = assignCondition,
  sliderWithReset = sliderWithReset,
  getPropLabel = getPropLabel,
  getPropEditor = getPropEditor,
  conditionPopupEditor = conditionPopupEditor,
}
