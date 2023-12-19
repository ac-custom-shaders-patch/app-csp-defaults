local App = require('src/App')
local ControlsBasic = require('src/ControlsBasic')
local ControlsAdvanced = require('src/ControlsAdvanced')
local SearchProvider = require('src/SearchProvider')
local Themes = require('src/Themes')
local Storage = require('src/Storage')
local Utils = require('src/Utils')
local ControlsInputFeatures = require('src/ControlsInputFeatures')

local timePeriods = {
  {'Last hour', 60 * 60},
  {'Last 24 hours', 24 * 60 * 60},
  {'Last 7 days', 7 * 24 * 60 * 60},
  {'Last 4 weeks', 4 * 7 * 24 * 60 * 60},
  {'All time', math.huge},
}

local function smallHeader(text)
  ui.pushFont(ui.Font.Small)
  ui.text(text)
  ui.popFont()
  ui.offsetCursorY(8)
end

local lastClearCfg

local function clearBrowsingDataDialog()
  local cfg = lastClearCfg or {history = false, cookies = false, passwords = false, cache = true, time = 1}
  ui.modalDialog('Clear browsing data', function ()
    smallHeader('Time range')
    for i, v in ipairs(timePeriods) do
      if ui.radioButton(v[1], i == cfg.time) then
        cfg.time = i
      end
    end

    ui.offsetCursorY(20)
    smallHeader('Data to clear')
    if ui.checkbox('Browsing history', cfg.history) then cfg.history = not cfg.history end
    if ui.checkbox('Cookies', cfg.cookies) then cfg.cookies = not cfg.cookies end
    if ui.checkbox('Cached images and files', cfg.cache) then cfg.cache = not cfg.cache end
    if ui.checkbox('Passwords', cfg.passwords) then cfg.passwords = not cfg.passwords end
    ui.newLine()
    ui.offsetCursorY(4)
    if ui.modernButton('Clear data', vec2(ui.availableSpaceX() / 2 - 4, 40), ui.ButtonFlags.Confirm, ui.Icons.Sweeping) then
      lastClearCfg = cfg
      if cfg.cache then
        App.selectedTab():clearCache()
      end
      local time = timePeriods[cfg.time][2]
      if cfg.cookies then
        if time == math.huge then
          App.selectedTab():clearCookies()
        else
          App.selectedTab():deleteRecentCookies(time)
        end
      end

      local threshold = os.time() - time
      if cfg.history then
        for i = #App.storedHistory, 1, -1 do
          local e = App.storedHistory:at(i)
          if e.time > threshold then
            App.storedHistory:remove(e)
          else
            break
          end
        end
        for i = #App.closedTabs, 1, -1 do
          local e = App.closedTabs:at(i)
          if e.closedTime > threshold then
            App.dumpClosedTab(e)
          else
            break
          end
        end
      end
      if cfg.passwords then
        App.passwords:removeAged(threshold, true)
        App.iterateAllTabs(function (t, _, h) t.attributes.passwordToSave = nil end)
      end
      return true
    end
    ui.sameLine(0, 8)
    return ui.modernButton('Cancel', vec2(-0.1, 40), ui.ButtonFlags.Cancel, ui.Icons.Cancel)
  end, true)
end

local function subPrivacy()
  if ui.checkbox('Offer to save passwords', Storage.settings.savePasswords) then
    Storage.settings.savePasswords = not Storage.settings.savePasswords
    App.iterateAllTabs(function (t, _, h) t.attributes.passwordToSave = nil end)
  end
  if ui.checkbox('Send a “Do Not Track” request with your browsing traffic', Storage.settings.doNotTrack) then
    Storage.settings.doNotTrack = not Storage.settings.doNotTrack
    App.iterateAllTabs(function (t, _, h) t:setHeaders(h) end, Storage.settings.doNotTrack and Utils.doNotTrackHeaders)
  end
  ui.offsetCursorY(8)
  if ui.button('Clear browsing data', vec2(-0.1, 28)) then
    clearBrowsingDataDialog()
  end
end

