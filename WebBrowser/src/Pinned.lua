local App = require('src/App')
local ControlsBasic = require('src/ControlsBasic')
local FaviconsProvider = require('src/FaviconsProvider')
local db = require('src/DbBackedStorage')
local Storage = require('src/Storage')
local ControlsAdvanced = require('src/ControlsAdvanced')
local Icons = require('src/Icons')
local Themes = require('src/Themes')

local pinnedModule
local drawImpl ---@type fun(tab: WebBrowser, size: vec2)
local function saveFilter(v, k)
  if k == 'release' or k == 'tab' then return nil end
  return v, k  
end

---@alias PinnedApp {id: string, originDomain: string, url: string, title: string, darkMode: boolean?, mobileMode: boolean?, backgroundColor: rgbm?, themeColor: rgbm?, release: function?, tab: WebBrowser?, muted: boolean?, lastURL: string?, rememberURL: boolean?}
---@type DbListStorage<PinnedApp>
local apps = db.List('pinned', math.huge, {
  encode = function (i)
    local f = table.filter(i, saveFilter)
    if i.tab then f.muted = i.tab:muted() or nil end
    return f
  end,
  decode = function (v)
    return v
  end
})

---@param baseURL string
---@param relativeURL string
local function resolveURL(baseURL, relativeURL)
  if (relativeURL:find('://', nil, true) or math.huge) < 8 then return relativeURL end
  if relativeURL:sub(1, 1) == '/' then return (baseURL:match('^[^/]+//[^/]+') or '')..relativeURL end
  if not baseURL:endsWith('/') then baseURL = baseURL:match('^.+/') or baseURL end
  while relativeURL:find('^.?./') do
    if relativeURL:sub(2, 2) == '.' then
      baseURL = baseURL:match('^(.+/).') or baseURL
      relativeURL = relativeURL:sub(4)
    else
      relativeURL = relativeURL:sub(3)
    end
  end
  return baseURL..relativeURL
end

local unloadListener
local registerApp

---@param app PinnedApp
local function getIconFilename(app)
  return string.format('%s/pinned_icon_%s.png', ac.getFolder(ac.FolderID.ScriptConfig), app.id)
end

---@param app PinnedApp
---@param toast boolean
local function removeApp(app, toast)
  apps:remove(app)

  if app.release then
    app.release()
    app.release = nil
  end

  if app.tab then
    app.tab:dispose()
    app.tab = nil
  end

  if toast then
    ui.toast(ui.Icons.Trash, 'Removed “%s”' % app.title, function ()
      apps:restore(app)
      registerApp(app, false)
    end)
  end

  if unloadListener then
    unloadListener()
  end
end

local monitorInterval

---@param app PinnedApp
local function drawApp(app)
  if not app.tab then 
    local url = app.url
    if app.rememberURL and app.lastURL 
        and WebBrowser.getDomainName(app.lastURL) == WebBrowser.getDomainName(app.url) then
      url = app.lastURL
    end
    app.tab = App.createWindowTab(url, { backgroundColor = app.backgroundColor or rgbm.colors.black })
    app.tab:setColorScheme(app.darkMode and 'dark-auto' or 'dark')
    if app.mobileMode then app.tab:setMobileMode('portrait') end
    if app.muted then app.tab:mute() end
    if not monitorInterval then
      monitorInterval = setInterval(function ()
        for _, v in ipairs(apps) do
          if v.tab and v.lastURL ~= v.tab:url() then
            v.lastURL = v.tab:url()
            apps:update(v)
          end
        end
      end, 1)
    end
  end
  app.tab:resize(ui.availableSpace())
  if drawImpl then drawImpl(app.tab, ui.availableSpace()) end
  App.processZoom(app.tab)
end

---@param app PinnedApp
local function unloadApp(app)
  app.release('close')
  setTimeout(function ()
    app.tab:dispose()
    app.tab = nil
    if unloadListener then
      unloadListener()
    end
  end)  
end

