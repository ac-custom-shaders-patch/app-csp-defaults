local FaviconsProvider = require('src/FaviconsProvider')

local App = require('src/App')
local db = require('src/DbBackedStorage')
local Icons = require('src/Icons')
local Utils = require('src/Utils')
local ControlsBasic = require('src/ControlsBasic')
local ControlsAdvanced = require('src/ControlsAdvanced')
local ControlsInputFeatures = require('src/ControlsInputFeatures')
local Themes = require('src/Themes')

local popup = Utils.uniquePopup()
local opened = nil

---@alias PermissionMetadata {key: WebBrowser.PermissionType, icon: ui.Icons, ask: string, media: boolean|'once', title: string}

---@type PermissionMetadata[]
local knownTypes = {
  {key = 'videoCapture', icon = ui.Icons.Camera, ask = 'Use your camera', media = true, title = 'Camera'},
  {key = 'audioCapture', icon = ui.Icons.Microphone, ask = 'Listen to your microphone', media = true, title = 'Microphone'},
  {key = 'displayCapture', icon = ui.Icons.Preview, ask = 'See the contents of your screen', media = 'once', title = 'Screen share'},
  {key = 'desktopAudioCapture', icon = ui.Icons.VolumeHigh, ask = 'Listen to your audio', media = 'once', title = 'Audio share'},
  {key = 'clipboardReadWrite', icon = ui.Icons.Copy, ask = 'See text and images copied to the clipboard', media = false, title = 'Clipboard'},
  {key = 'geolocation', icon = ui.Icons.Location, ask = 'Know your location', media = false, title = 'Location'},
  {key = 'multipleDownloads', icon = ui.Icons.Download, ask = 'Download multiple files', media = false, title = 'Automatic downloads'},
  {key = 'midiSysex', icon = ui.Icons.Wrench, ask = 'Control your MIDI devices', media = false, title = 'MIDI devices'},
}

---@param permission WebBrowser.PermissionType
---@return PermissionMetadata?
local function getPermissionMetadata(permission)
  for _, v in ipairs(knownTypes) do
    if v.key == permission then return v end
  end
  return nil
end

local permissionsStorage

---@return DbDictionaryStorage<table<WebBrowser.PermissionType, boolean>>
local function getPermissionsStorage()
  if not permissionsStorage then permissionsStorage = db.Dictionary('permissions') end
  return permissionsStorage
end

---@param url string
---@return table<WebBrowser.PermissionType, boolean>
local function getPermissionsForDomain(url)
  local domain = WebBrowser.getDomainName(url):lower()
  return getPermissionsStorage():get(domain) or {}
end

local function resetPermissions(url)
  local domain = WebBrowser.getDomainName(url):lower()
  getPermissionsStorage():remove(domain)
  for _, v in ipairs(App.tabs) do
    if v:domain():lower() == domain then
      v:restart()
    end
  end
end

---@param url string
---@param permissions WebBrowser.PermissionType[]
---@param state boolean?
local function setPermissionsForDomain(url, permissions, state)
  local domain = WebBrowser.getDomainName(url):lower()
  local anyChanged = false
  local known = getPermissionsStorage():get(domain) or {}
  for _, v in ipairs(permissions) do
    if known[v] ~= state then
      known[v] = state
      anyChanged = true
    end
  end
  if anyChanged then
    getPermissionsStorage():set(domain, known)
  end
end

