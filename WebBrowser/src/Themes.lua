local App = require('src/App')
local Utils = require('src/Utils')
local Storage = require('src/Storage')

---@alias Theme {icon: rgbm[], id: string, name: string}
---@type Theme[]
local themes = {    
  {icon = {rgbm.colors.cyan, rgbm.colors.gray}, id = 'd', name = 'Nature' },
  {icon = {rgbm.colors.gray, rgbm.colors.black}, id = 'b', name = 'Memory' },
  {icon = {rgbm.colors.white, rgbm.colors.cyan}, id = 'c', name = 'Dream' },
  {icon = {rgbm.colors.fuchsia, rgbm.colors.cyan}, id = 'p', name = 'Neon' },
  {icon = {rgbm.colors.white, rgbm.colors.gray}, id = 'custom', name = 'Select image…' },
}

---@type table<string, Theme>
local kv = table.map(themes, function (item) return item, item.id end)

local ColSaturationHint = rgbm(1, 1, 1, 0.1)
local uv1 = vec2()
local uv2 = vec2(1, 1)
local uis = ac.getUI()
local gradColor = rgbm()

local c1 = rgbm(0, 0, 0, 0.6)
local c2 = rgbm(0, 0, 0, 0.2)
local c3 = rgbm(0, 0, 0, 0)
local v1 = vec2()
local v2 = vec2()

---@param p1 vec2
---@param p2 vec2
---@param gradientIntensity number?
---@return rgbm @Accent color.
local function drawThemedBg(p1, p2, gradientIntensity)
  local newTabStyle = Storage.settings.newTabStyle
  if #newTabStyle > 1 then
    ui.drawRectFilled(p1, p2, rgbm.colors.black)
    ui.drawImage(newTabStyle, p1, p2, rgbm.colors.white, uv1, uv2, ui.ImageFit.Fill)
  else
    if newTabStyle ~= 'd' then
      ui.setShadingOffset(0, 0, 0, 1)
      ui.drawRectFilled(p1, p2, newTabStyle == 'c' and rgbm.colors.cyan or newTabStyle == 'p' and rgbm.colors.cyan or rgbm.colors.black)
    else
      ui.setShadingOffset(1, 0, 0, 1)
    end
    ui.drawImage('dynamic::screen', p1, p2, newTabStyle == 'p' and rgbm.colors.fuchsia or rgbm.colors.white, uv1, uv2, ui.ImageFit.Fill)
    ui.resetShadingOffset()
    if newTabStyle == 'c' then
      ui.drawImage('dynamic::screen', p1, p2, ColSaturationHint, uv1, uv2, ui.ImageFit.Fill)
    end
  end
  
  if #newTabStyle > 1 and gradientIntensity then
    local b = Storage.settings.customThemeBlurring / 0.04
    b = b / (1 + b)
    gradientIntensity = 0.6 - 0.4 * b
  end
  gradColor.mult = gradientIntensity or 1
  ui.drawRectFilledMultiColor(p1, p2, rgbm.colors.transparent, rgbm.colors.transparent, gradColor, gradColor)

  if ui.rectHovered(p1, p2, true) and ui.windowHovered() and ui.mouseReleased(ui.MouseButton.Right) then
    App.selectedTab():triggerContextMenu()
  end

  if Storage.settings.newTabStyle == 'b' then return rgbm(0.2, 0.2, 0.2, 1) end
  if Storage.settings.newTabStyle == 'c' then return rgbm.colors.cyan end
  if Storage.settings.newTabStyle == 'p' then return rgbm.colors.purple end
  if Storage.settings.newTabStyle ~= 'd' and Storage.settings.customThemeColor.mult ~= 0 then return Storage.settings.customThemeColor end
  return uis.accentColor
end

