local App = require('src/App')
local ControlsBasic = require('src/ControlsBasic')
local Utils = require('src/Utils')
local Controls = require('src/Controls')
local Storage = require('src/Storage')
local ControlsInputFeatures = require('src/ControlsInputFeatures')

---@param tab WebBrowser
local function formProcessReset(tab)
  tab.attributes.anythingTyped = false
end

---@param url string?
local function cleanURLBase(url)
  return url and url:lower():match('^https?://[^#?]+') ---@type string?
end

---@param url string?
local function cleanURL(url)
  local cleanedURL = cleanURLBase(url)
  return cleanedURL and WebBrowser.getDomainName(cleanedURL):lower()
end

---@param tab WebBrowser
---@param password string
---@param shownRef {[1]: boolean}
---@return string, boolean
local function inputPassword(tab, password, shownRef)  
  ui.pushStyleColor(ui.StyleColor.FrameBg, rgbm(0, 0, 0, 0.4))
  ui.setNextItemWidth(-0.1)
  if ui.isWindowAppearing() then ui.setKeyboardFocusHere() end
  local _, enterPressed
  password, _, enterPressed = ui.inputText('##pw', password, shownRef[1] and 0 or ui.InputTextFlags.Password)
  if shownRef[1] then
    ControlsInputFeatures.inputContextMenu(tab)
  end
  ui.popStyleColor()
  ui.offsetCursorY(8)

  ui.backupCursor()
  ui.setCursor(ui.itemRectMax() - 22)
  ui.setItemAllowOverlap()
  ui.pushStyleColor(ui.StyleColor.Button, rgbm.colors.transparent)
  if ui.iconButton(shownRef[1] and ui.Icons.Hide or ui.Icons.Eye, 22, 5) then
    shownRef[1] = not shownRef[1]
    ui.setKeyboardFocusHere(-2)
  end
  if ui.itemHovered() then ui.setMouseCursor(ui.MouseCursor.Arrow) end
  ui.popStyleColor()
  ui.restoreCursor()
  return password, enterPressed
end

---@param tab WebBrowser
local function formProcessFill(tab)
  local url = cleanURL(tab:url())
  if not url then return end

  local entry = App.passwords:get(url)
  if entry and entry.originURL ~= '' then
    tab:fillForm(entry.actionURL, entry.data)

    if cleanURLBase(entry.originURL) == cleanURLBase(tab:url()) and (not tab.attributes.savingPassword or not tab.attributes.passwordToSave) then
      tab.attributes.timeOfPasswordToSave = os.time()
      local shownRef = {false}
      local password = entry.data[entry.key]
      tab.attributes.passwordToSave = function ()
        if ui.isWindowAppearing() then shownRef[1] = false end    
        ui.pushFont(ui.Font.Title)
        ui.text('Saved password')
        ui.popFont()
        ui.offsetCursorY(8)    
        local enterPressed
        password, enterPressed = inputPassword(tab, password, shownRef)
        ui.setNextItemIcon(ui.Icons.Save)
        if ui.button('Save', vec2(80, 0)) or enterPressed then
          entry.data[entry.key] = password
          App.passwords:set(url, entry)
          return true
        end
        ui.sameLine(0, 4)
        if entry then
          ui.setNextItemIcon(ui.Icons.Trash)
          if ui.button('Remove', vec2(120, 0)) then
            local editFn = tab.attributes.passwordToSave
            App.passwords:remove(url)
            tab.attributes.passwordToSave = nil
            ui.toast(ui.Icons.Trash, 'Removed “%s”' % entry.title, function ()
              App.passwords:set(url, entry)
              tab.attributes.passwordToSave = editFn
            end)
            return false
          end
        end
        ui.offsetCursorY(8)
      end
    end
  elseif tab.attributes.passwordToSave and not tab.attributes.savingPassword then
    tab.attributes.passwordToSave = nil
  end
end

---@param oldEntry PasswordEntry
---@param newFormData WebBrowser.FormData
local function needsRefreshing(oldEntry, newFormData)
  if newFormData.actionURL ~= oldEntry.actionURL then
    return true
  end
  for k, v in pairs(newFormData.form) do
    if v.type == 'password' and oldEntry.data[k] ~= v.value then
      return true
    end
  end
  return false
end

---@param formData WebBrowser.FormData
local function needsSaving(formData)
  if table.nkeys(formData.form) > 4 then return end
  for k, v in pairs(formData.form) do
    if v.type == 'password' then return v.value, k end
  end
end

---@type WebBrowser.Handler.FormData
local function onFormData(tab, formData)
  tab.attributes.passwordToSave = nil
  if not Storage.settings.savePasswords then return end

  local url = cleanURL(formData.originURL)
  if not url then return end

  local password, passwordKey = needsSaving(formData)
  if not password or not passwordKey then return end

  local entry = App.passwords:get(url)
  if entry and (entry.originURL == '' or not needsRefreshing(entry, formData)) then return end

  tab.attributes.savingPassword = true
  local shownRef = {false}
  Controls.offerToSavePassword(tab, function ()
    if ui.isWindowAppearing() then shownRef[1] = false end

    ui.pushFont(ui.Font.Title)
    ui.text(entry and 'Edit password' or 'Save password?')
    ui.popFont()
    ui.offsetCursorY(8)
    
    local enterPressed
    password, enterPressed = inputPassword(tab, password, shownRef)

    ui.setNextItemIcon(entry and ui.Icons.Save or ui.Icons.Confirm)
    if ui.button('Save', vec2(80, 0)) or enterPressed then
      entry = {
        originURL = formData.originURL,
        actionURL = formData.actionURL,
        title = tab:title(true),
        time = os.clock(),
        key = passwordKey,
        data = table.map(formData.form, function (v, k) return v.value, k end)
      }
      entry.data[passwordKey] = password
      App.passwords:set(url, entry)
      return true
    end
    ui.sameLine(0, 4)
    if entry then
      ui.setNextItemIcon(ui.Icons.Trash)
      if ui.button('Remove', vec2(120, 0)) then
        local editFn = tab.attributes.passwordToSave
        App.passwords:remove(url)
        tab.attributes.passwordToSave = nil
        ui.toast(ui.Icons.Trash, 'Removed “%s”' % entry.title, function ()
          App.passwords:set(url, entry)
          tab.attributes.passwordToSave = editFn
        end)
        return false
      end
    else
      ui.setNextItemIcon(ui.Icons.Cancel)
      if ui.button('Do not save', vec2(120, 0)) then
        tab.attributes.passwordToSave = nil
        return false
      end
      ui.sameLine(0, 4)
      if ui.iconButton(ui.Icons.SquaresVertical, 22, 7) then
        Utils.popup(function ()
          ui.setNextTextSpanStyle(11, math.huge, nil, true)
          if ControlsBasic.menuItem(string.format('Never for %s', tab:domain())) then
            App.passwords:set(url, {originURL = ''})
            tab.attributes.passwordToSave = nil
          end
          if ControlsBasic.menuItem('Never save passwords') then
            tab.attributes.passwordToSave = nil
            Storage.settings.savePasswords = false
          end
          if ui.itemHovered() then
            ui.setTooltip('You can reenable passwords saving in privacy settings later')
          end
        end)
      end
    end
    ui.offsetCursorY(8)
  end)
end

return {
  formProcessReset = formProcessReset,
  formProcessFill = formProcessFill,
  onFormData = onFormData,
}