---@param app PinnedApp
---@param loadState boolean
registerApp = function(app, loadState)
  if app.release then return end
  local zoomState = {0}
  ac.log(app.id, app.title, app.url, app.lastURL, app.rememberURL)
  app.release = ui.addSettings({
    id = string.format('pinned_%s', app.id),
    icon = getIconFilename(app),
    name = app.title,
    size = {
      default = vec2(800, 600),
      min = vec2(200, 120),
    },
    padding = vec2(0, 0),
    backgroundColor = app.themeColor,
    category = 'main',
    onMenu = function ()
      local tab = app.tab
      if not tab then return end

      if ControlsBasic.menuItem('Return to the starting address') then
        tab:navigate(app.url)
      end

      if ControlsBasic.menuItem(tab:muted() and 'Unmute app' or 'Mute app') then
        tab:mute(not tab:muted())
        apps:update(app)
      end
      
      ui.separator()
      ControlsBasic.zoomMenuItem(tab, zoomState)
      ui.separator()

      if ControlsBasic.menuItem('Unload app') then
        unloadApp(app)
      end
      if ui.itemHovered() then
        ui.setTooltip('Closes app and stops web browser')
      end
      if ControlsBasic.menuItem('Edit app') then
        pinnedModule.edit(app, app.tab)
      end
      if ControlsBasic.menuItem('Remove app') then
        removeApp(app, true)
      end
      ui.separator()
    end,
    onRemove = function ()
      removeApp(app, true)
    end
  }, function ()
    if app.tab and (app.tab:muted() or app.tab:playingAudio()) then
      ui.pushClipRectFullScreen()
      ui.backupCursor()
      ui.setCursor(vec2(ui.windowWidth() - (ui.windowPinned() and 44 or 66), 0))
      ui.pushStyleColor(ui.StyleColor.Button, rgbm.colors.transparent)
      local icon = app.tab:muted() and Icons.Atlas.VolumeMuted or Icons.talkingIcon(app.tab:audioPeak())
      if ui.iconButton('%s###C' % tostring(icon), 22, 5) then
        app.tab:mute(not app.tab:muted())
        apps:update(app)
      end
      if ui.itemHovered() then ui.setTooltip(app.tab:muted() and 'App is muted' or 'App is playing audio') end
      ui.popStyleColor()
      ui.popClipRect()
      ui.restoreCursor()
    end
    drawApp(app)
  end)
end

for i = 1, #apps do
  registerApp(apps:at(i), true)
end

---@param app PinnedApp
---@param icon string
local function pinTab(app, icon)
  removeApp(app, false)
  if not app.id then
    app.id = tostring(bit.tohex(math.randomKey()))
    if icon then
      ui.ExtraCanvas(64):copyFrom(icon):save(getIconFilename(app), ac.ImageFormat.PNG):dispose()
    else
      ui.ExtraCanvas(64):update(function (dt)
        ui.drawIcon(ui.Icons.Earth, 0, 64)
      end):save(getIconFilename(app), ac.ImageFormat.PNG):dispose()
    end
  end
  apps:update(app)
  registerApp(app, false)
end

---@param tab WebBrowser
---@param callback fun(data: string?)?
local function getManifestURL(tab, callback)
  tab:onReceive('pwa_manifest', function (browser, data)
    if callback then pcall(callback, data) end
    callback = nil
  end)
  tab:execute([[AC.sendAsync('pwa_manifest',(document.querySelector('link[rel="manifest"]') || {}).href)]])
  setTimeout(function ()
    if callback then pcall(callback, nil) end
    tab:onReceive('pwa_manifest', nil)
  end, 1)
end

---@param tab WebBrowser
---@param callback fun(data: table?, url: string?)
local function loadManifest(tab, callback)
  getManifestURL(tab, function (data)
    if not data then
      callback(nil)
      return
    end
    web.get(data, function (err, response)
      callback(not err and JSON.parse(response.body) or nil, data)
    end)
  end)
end

---@param manifest table
---@return string?
local function findOptimalIcon(manifest)
  if type(manifest) ~= 'table' then return end
  local m, r = math.huge, nil
  for _, v in ipairs(manifest.icons) do
    local x, y = string.numbers(tostring(v.sizes))
    if x == y and x >= 16 or x <= 512 then
      local w = math.abs(9 - math.sqrt(x))
      if w < m then
        m, r = w, v.src
      end
    end
  end
  return r
end