---@param p1 vec2
---@param p2 vec2
---@param width number
local function beginColumnGroup(p1, p2, width)
  local newTabStyle = Storage.settings.newTabStyle
  if #newTabStyle > 1 then
    ui.beginBlurring()
    if p2.x - p1.x > width + 40 then
      local w = width + 40
      local p = (p1.x + p2.x) / 2
      local p1a = v1:set(p - w / 2, p1.y)
      local p2a = v2:set(p + w / 2, p2.y)
      ui.pushClipRect(p1a, p2a, true)
      ui.drawImage(newTabStyle, p1, p2, rgbm.colors.white, uv1, uv2, ui.ImageFit.Fill)
      ui.popClipRect()
    else
      ui.drawImage(newTabStyle, p1, p2, rgbm.colors.white, uv1, uv2, ui.ImageFit.Fill)
    end
    ui.endBlurring(Storage.settings.customThemeBlurring)
    local b = Storage.settings.customThemeBlurring / 0.02
    b = b / (1 + b)
    c1.mult = 0.8 - 0.4 * b
    c2.mult = 0.1 - 0.1 * b
  else
    c1.mult = 0.8
    c2.mult = 0.1
  end

  if p2.x - p1.x > width + 40 then
    local px, wh = (p1.x + p2.x) / 2, width / 2 + 20
    ui.drawRectFilled(v1:set(px - wh, p1.y), v2:set(px + wh, p2.y), c1)
    ui.drawRectFilledMultiColor(v1:set(px - (wh + 30), p1.y), v2:set(px - wh, p2.y), c3, c2, c2, c3)
    ui.drawRectFilledMultiColor(v1:set(px + wh, p1.y), v2:set(px + (wh + 30), p2.y), c2, c3, c3, c2)
    ui.drawRectFilledMultiColor(v1:set(px - (wh + 40), p1.y), v2:set(px - wh, p2.y), c3, c2, c2, c3)
    ui.drawRectFilledMultiColor(v1:set(px + wh, p1.y), v2:set(px + (wh + 40), p2.y), c2, c3, c3, c2)
    ui.setCursor(v1:set(px - width / 2, p1.y + 20))
    ui.beginGroup(400)
  else
    ui.drawRectFilled(p1, p2, c1)
    ui.setCursor(v1:set(20, p1.y + 20))
    ui.beginGroup(p2.x - p1.x - 40)
  end
end

local oldBackgroundsCleared = false

---@param tab WebBrowser
---@param url string
local function setBackgroundImage(tab, url)
  local dir = ac.getFolder(ac.FolderID.ScriptConfig)
  if not oldBackgroundsCleared then
    oldBackgroundsCleared = true
    local skip = io.getFileName(Storage.settings.newTabStyle)
    for _, v in ipairs(io.scanDir(dir, 'bg*.png')) do
      if v ~= skip then io.deleteFile(dir..'/'..v) end
    end
  end
  tab:downloadImageAsync(url, false, nil, function (err, data)
    if data then
      local filename
      filename = '%s/bg%s.png' % {dir, bit.tohex(ac.checksumXXH(url))}
      io.save(filename, data)
      local old, oldColor = Storage.settings.newTabStyle, Storage.settings.customThemeColor
      Storage.settings.newTabStyle = filename
      Utils.estimateAccentColor(filename, function (color)
        Storage.settings.customThemeColor = color
      end)
      ui.toast(ui.Icons.Confirm, 'Background updated', function ()
        Storage.settings.newTabStyle, Storage.settings.customThemeColor = old, oldColor
        io.deleteFile(filename)
      end)
    elseif err then
      ui.toast(ui.Icons.Warning, 'Couldn’t update background: '..err)
    end
  end)
end

return {
  themes = themes,
  set = function (id)    
    if id == 'custom' then
      os.openFileDialog({
        defaultFolder = Utils.Paths.pictures(),
        fileTypes = {{name = 'Images', mask = '*.png;*.jpg;*.jpeg'}},
        addAllFilesFileType = true
      }, function (err, filename)
        if not filename then return end
        local old, oldColor = Storage.settings.newTabStyle, Storage.settings.customThemeColor
        Storage.settings.newTabStyle = filename
        Utils.estimateAccentColor(filename, function (color)
          Storage.settings.customThemeColor = color
        end)
        ui.toast(ui.Icons.Confirm, 'Background updated', function ()
          Storage.settings.newTabStyle, Storage.settings.customThemeColor = old, oldColor
          io.deleteFile(filename)
        end)
      end)
    else
      Storage.settings.newTabStyle = id
    end
  end,
  selected = function ()
    return kv[Storage.settings.newTabStyle] or themes[#themes]
  end,
  accentOverride = function ()
    if Storage.settings.newTabStyle == 'b' then return rgbm.colors.orange end
    if Storage.settings.newTabStyle == 'c' then return rgbm.colors.cyan end
    if Storage.settings.newTabStyle == 'p' then return rgbm.colors.fuchsia end
    if Storage.settings.newTabStyle ~= 'd' and Storage.settings.customThemeColor.mult ~= 0 then return Storage.settings.customThemeColor end
  end,
  drawThemedBg = drawThemedBg,
  beginColumnGroup = beginColumnGroup,
  iconImage = function (theme)
    if not theme.iconImage then
      theme.iconImage = ui.ExtraCanvas(22):update(function (dt)
        ui.beginGradientShade()
        ui.drawCircleFilled(11, 11, rgbm.colors.white, 20)
        ui.endGradientShade(0, 22, theme.icon[1], theme.icon[2], false)
        if theme.id == 'custom' then
          ui.drawIcon(ui.Icons.Plus, 4, 18)
        end
      end)
    end
    return theme.iconImage
  end,
  setBackgroundImage = setBackgroundImage,
}