local radio = require('shared/utils/radio')

local settings = ac.storage{
  resume = true,
  lastUsedURL = '',
  infoIcons = '{}',
  infoLines = '{}',
  volume = 1
}

radio.setVolume(settings.volume)
local infoLines = stringify.tryParse(settings.infoLines, nil, {})
local infoIcons = stringify.tryParse(settings.infoIcons, nil, {})

---@param station radio.RadioStation
---@return {url: string?, description: string?}
local function getInfoLine(station)
  local r = infoLines[station.url]
  if r == nil then
    infoLines[station.url] = false
    radio.getStreamMetadataAsync(station.url, function (err, data)
      if data then
        infoLines[station.url] = data.description 
          and {url = data.url, description = data.description}
          or data.url and {url = data.url, description = data.url}
          or {url = station.url, description = station.url}
        settings.infoLines = stringify(infoLines)
      end
    end)
  end
  return r or {url = station.url, description = station.url}
end
 
local function getInfoIcon(station)
  local r = infoIcons[station.url]
  if r == nil then
    infoIcons[station.url] = false
    radio.getLogoAsync(station, function (err, url)
      infoIcons[station.url] = url or false
      settings.infoIcons = stringify(infoIcons)
    end)
  end
  return r
end

local pastelToneCache = {}

local function pastelTone(url)
  local r = pastelToneCache[url]
  if not r then
    r = rgbm.new(hsv(ac.checksumXXH(url) % 360, 0.6, 0.7):rgb(), 1)
    pastelToneCache[url] = r
  end
  return r
end

local search = ''
local dragging
-- local selected = rgbm(1, 1, 1, 0.25)

---@param i integer
---@param v radio.RadioStation
---@param cr1 vec2
---@param cr2 vec2
---@return boolean
local function stationItem(i, v, cr1, cr2)
  local draggingNow = dragging == v
  if draggingNow then
    ui.offsetCursorY(ui.mouseDragDelta().y)
    ui.pushStyleColor(ui.StyleColor.Button, ui.styleColor(ui.StyleColor.ButtonActive))
  end
  ui.pushID(i)
  ui.pushStyleVar(ui.StyleVar.FrameRounding, 2)
  local ret = false
  if ui.button('##btn', vec2(-20, 40)) and not dragging then
    ret = true
  end
  if draggingNow then
    ui.popStyleColor()
  end
  if v == radio.current() then
    local ir1, ir2 = ui.itemRect()
    ui.drawRectFilled(ir1, vec2(ir1.x + 4, ir2.y), ui.styleColor(ui.StyleColor.ButtonActive), 2, ui.CornerFlags.Left)
  end
  ui.setItemAllowOverlap()
  if ui.itemActive() and math.abs(ui.mouseDragDelta().y) > 5 then
    dragging = v
  end
  if ui.itemClicked(ui.MouseButton.Right, true) then
    ui.popup(function ()
      if ui.selectable('Rename') then
        local oldName = v.name
        ui.modalPrompt('Rename station', 'New name for “%s”' % v.name, v.name, 'Rename', 'Cancel', 
            ui.Icons.Confirm, ui.Icons.Cancel, function (newName)
          if newName then
            radio.renameStation(v, newName)
            ui.toast(ui.Icons.Confirm, 'Station renamed', function ()
              radio.renameStation(v, oldName)
            end)
          end
        end)
      end
      if ui.selectable('Delete') then
        local pos = table.indexOf(radio.stations(), v)
        radio.removeStation(v)
        ui.toast(ui.Icons.Trash, 'Station deleted', function ()
          radio.addStation(v.name, v.url, pos)
        end)
      end
    end)
  end
  ui.popStyleVar()
  ui.offsetCursorY(-40)
  ui.offsetCursorX(12)

  ui.pushClipRect(cr1, cr2, true)
  ui.dummy(28)
  local ir1, ir2 = ui.itemRect()
  ir1.y, ir2.y = ir1.y + 2, ir2.y + 2
  local icon = getInfoIcon(v)
  if icon then
    ui.drawImageRounded(getInfoIcon(v), ir1, ir2, 14)
    if ui.itemHovered() then
      ui.tooltip(0, function ()
        ui.image(getInfoIcon(v), 120)
      end)
    end
  else
    ui.drawCircleFilled((ir1 + ir2) / 2, 14, pastelTone(v.url), 24)
    ir1.y, ir2.y = ir1.y - 1, ir2.y - 1
    ui.drawTextClipped(v.name:sub(1, 1), ir1, ir2, rgbm.colors.white, 0.5)
  end
  ui.sameLine(0, 8)
  ui.beginGroup()
  ui.text(v.name)
  ui.pushFont(ui.Font.Small)
  local details = getInfoLine(v)
  if not details.url then
    ui.text(details.description)
  else
    if ui.textHyperlink(details.description) then
      os.openURL(details.url)
    end
    if ui.itemHovered() then
      ui.setTooltip(details.url)
      ret = false
    end
  end
  ui.popFont()
  ui.endGroup()
  ui.offsetCursorY(2 + 4)
  ui.popClipRect()
  ui.popID()
  return ret
