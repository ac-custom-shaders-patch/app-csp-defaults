local settings = ac.storage({
  USE_BUILTIN_EXE = true,
  KEEP_ALIVE = false
})

local function appFooter()
  ui.separator()
  ui.pushFont(ui.Font.Small)
  ui.alignTextToFramePadding()
  ui.text('Made possible thanks to ')
  ui.sameLine(0, 0)
  if ui.textHyperlink('OpenRGB') then
    os.openURL('https://openrgb.org')
  end
  if ui.itemHovered() then
    ui.setTooltip('https://openrgb.org')
  end
  ui.sameLine(0, 0)
  ui.text('. ')
  ui.sameLine(0, 0)
  if ui.textHyperlink('Restart app') then
    ac.restartApp()
  end
  if ui.itemHovered() then
    ui.setTooltip('If you don’t see newly plugged devices, restarting the app might help')
  end
  ui.sameLine(0, 0)
  ui.text('. ')
end

TiedPopup = function(cb, args)
  local pos = ui.windowPos() + vec2(ui.itemRectMin().x - ui.getScrollX(), ui.itemRectMax().y - ui.getScrollY())
  return ui.popup(cb, table.assign(ac.getUI().windowSize.y - pos.y < 200 and {
    position = ui.windowPos() + ui.itemRectMin(),
    pivot = vec2(0, 1)
  } or {
    position = pos,
    pivot = vec2(0, 0)
  }, args))
end

local openrgb = require('src/openrgb')
openrgb.init({ exe = settings.USE_BUILTIN_EXE and (settings.KEEP_ALIVE and 'keep-alive' or 'linked') or nil })

function script.windowSettings()
  if ui.checkbox('Use built-in executable', settings.USE_BUILTIN_EXE) then
    settings.USE_BUILTIN_EXE = not settings.USE_BUILTIN_EXE
  end
  if ui.itemHovered() then
    ui.setTooltip(
      'With this option, if app fails to detect a running instance of OpenRGB with SDK server active, it’ll download and run its own copy of OpenRGB. Generally speaking, running OpenRGB service on your side might work better, because you would be able to tune its settings and everything, but this option might make things easier.')
  end
  if not settings.USE_BUILTIN_EXE then ui.pushDisabled() end
  if ui.checkbox('Keep service running', settings.KEEP_ALIVE) then
    settings.KEEP_ALIVE = not settings.KEEP_ALIVE
  end
  if ui.itemHovered() then
    ui.setTooltip(
      'Enable this option to keep OpenRGB launched by this app running in system tray after AC is finished. Might speed up loading of subsequent sessions.')
  end
  if not settings.USE_BUILTIN_EXE then ui.popDisabled() end
  ui.offsetCursorY(12)
  appFooter()
end

---@alias App.Cfg.Entry {key: string, _name: string?}|{branch: 'if'|'else'|'elseif'|'end', conds: App.Conditions, hold: number?, stop: number?}|{prop: OpenRGB.TweakKey, value: number, conds: App.Conditions, hold: number?, stop: number?}
---@alias App.Cfg.Zone {zGlows: App.Cfg.Entry[], zTweaks: OpenRGB.Tweaks?}
---@alias App.Cfg.Device {perZone: table<integer, App.Cfg.Zone>, perCustomZone: table<integer, App.Cfg.Zone>, customZones: {name: string, leds: integer[]}[]}
---@alias App.Cfg table<string, App.Cfg.Device>

local Glows = require('src/glow')
local Utils = require('src/utils')
local Saving = require('src/saving')
require('src/glows')
require('src/conditions')

local editing = nil
local computedComplex = {}
local lastComputed, lastComputedF = nil, nil

---@param device OpenRGB.Device
---@param glow Glow<any>
---@param gcfg App.Cfg.Entry
---@param targetIndex  nil|integer|integer[]
---@param zone OpenRGB.Tweaks?
---@return rgb?
local function assignGlow(device, glow, gcfg, targetIndex, zone)
  local c, g1, g2, progress = glow.accessor(gcfg)
  if not c then return nil end
  if g1 or progress then
    computedComplex.main = c
    computedComplex.alt1 = g1
    computedComplex.alt2 = g2
    computedComplex.progress = (progress or 1) * 1.0001
    device:fill(computedComplex, targetIndex, nil, zone)
    return computedComplex.main
  else
    device:fill(c, targetIndex, nil, zone)
    return c
  end
end

---@type OpenRGB.Tweaks
local zoneOverrides = {}