---@param app PinnedApp
---@param tab WebBrowser
---@param icon {[1]: string}
---@param editedCallback fun(id: 'title'|'url')?
local function appEditDialog(app, tab, icon, editedCallback)
  local backup = table.clone(app, false)
  if backup.backgroundColor then backup.backgroundColor = backup.backgroundColor:clone() end
  if backup.themeColor then backup.themeColor = backup.themeColor:clone() end
  local originalColorScheme = tab:colorScheme()
  tab:setColorScheme(app.darkMode and 'dark-auto' or 'dark')
  ui.modalDialog(editedCallback and 'Install app?' or 'Edit app', function ()
    ui.offsetCursorY(8)
    ui.image(icon[1], 32)
    if ui.itemHovered() then
      ui.tooltip(function () ControlsBasic.tabTooltip(tab) end)
    end
    ui.sameLine(0, 12)
    ui.offsetCursorY(-8)
    ui.beginGroup()
    app.title = ui.inputText('Name', app.title, ui.InputTextFlags.Placeholder)
    if editedCallback and ui.itemEdited() then editedCallback('title') end

    app.url = ui.inputText('URL', app.url, ui.InputTextFlags.Placeholder)
    if editedCallback and ui.itemEdited() then editedCallback('url') end

    if ui.checkbox('Dark theme', app.darkMode or false) then
      app.darkMode = not app.darkMode
      tab:setColorScheme(app.darkMode and 'dark-auto' or 'dark')
    end
    if ui.itemHovered() then ui.setTooltip('Dark mode is an experimental option that tries to automatically reskin webpages to look dark') end
    if ui.checkbox('Mobile mode', app.mobileMode or false) then
      app.mobileMode = not app.mobileMode
      tab:setMobileMode(app.mobileMode and 'portrait' or nil)
    end
    if ui.checkbox('Remember URL', app.rememberURL or false) then
      app.rememberURL = not app.rememberURL
    end
    if ui.itemHovered() then ui.setTooltip('Load previous URL on startup') end

    if not editedCallback then
      ui.offsetCursorY(20)
      ui.header('Colors')
      ui.pushFont(ui.Font.Small)
      ui.textAligned('Background', 0, vec2(ui.availableSpaceX() / 2, 0))
      ui.sameLine(0, 4)
      ui.textAligned('Theme', 0, vec2(-0.1, 0))
      ui.popFont()
      ui.setNextItemWidth(ui.availableSpaceX() / 2 - 2)
      ui.colorPicker('##bg', app.backgroundColor, bit.bor(ui.ColorPickerFlags.NoAlpha, ui.ColorPickerFlags.NoInputs, ui.ColorPickerFlags.NoSidePreview, ui.ColorPickerFlags.PickerHueBar))
      if ui.itemEdited() and app.tab then
        app.tab:setBackgroundColor(app.backgroundColor)
      end
      ui.sameLine(0, 4)
      ui.setNextItemWidth(-0.1)
      ui.colorPicker('##theme', app.themeColor, bit.bor(ui.ColorPickerFlags.NoAlpha, ui.ColorPickerFlags.NoInputs, ui.ColorPickerFlags.NoSidePreview, ui.ColorPickerFlags.PickerHueBar))
      if ui.itemEdited() and app.release then
        app.release('backgroundColor:%s' % app.themeColor)
      end
    end

    ui.endGroup()

    ui.newLine()
    ui.offsetCursorY(4)
    
    if ui.modernButton(editedCallback and 'Add' or 'Save', vec2(ui.availableSpaceX() / 2 - 4, 40), ui.ButtonFlags.Confirm, ui.Icons.Confirm) then
      if not editedCallback and app.tab and backup and app.title == backup.title then
        if app.tab:url() == backup.url then
          app.tab:navigate(app.url)
        end
        backup = nil
        apps:update(app)
      else
        local opened = app.release and app.release('opened')
        backup = nil
        pinTab(app, icon[1])
        if editedCallback or opened then
          app.release('open')
        end
      end
      return true
    end
    ui.sameLine(0, 8)
    if editedCallback then
      return ui.modernButton('Cancel', vec2(-0.1, 40), ui.ButtonFlags.Cancel, ui.Icons.Cancel)
    else
      if ui.modernButton('Remove', vec2(-0.1, 40), ui.ButtonFlags.Cancel, ui.Icons.Trash) then
        backup = nil
        removeApp(app, true)
        return true
      end
      return false
    end
  end, true, function ()
    if tab ~= app.tab then
      ac.log('Resetting tab modifiers')
      tab:setColorScheme(originalColorScheme)
      tab:setMobileMode(nil)
    end
    if backup then table.assign(app, backup) end
  end)
end

---@param i integer
---@param app PinnedApp
---@param filter string
local function drawAppsTabItem(i, app, filter)
  ui.pushID(i)
  if ui.invisibleButton('', vec2(-0.1, 46)) then
    app.release('toggle')
    return
  end

  ControlsBasic.nativeHyperlinkBehaviour(app.url, function ()
    ui.separator()
    if ControlsBasic.menuItem('Edit app') then
      pinnedModule.edit(app, app.tab)
    end
    if ControlsBasic.menuItem('Remove app') then
      removeApp(app, true)
    end
  end)

  ui.backupCursor()
  local r1, r2 = ui.itemRectMin(), ui.itemRectMax()
  r1.x, r2.x = r1.x + 10, r2.x - 28

  ui.drawIcon(getIconFilename(app), r1 + vec2(8, 14), r1 + vec2(24, 30))
  r1.x = r1.x + 36

  ui.drawTextClipped(ControlsBasic.textHighlightFilter(app.title, filter), r1, r2, nil, vec2(0, 0.25), true)
  ui.pushFont(ui.Font.Small)
  ui.drawTextClipped(ControlsBasic.textHighlightFilter(app.originDomain, filter), r1, r2, nil, vec2(0, 0.75), true)
  ui.popFont()

  ui.pushStyleColor(ui.StyleColor.Button, rgbm.colors.transparent)

  if app.tab then
    ui.setCursor(r2 - vec2(24, 34))
    ui.setItemAllowOverlap()
    if ui.iconButton(ui.Icons.StopAlt, 22, 7) then unloadApp(app) end
    if ui.itemHovered() then
      ui.setTooltip((app.release('opened') and 'App is opened' or 'App is running in background')..'\nClick to fully stop it and unload the webpage') 
    end
  end

  ui.setCursor(r2 - vec2(4, 34))
  ui.setItemAllowOverlap()
  if ui.iconButton(Icons.Cancel, 22, 7) then removeApp(app, true) end
  if ui.itemHovered() then ui.setTooltip('Remove item from list') end
  ui.popStyleColor()
  ui.restoreCursor()

  ui.popID()