local mightNeedRestart = false
local function subVisual()
  smallHeader('Theme')

  ui.pushStyleVar(ui.StyleVar.ItemSpacing, 12)
  for _, v in ipairs(Themes.themes) do
    if v == Themes.selected() then ui.setNextTextBold() end
    local customActive = v.id == 'custom' and v == Themes.selected()
    if ControlsBasic.menuItem('\t\t'..(customActive and 'Custom' or v.name)) then Themes.set(v.id) end
    local c = ui.itemRectMin()
    c.x, c.y = c.x + 28, c.y + 4
    if ui.itemHovered() or Storage.settings.newTabStyle == v.id then
      ui.drawCircle(c + 9, 10, ui.itemHovered() and rgbm.colors.white or rgbm.new(0.7, 1), 20, 2)
    end
    if customActive then
      ui.beginBlurring()
      ui.drawImageRounded(Storage.settings.newTabStyle, c, c + 18, 20)
      ui.endBlurring(0.2)
    else
      ui.beginGradientShade()
      ui.drawCircleFilled(c + 9, 9, rgbm.colors.white, 20)
      ui.endGradientShade(c, c + 18, v.icon[1], v.icon[2], false)
      if v.id == 'custom' then
        ui.drawIcon(ui.Icons.Plus, c + 3, c + 16)
      end
    end
  end
  ui.popStyleVar()

  if Themes.selected().id == 'custom' then
    ui.backupCursor()
    ui.sameLine(140)
    ui.setItemAllowOverlap()
    ui.setNextItemWidth(ui.availableSpaceX())
    ui.offsetCursorY(-4)
    Storage.settings.customThemeBlurring = ui.slider('##blur', Storage.settings.customThemeBlurring * 1e3, 0, 100, '%.0f%%') / 1e3
    ui.restoreCursor()
  end
  
  ui.offsetCursorY(20)
  smallHeader('Content style')

  local cur = Storage.settings.contentStyle
  if cur == 2 then ui.setNextTextBold() end
  if ui.radioButton('Apply dark mode', cur == 2) then Storage.settings.contentStyle = 2 end
  if ui.itemHovered() then ui.setTooltip('Dark mode is an experimental option that tries to automatically reskin webpages to look dark') end
  if cur == 1 then ui.setNextTextBold() end
  if ui.radioButton('Ask for dark color scheme', cur == 1) then Storage.settings.contentStyle = 1 end
  if ui.itemHovered() then ui.setTooltip('Some websites can automatically use darker style with this option') end
  if cur == 0 then ui.setNextTextBold() end
  if ui.radioButton('Use basic look', cur == 0) then Storage.settings.contentStyle = 0 end

  if cur ~= Storage.settings.contentStyle then
    mightNeedRestart = true
    table.forEach(App.tabs, function (t) ---@param t WebBrowser
      t:setColorScheme(Storage.settings.contentStyle == 2 and 'dark-auto' or Storage.settings.contentStyle == 1 and 'dark' or 'light')
        :setBackgroundColor(Storage.settings.contentStyle ~= 0 and rgbm.colors.black or rgbm.colors.white)
    end)
  end

  if mightNeedRestart then
    ui.sameLine(0, 0)
    ui.offsetCursorX(ui.availableSpaceX() - 100)
    ui.setNextItemIcon(ui.Icons.Wrench)
    if ui.button('Restart##s', vec2(-0.1, 0)) then
      mightNeedRestart = false
      WebBrowser.restartProcess()
    end
    if ui.itemHovered() then
      ui.setTooltip('Some websites might need a restart to apply the new theme in full')
    end
  end
  
  -- ui.offsetCursorY(20)
  -- smallHeader('Default page zoom')
  -- ui.setNextItemWidth(-0.1)
  -- local newZoom = ui.slider('##zoom', math.pow(1.2, Storage.settings.defaultZoom) * 100, 25, 500, '%.0f%%', 2)
  -- if ui.itemEdited() then
  --   Storage.settings.defaultZoom = math.log(newZoom / 100, 1.2)
  --   ac.log(Storage.settings.defaultZoom)
  --   if math.abs(Storage.settings.defaultZoom) < 0.01 then Storage.settings.defaultZoom = 0 end
  -- end

  ui.offsetCursorY(20)
  smallHeader('Components')
  if ui.checkbox('Integrated tabs', Storage.settings.integratedTabs) then
    Storage.settings.integratedTabs = not Storage.settings.integratedTabs
  end
  if ui.itemHovered() then
    ui.setTooltip('Actual URL for home page can be configured in “Browser” section')
  end  
  if ui.checkbox('Show home button', Storage.settings.homeButton) then
    Storage.settings.homeButton = not Storage.settings.homeButton
  end
  if ui.itemHovered() then
    ui.setTooltip('Actual URL for home page can be configured in “Browser” section')
  end
  if #App.storedBookmarks > 0 then
    if ui.checkbox('Show bookmarks bar', Storage.settings.bookmarksBar) then
      Storage.settings.bookmarksBar = not Storage.settings.bookmarksBar
    end
    if ui.itemHovered() then
      ui.setTooltip('Press Ctrl+Shift+B to toggle the bookmarks bar outside of settings')
    end
  end
  if ui.onExclusiveHUD ~= nil then
    if ui.checkbox('Exclusive fullscreen', Storage.settings.properFullscreen) then
      Storage.settings.properFullscreen = not Storage.settings.properFullscreen
    end
    if ui.itemHovered() then
      ui.setTooltip('Display page fullscreen over everything else in fullscreen mode')
    end
  end