---@param device OpenRGB.Device
---@param zone App.Cfg.Zone
---@param targetIndex nil|integer|integer[]
---@return rgb?
local function computeColor(device, zone, targetIndex)
  local anyZoneOverrides = false
  if zone then
    local count = #zone.zGlows
    if count > 0 then
      local stepper = Utils.conditionsStepper()
      for i = 1, count do
        local gcfg = zone.zGlows[i]
        if gcfg.branch then
          stepper(gcfg)
        elseif stepper() then
          local glow = Glows.getGlowByKey(gcfg.key)
          if glow then
            local c = assignGlow(device, glow, gcfg, targetIndex, anyZoneOverrides and zoneOverrides or zone.zTweaks)
            if c then return c end
          elseif gcfg.prop then
            if not anyZoneOverrides then
              anyZoneOverrides = true
              table.assign(zoneOverrides, zone.zTweaks)
            end
            if not gcfg.conds or Utils.isConditionPassing(gcfg.conds, gcfg.hold, gcfg.stop) then
              zoneOverrides[gcfg.prop] = gcfg.value
            end
          end
        end
      end
    end
  end
  if targetIndex == nil then
    device:fill(rgb.colors.black, nil, nil, anyZoneOverrides and zoneOverrides or zone.zTweaks)
  end
  return nil
end

local targetFrequency = 30
local timeAccumulator = 0
local customZoneEditor

local function hoverColor()
  return ac.getUI().accentColor.rgb * (0.6 + 0.4 * math.sin(os.preciseClock() * 8))
end

---@param dcfg App.Cfg.Device
---@param zoneIndex integer
---@return nil|integer|integer[]
local function getDeviceIndex(dcfg, zoneIndex)
  if zoneIndex <= 1000 then
    return zoneIndex > 1 and zoneIndex - 1 or nil
  else
    return dcfg.customZones[zoneIndex - 1000].leds
  end
end

function script.update(dt)
  timeAccumulator = timeAccumulator + dt * targetFrequency
  if timeAccumulator > 1 then
    timeAccumulator = math.fmod(timeAccumulator, 1)
    local devices = openrgb.devices()
    if devices then
      for i = 1, #devices do
        local device = devices[i]
        if customZoneEditor and device == customZoneEditor[1] then
          for j = 1, #customZoneEditor[2] do
            device:fill(
              j == customZoneEditor[3] and hoverColor() or customZoneEditor[2][j] and rgb.colors.white or
              rgb.colors.black,
              j - 1, 1)
          end
          device:commit()
        else
          local dcfg = Saving.cfg[device.uuid]
          if dcfg then
            local lastComputedD = lastComputed and lastComputed[1] == device and lastComputed or nil
            for j = 1, dcfg.perZone and #dcfg.perZone or 0 do
              local c = computeColor(device, dcfg.perZone[j], getDeviceIndex(dcfg, j))
              if c and lastComputedD then lastComputedD[2][j] = c end
            end
            for j = 1, dcfg.perCustomZone and #dcfg.perCustomZone or 0 do
              local c = computeColor(device, dcfg.perCustomZone[j], dcfg.customZones[j].leds)
              if c and lastComputedD then lastComputedD[2][1000 + j] = c end
            end
            if editing and editing[1] == device then
              if editing[3] then
                assignGlow(device, editing[3], editing[4] or editing[3].defaults, getDeviceIndex(dcfg, editing[2]), nil)
              else
                device:fill(hoverColor(), getDeviceIndex(dcfg, editing[2]))
              end
            end
            device:commit()
          end
        end
      end
    end
  end
  editing = nil
  lastComputedF, lastComputed = lastComputed, nil
  customZoneEditor = nil
end

local dragging = nil ---@type {device: OpenRGB.Device, zone: integer, from: integer, name: string}?

---@param entry App.Cfg.Entry
local function getEntryName(entry)
  if (entry.branch or entry.prop) and not Glows.getGlowByKey(entry.key) then
    if entry.branch then return 'Branch' end
    if entry.prop then return 'Modifier' end
  end
  return 'Glow'
end

local function addEntry(zcfg, entry)
  table.insert(zcfg.zGlows, entry)
  Saving.save()
  ui.toast(ui.Icons.Confirm, '%s added' % getEntryName(entry), function()
    table.removeItem(zcfg.zGlows, entry)
    Saving.save()
  end)
end