end

---@param p1 vec2
---@param p2 vec2
---@param tab WebBrowser
local function drawAppsTab(p1, p2, tab)
  Themes.drawThemedBg(p1, p2, 0.5)
  Themes.beginColumnGroup(p1, p2, 400)

  tab.attributes.appsQuery = ControlsAdvanced.searchBar('Search apps', tab.attributes.appsQuery, tab)
  ui.offsetCursorY(12)

  ui.childWindow('apps', vec2(), false, bit.bor(ui.WindowFlags.NoScrollbar, ui.WindowFlags.NoBackground), function ()
    ui.thinScrollbarBegin(true)

    local filter = tab.attributes.appsQuery or ''
    local anyShown = false
    for i, v in ipairs(apps) do
      if filter == ''
          or v.title:findIgnoreCase(filter)
          or v.originDomain:findIgnoreCase(filter) then
        anyShown = true
        drawAppsTabItem(i, v, filter)
      end
    end

    if not anyShown then
      ui.offsetCursorY(12)
      ui.text('Nothing to show.')
    end

    ui.offsetCursorY(20)
    ui.thinScrollbarEnd()
  end)
end

pinnedModule = {
  ---@param tab WebBrowser
  add = function (tab)
    local titleEdited = false
    local urlEdited = false
    local icon = {FaviconsProvider.get(tab)}
  
    ---@type PinnedApp
    local app = {
      title = tab:title(),
      url = tab:url(),
      originDomain = tab:domain(),
      rememberURL = true
    }

    if Storage.settings.contentStyle == 2 then
      app.darkMode = true
    end

    loadManifest(tab, function (d, manifestURL)
      if d then
        ac.log('Manifest', d)
        if not titleEdited and type(d.short_name) == 'string' then
          app.title = d.short_name or d.name
        end
        if not urlEdited and type(d.start_url) == 'string' then
          app.url = resolveURL(manifestURL, d.start_url)
        end
        local foundIcon = findOptimalIcon(d)
        if foundIcon then
          icon[1] = resolveURL(manifestURL, foundIcon)
        end
        if d.background_color then app.backgroundColor = rgbm.new(d.background_color) end
        if d.theme_color then app.themeColor = rgbm.new(d.theme_color) end
      end
    end)

    appEditDialog(app, tab, icon, function (id)
      if id == 'title' then titleEdited = true end
      if id == 'url' then urlEdited = true end
    end)
  end,

  ---@return PinnedApp?
  added = function (domain)
    for _, v in ipairs(apps) do
      if v.originDomain == domain then
        return v
      end
    end
  end,

  ---@param item PinnedApp
  ---@param tab WebBrowser
  edit = function (item, tab)
    appEditDialog(item, tab, {getIconFilename(item)})
  end,
  
  ---@param item WebBrowser|PinnedApp
  remove = function (item)
    if item.draw then
      for _, v in ipairs(apps) do
        if v.tab == item then
          removeApp(v, true)
          break
        end
      end
    else
      for _, v in ipairs(apps) do
        if v == item then
          removeApp(v, true)
          break
        end
      end
    end
  end,

  anyActive = function ()
    for _, v in ipairs(apps) do
      if v.tab ~= nil then return true end
    end
    return false
  end,

  canUnload = function ()
    return #apps == 0
  end,

  ---@param fn fun(tab: WebBrowser, size: vec2)
  registerBrowserBlockDraw = function (fn)
    drawImpl = fn
  end,
  
  ---@param fn fun(tab: WebBrowser)
  iteratePinnedTabs = function (fn)
    for _, v in ipairs(apps) do
      if v.tab then
        fn(v.tab)
      end
    end
  end,

  ---@param fn function
  onUnload = function (fn)
    unloadListener = fn
  end,

  drawAppsTab = drawAppsTab
}

return pinnedModule