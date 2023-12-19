local Themes = require('src/Themes')
local db = require('src/DbBackedStorage')
local App = require('src/App')
local Controls = require('src/Controls')
local Storage = require('src/Storage')
local Utils = require('src/Utils')

---@param tab WebBrowser
local function javaScriptDialogPart(tab)
  ui.newLine()
  ui.pushFont(ui.Font.Small)
  if ui.checkbox('Prevent this tab from showing more dialogs', tab.attributes.preventDialogs) then
    tab.attributes.preventDialogs = not tab.attributes.preventDialogs
  end
  ui.popFont()
  ui.offsetCursorY(4)
end

---@type WebBrowser.Handler.JavaScriptDialog
local function onJavaScriptDialog(tab, data, callback)
  if tab.attributes.preventDialogs or tab.attributes.windowTab then
    callback(false, '')
    return
  end
  if tab ~= App.selectedTab() then
    -- do not trigger messages for tabs outside of user focus until focused back
    table.insert(tab.attributes.selectedQueue, function ()
      onJavaScriptDialog(tab, data, callback)
    end)
    return
  end
  if data.type == 'alert' then -- two other ones are ignored at the moment (also, there is no API to reply to a prompt yet)
    ui.modalDialog(tab:domain()..' says', function ()
      ui.textWrapped(data.message)
      javaScriptDialogPart(tab)
      return ui.modernButton('OK', vec2(-0.1, 40), ui.ButtonFlags.None, ui.Icons.Confirm)
    end, true, function () callback(true, nil) end)
  elseif data.type == 'confirm' then
    ui.modalDialog(tab:domain()..' says', function ()
      ui.textWrapped(data.message)
      javaScriptDialogPart(tab)
      local r = ui.modernButton('Confirm', vec2(ui.availableSpaceX() / 2 - 4, 40), ui.ButtonFlags.Confirm, ui.Icons.Confirm)
      if r then callback(true, nil) end
      ui.sameLine(0, 8)
      return ui.modernButton('Cancel', vec2(-0.1, 40), ui.ButtonFlags.Cancel, ui.Icons.Cancel) or r
    end, true, function () callback(false, nil) end)
  elseif data.type == 'prompt' then
    ui.modalPrompt(tab:domain()..' asks', data.message, data.defaultPrompt, function (value)
      callback(value ~= nil, value)
    end)
  elseif data.type == 'beforeUnload' then
    ui.modalDialog('Leave site?', function ()
      ui.textWrapped('Changes you made may not be saved.')
      javaScriptDialogPart(tab)
      local r = ui.modernButton('Leave', vec2(ui.availableSpaceX() / 2 - 4, 40), ui.ButtonFlags.Confirm, ui.Icons.Confirm)
      if r then callback(true, nil) end
      ui.sameLine(0, 8)
      return ui.modernButton('Cancel', vec2(-0.1, 40), ui.ButtonFlags.Cancel, ui.Icons.Cancel) or r
    end, false, function () callback(false, nil) end)
  else
    callback(false, '')
  end  
end