---@param device OpenRGB.Device
local function openRGBDevice(device)
  ---@type App.Cfg.Device
  local dcfg = table.getOrCreate(Saving.cfg, device.uuid, function() return { perZone = {} } end)
  lastComputed = { device, {} }

  local function zone(index, zoneName, ledsCount)
    if index > 1000 and not dcfg.perCustomZone then
      dcfg.perCustomZone = {}
    end

    ---@type App.Cfg.Zone
    local zcfg = index > 1000
        and table.getOrCreate(dcfg.perCustomZone, index - 1000, function() return { zGlows = {} } end)
        or table.getOrCreate(dcfg.perZone, index, function() return { zGlows = {} } end)

    local nodeOpened = ui.beginTreeNode('%s###%d' % { zoneName, index },
      bit.bor((index == 1 or #zcfg.zGlows > 0) and ui.TreeNodeFlags.DefaultOpen or 0, ui.TreeNodeFlags.Framed))
    do
      local ret = lastComputedF and lastComputedF[2] and lastComputedF[2][index]
      local r1, r2 = ui.itemRect()
      local w = ui.measureText(zoneName).x
      local t1 = vec2(r1.x + w + 40, r1.y)
      local t2 = r2:clone()
      local p1 = vec2(r2.x - 8, r1.y + 4)
      local p2 = vec2(r2.x - 4, r2.y - 4)
      ui.drawTextClipped('• %d LED%s' % { ledsCount, ledsCount == 1 and '' or 's' }, t1, t2, ui.itemTextColor(0.5),
        vec2(0, 0.5))
      if #zcfg.zGlows > 0 then
        if ret then
          ui.drawRectFilled(p1, p2, ret)
        else
          ui.drawRect(p1, p2, rgbm.colors.gray)
        end
        t2.x = t2.x - 16
        ui.drawTextClipped(#zcfg.zGlows == 1 and '1 item' or '%d items' % #zcfg.zGlows, t1, t2, ui.itemTextColor(),
          vec2(1, 0.5))
      end
    end
    if ui.itemHovered() then
      editing = { device, index }
    end
    if nodeOpened then
      ui.pushFont(ui.Font.Small)
      local move
      local seenActive
      local draggingDst = -1
      local draggingSameList = dragging and dragging.device == device and dragging.zone == index
      if dragging then
        draggingDst = math.floor((ui.mouseLocalPos().y - ui.getCursorY()) / 23) + 1
        if draggingDst > ((not draggingSameList or draggingDst > dragging.from) and #zcfg.zGlows + 1 or #zcfg.zGlows) then
          draggingDst = -1
        end
        if not ui.mouseDown() and draggingDst ~= -1 and draggingDst >= 1 then
          move = draggingSameList
              and { dragging.from, draggingDst > dragging.from and draggingDst - 1 or draggingDst }
              or { draggingDst, dragging.from, dragging.device, dragging.zone }
          dragging = nil
        end
      end
      local condsStepper = Utils.conditionsStepper()
      local restAreBlocked
      for i, gcfg in ipairs(zcfg.zGlows) do
        ui.pushID(i)
        local glow = Glows.getGlowByKey(gcfg.key)
        local hasSettings = glow and glow.settings or not glow and (gcfg.conds or gcfg.prop)
        local gapRight = hasSettings and -84 or -60
        local draggingMe = dragging and draggingSameList and dragging.from == i

        if restAreBlocked and restAreBlocked == Utils.conditionsStepperDepth() and not glow and gcfg.branch and gcfg.branch ~= 'if' then
          restAreBlocked = nil
        end

        local fadeEntry = dragging and not draggingMe or not dragging and restAreBlocked
        local clipped = ui.availableSpaceX() - 20 * Utils.conditionsStepperDepth() - 40 < -gapRight
        if clipped then
          ui.pushClipRect(vec2(), vec2(ui.getCursorX() + ui.availableSpaceX() + gapRight, math.huge), true)
        end

        if draggingMe then
          -- ui.pushStyleVarAlpha(0.5)
        elseif dragging and draggingDst == i and (not draggingSameList or dragging.from + 1 ~= i) then
          local c = ui.getCursor()
          c.y = c.y - 3
          ui.drawLine(c, c + vec2(ui.windowWidth(), 0), rgbm.colors.white, 1)
        end
        do
          ui.backupCursor()
          ui.offsetCursorX(28)
          ui.invisibleButton('#drag', vec2(gapRight, 20))
          if ui.itemHovered() or dragging == i then
            ui.setMouseCursor(ui.MouseCursor.ResizeNS)
          end
          if ui.itemActive() then
            local dragName = glow and glow.name or gcfg.branch and 'Branch' or gcfg.prop and 'Modifier' or 'Unknown'
            dragging = { device = device, zone = index, from = i, name = '%s/%s/%s' % {device.name, zoneName, dragName} }
          end
          if ui.itemClicked(ui.MouseButton.Right) then
            TiedPopup(function ()
              if ui.menuItem('Duplicate') then
                table.insert(zcfg.zGlows, i + 1, table.clone(gcfg, 'full'))
              end
            end)
          end
          ui.restoreCursor()
        end
        ui.offsetCursorX(20 * Utils.conditionsStepperDepth())
        ui.alignTextToFramePadding()

        if not glow and not gcfg.branch and not gcfg.prop then
          if fadeEntry then ui.pushStyleVarAlpha(0.5) end
          ui.text('“%s” is missing' % gcfg.key)
          if fadeEntry then ui.popStyleVar() end
        elseif not glow and gcfg.branch then
          local passing = condsStepper(gcfg)
          if gcfg.branch ~= 'if' and passing ~= 0 then
            ui.offsetCursorX(-20)
          end
          ui.dummy(20)
          if ui.itemHovered() then
            if passing == 0 then ui.setTooltip('No matching “if” branch before this one') end
            if passing == true then ui.setTooltip('Branch is active') end
            if passing == false then ui.setTooltip('Branch is inactive') end
          end
          local r1, r2 = ui.itemRect()
          if passing ~= nil then
            ui.drawCircleFilled((r1 + r2) / 2, 10,
              passing == 0 and rgbm.colors.black or passing and rgbm.colors.lime or rgbm.colors.red, 4)
          else
            ui.drawCircle((r1 + r2) / 2, 10, rgbm.colors.gray, 4)
          end
          ui.drawIcon(ui.Icons.Pitlane, r1 + 5, r2 - 6, rgbm.colors.white)
          ui.sameLine(0, 8)

          local branchDisplay = gcfg.branch == 'elseif' and 'else if' or gcfg.branch
          local label = gcfg.conds and Utils.getConditionLabel(gcfg.conds)
          local textToShow = label and string.format('B.: %s %s', branchDisplay, label)
              or string.format('Branch: %s', branchDisplay)
          if fadeEntry then ui.pushStyleVarAlpha(0.5) end
          ui.textAligned(textToShow, vec2(0, 0.5), vec2(gapRight, 20), true)
          if fadeEntry then ui.popStyleVar() end
          if ui.itemHovered() then
            ui.setTooltip(label and string.format('Branch: %s %s', branchDisplay, label) or textToShow)
          end
        elseif not glow and gcfg.prop then
          local condsActive = condsStepper() and
              (not gcfg.conds or Utils.isConditionPassing(gcfg.conds, gcfg.hold, gcfg.stop))
          ui.dummy(20)
          if ui.itemHovered() then
            ui.setTooltip(not condsActive and 'Tweak is not active'
              or seenActive and 'Tweak is active, but blocked an active glow set earlier and therefore not contributing'
              or 'Tweak is active')
          end
          local r1, r2 = ui.itemRect()
          if condsActive and not seenActive then
            ui.drawRectFilled(r1, r2, rgbm.colors.white)
          else
            ui.drawRect(r1, r2, rgbm.colors.gray)
          end
          ui.drawIcon(ui.Icons.SettingsAlt, r1 + 4, r2 - 4,
            condsActive and not seenActive and rgbm.colors.black or rgbm.colors.white)
          ui.sameLine(0, 8)
          if fadeEntry then ui.pushStyleVarAlpha(0.5) end
          local labCond = gcfg.conds and Utils.getConditionLabel(gcfg.conds)
          local labShort = Utils.getPropLabel(gcfg.prop, gcfg.value, true)
          if labCond then labShort = '%s if %s' % { labShort, labCond } end
          ui.textAligned(labShort, vec2(0, 0.5), vec2(gapRight, 20), true)
          if fadeEntry then ui.popStyleVar() end
          if ui.itemHovered() then
            local labLong = Utils.getPropLabel(gcfg.prop, gcfg.value, false)
            if labCond then labLong = '%s if %s' % { labLong, labCond } end
            ui.setTooltip(labLong)
          end
        else
          local condsActive = condsStepper()
          if not glow.condition and not restAreBlocked then
            restAreBlocked = Utils.conditionsStepperDepth()
          end
          do
            local col = glow.accessor(gcfg)
            ui.dummy(20)
            local r1, r2 = ui.itemRect()
            if col then
              ui.drawCircleFilled((r1 + r2) / 2, 10, rgbm.tmp():set(col, 1), 20)
              if ui.itemHovered() then
                ui.setTooltip('This glow produces a color: %s.%s'
                  % { col:hex():upper(), fadeEntry and
                  '\nWith constantly active glow above, this one will never contribute.'
                  or not seenActive and condsActive and '\nDefines zone as the first active glow.' or '' })
              end
              if condsActive and not seenActive then
                seenActive = i
              end
            else
              ui.drawCircle((r1 + r2) / 2, 10, rgbm.colors.gray, 20)
              if ui.itemHovered() then
                ui.setTooltip('This glow is not active at the moment')
              end
            end
            ui.sameLine(0, 8)
            if i == seenActive then
              ui.setNextTextBold()
            end
            if fadeEntry then ui.pushStyleVarAlpha(0.5) end
            ui.textAligned(gcfg._name or glow.name, vec2(0, 0.5), vec2(gapRight, 20), true)
            if fadeEntry then ui.popStyleVar() end
          end
          if ui.itemHovered() then
            ui.setTooltip(gcfg._name and gcfg._name .. '\n' .. glow.description or glow.description)
          end
        end

        if clipped then
          ui.popClipRect()
        end

        if hasSettings then
          ui.sameLine(ui.getCursorX() + ui.availableSpaceX() - 80)
          if ui.iconButton(ui.Icons.Settings, vec2(20, 0), 5, true, 0) then
            if glow then
              TiedPopup(function()
                Utils.glowSettings('%s/%s/%s:' % { device.name, zoneName, glow.name }, glow, gcfg)
                editing = { device, index, glow, gcfg }
              end)
            elseif gcfg.prop then
              TiedPopup(function()
                gcfg.value = Utils.getPropEditor('%s/%s:' % { device.name, zoneName }, gcfg.prop, gcfg.value)
                if ui.checkbox(gcfg.conds and Utils.getConditionLabel(gcfg.conds) or 'Condition', gcfg.conds) then
                  if gcfg.conds then
                    gcfg.conds = nil
                  else
                    Utils.conditionPopupEditor(true, nil, function(arg) Utils.assignCondition(gcfg, arg) end)
                  end
                end
                if gcfg.conds then
                  ui.sameLine()
                  if ui.button('Edit') then
                    Utils.conditionPopupEditor(true, gcfg, function(arg) Utils.assignCondition(gcfg, arg) end)
                  end
                end
              end)
            else
              Utils.conditionPopupEditor(gcfg.branch == 'if', gcfg, function(arg) Utils.assignCondition(gcfg, arg) end)
            end
          end
          if ui.itemHovered() then
            ui.setTooltip(glow and 'Configure this glow' or 'Configure this branch')
          end
        end
        ui.sameLine(ui.getCursorX() + ui.availableSpaceX() - 56)
        if ui.iconButton(ui.Icons.ArrowUp, vec2(16, 0), 5, true, i > 1 and 0 or ui.ButtonFlags.Disabled) then
          move = { i, i - 1 }
        end
        local h = ui.itemHovered()
        ui.sameLine(ui.getCursorX() + ui.availableSpaceX() - 56 + 16)
        if ui.iconButton(ui.Icons.ArrowDown, vec2(16, 0), 5, true, i < #zcfg.zGlows and 0 or ui.ButtonFlags.Disabled) then
          move = { i, i + 1 }
        end
        if h or ui.itemHovered() then
          ui.setTooltip(
            'First active glow on the list defines the final color of the zone. Move conditional glows (such as race flag one) higher on the list, and constantly active glows (such as solid color one) lower.\n\nNote: you can also drag items with your mouse button, this also allows to drag items across zones and devices.')
        end
        ui.sameLine(ui.getCursorX() + ui.availableSpaceX() - 20)
        if ui.iconButton(ui.Icons.Delete, vec2(20, 0), 5, true, 0) and table.removeItem(zcfg.zGlows, gcfg) then
          Saving.save()
          ui.toast(ui.Icons.Delete, '%s removed' % getEntryName(gcfg), function()
            table.insert(zcfg.zGlows, math.min(#zcfg.zGlows + 1, i), gcfg)
            Saving.save()
          end)
        end
        if ui.itemHovered() then
          ui.setTooltip('Remove this glow')
        end
        ui.popID()
      end
      if dragging and draggingDst == #zcfg.zGlows + 1 and (not draggingSameList or dragging.from < #zcfg.zGlows) then
        local c = ui.getCursor()
        c.y = c.y - 3
        ui.drawLine(c, c + vec2(ui.windowWidth(), 0), rgbm.colors.white, 1)
      end
      ui.setNextItemIcon(ui.Icons.Plus)
      if ui.button('Add', vec2(ui.availableSpaceX() / 2 - 4, 0)) then
        TiedPopup(function()
          ui.pushFont(ui.Font.Small)
          ui.setNextItemIcon(ui.Icons.Contrast)
          if ui.beginMenu('Conditionally active') then
            for _, glow in ipairs(Glows.glows) do
              if glow.condition then
                if ui.selectable(glow.name) then
                  addEntry(zcfg, Glows.instatiate(glow))
                end
                if ui.itemHovered() then
                  ui.setNextWindowPosition(ui.windowPos() - vec2(0, 4), vec2(0, 1))
                  ui.setTooltip(glow.description)
                  editing = { device, index, glow }
                end
              end
            end
            ui.endMenu()
          end
          if ui.itemHovered() then
            ui.setNextWindowPosition(ui.windowPos() - vec2(0, 4), vec2(0, 1))
            ui.setTooltip(
              'Place these items at the top: sometimes they won’t return a color and instead let items below to do their thing')
          end
          ui.setNextItemIcon(ui.Icons.Record)
          if ui.beginMenu('Always active') then
            for _, glow in ipairs(Glows.glows) do
              if not glow.condition then
                if ui.selectable(glow.name) then
                  addEntry(zcfg, Glows.instatiate(glow))
                end
                if ui.itemHovered() then
                  ui.setNextWindowPosition(ui.windowPos() - vec2(0, 4), vec2(0, 1))
                  ui.setTooltip(glow.baseDescription)
                  editing = { device, index, glow }
                end
              end
            end
            ui.endMenu()
          end
          if ui.itemHovered() then
            ui.setNextWindowPosition(ui.windowPos() - vec2(0, 4), vec2(0, 1))
            ui.setTooltip('Place these items at the bottom: they will always return a color')
          end
          ui.separator()
          ui.setNextItemIcon(ui.Icons.Pitlane)
          if ui.beginMenu('Branches') then
            local ifClicked = ui.menuItem('If …')
            if ui.menuItem('… else if …') or ifClicked then
              local created = { branch = ifClicked and 'if' or 'elseif', conds = { { invert = false } } }
              TiedPopup(function()
                if Utils.conditionFullEditor(ifClicked, created) then
                  addEntry(zcfg, created)
                end
              end, { parentless = true })
            end
            if ui.menuItem('… else …') then
              addEntry(zcfg, { branch = 'else' })
            end
            if ui.menuItem('… end') then
              addEntry(zcfg, { branch = 'end' })
            end
            ui.endMenu()
          end
          if ui.itemHovered() then
            ui.setNextWindowPosition(ui.windowPos() - vec2(0, 4), vec2(0, 1))
            ui.setTooltip('Place condition between glows to redirect final color computation')
          end
          ui.setNextItemIcon(ui.Icons.SettingsAlt)
          if ui.beginMenu('Zone tweaks') then
            if ledsCount > 1 then
              if ui.menuItem('Single color') then addEntry(zcfg, { prop = 'singleColor', value = true }) end
              if ui.menuItem('Partial coverage') then addEntry(zcfg, { prop = 'partialCoverage', value = true }) end
              if ui.menuItem('Background color') then addEntry(zcfg, { prop = 'backgroundColor', value = rgb() }) end
              if ui.menuItem('Flip direction') then addEntry(zcfg, { prop = 'flipX', value = true }) end
              ui.separator()
            end
            if ui.menuItem('Delay') then addEntry(zcfg, { prop = 'delay', value = 0 }) end
            if ui.menuItem('Smoothing') then addEntry(zcfg, { prop = 'smoothing', value = 1 }) end
            if ledsCount > 1 then
              if ui.menuItem('Delay (alt.)') then addEntry(zcfg, { prop = 'delay2', value = 0 }) end
              if ui.menuItem('Smoothing (alt.)') then addEntry(zcfg, { prop = 'smoothing2', value = 1 }) end
            end
            ui.separator()
            if ui.menuItem('Saturation') then addEntry(zcfg, { prop = 'saturation', value = 1 }) end
            if ui.menuItem('Brightness') then addEntry(zcfg, { prop = 'brightness', value = 1 }) end
            if ui.menuItem('Gamma') then addEntry(zcfg, { prop = 'gamma', value = 1 }) end
            ui.endMenu()
          end
          if ui.itemHovered() then
            ui.setNextWindowPosition(ui.windowPos() - vec2(0, 4), vec2(0, 1))
            ui.setTooltip(
              'Place within a condition (or set a local condition within) to alter final zone tweaks if triggered')
          end
          ui.popFont()
        end)
      end
      ui.sameLine(0, 4)
      ui.setNextItemIcon(ui.Icons.SettingsAlt)
      if ui.button('Zone', vec2(-0.1, 0)) then
        TiedPopup(function()
          ui.header('%s/%s (%d LED%s):' % { device.name, zoneName, ledsCount, ledsCount == 1 and '' or 's' })
          ui.pushFont(ui.Font.Small)
          local ztw = zcfg.zTweaks
          if not ztw then
            ztw = {}
            zcfg.zTweaks = ztw
          end
          if ledsCount > 1 then
            if ui.checkbox('Single color', ztw.singleColor) then
              ztw.singleColor = not ztw.singleColor
              Saving.save()
            end
            if ui.itemHovered() then
              ui.setTooltip(
                'Set a single color even if there are multiple LEDs in this zone and the source provides several colors for a gradient')
            end
            if ui.checkbox('Partial coverage', ztw.partialCoverage) then
              ztw.partialCoverage = not ztw.partialCoverage
              Saving.save()
            end
            if ui.itemHovered() then
              ui.setTooltip('If zone reports a fill percentage, use it to disable LEDs above it')
            end
            if ztw.partialCoverage then
              ui.sameLine()
              local col = ztw.backgroundColor or rgb.colors.black:clone()
              ui.colorButton('##bg', col, ui.ColorPickerFlags.PickerHueWheel)
              Saving.item()
              ztw.backgroundColor = col ~= rgb.colors.black and col or nil
              if ui.itemHovered() then
                ui.setTooltip('Color for disabled LEDs')
              end
            end
            if (not ztw.singleColor or ztw.partialCoverage) and ui.checkbox('Flip direction', ztw.flipX) then
              ztw.flipX = not ztw.flipX
              Saving.save()
            end
            if ui.itemHovered() then
              ui.setTooltip('Flip LEDs behavior')
            end
          end

          ztw.smoothing = 1 -
              Utils.sliderWithReset('##sm', 100 - (ztw.smoothing or 1) * 100, 0, 100, 0, 'Smoothing: %.0f%%', 0.5) / 100
          ztw.delay = Utils.sliderWithReset('##de', ztw.delay or 0, 0, 3, 0, 'Delay: %.2f s')
          if ledsCount > 1 and ui.checkbox('Alternate values across LEDs', ztw.smoothing2 ~= nil) then
            ztw.smoothing2 = not ztw.smoothing2 and ztw.smoothing or nil
          end
          if ledsCount > 1 and ztw.smoothing2 then
            ztw.smoothing2 = 1 -
                Utils.sliderWithReset('##sm2', 100 - (ztw.smoothing2 or 1) * 100, 0, 100, 0, 'Smoothing (alt): %.0f%%',
                  0.5) /
                100
            ztw.delay2 = Utils.sliderWithReset('##de2', ztw.delay2 or 0, 0, 3, 0, 'Delay (alt): %.2f s')
          end

          ui.offsetCursorY(12)
          ztw.saturation = Utils.sliderWithReset('##sa', (ztw.saturation or 1) * 100, 0, 300, 100, 'Saturation: %.0f%%') /
              100
          ztw.brightness = Utils.sliderWithReset('##br', (ztw.brightness or 1) * 100, 0, 300, 100, 'Brightness: %.0f%%') /
              100
          ztw.gamma = Utils.sliderWithReset('##ga', (ztw.gamma or 1) * 100, 0, 300, 100, 'Gamma: %.0f%%') / 100

          if index > 1000 then
            ui.offsetCursorY(12)
            ui.header('Custom zone:')
            ui.setNextItemIcon(ui.Icons.Trash)
            if ui.button('Delete custom zone', vec2(248, 0)) then
              local customZoneToRemove = index - 1000
              local removedZone = table.remove(dcfg.customZones, customZoneToRemove)
              local removedZoneCfg = table.remove(dcfg.perCustomZone, customZoneToRemove)
              Saving.save()
              ui.closePopup()
              ui.toast(ui.Icons.Trash, 'Custom zone “%s” has been removed' % removedZone.name, function()
                table.insert(dcfg.customZones, removedZone)
                table.insert(dcfg.perCustomZone, removedZoneCfg)
                Saving.save()
              end)
            end
          end

          ui.offsetCursorY(12)
          ui.header('Zone preset:')
          ui.setNextItemIcon(ui.Icons.Rubber)
          if ui.button('Clear out', vec2(80, 0)) then
            Saving.resetZoneConfig(zcfg)
          end
          ui.sameLine(0, 4)
          ui.setNextItemIcon(ui.Icons.Folder)
          if ui.button('Load', vec2(80, 0)) then
            Saving.loadZonePreset(zcfg, '%s/%s' % { device.name, zoneName })
          end
          ui.sameLine(0, 4)
          ui.setNextItemIcon(ui.Icons.Save)
          if ui.button('Save', vec2(80, 0)) then
            Saving.saveZonePreset(zcfg)
          end
          ui.popFont()
        end)
      end
      if ui.itemHovered() then
        ui.setTooltip('Zone tweaks alter how glow colors are output onto a device')
      end
      ui.popFont()
      if move and (#zcfg.zGlows > 0 or #move == 4) then
        if #move == 2 then -- moving withing this list
          move[1] = math.clamp(move[1], 1, #zcfg.zGlows)
          move[2] = math.clamp(move[2], 1, #zcfg.zGlows)
          local moved = table.remove(zcfg.zGlows, move[1])
          table.insert(zcfg.zGlows, move[2], moved)
        else -- moving across lists
          move[1] = math.clamp(move[1], 1, #zcfg.zGlows + 1)
          local src = move[4] > 1000 and Saving.cfg[move[3].uuid].perCustomZone[move[4] - 1000] or
              Saving.cfg[move[3].uuid].perZone[move[4]]
          if src then
            move[2] = math.clamp(move[2], 1, #src.zGlows)
            local moved = table.remove(src.zGlows, move[2])
            if moved then
              table.insert(zcfg.zGlows, move[1], moved)
            end
          end
        end
        Saving.save()
      end
      ui.endTreeNode()
    end
  end

  zone(1, 'All zones', #device.leds)
  for i, z in ipairs(device.zones) do
    zone(i + 1, z.name, z.ledsCount)
  end
  if dcfg.customZones then
    for i, z in ipairs(dcfg.customZones) do
      zone(1000 + i, 'Custom: %s' % z.name, #z.leds)
    end
  end
  ui.offsetCursorX(-9)
  ui.pushStyleVar(ui.StyleVar.ButtonTextAlign, vec2(0, 0.5))
  ui.pushStyleVar(ui.StyleVar.FramePadding, vec2(35, 0))
  if ui.button('Define a custom zone', vec2(ui.availableSpaceX() + 10, 22)) then
    local mask = table.range(#device.leds, function() return false end)
    local name = ''
    TiedPopup(function()
      local h = -1
      ui.pushStyleColor(ui.StyleColor.FrameBg, rgbm.colors.black)
      for _, z in ipairs(device.zones) do
        ui.header(z.name)
        for i = 1, z.ledsCount do
          local j = i + z.ledsStart
          if i % 10 ~= 1 then
            ui.sameLine(0, 4)
          end
          if ui.checkbox('##%d' % j, mask[j]) then
            mask[j] = not mask[j]
          end
          if ui.itemHovered() then
            h = j
          end
        end
        ui.offsetCursorY(12)
      end
      ui.popStyleColor()
      ui.setNextItemWidth(240)
      name = ui.inputText('Zone name', name, ui.InputTextFlags.Placeholder)
      local selected = table.count(mask, function(item) return item end)
      if ui.button('Define a zone with %d LED%s' % { selected, selected == 1 and '' or 's' }, vec2(240, 0),
            selected == 0 and ui.ButtonFlags.Disabled or 0) then
        ui.closePopup()
        if not dcfg.customZones then dcfg.customZones = {} end
        name = name:trim()
        if #name == 0 then name = 'Unnamed' end
        local created = { name = name, leds = table.map(mask, function(item, index) return item and index - 1 or nil end) }
        table.insert(dcfg.customZones, created)
        Saving.save()
        ui.toast(ui.Icons.Confirm, 'New zone “%s” has been created' % created.name, function()
          local i = table.indexOf(dcfg.customZones, created)
          if i then
            table.remove(dcfg.customZones, i)
            table.remove(dcfg.perCustomZone, i)
            Saving.save()
          end
        end)
      end
      customZoneEditor = { device, mask, h }
    end)
  end
  ui.addIcon(ui.Icons.Plus, 10, vec2(0, 0.5), nil, vec2(10, 0))
  ui.popStyleVar(2)
end

local shown = 0
local forceOpenNext
function script.windowMain()
  local devices = openrgb.devices()
  if not devices then
    ui.pushAlignment(true, 0.4)
    ui.pushAlignment(false, 0.5)
    ui.dummy(16)
    ui.drawLoadingSpinner(ui.itemRect())
    ui.sameLine(0, 8)
    ui.text(openrgb.status() or 'Loading…')
    ui.popAlignment()
    ui.popAlignment()
    if shown > 10 then
      ui.pushAlignment(true, 1)
      ui.pushFont(ui.Font.Small)
      ui.textWrapped('It might help to install and launch OpenRGB manually. Make sure to enable SDK Server.')
      if ui.button('Download OpenRGB', vec2(ui.availableSpaceX() / 2 - 4, 0)) then
        os.openURL('https://openrgb.org/releases.html')
      end
      ui.sameLine(0, 4)
      if ui.button('Restart app', vec2(-0.1, 0)) then
        ac.restartApp()
      end
      ui.popFont()
      ui.popAlignment()
    else
      shown = shown + ui.deltaTime()
    end
    return
  end

  shown = 0
  if #devices == 0 then
    ui.pushAlignment(true, 0.4)
    if settings.USE_BUILTIN_EXE and not settings.KEEP_ALIVE then
      ui.pushAlignment(false, 0.5)
      ui.text('No devices found')
      ui.popAlignment()
      ui.offsetCursorY(8)
      ui.pushAlignment(false, 0.5)
      if ui.button('Restart app and OpenRGB') then
        ac.restartApp()
      end
      ui.popAlignment()
    else
      ui.pushAlignment(false, 0.5)
      ui.text('No devices found, fix OpenRGB\nand restart the app')
      ui.popAlignment()
      ui.offsetCursorY(8)
      ui.pushAlignment(false, 0.5)
      if ui.button('Restart app') then
        ac.restartApp()
      end
      ui.popAlignment()
    end
    ui.popAlignment()
    return
  end

  ui.tabBar('devices', bit.bor(ui.TabBarFlags.IntegratedTabs, #devices > 2 and ui.TabBarFlags.TabListPopupButton or 0),
    function()
      local openNow = forceOpenNext
      forceOpenNext = nil
      for i, device in ipairs(devices) do
        ui.pushID(i)
        local opened = ui.beginTabItem(device.name, openNow == i and ui.TabItemFlags.SetSelected or 0)
        local r1, r2 = ui.itemRect()
        if dragging and ui.rectHovered(r1, r2, true) and not opened then
          forceOpenNext = i
        end
        if opened then
          ui.setCursorX(0)
          ui.childWindow('device', vec2(ui.windowWidth(), -30), false,
            bit.bor(ui.WindowFlags.AlwaysUseWindowPadding, ui.WindowFlags.NoBackground), function()
              openRGBDevice(device)
            end)
          ui.endTabItem()
        end
        ui.popID()
      end
    end)

  if ui.windowWidth() > 400 then
    appFooter()
    ui.sameLine(ui.windowWidth() - 138, 0)
  else
    ui.setExtraContentMark(true)
    ui.separator()
    ui.pushFont(ui.Font.Small)
    ui.setCursorX(ui.windowWidth() - 138)
  end
  ui.setNextItemIcon(ui.Icons.File)
  if ui.button('Load') then
    Saving.loadAppPreset()
  end
  ui.sameLine(0, 4)
  ui.setNextItemIcon(ui.Icons.Save)
  if ui.button('Save') then
    Saving.saveAppPreset()
  end
  ui.popFont()

  if dragging then
    if not ui.mouseDown() then
      dragging = nil
    else
      ui.setMouseCursor(ui.MouseCursor.Arrow)
      ui.setTooltip('RGB Control:\nDragging “%s”' % dragging.name)
    end
  end
end
