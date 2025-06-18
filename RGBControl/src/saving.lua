local cfg = stringify.tryParse(ac.storage.cfg) or {} ---@type App.Cfg
local saving = false
local presetsPhase = 0

local function save()
  if saving then return end
  saving = true
  setTimeout(function()
    saving = false
    ac.storage.cfg = stringify(cfg, true)
  end, 0.5)
end

local function resetZoneConfig(zcfg)
  local prev = stringify.binary(zcfg)
  table.clear(zcfg)
  table.assign(zcfg, { zGlows = {} })
  save()
  ui.toast(ui.Icons.File, 'Zone configuration reset', function()
    table.clear(zcfg)
    table.assign(zcfg, { zGlows = {} }, stringify.binary.parse(prev))
    save()
  end)
end

local function applyLoadedZonePreset(zcfg, loaded, name)
  local prev = stringify.binary(zcfg)
  table.clear(zcfg)
  table.assign(zcfg, { zGlows = {} }, loaded)
  save()
  if name then
    ui.toast(ui.Icons.File, 'Zone configuration replaced with “%s”' % name, function()
      table.clear(zcfg)
      table.assign(zcfg, { zGlows = {} }, stringify.binary.parse(prev))
      save()
    end)
  end
end

local function applyLoadedAppPreset(loaded, name)
  local prev = stringify.binary(cfg)
  table.clear(cfg)
  table.assign(cfg, loaded)
  save()
  ui.toast(ui.Icons.File,
    name and 'Entire configuration replaced with “%s”' % (name or '?') or 'Entire configuration cleared out', function()
      table.clear(cfg)
      table.assign(cfg, stringify.binary.tryParse(prev, {}))
      save()
    end)
end

local function presetContextMenu(filename, rescanCallback)
  if ui.itemClicked(ui.MouseButton.Right) then
    TiedPopup(function()
      if ui.selectable('Rename preset…') then
        ui.modalPrompt('Rename “%s”?' % io.getFileName(filename, true), 'New name:', io.getFileName(filename, true),
          'Rename', 'Cancel', ui.Icons.Confirm, ui.Icons.Cancel, function(value)
            if value and value ~= io.getFileName(filename, true) then
              if not io.isFileNameAcceptable(value) or not io.move(filename, io.getParentPath(filename) .. '/' .. value .. '.lon') then
                ui.toast(ui.Icons.Warning, 'Can’t rename preset')
              else
                ui.toast(ui.Icons.Confirm, 'Preset renamed')
              end
            end
          end)
      end
      if ui.selectable('View in Explorer') then
        os.showInExplorer(filename)
      end
      ui.separator()
      if ui.selectable('Delete preset') then
        local data = io.load(filename)
        if io.deleteFile(filename) then
          if rescanCallback then rescanCallback() end
          ui.toast(ui.Icons.Trash, 'Preset “%s” removed' % io.getFileName(filename, true), function()
            io.save(filename, data, true)
            if rescanCallback then rescanCallback() end
          end)
        else
          ui.toast(ui.Icons.Warning, 'Failed to remove preset “%s”' % io.getFileName(filename, true))
        end
      end
      if ui.selectable('Rec preset') then
        local data = io.load(filename)
        if io.recycle(filename) then
          if rescanCallback then rescanCallback() end
          ui.toast(ui.Icons.Trash, 'Preset “%s” removed' % io.getFileName(filename, true), function()
            io.save(filename, data, true)
            if rescanCallback then rescanCallback() end
          end)
        else
          ui.toast(ui.Icons.Warning, 'Failed to remove preset “%s”' % io.getFileName(filename, true))
        end
      end
    end)
  end
end

local function loadZonePresetItem(zcfg, v, dir, rescanCallback)
  if ui.selectable(v:sub(1, -5)) then
    io.loadAsync(dir .. '/' .. v, function(err, response)
      local parsed = not err and stringify.tryParse(response)
      if type(parsed) == 'table' then
        applyLoadedZonePreset(zcfg, parsed, v:sub(1, -5))
      else
        print(err, parsed)
        ui.toast(ui.Icons.Warning, 'Failed to load zone preset “%s”' % v:sub(1, -5))
      end
    end)
  end
  presetContextMenu(dir .. '/' .. v, rescanCallback)
end

