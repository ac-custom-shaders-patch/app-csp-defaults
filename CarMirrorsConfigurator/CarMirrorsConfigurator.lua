local types = { [0] = 'TN', 'VA', 'IPS' }

local function mirrorSettings(i)
  local p, c = ac.getRealMirrorParams(i - 1), true

  ui.beginGroup()

  ui.setNextItemWidth((ui.availableSpaceX() - 4) / 2)
  p.rotation.x = ui.slider('##rotationX', p.rotation.x * 100, -60, 60, 'Rotation X: %.1f%%') / 100
  ui.sameLine(0, 4)
  ui.setNextItemWidth(ui.availableSpaceX())
  p.rotation.y = ui.slider('##rotationY', p.rotation.y * 100, -60, 60, 'Rotation Y: %.1f%%') / 100
  
  ui.setNextItemWidth((ui.availableSpaceX() - 4) / 2)
  p.fov = ui.slider('##fov', p.fov, 2, 60, 'FOV: %.2f°', 2)   
  ui.sameLine(0, 4)
  ui.setNextItemWidth(ui.availableSpaceX())
  p.aspectMultiplier = ui.slider('##ratio', p.aspectMultiplier, 0.5, 2, 'Aspect mult.: %.2f', 1.6)   

  ui.setNextItemWidth((ui.availableSpaceX() - 12) / 4)
  if ui.checkbox('Flip X', bit.band(p.flip, ac.MirrorPieceFlip.Horizontal) ~= 0) then p.flip, c = bit.bxor(p.flip, ac.MirrorPieceFlip.Horizontal), true end
  ui.sameLine(0, 4)
  ui.setNextItemWidth((ui.availableSpaceX() - 8) / 3)
  if ui.checkbox('Monitor', p.isMonitor) then p.isMonitor, c = not p.isMonitor, true end

  local cur = ui.getCursor()
  ui.sameLine(0, 4)
  ui.beginGroup()
  if p.isMonitor then
    ui.setNextItemWidth((ui.availableSpaceX() - 8) / 2)
    ui.combo('##monitorType', p.useMonitorShader and 'Matrix: '..types[p.monitorShaderType] or 'Matrix: perfect', function ()
      if ui.selectable('Perfect') then p.useMonitorShader, c = false, true end
      for j = 0, #types do
        if ui.selectable(types[j]) then p.useMonitorShader, p.monitorShaderType, c = true, j, true end
      end
    end)
    ui.sameLine(0, 4)
    ui.setNextItemWidth(ui.availableSpaceX())
    p.monitorShaderSkew = ui.slider('##monitorShaderSkew', p.monitorShaderSkew * 100, -10, 10, 'Skew: %.1f%%') / 100
 
    if const(ac.getPatchVersionCode() >= 2611) then
      ui.setNextItemWidth(ui.availableSpaceX() / 2 - 4)
      p.monitorShaderScale.x = math.ceil(ui.slider('##monitorShaderScale.x', p.monitorShaderScale.x, 80, 800, string.format('Resolution: %.0f px', p.monitorShaderScale.x)) / 10) * 10
      if ui.itemEdited() then p.monitorShaderScale.y = p.monitorShaderScale.x / 4 end

      ui.sameLine(0, 4)
      ui.setNextItemWidth(ui.availableSpaceX())
      p.monitorBrightness = ui.slider('##monitorBrightness', p.monitorBrightness * 100, 50, 200, 'Brightness: %.0f%%') / 100
    else
      ui.setNextItemWidth(ui.availableSpaceX())
      p.monitorShaderScale.x = math.ceil(ui.slider('##monitorShaderScale.x', p.monitorShaderScale.x, 80, 800, string.format('Resolution: %.0f px', p.monitorShaderScale.x)) / 10) * 10
      if ui.itemEdited() then p.monitorShaderScale.y = p.monitorShaderScale.x / 4 end
    end
  else
    ui.setCursor(vec2(304, 80))
    ui.textWrapped('For better precision hold Shift while moving slider.\nOr, hold Ctrl and click it to edit number directly.')
  end
  ui.endGroup()
  ui.setCursor(cur)

  ui.setNextItemWidth((ui.availableSpaceX() - 12) / 4)
  if ui.checkbox('Flip Y', bit.band(p.flip, ac.MirrorPieceFlip.Vertical) ~= 0) then p.flip, c = bit.bxor(p.flip, ac.MirrorPieceFlip.Vertical), true end
  
  ui.endGroup()

  if c or ui.itemEdited() then
    ac.setRealMirrorParams(i - 1, p)
  end
end

function script.windowMain(dt)
  if ac.getRealMirrorCount() < 0 then
    ui.header('Real Mirrors are not available')
    if ac.getSim().isVirtualMirrorActive then
      ui.textWrapped('With current settings, real mirrors are not available when virtual mirror is active.')
    elseif ac.getSim().cameraMode ~= ac.CameraMode.Cockpit then
      ui.textWrapped('Switch to cockpit camera first.')
      ui.offsetCursorY(4)
      ui.setNextItemIcon(ui.Icons.Settings)
      if ui.button('Switch now', vec2(-0.1, 0)) then
        ac.setCurrentCamera(ac.CameraMode.Cockpit)
      end
    else
      ui.textWrapped('Make sure Smart Mirror module and its “Real Mirrors” option is enabled.')
      ui.offsetCursorY(4)
      ui.setNextItemIcon(ui.Icons.Settings)
      if ui.button('Activate now', vec2(-0.1, 0)) then
        local cfg = ac.INIConfig.cspModule(ac.CSPModuleID.SmartMirror)
        cfg:setAndSave('BASIC', 'ENABLED', true)
        cfg:setAndSave('REAL_MIRRORS', 'ENABLED', true)
      end
    end
    return
  end

  if ac.getRealMirrorCount() == 0 then
    ui.header('No mirrors found')
    ui.pushFont(ui.Font.Small)
    ui.textWrapped('Could it be that this car does not have any rear view mirrors?')
    ui.popFont()
    return
  end

  ui.tabBar('mirrors', ui.TabBarFlags.IntegratedTabs, function ()
    for i = 1, ac.getRealMirrorCount() do
      ui.tabItem(string.format('Mirror %d', i), function ()
        ui.pushFont(ui.Font.Small)
        mirrorSettings(i)
        ui.popFont()
      end)
    end
    ui.tabItem('Car config', function ()
      ui.textWrapped('If you are making a new car, working on its CSP config and need to adjust rear view mirrors, please move mirrors settings to it. You can find settings in “Documents/AC/cfg/extension/real_mirrors”. Simply copy-paste content of a file for this car to the config.')
      ui.offsetCursorY(4)
      ui.setNextItemIcon(ui.Icons.Folder)
      if ui.button('Folder with settings', vec2(-0.1, 0)) then
        local dir = ac.getFolder(ac.FolderID.Documents)..'/Assetto Corsa/cfg/extension/real_mirrors'
        local filename = dir..'/'..ac.getCarID(0)..'.ini'
        if io.exists(filename) then os.showInExplorer(filename)
        else os.openInExplorer(dir) end
      end
    end)
  end)
end