---@type WebBrowser.Handler.ContextMenu
local function onContextMenu(tab, data)
  if Utils.anyActivePopup() then return end
  tab.attributes.contextMenuMousePosition = tab:mousePosition()

  -- Context menu, could be for a link, a resource, a editable text
  Utils.popup(function ()
    Utils.noteActivePopup()
    ---@param label string
    ---@param hotkey string?
    ---@param flags integer?
    ---@return boolean
    local function item(label, hotkey, flags)
      if Controls.menuItem(label, hotkey, flags) then
        App.focusNext = 'browser'
        return true
      end
      return false
    end
    if data.linkURL then
      if item('Open URL') then tab:navigate(data.linkURL) end
      if not tab.attributes.windowTab then
        if not App.canOpenMoreTabs() then ui.pushDisabled() end
        if item('Open in new tab') then App.addAndSelectTab(data.linkURL, nil, nil, tab) end
        if item('Open in background') then App.addTab(data.linkURL, nil, nil, tab) end
        if not App.canOpenMoreTabs() then ui.popDisabled() end
      else
        if item('Open in browser app') then
          ac.setWindowOpen('main', true)
          App.addAndSelectTab(data.linkURL, nil, nil, tab)
        end
      end
      if WebBrowser.knownProtocol(data.linkURL) then
        if item('Open in system browser') then Utils.openURLInSystemBrowser(data.linkURL) end
      end
      ui.separator()
      if item('Copy URL') then ac.setClipboadText(data.unfilteredLinkURL or data.linkURL or '?') end
      if item(Storage.settings.askForDownloadsDestination and 'Save link as…' or 'Download link') then tab:download(data.unfilteredLinkURL or data.linkURL) end
    end
    if data.sourceURL then
      if ui.getCursorY() > 8 then ui.separator() end
      if not tab.attributes.windowTab then
        if not App.canOpenMoreTabs() then ui.pushDisabled() end
        if item('Open image in new tab') then App.addAndSelectTab(data.sourceURL, nil, nil, tab) end
        if item('Open image in background') then App.addTab(data.sourceURL, nil, nil, tab) end
        if not App.canOpenMoreTabs() then ui.popDisabled() end
      end
      if WebBrowser.knownProtocol(data.sourceURL) then
        if item('Open image in system browser') then Utils.openURLInSystemBrowser(data.sourceURL) end
      end
      if item('Copy image URL') then ac.setClipboadText(data.sourceURL) end
      if item(Storage.settings.askForDownloadsDestination and 'Save image as…' or 'Download image') then tab:download(data.sourceURL) end
      if item('Set theme background') then Themes.setBackgroundImage(tab, data.sourceURL) end
    end
    if data.selectedText then
      if ui.getCursorY() > 8 then ui.separator() end
      if not data.editable and item('Copy text', 'Ctrl+C') then ac.setClipboadText(data.selectedText) end

      local l, u = Utils.searchSelectedHelper(data.selectedText)
      if item(l) then App.addAndSelectTab(u, nil, nil, tab) end
    end
    if data.editable then
      if ui.getCursorY() > 8 then ui.separator() end
      if data.selectedText and item('Copy', 'Ctrl+C') then tab:command('copy') end
      if data.selectedText and item('Cut', 'Ctrl+X') then tab:command('cut') end
      if item('Paste', 'Ctrl+V') then tab:command('paste') end
      if item('Select all', 'Ctrl+A') then tab:command('selectAll') end
      if data.selectedText and item('Delete', 'Delete') then tab:command('delete') end
    end
    if not data.linkURL and not data.selectedText and not data.editable then
      if ui.getCursorY() > 8 then ui.separator() end
      if item('Back', 'Alt+←', tab:canGoBack() and 0 or ui.SelectableFlags.Disabled) then tab:navigate('back') end
      if item('Forward', 'Alt+→', tab:canGoForward() and 0 or ui.SelectableFlags.Disabled) then tab:navigate('forward') end
      if not tab:blank() then
        if item('Reload', 'Ctrl+R') then tab:reload() end
        if not tab.attributes.windowTab then
          ui.separator()
          if item('Save as…', 'Ctrl+S') then Utils.saveWebpage(tab) end
          if item('Print…', 'Ctrl+P') then tab:command('print') end
        end
      else
        if tab:blank() and tab:url() == '' and not tab.attributes.anonymous then
          ui.separator()
          ui.pushFont(ui.Font.Small)
          ui.text('Style:')
          ui.popFont()
          for _, v in ipairs(Themes.themes) do
            local c = ui.getCursor()
            if ui.invisibleButton(v.id, 22) then
              Themes.set(v.id)
            end
            local customActive = v.id == 'custom' and v == Themes.selected()
            if ui.itemHovered() or Storage.settings.newTabStyle == v.id or customActive then
              ui.drawCircle(c + 11, 12, ui.itemHovered() and rgbm.colors.white or rgbm.new(0.7, 1), 20, 2)
            end
            if customActive then
              ui.beginBlurring()
              ui.drawImageRounded(Storage.settings.newTabStyle, c, c + 22, 20)
              ui.endBlurring(0.2)
            else
              ui.beginGradientShade()
              ui.drawCircleFilled(c + 11, 11, rgbm.colors.white, 20)
              ui.endGradientShade(c, c + 22, v.icon[1], v.icon[2], false)
              if v.id == 'custom' then
                ui.drawIcon(ui.Icons.Plus, c + 4, c + 18)
              end
            end
            if ui.itemHovered() then ui.setTooltip(customActive and 'Custom' or v.name) end
            ui.sameLine()
          end
          ui.newLine()
        end
      end      
      if tab:url() ~= '' and not tab.attributes.windowTab and not tab:blank() then
        ui.separator()
        if WebBrowser.knownProtocol(tab:url()) then
          if item('Open this page in system browser') then Utils.openURLInSystemBrowser(tab:url()) end
        end
        if item('Copy this webpage URL') then ac.setClipboadText(tab:url()) end
        if Storage.settings.developerTools then
          if ui.getCursorY() > 8 then ui.separator() end
          if not App.canOpenMoreTabs() then ui.pushDisabled() end
          if item('View source', 'Ctrl+U') then App.addAndSelectTab(WebBrowser.sourceURL(tab:url()), nil, nil, tab) end
          if not App.canOpenMoreTabs() then ui.popDisabled() end
          if item('Inspect', 'F12') then Utils.openDevTools(tab, false) end
        else
          if not App.canOpenMoreTabs() then ui.pushDisabled() end
          if item('View source', 'Ctrl+U') then App.addAndSelectTab(WebBrowser.sourceURL(tab:url()), nil, nil, tab) end
          if not App.canOpenMoreTabs() then ui.popDisabled() end
        end
      end 
    elseif Storage.settings.developerTools then
      ui.separator()
      if item('Inspect', 'F12') then Utils.openDevTools(tab, false) end
    end
  end, { onClose = function ()
    setTimeout(function ()
      tab.attributes.contextMenuMousePosition = nil
    end, 1)
  end })