end

local startupOptions = {
  'Open the New Tab page',
  'Open the home page',
  'Continue where you left off',
}

local function subBrowser()
  smallHeader('Search engine')
  ui.pushStyleVar(ui.StyleVar.ItemSpacing, 12)
  for _, v in ipairs(SearchProvider.list) do
    if v.id == Storage.settings.searchProviderID then ui.setNextTextBold() end
    if ControlsBasic.menuItem('\t   '..v.name) then Storage.settings.searchProviderID = v.id end

    local c = ui.itemRectMin()
    c.x, c.y = c.x + 28, c.y + 4
    if ui.itemHovered() or Storage.settings.newTabStyle == v.id then
      ui.drawCircle(c + 9, 10, ui.itemHovered() and rgbm.colors.white or rgbm.new(0.7, 1), 20, 2)
    end
    ui.drawImage(v.icon, c, c + 18)
  end
  ui.popStyleVar()

  ui.offsetCursorY(20)
  smallHeader('On startup')
  for i, v in ipairs(startupOptions) do
    if i == Storage.settings.startupMode then ui.setNextTextBold() end
    if ui.radioButton(v, i == Storage.settings.startupMode) then Storage.settings.startupMode = i end
  end


  ui.offsetCursorY(20)
  ui.alignTextToFramePadding()
  ui.text('Home page:')
  ui.sameLine(120)
  ui.setNextItemWidth(ui.availableSpaceX())
  Storage.settings.homePage = ui.inputText('URL', Storage.settings.homePage, ui.InputTextFlags.Placeholder)
  ControlsInputFeatures.inputContextMenu()
  if ui.checkbox('Show home button', Storage.settings.homeButton) then
    Storage.settings.homeButton = not Storage.settings.homeButton
  end
end

local function subDownloads()
  local downloadDirectory = Storage.settings.lastDownloadDirectory
  if downloadDirectory == '' then
    downloadDirectory = Utils.Paths.downloads()
  end

  if ui.checkbox('Ask where to save each file before downloading', Storage.settings.askForDownloadsDestination) then
    Storage.settings.askForDownloadsDestination = not Storage.settings.askForDownloadsDestination
  end
  if ui.checkbox('Show downloads when they’re done', Storage.settings.showDownloadsWhenReady) then
    Storage.settings.showDownloadsWhenReady = not Storage.settings.showDownloadsWhenReady
  end

  ui.offsetCursorY(20)
  smallHeader('Location')
  ui.alignTextToFramePadding()
  -- ui.sameLine(120)
  ui.setNextItemWidth(ui.availableSpaceX() - 80)
  Storage.settings.lastDownloadDirectory = ui.inputText('Folder for downloads', downloadDirectory, ui.InputTextFlags.Placeholder)
  ControlsInputFeatures.inputContextMenu()
  ui.sameLine(0, 4)
  if ui.button('Change', vec2(-0.1, 0)) then
    os.openFileDialog({
      folder = downloadDirectory,
      defaultFolder = Utils.Paths.downloads(),
      addAllFilesFileType = true,
      flags = bit.bor(os.DialogFlags.PathMustExist, os.DialogFlags.PickFolders)
    }, function (err, filename)
      if not err and filename then
        Storage.settings.lastDownloadDirectory = filename
      end
    end)
  end