---@param originURL string
---@param permissions WebBrowser.PermissionType[]
---@param callback fun(result: boolean?)
---@param position vec2
local function showPermissionPopup(originURL, permissions, callback, position)
  local domain = WebBrowser.getDomainName(originURL)
  if not domain or #permissions == 0 then
    callback(nil)
    return
  end
  local filtered = {} ---@type PermissionMetadata[]
  local media = false ---@type boolean|'once'
  local anyGranted = false
  local known = getPermissionsForDomain(domain)
  for _, v in ipairs(permissions) do
    if known[v] then
      anyGranted = true
    elseif known[v] == false then
      callback(false)
      return
    else
      local entry = getPermissionMetadata(v)
      if not entry then
        callback(nil)
        return
      end
      if entry.media and media ~= 'once' then
        media = entry.media
      end
      table.insert(filtered, entry)
    end
  end
  if anyGranted and #filtered == 0 then
    callback(true)
    return
  end
  if opened then
    opened(nil)
  end
  opened = callback
  Utils.popup(function()
    ui.pushFont(ui.Font.Title)
    ui.setNextTextSpanStyle(1, #domain, nil, true)
    ui.text('%s wants to' % domain)
    ui.popFont()
    ui.offsetCursorY(8)
    for _, v in ipairs(filtered) do
      ui.icon(v.icon, 12)
      ui.sameLine(0, 6)
      ui.offsetCursorY(-2)
      ui.text(v.ask)
      ui.offsetCursorY(4)
    end
    ui.offsetCursorY(8)
    if media then
      if media ~= 'once' then
        ui.setNextItemIcon(ui.Icons.Verified)
        if ui.button('Always', vec2(80, 0)) then
          setPermissionsForDomain(originURL, permissions, true)
          opened = nil
          callback(true)
          ui.closePopup()
        end
        ui.sameLine(0, 4)
      end
      ui.setNextItemIcon(ui.Icons.Confirm)
      if ui.button('Once', vec2(80, 0)) then
        opened = nil
        callback(true)
        ui.closePopup()
      end
    else
      ui.setNextItemIcon(ui.Icons.Confirm)
      if ui.button('Allow', vec2(80, 0)) then
        setPermissionsForDomain(originURL, permissions, true)
        opened = nil
        callback(true)
        ui.closePopup()
      end
    end
    ui.sameLine(0, 4)
    ui.setNextItemIcon(ui.Icons.Cancel)
    if ui.button('Deny', vec2(80, 0)) then
      setPermissionsForDomain(originURL, permissions, false)
      opened = nil
      callback(false)
      ui.closePopup()
    end
    ui.offsetCursorY(8)
  end, {
    position = position,
    pivot = vec2(0, 0),
    onClose = function()
      if opened then
        opened(nil)
        opened = nil
      end
    end
  })
end
 
local function managePermissions(url)
  local permissions = getPermissionsForDomain(url)
  local anyAllowed = false
  local anyProhibited = false
  for k, v in pairs(permissions) do
    if v == true then anyAllowed = true end
    if v == false then anyProhibited = true end
  end
  ui.modalDialog('Permissions', function ()
    if anyAllowed then
      ui.header('Allowed')
      ui.offsetCursorY(4)
      for k, v in pairs(permissions) do
        if v then
          local e = getPermissionMetadata(k)
          if e then
            ui.icon(e.icon, 12)
            ui.sameLine(0, 6)
            ui.offsetCursorY(-2)
            ui.text(e.title)
            ui.offsetCursorY(4)
          end
        end
      end
    end
    if anyProhibited then
      if anyAllowed then
        ui.offsetCursorY(8)
      end
      ui.header('Denied')
      ui.offsetCursorY(4)
      for k, v in pairs(permissions) do
        if not v then
          local e = getPermissionMetadata(k)
          if e then
            ui.icon(e.icon, 12)
            ui.sameLine(0, 6)
            ui.offsetCursorY(-2)
            ui.text(e.title)
            ui.offsetCursorY(4)
          end
        end
      end
    elseif not anyAllowed then
      ui.text('No entries.')
    end
    ui.newLine()
    ui.offsetCursorY(4)
    if ui.modernButton('Close', vec2(ui.availableSpaceX() / 2 - 4, 40), 0, ui.Icons.Back) or ui.keyPressed(ui.Key.Enter) then
      return true
    end
    ui.sameLine(0, 8)
    if ui.modernButton('Reset', vec2(-0.1, 40), ui.ButtonFlags.Cancel, ui.Icons.Reset) then
      resetPermissions(url)
      return true
    end
    return false
  end, true)
end

local function isPopupOpened()
  return opened ~= nil
end

return {
  isPopupOpened = isPopupOpened,
  showPermissionPopup = showPermissionPopup,
  getPermissionsForDomain = getPermissionsForDomain,
  setPermissionsForDomain = setPermissionsForDomain,
  managePermissions = managePermissions,
}
