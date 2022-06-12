local types = { [0] = 'TN', 'VA', 'IPS' }

local function mirrorSettings(i)
  local p, c = ac.getRealMirrorParams(i - 1), true

  ui.beginGroup()

  ui.setNextItemWidth((ui.availableSpaceX() - 4) / 2)
  p.rotation.x = ui.slider('##rotationX', p.rotation.x, -1, 1, 'Rotation X: %.2f')
  ui.sameLine(0, 4)
  ui.setNextItemWidth(ui.availableSpaceX())
  p.rotation.y = ui.slider('##rotationY', p.rotation.y, -1, 1, 'Rotation Y: %.2f')
  
  ui.setNextItemWidth((ui.availableSpaceX() - 4) / 2)
  p.fov = ui.slider('##fov', p.fov, 2, 20, 'FOV: %.2f°')   
  ui.sameLine(0, 4)
  ui.setNextItemWidth(ui.availableSpaceX())
  p.aspectMultiplier = ui.slider('##ratio', p.aspectMultiplier, 0.5, 2, 'Aspect mult.: %.2f', 1.6)   

  ui.setNextItemWidth((ui.availableSpaceX() - 12) / 4)
  if ui.checkbox('Flip X', bit.band(p.flip, ac.MirrorPieceFlip.Horizontal) ~= 0) then p.flip, c = bit.bxor(p.flip, ac.MirrorPieceFlip.Horizontal), true end
  ui.sameLine(0, 4)
  ui.setNextItemWidth((ui.availableSpaceX() - 8) / 3)
  if ui.checkbox('Flip Y', bit.band(p.flip, ac.MirrorPieceFlip.Vertical) ~= 0) then p.flip, c = bit.bxor(p.flip, ac.MirrorPieceFlip.Vertical), true end
  
  ui.setNextItemWidth((ui.availableSpaceX() - 12) / 4)
  if ui.checkbox('Monitor', p.isMonitor) then p.isMonitor, c = not p.isMonitor, true end
  if p.isMonitor then
    ui.sameLine(0, 4)
    ui.setNextItemWidth((ui.availableSpaceX() - 8) / 3)
    ui.combo('##monitorType', p.useMonitorShader and 'Shader: '..types[p.monitorShaderType] or 'Shader: disabled', function ()
      if ui.selectable('Disabled') then p.useMonitorShader, c = false, true end
      for j = 0, #types do
        if ui.selectable(types[j]) then p.useMonitorShader, p.monitorShaderType, c = true, j, true end
      end
    end)
    ui.sameLine(0, 4)
    ui.setNextItemWidth((ui.availableSpaceX() - 4) / 2)
    p.monitorShaderSkew = ui.slider('##monitorShaderSkew', p.monitorShaderSkew * 100, -10, 10, 'Skew: %.1f%%') / 100
    ui.sameLine(0, 4)
    ui.setNextItemWidth(ui.availableSpaceX())
    p.monitorShaderScale.x = math.ceil(ui.slider('##monitorShaderScale.x', p.monitorShaderScale.x, 80, 800, string.format('Resolution: %.0f px', p.monitorShaderScale.x)) / 10) * 10
    if ui.itemEdited() then p.monitorShaderScale.y = p.monitorShaderScale.x / 4 end
  else
    ui.setCursor(vec2(304, 80))
    ui.textWrapped('For better precision hold Shift while moving slider.\nOr, hold Ctrl and click it to edit number directly.')
  end
  
  ui.endGroup()

  if c or ui.itemEdited() then
    ac.setRealMirrorParams(i - 1, p)
  end
end

function script.windowMain(dt)
  if ac.getRealMirrorCount() == 0 then
    ui.text('No Real Mirrors available')
  end

  ui.tabBar('mirrors', ui.TabBarFlags.IntegratedTabs, function ()
    for i = 1, ac.getRealMirrorCount() do
      ui.tabItem(string.format('Mirror %d', i), function ()
        ui.pushFont(ui.Font.Small)
        mirrorSettings(i)
        ui.popFont()
      end)
    end
    ui.tabItem('Configs', function ()
      ui.textWrapped('If you are creating a config for this car, please move mirrors settings to it. You can find settings in “Documents/AC/cfg/extension/real_mirrors”. Simply copy-paste content of a file for this car to the config.')
      if ui.button('Folder with settings') then
        local dir = ac.getFolder(ac.FolderID.Documents)..'/Assetto Corsa/cfg/extension/real_mirrors'
        local filename = dir..'/'..ac.getCarID(0)..'.ini'
        if io.exists(filename) then os.showInExplorer(filename)
        else os.openInExplorer(dir) end
      end
    end)
  end)
end