end

---@type WebBrowser.Handler.Download
local function onDownload(tab, data, callback)
  if tab.attributes.awaitDownload and tab.attributes.awaitDownload.url == data.originalURL 
      and (os.preciseClock() - tab.attributes.awaitDownload.time) < 3 then
    callback(tab.attributes.awaitDownload.destination)
    if tab.attributes.awaitDownload.closeOnceTriggered then
      App.closeTab(tab)
    end
    return
  end

  if tab.attributes.emptySoFar then
    App.closeTab(tab)
  end

  local downloadDirectory = Storage.settings.lastDownloadDirectory
  if downloadDirectory == '' then
    downloadDirectory = Utils.Paths.downloads()
  end
  local name = data.suggestedName
  if io.exists(downloadDirectory..'/'..name) then
    local p, e = name:regmatch('^(.+?)(\\.\\w+)$')
    if not p then
      p, e = name, ''
    end
    for i = 1, 1e6 do
      local c = '%s (%d)%s' % {p, i, e}
      if not io.exists(downloadDirectory..'/'..c) then
        name = c
        break
      end
    end
  end

  if io.dirExists(downloadDirectory) and not io.exists(downloadDirectory..'/'..name) 
      and not Storage.settings.askForDownloadsDestination then
    callback(downloadDirectory..'/'..name)
    return
  end

  os.saveFileDialog({
    title = 'Download',
    defaultFolder = downloadDirectory,
    folder = downloadDirectory,
    fileName = name,
    places = { Utils.Paths.downloads() },
    addAllFilesFileType = true,
    fileTypes = {{name = 'Files', mask = '*'..data.suggestedName:regmatch('\\.\\w+$')}},
    fileTypeIndex = 1,
    defaultExtension = data.suggestedName:regmatch('\\.(\\w+)$')
  }, function (err, filename)
    if not err and filename and not tab.attributes.anonymous then
      Storage.settings.lastDownloadDirectory = io.getParentPath(filename)
    end
    callback(not err and filename or nil)
  end)
end

---@type WebBrowser.Handler.DownloadStarted
local function onDownloadStarted(tab, item)
  item.attributes.browser = tab
  item.attributes.startedTime = os.time()
  table.insert(App.recentDownloads, item)
  table.insert(App.activeDownloads, item)
  App.storedDownloads:add(item)
  Controls.showDownloadsMenu(false)
end

---@type WebBrowser.Handler.DownloadFinished
local function onDownloadFinished(tab, data)
  App.ensureAliveTabsAreWorthy()
  data.attributes.finishedTime = os.time()
  table.removeItem(App.activeDownloads, data)
  if Storage.settings.showDownloadsWhenReady then
    Controls.showDownloadsMenu(false)
  end
  if tab.attributes.finishedTime then
    setTimeout(function ()
      if not next(tab:downloads()) then
        tab:dispose()
      end
    end)
  end
end

local credentialsStorage

