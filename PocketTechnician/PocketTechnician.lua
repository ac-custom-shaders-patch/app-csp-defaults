local setup = ac.INIConfig.carData(0, 'setup.ini')

---@alias ItemInfo {name: string, label: string, format: string?, x: number, y: number, linked: ItemInfo?, hidden: boolean?}
---@return {name: string, items: ItemInfo[], singleColumn: boolean?}[]
local function arrangeTabs()
  ---@param tab string
  local function getTabName(tab)
    return tab:replace('_', ' '):lower():reggsub('\\b[a-z]', function (x)
      return x:upper()
    end)
  end

  ---@param name string
  ---@param hasRightCounterpart boolean
  local function getItemName(name, hasRightCounterpart)
    local ret = name:replace('_', ' '):lower():reggsub('\\b[a-z](?:\\w\\b)?', function (x) return x:upper() end)
    if hasRightCounterpart then
      if ret:regfind(' [LR]F$') then ret = ret:sub(1, #ret - 2)..'Front' end
      if ret:regfind(' [LR]R$') then ret = ret:sub(1, #ret - 2)..'Rear' end
    end
    return ret
  end

  local tabs = {}
  local tabTweaks = {}
  local posToItems = {}
  local tabCoords = {}

  for k, v in pairs(setup.sections) do
    if v.TAB and v.POS_X and v.POS_Y then
      local vTab = v.TAB and v.TAB[1]
      local vPosX = tonumber(v.POS_X and v.POS_X[1]) or 0
      local vPosY = tonumber(v.POS_Y and v.POS_Y[1]) or 0
      if vPosX >= 0 and vPosY >= 0 and vPosX <= 3 and vPosY <= 99 then
        local hasRightCounterpart = false

        if (k:endsWith('_RF') or k:endsWith('_RR')) and setup.sections[k:sub(1, #k - 3)..(k:endsWith('_RF') and '_LF' or '_LR')]
          or (k:endsWith('_LF') or k:endsWith('_LR')) and setup.sections[k:sub(1, #k - 3)..(k:endsWith('_LF') and '_RF' or '_RR')] then
          hasRightCounterpart = true
          vPosX = 0.5
        end

        local posKey = '%s;%d;%d' % {vTab, vPosX, vPosY}
        if posToItems[posKey] then posToItems[posKey].hidden = true end

        local created = {name = k, label = getItemName(v.NAME and v.NAME[1] or k, hasRightCounterpart), x = vPosX, y = vPosY, linked = posToItems[posKey]}
        local coords = table.getOrCreate(tabCoords, vTab, function () return {x = {}, y = {}} end)
        if not table.contains(coords.x, created.x) then table.insert(coords.x, created.x) end
        if not table.contains(coords.y, created.y) then table.insert(coords.y, created.y) end
        posToItems[posKey] = created
        table.insert(table.getOrCreate(tabs, vTab, function () return {} end), created)
      end
    end
  end
  for k, v in pairs(tabs) do
    local coords = tabCoords[k]
    table.sort(coords.x)
    table.sort(coords.y)
    if #coords.x == 1 then tabTweaks[k] = 1 end
    for j = #coords.y, 2, -1 do
      if coords.y[j - 1] ~= coords.y[j] - 1 then
        for i, e in ipairs(v) do
          if e.y > coords.y[j - 1] then e.y = e.y + (coords.y[j - 1] - coords.y[j] + 1) end
        end
      end
    end
    for i, e in ipairs(v) do
      e.y = e.y - coords.y[1]
    end
  end

  local tabsOrdered = table.map(tabs, function (v, k) return {name = getTabName(k), items = v, singleColumn = tabTweaks[k] == 1} end)
  table.sort(tabsOrdered, function (a, b)
    if a.name == 'Suspensions' then return 'Suspension' < b.name end
    if b.name == 'Suspensions' then return a.name < 'Suspension' end
    return a.name < b.name
  end)
  return tabsOrdered
end

local tabsOrdered = arrangeTabs()
local changed = false
local savedAs
local scanned

ac.onSetupsListRefresh(function ()
  scanned = nil
end)

---@return {track: string, setups: string[]}[]
local function scanSetups()
  if scanned == nil then
    local dir = '%s/%s' % {ac.getFolder(ac.FolderID.UserSetups), ac.getCarID(0)}
    scanned = {}
    io.scanDir(dir, '*', function (file, attr)
      if attr.isDirectory then
        local setups = io.scanDir(dir..'/'..file, '*.ini')
        if #setups > 0 then
          table.insert(scanned, {track = file, setups = setups})
        end
      end
      return nil
    end)
  end
  return scanned
end

function script.windowMain()
  if not ac.isCarResetAllowed() then
    ui.setNextTextSpanStyle(1, 17, nil, true)
    ui.textWrapped('Pocket Technician can help you change car setup outside of pits, but only in single-player practice sessions. Have to keep things fair.')
    ui.setNextItemIcon(ui.Icons.Confirm)
    if ui.button('OK', vec2(-0.1, 0)) then
      ac.setWindowOpen('main', false)
    end
    return
  end

  local setups = ac.getSetupSpinners()
  local getByID = function (id)
    for _, v in ipairs(setups) do
      if v.name == id then return v end
    end
    return nil
  end
  ui.tabBar('##tabs', ui.TabBarFlags.IntegratedTabs, function ()
    for _, tabInfo in ipairs(tabsOrdered) do
      ui.tabItem(tabInfo.name, function ()
        local w = ui.availableSpaceX()
        local x, y = ui.getCursorX(), ui.getCursorY()
        ui.pushItemWidth((tabInfo.singleColumn and w or w / 2 - 2) - 26)
        for i, v in ipairs(tabInfo.items) do
          if not v.hidden then
            local s = getByID(v.name) 
            if s then
              ui.pushID(v.name)
              if not tabInfo.singleColumn then ui.setCursorX(x + v.x * (w / 2 + 2)) end
              ui.setCursorY(y + v.y * 26)
              if not v.format then
                local u = s.units == '%' and '%%' or s.units == 'deg' and '°' or (s.units and ' '..s.units or ''):replace('%', '%%')
                v.format = v.label..': %%.%df%s' % {math.max(math.round(-math.log10(s.displayMultiplier)), 0), u}
              end
              local newValue
              if s.step > 1 then
                local format = (v.format % (s.value * s.displayMultiplier)):replace('%', '%%')
                newValue = ui.slider('##'..v.name, (s.value - s.min) / s.step, 0, (s.max - s.min) / s.step, format, true)
                if ui.itemActive() then ac.debug('newValue', newValue) end
                newValue = ui.itemEdited() and newValue * s.step + s.min or nil
              else
                newValue = ui.slider('##'..v.name, s.value * s.displayMultiplier, s.min * s.displayMultiplier, s.max * s.displayMultiplier, v.format)
                newValue = ui.itemEdited() and newValue / s.displayMultiplier or nil
              end
              ui.sameLine(0, 4)
              if ui.iconButton(ui.Icons.Stay, 22) then
                newValue = s.defaultValue or math.round((s.min + s.max) / 2)
              end
              if ui.itemHovered() then
                ui.setTooltip('Reset to default')
              end
              if newValue then
                changed = true
                physics.awakeCar(0)
                ac.setSetupSpinnerValue(s.name, newValue)
                local linked = v.linked
                while linked ~= nil do
                  local linkedS = getByID(linked.name)
                  if linkedS then
                    ac.setSetupSpinnerValue(linked.name, math.lerp(linkedS.min, linkedS.max, math.lerpInvSat(newValue, s.min, s.max)))
                    linked = linked.linked
                  end
                end
              end
              ui.popID()
            end
          end
        end
        ui.popItemWidth()

        ui.setCursorY(ui.getMaxCursorY() + 4)
        ui.setNextItemIcon(ui.Icons.File)
        ui.setNextItemWidth(w / 2 - 2)
        ui.pushFont(changed and ui.Font.Italic or ui.Font.Main)
        if not savedAs then ui.setNextTextSpanStyle(1, math.huge, rgbm.colors.gray) end
        ui.combo('##load', savedAs and savedAs:sub(1, #savedAs - 4) or 'Unsaved', function ()
          ui.pushFont(ui.Font.Main)
          ui.pushClipRect(0, ui.windowSize(), false)
          for _, v in ipairs(scanSetups()) do
            ui.treeNode(v.track, bit.bor((v.track == 'generic' or v.track == ac.getTrackID()) and ui.TreeNodeFlags.DefaultOpen or 0, 
                ui.TreeNodeFlags.Framed, ui.TreeNodeFlags.SpanClipRect), function ()
              for _, s in ipairs(v.setups) do
                local fullName = v.track..'/'..s
                if ui.selectable(s:sub(1, #s - 4), false, ui.SelectableFlags.SpanClipRect) then
                  local tmpFilename = ac.getFolder(ac.FolderID.AppDataTemp)..'/_tmp_setup.ini'
                  ac.saveCurrentSetup(tmpFilename)
                  local previousSetup, previousSavedAs, previousChanged = io.load(tmpFilename), savedAs, changed
                  ac.loadSetup(v.track..'/'..s)
                  savedAs = fullName
                  changed = false
                  ui.toast('icon.png', 'Setup “%s” loaded' % fullName:sub(1, #fullName - 4), previousSetup and function ()
                    io.save(tmpFilename, previousSetup)
                    ac.loadSetup(tmpFilename)
                    savedAs = previousSavedAs
                    changed = previousChanged
                  end)
                end
              end
            end)
          end
          ui.popClipRect()
          ui.popFont()
        end)
        ui.popFont()
        ui.sameLine(x + w / 2 + 2)

        ui.setNextItemIcon(ui.Icons.Save)
        if ui.button('Save', vec2(-0.1)) then
          ui.modalPrompt('Save setup?', 'Setup name:', savedAs and savedAs:sub(1, #savedAs - 4) or 'generic/pocket-%s' % os.date('%Y%m%d-%H%M%S', os.time()),
          'Save', 'Cancel', ui.Icons.Save, ui.Icons.Cancel, function (ret)
            if ret then
              if ret:find('/', nil, true) == nil then ret = 'generic/'..ret end
              if ret:regfind('\\.ini$', nil, true) == nil then ret = ret..'.ini' end
              ac.saveCurrentSetup(ret)
              savedAs = ret
              changed = false
            end
          end)
        end
      end)
    end
  end)
end