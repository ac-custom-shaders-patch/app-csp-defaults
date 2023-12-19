local sim = ac.getSim()
local light = nil ---@type ac.LightSource?
local alignOnce = true

local storage = ac.storage({
  color = rgb(0.6, 0.9, 1),
  brightness = 10,
  spot = 45,
  sharpness = 0.9,
  range = 10,
  align = true
})

function script.windowMain(dt)
  if not light then
    light = ac.LightSource(ac.LightType.Regular)
  end

  ui.beginGroup(ui.availableSpaceX() - 24)
  ui.pushItemWidth(ui.availableSpaceX())
  local newColor = storage.color:clone()
  ui.colorButton('Color', newColor, ui.ColorPickerFlags.PickerHueBar)
  if ui.itemEdited() then
    storage.color = newColor
  end
  ui.sameLine(0, 4)
  ui.setNextItemWidth(ui.availableSpaceX())
  storage.brightness = ui.slider('##brightness', storage.brightness, 0, 1000, 'Brightness: %.2f', 2)
  light.color:set(storage.color):scale(storage.brightness)
  light.specularMultiplier = 1

  storage.spot = ui.slider('##spot', storage.spot, 10, 160, 'Spot: %.1f°')
  storage.sharpness = ui.slider('##sharpness', storage.sharpness * 100, 0, 100, 'Sharpness: %.1f%') / 100
  storage.range = ui.slider('##range', storage.range, 0, 100, 'Range: %.1f m')

  light.spot = storage.spot
  light.spotSharpness = storage.sharpness
  light.range = storage.range
  light.rangeGradientOffset = 0
  
  light.shadows = true
  light.shadowsRange = light.range

  ui.popItemWidth()
  ui.endGroup()
  ui.sameLine(0, 4)
  if ui.iconButton(ui.Icons.Link, ui.availableSpace(), 4, true,
      storage.align and ui.ButtonFlags.Active or 0) then
    storage.align = not storage.align
  end
  if ui.itemHovered() then
    ui.setTooltip('Move with camera')
  end
end

function script.onHideWindowMain()
  if light then
    alignOnce = true
    light:dispose()
    light = nil
  end
end

function script.update(dt)
  if light and (storage.align or alignOnce) then
    light.position:set(sim.cameraPosition):addScaled(sim.cameraLook, 0.1)
    light.direction:set(sim.cameraLook)
    alignOnce = false
  end
end