end

local function addNewStation()  
  local url = ''
  local delay = -1
  local metadata, metadataURL
  local originalName
  ui.modalDialog('Add radio station', function ()
    url = ui.inputText('Station stream URL', url, ui.InputTextFlags.Placeholder)
    if ui.itemEdited() then
      clearTimeout(delay)
      if url:urlCheck() then
        if table.some(radio.stations(), function (item) return item.url:lower() == url:lower() end) then
          metadata = true
        else
          metadata = false
          delay = setTimeout(function ()
            radio.getStreamMetadataAsync(url, function (err, data)
              metadataURL = url
              metadata = err or data
              if data then originalName = data.name end
            end)
          end, 0.5)
        end
      else
        metadata = nil
      end
    end
    ui.offsetCursorY(12)
    ui.header('Found station:')
    ui.backupCursor()
    if type(metadata) == 'table' then
      ui.bulletText('Name: ')
      ui.sameLine(0, 0)
      ui.pushStyleVar(ui.StyleVar.FramePadding, vec2())
      ui.setNextItemWidth(ui.availableSpaceX())
      metadata.name = ui.inputText(originalName, metadata.name, ui.InputTextFlags.Placeholder)
      ui.popStyleVar()
      if metadata.description then
        ui.bulletText('Description: %s' % metadata.description)
      end
      if metadata.genre then
        ui.bulletText('Genre: %s' % metadata.genre)
      end
      if metadata.url then
        ui.bulletText('URL: ')
        ui.sameLine(0, 0)
        if ui.textHyperlink(metadata.url) then
          os.openURL(metadata.url)
        end
      end
      if metadata.bitrateKbps then
        ui.bulletText('Bitrate: %s Kb/s' % metadata.bitrateKbps)
      end
    elseif type(metadata) == 'string' then
      ui.textWrapped('Failed to load metadata: %s.' % metadata:lower())
    elseif metadata == true then
      ui.textWrapped('Already in the list of known stations.')
    elseif metadata == false then
      ui.textWrapped('Loading metadata…')
    else
      ui.textWrapped('Enter stream URL first. You can find more URLs here:')
      if ui.textHyperlink('https://truck-simulator.fandom.com/wiki/Radio_Stations') then
        os.openURL('https://truck-simulator.fandom.com/wiki/Radio_Stations')
      end
    end
    ui.restoreCursor()
    ui.offsetCursorY(120)
    local w = ui.availableSpaceX() / 2 - 4
    if ui.modernButton('Add station', vec2(w, 40), type(metadata) == 'table' and ui.ButtonFlags.Confirm or ui.ButtonFlags.Disabled,
      metadata == false and ui.Icons.LoadingSpinner or ui.Icons.Confirm) and type(metadata) == 'table' then
      radio.addStation(#metadata.name == 0 and originalName or metadata.name, metadataURL)
    end
    ui.sameLine(0, 4)
    if ui.modernButton('Cancel', vec2(w, 40), ui.ButtonFlags.None, ui.Icons.Cancel) then
      return true
    end
  end, true)
end

---@return radio.RadioStation?
local function stationSelection()
  local ret
  local cr1, cr2 = vec2(0, 0), vec2(ui.getCursorX() + ui.availableSpaceX() - 20, math.huge)
  ui.setNextItemWidth(ui.availableSpaceX())
  ui.pushStyleVar(ui.StyleVar.FrameRounding, 2)
  search = ui.availableSpaceY() < 100 and ''
    or ui.inputText('Search', search, bit.bor(ui.InputTextFlags.Placeholder, ui.InputTextFlags.AutoSelectAll))
  ui.popStyleVar()
  ui.pushClipRect(vec2(), ui.windowSize(), false)
  ui.childWindow('##scroll', vec2(ui.availableSpaceX() + 20, ui.availableSpaceY() + 8), false, bit.bor(ui.WindowFlags.NoBackground, ui.WindowFlags.NoScrollbar), function ()
    ui.thinScrollbarBegin(true)
    local draggingPos
    for i, v in ipairs(radio.stations()) do
      if search ~= '' and not v.name:findIgnoreCase(search) then
        goto skip
      end
      if v == dragging then
        draggingPos = ui.getCursorY()
        ui.offsetCursorY(46)
      elseif stationItem(i, v, cr1, cr2) then
        ret = v
      end
      ::skip::
    end
    ui.pushStyleVar(ui.StyleVar.FrameRounding, 2)
    ui.setNextItemIcon(ui.Icons.Plus)
    ui.pushFont(ui.Font.Small)
    local addClicked = ui.button('Add station', vec2(-20, 0))
    ui.popFont()
    if dragging and draggingPos then
      ui.backupCursor()
      ui.setCursorY(draggingPos)
      stationItem(table.indexOf(radio.stations(), dragging) or -1, dragging, cr1, cr2)
      ui.restoreCursor()
      if not ui.mouseDown(ui.MouseButton.Left) then
        local shift = ui.mouseDragDelta().y / 46
        if math.abs(shift) > 0.8 then
          radio.moveStation(dragging, math.round(table.indexOf(radio.stations(), dragging) + shift - math.sign(shift) * 0.5))
        end
        dragging = nil
      end
    end
    if addClicked then
      addNewStation()
    end
    ui.popStyleVar()
    ui.offsetCursorY(12)
    ui.thinScrollbarEnd()
  end)
  ui.popClipRect()
  return ret
end

local styled = false
local syncedStyle
local brightMode = false

---@param station radio.RadioStation?
local function syncWindowStyle(station)
  syncedStyle = station
  if not station then
    ac.setWindowTitle('main', nil)
    ac.setWindowBackground('main', nil)
    brightMode = false
    return
  end
  ac.setWindowTitle('main', station.name)
  local icon = getInfoIcon(station)
  styled = false
  if icon then
    ui.onImageReady(icon, function ()
      ui.ExtraCanvas(4, 4):copyFrom(icon):accessData(function (err, data)
        if syncedStyle == station then
          brightMode = data:color(2, 0).rgb:value() > 0.6
          ac.setWindowBackground('main', data:color(2, 0), brightMode)
        end
        styled = true
      end)
    end)
  else
    local col = pastelTone(station.url)
    col.rgb:scale(0.5):adjustSaturation(2)
    brightMode = false
    ac.setWindowBackground('main', col)
    styled = true
  end
end

local fadeColor0 = rgbm(1, 1, 1, 0)
local fadeColor1 = rgbm(1, 1, 1, 0.8)
local fadeColor2 = rgbm(1, 1, 1, 0.1)
local btnCol0 = rgbm(1, 1, 1, 0.1)
local btnCol1 = rgbm(1, 1, 1, 0.15)
local btnCol2 = rgbm(1, 1, 1, 0.2)
local artworkPrev
local artworkDark = false

function script.windowSettings(dt)
  if ui.checkbox('Automatically connect to the last used station on launch', settings.resume) then
    settings.resume = not settings.resume
  end
end

---@param current radio.RadioStation
local function stationUI(current)
  local artworkCur = radio.getArtwork()
  if artworkPrev ~= artworkCur then
    artworkPrev = artworkCur
    if artworkCur ~= nil then
      ui.onImageReady(artworkCur, function ()
        ui.ExtraCanvas(3):copyFrom(artworkCur):accessData(function (err, data)
          if artworkPrev == artworkCur then
            artworkDark = data and data:color(1, 2).rgb:value() < 0.2
          end
        end)
      end)
    else
      artworkDark = false
    end
  end

  local icon = getInfoIcon(current)
  if icon and styled then
    ui.pushClipRect(vec2(0, 20), ui.windowSize(), false)
    ui.beginBlurring()
    ui.drawImage(icon, 0, ui.windowSize())
    ui.endBlurring(0.3)
    if artworkCur then
      ui.beginBlurring() 
      ui.beginTextureShade(artworkCur)
      ui.drawRectFilledMultiColor(0, ui.windowSize(), fadeColor0, fadeColor0, fadeColor1, fadeColor1)
      ui.endTextureShade(0, ui.windowSize())
      ui.endBlurring(0.15 - 0.01 * ac.mediaCurrentPeak().x)
    end
    ui.beginSubtraction()
    ui.drawRectFilledMultiColor(0, ui.windowSize(), fadeColor0, fadeColor0, fadeColor2, fadeColor2)
    ui.endSubtraction()
    ui.popClipRect()
  end
  ui.pushAlignment(true)
  if ui.availableSpaceY() > 60 then
    if radio.hasMetadata(current) then
      if artworkCur and ui.availableSpaceY() > 200 then
        ui.pushAlignment()
        ui.image(artworkCur, 120, ui.ImageFit.Fill)
        ui.popAlignment()
        ui.offsetCursorY(4)
      end
      ui.pushFont(ui.Font.Title)
      ui.textAligned(radio.getTitle() or '<Unknown>', 0.5, vec2(-0.1, 0), true)
      ui.popFont()
      if ui.availableSpaceY() > 80 then
        ui.textAligned(radio.getArtist() or current.name, 0.5, vec2(-0.1, 0), true)
      end
    else
      ui.pushFont(ui.Font.Title)
      ui.textAligned(current.name, 0.5, vec2(-0.1, 0), true)
      ui.popFont()
      if ui.availableSpaceY() > 80 then
        ui.pushStyleVarAlpha(0.5)
        ui.textAligned(current.url, 0.5, vec2(-0.1, 0), true)
        ui.popStyleVar()
      end
    end
    ui.offsetCursorY(12)
  end
  
  ui.pushAlignment()
  ui.pushStyleColor(ui.StyleColor.Button, btnCol0)
  ui.pushStyleColor(ui.StyleColor.ButtonHovered, btnCol1)
  ui.pushStyleColor(ui.StyleColor.ButtonActive, btnCol2)
  ui.pushStyleVar(ui.StyleVar.FrameRounding, 2)
  if ui.iconButton(ui.Icons.StopAlt, 32, 10) then
    radio.play(nil)
  end
  ui.sameLine(0, 8)
  if ui.iconButton(not radio.loaded() and ui.Icons.LoadingSpinner 
      or radio.playing() and ui.Icons.Pause or ui.Icons.Play, 32, 10) then
    radio.pause(radio.playing())
  end
  if ui.windowWidth() > 150 then
    ui.sameLine(0, 8)
    local volume = radio.getVolume()
    if ui.iconButton(volume == 0 and ui.Icons.Mute or volume < 0.33 and ui.Icons.VolumeLow or volume < 0.66 
        and ui.Icons.VolumeMedium or ui.Icons.VolumeHigh, 32, 10) then
      ui.popup(function ()
        local newValue = ui.slider('##volume', radio.getVolume() * 100, 0, 100, 'Volume: %.0f%%')
        if ui.itemEdited() then
          radio.setVolume(newValue / 100)
        end
      end)
    end
  end
  ui.popStyleColor(3)
  ui.popStyleVar()
  ui.popAlignment()

  ui.popAlignment()
end

local minimized = false

function script.windowMain(dt)
  local current = radio.current()
  if current ~= nil and not minimized then
    if brightMode and not artworkDark then
      ui.pushStyleColor(ui.StyleColor.Text, rgbm.colors.black)
      stationUI(current)
      ui.popStyleColor()
    else
      stationUI(current)
    end
    if ui.windowHeight() > 200 then
      ui.pushClipRectFullScreen()
      ui.setCursorX(0)
      ui.setCursorY(20)
      ui.pushStyleColor(ui.StyleColor.Button, rgbm.colors.transparent)
      ui.pushStyleColor(ui.StyleColor.ButtonHovered, btnCol1)
      ui.pushStyleColor(ui.StyleColor.ButtonActive, btnCol2)
      if ui.iconButton(ui.Icons.ArrowLeft, 32, 10) or ui.mouseClicked(ui.MouseButton.Extra1) then
        minimized = true
      end
      ui.popStyleColor(3)
      ui.popClipRect()
    end
  else
    current = stationSelection()
    if current then
      radio.play(current)
      minimized = false
    elseif minimized then
      current = radio.current()
      if ui.mouseClicked(ui.MouseButton.Extra2) then
        minimized = false
      end
    end
  end
  if syncedStyle ~= current then
    syncWindowStyle(current)
  end
end

local skipSession = ac.getSim().isReplayOnlyMode
local current = radio.current()
if current ~= nil then
  syncWindowStyle(current)
elseif settings.resume and #settings.lastUsedURL > 0 and not skipSession then
  local station = table.findFirst(radio.stations(), function (x) return x.url == settings.lastUsedURL end)
  if station ~= nil then
    radio.play(station)
    syncWindowStyle(station)
  end
end

setInterval(function ()
  if settings.resume then
    -- If we need to resume playback in the next run, gotta keep running to track current station URL
    -- Running only this function once a second is beyond cheap anyway (there is no `script.update()`)
    if not skipSession then
      settings.lastUsedURL = radio.current() and radio.playing() and radio.current().url or ''
    elseif radio.playing() then
      skipSession = false
    end
  else
    -- Note: if any app window is visible, this function will have no effect
    ac.unloadApp()
  end
  if settings.volume ~= radio.getVolume() then
    settings.volume = radio.getVolume()
  end
end, 1)