end

local dockOptions = {'Open in separate window', 'Dock: left', 'Dock: bottom', 'Dock: right'}
local fpsNeedsRestart = false

local function subSystem()
  smallHeader('Integration')
  if ui.checkbox('FMOD audio', Storage.settings.fmodAudio) then
    Storage.settings.fmodAudio = not Storage.settings.fmodAudio
    for _, v in ipairs(App.tabs) do
      v:settings().redirectAudio = Storage.settings.fmodAudio
      v:restart()
    end
  end
  if ui.itemHovered() then
    ui.setTooltip('Use AC audio engine to play any sounds for more seamless integration')
  end
  if ui.checkbox('Open URLs in browser', Storage.settings.interceptURLs) then
    Storage.settings.interceptURLs = not Storage.settings.interceptURLs
  end
  if ui.itemHovered() then
    ui.setTooltip('Intercept URLs being open in system browser (for example, from server description) and instead open them here')
  end

  ui.offsetCursorY(20)
  smallHeader('Optimizations')
  if ui.checkbox('Direct message loop', not Storage.settings.useCEFLoop) then
    Storage.settings.useCEFLoop = not Storage.settings.useCEFLoop
    WebBrowser.configure({useCEFLoop = Storage.settings.useCEFLoop})
  end
  if ui.itemHovered() then
    ui.setTooltip('Direct message loop can help to reduce latency and increase overall responsiveness')
  end
  if Storage.settings.useCEFLoop ~= WebBrowser.usesCEFLoop() then
    ui.sameLine(0, 0)
    ui.offsetCursorX(ui.availableSpaceX() - 100)
    ui.setNextItemIcon(ui.Icons.Wrench)
    if ui.button('Restart##loop', vec2(-0.1, 0)) then
      WebBrowser.restartProcess()
    end
    if ui.itemHovered() then
      ui.setTooltip('Backend process requires a restart to change used message loop')
    end
  end

  if WebBrowser.targetFPS then
    if Storage.settings.useCEFLoop then
      ui.pushDisabled()
    end
    ui.alignTextToFramePadding()
    ui.text('Target FPS:')
    ui.sameLine(140)
    ui.setNextItemWidth(fpsNeedsRestart and -104 or -0.1)
    local newValue = ui.slider('##fps', Storage.settings.targetFPS, 30, 144, '%.0f FPS')
    if ui.itemEdited() then
      Storage.settings.targetFPS = math.clamp(math.round(newValue), 1, 300)
      WebBrowser.configure({targetFPS = Storage.settings.targetFPS})
    end
    if not ui.itemActive() then
      fpsNeedsRestart = Storage.settings.targetFPS ~= WebBrowser.targetFPS()
    end
    if fpsNeedsRestart then
      ui.sameLine(0, 0)
      ui.offsetCursorX(ui.availableSpaceX() - 100)
      ui.setNextItemIcon(ui.Icons.Wrench)
      if ui.button('Restart##fps', vec2(-0.1, 0)) then
        WebBrowser.restartProcess()
      end
      if ui.itemHovered() then
        ui.setTooltip('Backend process requires a restart to change target FPS')
      end
    end
    if Storage.settings.useCEFLoop then
      ui.popDisabled()
    end
    ui.offsetCursorY(12)
  end

  if ui.checkbox('Skip proxy initialization', Storage.settings.skipProxyServer) then
    Storage.settings.skipProxyServer = not Storage.settings.skipProxyServer
  end
  if ui.itemHovered() then
    ui.setTooltip('Might improve loading speed by ignoring your system proxy configuration')
  end
  if ui.checkbox('Filter certain web requests', Storage.settings.filtering) then
    Storage.settings.filtering = not Storage.settings.filtering
    App.iterateAllTabs(function (t) t:blockURLs(Storage.settings.filtering and Utils.webFilter or nil) end)
  end
  if ui.itemHovered() then
    ui.setTooltip('Filtering improves performance by blocking out some unnecessary HTTP requests')
  end

  ui.offsetCursorY(20)
  smallHeader('Miscellaneous')
  if ui.checkbox('Developer tools', Storage.settings.developerTools) then
    Storage.settings.developerTools = not Storage.settings.developerTools
  end

  if Storage.settings.developerTools then
    ui.backupCursor()
    ui.sameLine(140)
    ui.setItemAllowOverlap()
    ui.setNextItemWidth(ui.availableSpaceX())
    local oldValue = Storage.settings.developerToolsDock
    ui.combo('##dock', dockOptions[oldValue], function ()
      App.pauseEvents()
      Utils.noteActivePopup()
      for i, v in ipairs(dockOptions) do
        if ControlsBasic.menuItem(v) then
          Storage.settings.developerToolsDock = i
        end
      end
    end)
    if oldValue ~= 1 and Storage.settings.developerToolsDock == 1 then
      for _, tab in ipairs(App.tabs) do
        if tab.attributes.devTools then
          Utils.openDevTools(tab, 'reuse')
        end
      end
    end
    
    ui.restoreCursor()
  end

  if ui.checkbox('Safe mode', Storage.settings.safeMode) then
    Storage.settings.safeMode = not Storage.settings.safeMode
    for _, v in ipairs(App.tabs) do
      v:settings().directRender = not Storage.settings.safeMode
      v:restart()
    end
  end
  if ui.itemHovered() then
    ui.setTooltip('Slower and worse, but might help with compatibility issues on older systems')
  end

  if ui.checkbox('Continue running when app is closed', Storage.settings.keepRunning) then
    Storage.settings.keepRunning = not Storage.settings.keepRunning
  end
  if ui.itemHovered() then
    ui.setTooltip('Required for web apps or for things like listering music in background')
  end