---@param zcfg App.Cfg.Zone
local function loadZonePreset(zcfg, targetName)
  local dir = ac.getFolder(ac.FolderID.ScriptConfig) .. '/zp'
  local dirExchange = ac.getFolder(ac.FolderID.ScriptConfig) .. '/zx'
  local files = io.scanDir(dir, '*.lon')
  local filesExchange = io.scanDir(dirExchange, '*.lon')
  TiedPopup(function()
    ui.setNextItemIcon(ui.Icons.Plus)
    if ui.selectable('New configuration') then
      resetZoneConfig(zcfg)
    end
    ui.setNextItemIcon(ui.Icons.InboxFull)
    if ui.selectable('Browse RGB Exchange') then
      local targetDeviceUUID = select(2, table.findFirst(cfg, function(item)
        return item.perZone and table.contains(item.perZone, zcfg)
            or item.perCustomZone and table.contains(item.perCustomZone, zcfg)
      end, nil))
      local zoneIndex = targetDeviceUUID and table.indexOf(cfg[targetDeviceUUID].perZone, zcfg)
      local prevPhase = -1
      local listData
      require('src/exchange').open(targetName, dirExchange, {
        list = function()
          if prevPhase ~= presetsPhase then
            prevPhase = presetsPhase
            listData = table.map(files, function(item)
              return { filename = dir .. '/' .. item, name = item:sub(1, -5) }
            end)
          end
          return listData
        end,
        current = function()
          return stringify(zcfg, true)
        end,
        load = function(data, name)
          applyLoadedZonePreset(zcfg, stringify.tryParse(data), name)
        end,
        valid = function()
          if table.some(cfg, function(item)
                return item.perZone and table.contains(item.perZone, zcfg)
                    or item.perCustomZone and table.contains(item.perCustomZone, zcfg)
              end) then
            return true
          end
          if cfg[targetDeviceUUID] and cfg[targetDeviceUUID].perZone and cfg[targetDeviceUUID].perZone[zoneIndex] then
            zcfg = cfg[targetDeviceUUID].perZone[zoneIndex]
            return true
          end
          return false
        end
      })
    end
    ui.separator()
    if #filesExchange > 0 then
      if ui.beginMenu('Loaded') then
        for _, v in ipairs(filesExchange) do
          loadZonePresetItem(zcfg, v, dirExchange, function()
            filesExchange = io.scanDir(dirExchange, '*.lon')
          end)
        end
        ui.endMenu()
      end
    end
    for _, v in ipairs(files) do
      loadZonePresetItem(zcfg, v, dir, function()
        files = io.scanDir(dir, '*.lon')
        presetsPhase = presetsPhase + 1
      end)
    end
  end)
end

local lastNames = setmetatable({}, { __mode = 'kv' })
local function genSavingDialog(title, message, dir, associate, callback)
  local files = table.map(io.scanDir(dir, '*.lon'), function(item) return item:sub(1, -5):lower() end)
  local name = lastNames[associate] or ''
  ui.modalDialog(title, function()
    local ret = false
    ui.text(message)
    ui.newLine()
    name = ui.inputText('Random name', name, ui.InputTextFlags.Placeholder)
    ui.offsetCursorY(8)
    if ui.modernButton(table.contains(files, name:lower()) and 'Overwrite' or 'Save', vec2(ui.availableSpaceX() / 2 - 4, 40), ui.ButtonFlags.Confirm, ui.Icons.Save) then
      name = name and name:trim() or ''
      lastNames[associate] = name
      if #name == 0 then name = 'P%x' % (math.randomKey() % 65536) end
      if not io.isFileNameAcceptable(name) then
        ui.toast(ui.Icons.Warning, 'Failed to save zone preset: name is not acceptable')
      else
        local dst = dir .. '/' .. name .. '.lon'
        io.createFileDir(dst)
        callback(dst, io.fileExists(dst) and io.load(dst))
        presetsPhase = presetsPhase + 1
      end
      ret = true
    end
    ui.sameLine(0, 8)
    if ui.modernButton('Cancel', vec2(-0.1, 40), ui.ButtonFlags.Cancel, ui.Icons.Cancel) then
      ret = true
    end
    return ret
  end)
end

---@param data App.Cfg.Zone
local function saveZonePreset(data)
  genSavingDialog('Save zone preset?', 'Name for the new preset:', ac.getFolder(ac.FolderID.ScriptConfig) .. '/zp',
    data, function(dst, bak)
      if not io.save(dst, stringify(data), true) then
        ui.toast(ui.Icons.Warning, 'Failed to save zone preset')
        return
      end
      ui.toast(ui.Icons.Save, 'Zone preset saved as “%s”' % io.getFileName(dst, true), bak and function()
        io.save(dst, bak)
      end or nil)
    end)
end

local function loadAppPreset()
  local dir = ac.getFolder(ac.FolderID.ScriptConfig) .. '/ap'
  local files = io.scanDir(dir, '*.lon')
  TiedPopup(function()
    ui.setNextItemIcon(ui.Icons.Plus)
    if ui.selectable('New configuration') then
      applyLoadedAppPreset({}, nil)
    end
    ui.separator()
    for i, v in ipairs(files) do
      if ui.selectable(v:sub(1, -5)) then
        io.loadAsync(dir .. '/' .. v, function(err, response)
          local parsed = not err and stringify.tryParse(response)
          if type(parsed) == 'table' then
            applyLoadedAppPreset(parsed, v:sub(1, -5))
          else
            print(err, parsed)
            ui.toast(ui.Icons.Warning, 'Failed to load configuration “%s”' % v:sub(1, -5))
          end
        end)
      end
      presetContextMenu(dir .. '/' .. v, function()
        files = io.scanDir(dir, '*.lon')
      end)
    end
  end)
end

local function saveAppPreset()
  genSavingDialog('Save configuration?', 'Name for the configuration:', ac.getFolder(ac.FolderID.ScriptConfig) .. '/ap',
    cfg, function(dst, bak)
      if not io.save(dst, stringify(cfg), true) then
        ui.toast(ui.Icons.Warning, 'Failed to save configuration')
        return
      end
      ui.toast(ui.Icons.Save, 'Configuration saved as “%s”' % io.getFileName(dst, true), bak and function()
        io.save(dst, bak)
      end or nil)
    end)
end

return {
  cfg = cfg,
  save = save,
  item = function()
    if ui.itemEdited() or ui.itemActive() then
      save()
    end
  end,
  saveZonePreset = saveZonePreset,
  loadZonePreset = loadZonePreset,
  resetZoneConfig = resetZoneConfig,
  saveAppPreset = saveAppPreset,
  loadAppPreset = loadAppPreset,
}