---@return DbDictionaryStorage<{username: string, password: string}>
local function getCredentialsStorage()
  if not credentialsStorage then credentialsStorage = db.Dictionary('credentials') end
  return credentialsStorage
end

local lastRequestDomain, lastRequestTime = nil, -5

---@type WebBrowser.Handler.AuthCredentials
local function onAuthCredentials(tab, data, callback)
  local key = tab:domain()
  local values = getCredentialsStorage():get(key) or {username = '', password = ''}
  local save = values.username ~= '' or values.password ~= ''
  if save and (key ~= lastRequestDomain or os.preciseClock() > lastRequestTime + 5) then
    lastRequestDomain, lastRequestTime = key, os.preciseClock()
    callback(values.username, values.password)
    return
  end
  ui.modalDialog('Sign in', function ()
    values.username = ui.inputText('Username', values.username, ui.InputTextFlags.Placeholder)
    values.password = ui.inputText('Password', values.password, bit.bor(ui.InputTextFlags.Placeholder, ui.InputTextFlags.Password))
    if Storage.settings.savePasswords and ui.checkbox('Save credentials', save) then
      save = not save
    end
    ui.newLine()
    ui.offsetCursorY(4)
    if ui.modernButton('OK', vec2(ui.availableSpaceX() / 2 - 4, 40), ui.ButtonFlags.Confirm, ui.Icons.Confirm) or ui.keyPressed(ui.Key.Enter) then
      if save then
        getCredentialsStorage():set(key, values)
      else
        getCredentialsStorage():remove(key)
      end
      callback(values.username, values.password)
      return true
    end
    ui.sameLine(0, 8)
    return ui.modernButton('Cancel', vec2(-0.1, 40), ui.ButtonFlags.Cancel, ui.Icons.Cancel)
  end, true, function ()
    callback(nil, nil)
  end)
end

local function onFormResubmission(tab, callback)
  ui.modalPopup('Confirm form resubmission', 'The page that you’re looking for used information that you entered. Returning to that page might cause any action you took to be repeated. Do you want to continue?', 'Resubmit', 'Cancel', ui.Icons.RestartWarning, ui.Icons.Cancel, function (okPressed)
    if okPressed then
      callback()
    end
  end)
end

local function onPreventedNavigation(tab, u)
  local website = WebBrowser.getDomainName(u.originURL)
  local name = u.targetURL:startsWith('acmanager') and 'Content Manager'  
    or u.targetURL:startsWith('ts') and 'TeamSpeak'
    or u.targetURL:startsWith('mumble') and 'Mumble' 
    or 'application'
  local key = website..'/'..name
  local loaded = App.openAppDoNotAskAgain:get(key)
  if loaded then
    if loaded.allow then 
      Utils.openURLInSystemBrowser(u.targetURL)
    end
    return
  end
  local doNotAskAgain = false
  ui.modalDialog('Open %s?' % name, function ()
    ui.setNextTextSpanStyle(1, #website, nil, true)
    ui.text('%s wants to open this application.' % website)
    ui.newLine()
    ui.pushFont(ui.Font.Small)
    if ui.checkbox('Don’t ask again for this website', doNotAskAgain) then
      doNotAskAgain = not doNotAskAgain
    end
    ui.popFont()
    ui.offsetCursorY(4)
    local r = ui.modernButton('Open', vec2(ui.availableSpaceX() / 2 - 4, 40), ui.ButtonFlags.Confirm, ui.Icons.Confirm)
    if r then
      if doNotAskAgain then App.openAppDoNotAskAgain:set(key, {allow = true}) end
      Utils.openURLInSystemBrowser(u.targetURL)
    end
    ui.sameLine(0, 8)
    if ui.modernButton('Cancel', vec2(-0.1, 40), ui.ButtonFlags.Cancel, ui.Icons.Cancel) then
      if doNotAskAgain then App.openAppDoNotAskAgain:set(key, {allow = false}) end
      r = true
    end
    return r
  end)
end

return {
  onJavaScriptDialog = onJavaScriptDialog,
  onContextMenu = onContextMenu,
  onDownload = onDownload,
  onDownloadStarted = onDownloadStarted,
  onDownloadFinished = onDownloadFinished,
  onAuthCredentials = onAuthCredentials,
  onFormResubmission = onFormResubmission,
  onPreventedNavigation = onPreventedNavigation,
}