end

local categories = {
  {ui.Icons.TopHat, 'Privacy', subPrivacy},
  {ui.Icons.Palette, 'Visual', subVisual},
  {ui.Icons.Search, 'Browser', subBrowser},
  {ui.Icons.Download, 'Downloads', subDownloads},
  {ui.Icons.Wrench, 'System', subSystem},
}

local map = table.map(categories, function (item) return item[3], 'about:settings/'..item[2]:lower() end)

---@param tab WebBrowser
---@param icon ui.Icons
---@param id string
---@param size vec2
local function subCategory(tab, icon, id, size)
  local selected = tab:url() == 'about:settings/'..id:lower()
  if not selected then ui.pushStyleColor(ui.StyleColor.Button, rgbm(0, 0, 0, 0.4)) end
  ui.setNextItemIcon(icon)
  if ui.button(id, size) then ControlsBasic.nativeHyperlinkNavigate('about:settings/'..id:lower()) end
  ControlsBasic.nativeHyperlinkBehaviour('about:settings/'..id:lower())
  if not selected then ui.popStyleColor() end
end

---@param tab WebBrowser
local function subCategories(tab)
  ui.pushFont(ui.Font.Small)
  ui.offsetCursorX(-20)
  local size = vec2((ui.availableSpaceX() + 20) / #categories, 40)
  for i, v in ipairs(categories) do
    if i > 1 then ui.sameLine(0, 0) end
    subCategory(tab, v[1], v[2], size)
  end
  ui.popFont()
end

---@param p1 vec2
---@param p2 vec2
---@param tab WebBrowser
local function drawSettingsTab(p1, p2, tab)
  Themes.drawThemedBg(p1, p2, 0.5)
  Themes.beginColumnGroup(p1, p2, 400)  
  ui.pushStyleColor(ui.StyleColor.FrameBg, rgbm(0, 0, 0, 0.4))
  ui.pushClipRect(ui.getCursor() - vec2(20, 1e6), ui.getCursor() + ui.availableSpace() + vec2(20, 1e6))

  subCategories(tab)
  ui.offsetCursorY(-4)

  ui.offsetCursorX(-20)
  ui.childWindow('#scroll', ui.availableSpace() + vec2(20, 0), false, bit.bor(ui.WindowFlags.NoScrollbar, ui.WindowFlags.NoBackground), function ()
    ui.offsetCursorY(20)
    ui.offsetCursorX(20)
    ui.beginGroup(ui.availableSpaceX() - 20)
    local fn = map[tab:url()] or categories[1][3]
    fn(tab)
    ui.endGroup()
    ui.offsetCursorY(20)
    ui.thinScrollbarBegin(true)    
    ui.thinScrollbarEnd()
  end)

  ui.popClipRect()
  ui.popStyleColor()
  ui.endGroup()
end

return {
  drawSettingsTab = drawSettingsTab
}