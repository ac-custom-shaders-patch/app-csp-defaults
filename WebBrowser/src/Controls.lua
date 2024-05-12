local WebUI = require('shared/web/ui')

local App = require('src/App')
local FaviconProvider = require('src/FaviconsProvider')
local Icons = require('src/Icons')
local Pinned = require('src/Pinned')
local SearchProvider = require('src/SearchProvider')
local Storage = require('src/Storage')
local Themes = require('src/Themes')
local Utils = require('src/Utils')

local ControlsBasic = require('src/ControlsBasic')
local ControlsInputFeatures = require('src/ControlsInputFeatures')
local menuItem = ControlsBasic.menuItem

local ColTabSelected = rgbm(0.15, 0.15, 0.15, 1)
ControlsBasic.barBackgroundColor = ColTabSelected

local ColTabBg = rgbm(0.25, 0.25, 0.25, 1)
local ColTabLoadingBar = rgbm(1, 1, 1, 0.1)
local ColTabSeparator = rgbm(1, 1, 1, 0.3)
local ColTabCloseHovered = rgbm(1, 1, 1, 0.1)
local ColAddressStatus = rgbm(1, 1, 1, 0.4)
local ColAddressCover = rgbm(ColTabSelected.r, ColTabSelected.g, ColTabSelected.b, 0.5)

local function update(focused)
  local v = focused and 0.15 or 0.19
  ColTabSelected.r, ColTabSelected.g, ColTabSelected.b = v, v, v
  ColAddressCover.rgb:set(ColTabSelected.rgb)
end

local tabHeight = const(22)
local tabSize = vec2(1, tabHeight)
local pinnedTabSize = vec2(28, tabHeight)
local tabCloseButtonSize = vec2(tabHeight, tabHeight)
local tabColTransparent = rgbm()
local tabVec1 = vec2()
local tabVec2 = vec2()
local tabVec3 = vec2()

local newTabButtonSize = vec2(tabHeight, tabHeight)
local addressBarButtonSize = vec2(22, 22)

local lastWindowPos = vec2()
local tabsPivotY = 0
local menuPivotY = 0
local appMenuPivotX = 0
local downloadsMenuPivotX = 0
local tabsMenuPivotX = 0
local bookmarksMenuPivotX = 0
local passwordMenuPivotX = 0

local showDownloadsIcon = false

local ControlsDownload = require('src/ControlsDownloads')

---@param toggle boolean
local function showDownloadsMenu(toggle)
  showDownloadsIcon = true
  if downloadsMenuPivotX == 0 then
    setTimeout(showDownloadsMenu)
    return
  end
  ControlsDownload.showDownloadsMenu(toggle, lastWindowPos + vec2(downloadsMenuPivotX, menuPivotY))
end

local ControlsTabsMenu = require('src/ControlsTabsMenu')

---@param toggle boolean
local function showTabsMenu(toggle)
  ControlsTabsMenu.showTabsMenu(toggle, lastWindowPos + vec2(tabsMenuPivotX, tabsPivotY))
end

local ControlsBookmarks = require('src/ControlsBookmarks')

---@param toggle boolean
local function showBookmarksMenu(toggle)
  local x = bookmarksMenuPivotX == 0 and appMenuPivotX - 22 or bookmarksMenuPivotX
  ControlsBookmarks.showBookmarksMenu(toggle, lastWindowPos + vec2(x, menuPivotY))
end

local passwordPopup = Utils.uniquePopup()

---@param toggle boolean
local function showPasswordMenu(toggle)
  local x = passwordMenuPivotX == 0 and appMenuPivotX - 22 or passwordMenuPivotX
  passwordPopup(toggle, function ()
    local tab = App.selectedTab()
    if tab.attributes.passwordToSave then
      local r = tab.attributes.passwordToSave()
      if r ~= nil then
        tab.attributes.passwordSaved = r
        ui.closePopup()
      end
    else
      ui.closePopup()
    end
  end, {position = lastWindowPos + vec2(x, menuPivotY), pivot = vec2(1, 0)})
end

local appMenuPopup = Utils.uniquePopup()

---@param toggle boolean
local function showAppMenu(toggle)
  local zoomState = {0}
  appMenuPopup(toggle, function ()
    local tab = App.selectedTab()
    local cx = ui.getCursorX()
    ui.setCursorX(240)
    ui.setCursorX(cx)

    if not App.canOpenMoreTabs() then ui.pushDisabled() end
    if menuItem('New tab', 'Ctrl+T') then App.addAndSelectTab() end
    if menuItem('New incognito tab', 'Ctrl+Shift+N') then App.addAndSelectTab(nil, true) end
    if not App.canOpenMoreTabs() then ui.popDisabled() end

    ui.separator()

    if menuItem('History', 'Ctrl+H') then App.selectOrOpen('about:history') end
    if menuItem('Downloads', 'Ctrl+J') then setTimeout(showDownloadsMenu) end
    if menuItem('Bookmarks', 'Ctrl+Shift+O') then App.selectOrOpen('about:bookmarks') end
    if menuItem('Tabs', 'Ctrl+Shift+A') then setTimeout(showTabsMenu) end
    if menuItem('Apps') then App.selectOrOpen('about:apps') end

    if not tab:blank() then
    
      local w = ui.availableSpaceX()
      ui.separator()
      ControlsBasic.zoomMenuItem(tab, zoomState)
      ui.separator()

      if menuItem('Find…', 'Ctrl+F') then Utils.toggleSearch(tab, true, false, false) end
      if menuItem('Print…', 'Ctrl+P') then tab:command('print') end
      if menuItem('Save page as…', 'Ctrl+S') then Utils.saveWebpage(tab) end

      local pinnedApp = Pinned.added(tab:domain())
      if pinnedApp then
        if menuItem('Edit app…') then Pinned.edit(pinnedApp, tab) end
      else
        if menuItem('Install app…') then Pinned.add(tab) end
      end

      if ui.itemHovered() then ui.setTooltip('Access your favorite webpages directly from AC apps list') end
      if Storage.settings.developerTools and menuItem('Developer tools', 'F12') then
        Utils.openDevTools(tab, true)
      end

      ui.separator()
      
      ui.text('Edit')
      ui.pushStyleColor(ui.StyleColor.Button, rgbm.colors.transparent)
      ui.sameLine(w - 130)
      ui.offsetCursorY(-4)
      if ui.button('Cut', vec2(50, 0)) then tab:command('cut') ui.closePopup() App.focusNext = 'browser' end
      ui.sameLine(0, 0)
      if ui.button('Copy', vec2(50, 0)) then tab:command('copy') ui.closePopup() App.focusNext = 'browser' end
      ui.sameLine(0, 0)
      if ui.button('Paste', vec2(50, 0)) then tab:command('paste') ui.closePopup() App.focusNext = 'browser' end
      ui.popStyleColor()
      ui.offsetCursorY(-4)
    end

    ui.separator()

    if menuItem('Settings') then App.selectOrOpen('about:settings') end
    if menuItem('About') then App.selectOrOpen('about:about') end
  end, {position = lastWindowPos + vec2(appMenuPivotX, menuPivotY), pivot = vec2(1, 0)})
end

local ColIncognitoOverlay = rgbm(0, 0, 0, 0.2)
local tabDraggingStart

---@param i number
---@param tab WebBrowser
---@param tabX number
---@param posY number
---@param tabSize vec2
local function drawTabItem(i, tab, tabX, posY, tabSize)
  ui.pushID(i)
  local dragOffset = 0
  if i == App.selected and tabDraggingStart ~= nil then
    if ui.mouseDown(ui.MouseButton.Left) then
      dragOffset = ui.mousePos().x - tabDraggingStart
      ui.captureMouse(true)
    else
      tabDraggingStart = nil
    end
  end

  local visualOffset = tab.attributes.tabOffset
  if math.abs(dragOffset) > 0.1 or math.abs(visualOffset) > 0.1 then
    visualOffset = math.round(math.applyLag(visualOffset, math.abs(dragOffset) > 10 and dragOffset or 0, 0.7, ui.deltaTime()))
    tab.attributes.tabOffset = visualOffset
    if visualOffset ~= 0 then
      tabX = tabX + visualOffset
    end
  end
  ui.setCursorX(tabX)
  ui.setCursorY(posY)

  ui.setNextItemIcon(tab:loading() and ui.Icons.LoadingSpinner or FaviconProvider.get(tab))
  local tabColor = i == App.selected and ColTabSelected or ColTabBg
  if rawequal(tabColor, ColTabSelected) then
    ui.pushStyleColor(ui.StyleColor.Button, tabColor)
    ui.pushStyleColor(ui.StyleColor.ButtonHovered, tabColor)
    ui.pushStyleColor(ui.StyleColor.ButtonActive, tabColor)
  end
  local title = tab:title(true)
  ui.button(title, tabSize, ui.ButtonFlags.PressedOnClick)
  local hovered = ui.itemHovered(ui.HoveredFlags.AllowWhenBlockedByPopup)
  local selected = hovered and (ui.itemClicked(ui.MouseButton.Left) or ui.mouseReleased(ui.MouseButton.Left))
  if ui.itemClicked(ui.MouseButton.Right, true) then
    ControlsBasic.showTabMenu(tab)
  end
  if not tabDraggingStart and ui.itemActive() then
    tabDraggingStart = ui.mousePos().x
  end
  if rawequal(tabColor, ColTabSelected) then
    ui.popStyleColor(3)
  end
  tabVec1.y, tabVec2.y = posY, posY + tabHeight
  -- if ui.itemHovered() and i ~= App.selected and not ui.mouseDown() and not tab:blank() then
  if hovered and i ~= App.selected and not ui.mouseDown() then
    if ui.mouseDelta():lengthSquared() < 1 then
      tab:awake()
    end
    ui.tooltip(function () ControlsBasic.tabTooltip(tab) end)
  end

  local showAudioIcon = not tab.attributes.pinned and (tab:playingAudio() or tab:muted())
  if not tab.attributes.pinned then
    local o = showAudioIcon and tabHeight * 2 or tabHeight
    tabColTransparent.rgb:set(tabColor.rgb)
    tabVec1.x, tabVec2.x = tabX + tabSize.x - (o + 2), tabX + tabSize.x - (o - 6)
    ui.drawRectFilledMultiColor(tabVec1, tabVec2, tabColTransparent, tabColor, tabColor, tabColTransparent)
    tabVec1.x, tabVec2.x = tabVec2.x, tabX + tabSize.x
    ui.drawRectFilled(tabVec1, tabVec2, tabColor)
  end
  ui.setCursorX(tabX + tabSize.x - tabHeight)
  ui.setCursorY(posY)
  tabVec1.x, tabVec2.x = tabX, tabX + tabSize.x
  local close = ui.itemHovered() and ui.mouseClicked(ui.MouseButton.Middle)
  if not tab.attributes.pinned then
    if tab:playingAudio() then
      ui.backupCursor()
      ui.offsetCursor(vec2(-tabHeight + 12, 5))
      ui.image(Icons.talkingIcon(tab:audioPeak()), tabHeight - 10)
      if ui.itemHovered() and tab == App.selectedTab() then
        ui.setTooltip('This tab is playing audio')
      end
      ui.restoreCursor()
    end
    if tab:muted() then
      ui.backupCursor()
      ui.offsetCursor(vec2(-tabHeight + 12, 5))
      ui.image(Icons.Atlas.VolumeMuted, tabHeight - 10)
      if ui.itemHovered() then ui.setTooltip('Tab is muted') end
      ui.restoreCursor()
    end

    ui.pushStyleColor(ui.StyleColor.Button, rgbm.colors.transparent)
    ui.pushStyleColor(ui.StyleColor.ButtonHovered, rgbm.colors.transparent)
    ui.pushStyleColor(ui.StyleColor.ButtonActive, rgbm.colors.transparent)
    ui.setItemAllowOverlap()
    ui.iconButton('vs:u2;_0,0,1,1,1;_0,1,1,0,1', tabCloseButtonSize, 8)
    if ui.itemHovered() then selected = false end
    if ui.itemClicked(ui.MouseButton.Left, true) or close then App.closeTab(tab) end
    if ui.itemHovered() then
      ui.drawCircleFilled(tabVec3:set(tabVec2.x - tabHeight / 2, tabVec2.y - tabHeight / 2), 8, ColTabCloseHovered)
    end
    ui.popStyleColor(3)
  elseif close then
    selected = false
    App.closeTab(tab)
  end

  if selected then
    App.selectTab(tab, true)
  end
  
  ui.popID()
  if tab.attributes.anonymous then
    ui.setShadingOffset(0, 0, 0, 1)
    ui.beginTextureShade('res/overlay.png')
    ui.drawRectFilledMultiColor(tabVec1, tabVec2, ColIncognitoOverlay, ColIncognitoOverlay, rgbm.colors.transparent, rgbm.colors.transparent)
    ui.endTextureShade(tabVec1, tabVec1 + 12, false)
    ui.resetShadingOffset()
  end
  if tab:loading() and tab:loadingProgress() < 0.99 then
    -- tabVec3:set(tabVec1)
    tabVec1.x = math.lerp(tabVec1.x, tabVec2.x, tab:loadingProgress())
    -- ui.drawRectFilledMultiColor(tabVec1, tabVec2, ColTabLoadingBar, ColTabLoadingBar, tabColTransparent, tabColTransparent)
    ColTabLoadingBar.mult = 0.2 * (1 - tab:loadingProgress())
    ui.drawRectFilledMultiColor(tabVec1, tabVec2, ColTabLoadingBar, tabColTransparent, tabColTransparent, ColTabLoadingBar)

    -- ColTabLoadingBar.rgb = ui.styleColor(ui.StyleColor.PlotHistogramHovered).rgb
    -- ColTabLoadingBar.mult = 0.05
    -- ui.drawRectFilled(tabVec1, tabVec2, ColTabLoadingBar)

    -- ui.setShadingOffset(0, 0, 0, 1)
    -- ui.beginTextureShade('res/overlay.png')
    -- ui.drawRectFilledMultiColor(tabVec1, tabVec2, rgbm.colors.white, rgbm.colors.white, rgbm.colors.transparent, rgbm.colors.transparent)
    -- ui.endTextureShade(tabVec3, tabVec3 + 12, false)
    -- ui.resetShadingOffset()
  end
  if i > 1 and (i < App.selected or i > App.selected + 1) then
    ui.drawSimpleLine(tabVec1:set(tabX, posY + 4), tabVec2:set(tabX, posY + tabHeight - 4), ColTabSeparator, 1)
  end
end

local function tabsBar()
  local tabsCount = #App.tabs
  local pinned = 0
  for i = 1, tabsCount do
    if App.tabs[i].attributes.pinned then
      pinned = i
    else
      break
    end
  end

  local pinnedSize = pinned * 28

  tabSize.x = math.min(220, (ui.availableSpaceX() - pinnedSize - 22 * 2) / (tabsCount - pinned))
  local posX, posY, selectedX = ui.getCursorX(), ui.getCursorY(), -1
  local selFixed = App.selected

  ui.pushStyleColor(ui.StyleColor.Button, ColTabBg)
  ui.pushStyleColor(ui.StyleColor.ButtonHovered, ColTabBg)
  ui.pushStyleColor(ui.StyleColor.ButtonActive, ColTabBg)
  for i = 1, tabsCount do
    local tab = App.tabs[i]
    local size = tab.attributes.pinned and pinnedTabSize or tabSize
    if i == selFixed then
      selectedX = math.round(posX)
    else
      drawTabItem(i, tab, math.round(posX), posY, size)
    end
    posX = posX + size.x
  end
  if selectedX ~= -1 then
    local tab = App.tabs[selFixed]
    local size = tab.attributes.pinned and pinnedTabSize or tabSize
    drawTabItem(selFixed, tab, math.round(selectedX), posY, size)
  end
  ui.popStyleColor(3)

  if tabDraggingStart then
    local dragged = App.tabs[App.selected]
    local size = dragged.attributes.pinned and pinnedTabSize or tabSize
    if dragged.attributes.tabOffset > size.x / 2 and App.tabs[App.selected + 1] and App.tabs[App.selected + 1].attributes.pinned == dragged.attributes.pinned 
        or dragged.attributes.tabOffset < -size.x / 2 and App.tabs[App.selected - 1] and App.tabs[App.selected - 1].attributes.pinned == dragged.attributes.pinned then
      local s = math.sign(dragged.attributes.tabOffset)
      App.tabs[App.selected], App.tabs[App.selected + s] = App.tabs[App.selected + s], App.tabs[App.selected]
      App.tabs[App.selected + s].attributes.tabOffset = App.tabs[App.selected + s].attributes.tabOffset - size.x * s
      App.tabs[App.selected].attributes.tabOffset = App.tabs[App.selected].attributes.tabOffset + size.x * s
      tabDraggingStart, App.selected = tabDraggingStart + size.x * s, App.selected + s
      App.saveTabs()
    end
  end

  ui.pushStyleColor(ui.StyleColor.Button, rgbm.colors.transparent)
  if App.canOpenMoreTabs() then
    local tabX = math.round(posX)
    ui.setCursorX(tabX)
    ui.setCursorY(posY)
    if App.selected ~= #App.tabs then
      ui.drawSimpleLine(tabVec1:set(tabX, posY + 4), tabVec2:set(tabX, posY + tabHeight - 4), ColTabSeparator, 1)
    end
    ui.iconButton('vs:u2;_0.55,0,0.55,0.9,1;_0.1,0.5,1,0.5,1', newTabButtonSize, 6)
    if ui.itemHovered() then ui.setTooltip('New tab (Ctrl+T)') end
    if ui.itemClicked(ui.MouseButton.Left, true) then App.addAndSelectTab() end
    tabVec1:set(ui.itemRectMin())
    tabVec2:set(ui.itemRectMax())
  end
  
  tabsPivotY = ui.getCursorY() - 4
  ui.sameLine(0, 0)
  ui.offsetCursorX(ui.availableSpaceX() - 22)
  tabsMenuPivotX = ui.getCursorX() + 22
  if ui.iconButton(ui.Icons.Ellipsis, addressBarButtonSize, 7, true, ui.ButtonFlags.PressedOnClick) then showTabsMenu(true) end
  if ui.itemHovered() then ui.setTooltip('Search tabs (Ctrl+Shift+A)') end
  ui.popStyleColor(1)

  ui.setTitleBarContentHint(66, ui.windowSize().x - posX)
end

---@param tab WebBrowser
local function websitePrivacyMenu(tab, params)
  local url, data
  Utils.popup(function ()
    Utils.noteActivePopup()
    ui.pushFont(ui.Font.Title)
    ui.text(tab:domain())
    ui.popFont()
    ui.offsetCursorY(8)

    if tab:blank() then
      ui.text('You’re viewing a secure page')
      return
    end

    if url ~= tab:url() then
      url = tab:url()
      data = nil
    end
    local state = tab:pageState()
    if not state then
      if tab:crash() then
        ui.text('Not available')
      else
        ui.text('Loading: %.0f%%' % (100 * tab:loadingProgress()))
      end
    else
      if not data then
        tab:countCookiesAsync(url, function (reply) data = reply end)
      end
      ui.setNextItemIcon(state.secure and ui.Icons.Padlock or ui.Icons.Warning, nil, 0.3)
      if ui.selectable(state.secure and 'Connection is secure' or 'Connection is not secure', false) then
        WebUI.DefaultPopups.SSLStatus(tab)
      end
      ui.setNextItemIcon(ui.Icons.ListAlt, nil, 0.3)
      if ui.selectable('Cookies: %s' % (data and tostring(data) or '…'), false, data and 0 or ui.SelectableFlags.Disabled) and data then
        WebUI.DefaultPopups.Cookies(tab, data)
      end
    end
  end, params)
end

local downloadAnimation = 0
local downloadBarFade = 1
local downloadBarIcon = nil

local addressSuggestions = ControlsInputFeatures.inputSuggestions(function (query, callback)
  SearchProvider.suggestions(query, function (items)
    items = table.slice(items, 1, 5)

    if query:find('^%w*:') or query:find('/', nil, true) or query:find('.', nil, true) then
      table.insert(items, 1, '\4'..query)
      table.insert(items, 2, '\5'..query)
    end

    local found = {}
    for i, t in ipairs(App.tabs) do
      if i ~= App.selected and not found[t:url()] and (t:title():findIgnoreCase(query) or t:url():findIgnoreCase(query)) then
        found[t:url()] = true
        items[#items + 1] = '\1'..t:url()
        if table.nkeys(found) >= 5 then break end
      end
    end
    for i = 1, #App.storedBookmarks do
      local b = App.storedBookmarks:at(i)
      if not found[b.url] and b.title ~= '' and (b.title:findIgnoreCase(query) or b.url:findIgnoreCase(query)) then
        found[b.url] = true
        items[#items + 1] = '\2'..b.url..'\2'..b.title
        if table.nkeys(found) >= 5 then break end
      end
    end
    for i = #App.storedHistory, math.max(1, #App.storedHistory - 100), -1 do   
      local b = App.storedHistory:at(i)
      if not found[b.url] and not b.url:startsWith('view-source:') and b.title ~= '' and (b.title:findIgnoreCase(query) or b.url:findIgnoreCase(query)) then
        found[b.url] = true
        items[#items + 1] = '\3'..b.url..'\3'..b.title
        if table.nkeys(found) >= 5 then break end
      end
    end
    callback(items)
  end)
end)

local function searchProviderSelector()
  ui.separator()    
  ui.pushFont(ui.Font.Small)
  ui.text('Search engine:')
  ui.popFont()

  local function offerStyle(icon, id, name)
    local c = ui.getCursor()
    if ui.invisibleButton(id, 22) then
      Storage.settings.searchProviderID = id
    end
    if ui.itemHovered() or Storage.settings.searchProviderID == id then
      ui.drawCircle(c + 11, 12, ui.itemHovered() and rgbm.colors.white or rgbm.new(0.7, 1), 20, 2)
    end
    ui.beginTextureShade(icon)
    ui.drawCircleFilled(c + 11, 11, rgbm.colors.white, 20)
    ui.endTextureShade(c, c + 22)
    if ui.itemHovered() then
      ui.setTooltip(name)
    end
    ui.sameLine()
  end
  for _, v in ipairs(SearchProvider.list) do
    offerStyle(v.icon, v.id, v.name)
  end
  ui.newLine()
end

local clipboardContent

local function urlInputExtraContextItems()
  if ui.isWindowAppearing() then
    clipboardContent = ui.getClipboardText():trim()
    if #clipboardContent > 120 then clipboardContent = clipboardContent:sub(1, 120) end
  end
  if clipboardContent ~= '' then
    local displayContent = clipboardContent
    if #displayContent > 20 then
      displayContent = displayContent:sub(1, 20):trim()..'…'
    end
    if clipboardContent:match('^https?://') then
      if ControlsBasic.menuItem('Paste and navigate to “%s”' % displayContent) then
        App.selectedTab():navigate(clipboardContent)
        App.focusNext = 'browser'
      end
    else
      if ControlsBasic.menuItem('Paste and search for “%s”' % displayContent) then
        App.selectedTab():navigate(SearchProvider.userInputToURL(clipboardContent, true))
        App.focusNext = 'browser'
      end
    end
    ui.separator()
  end
end

local addressActive = false

---@param tab WebBrowser
local function addressBar(tab)
  lastWindowPos = ui.windowPos()
  menuPivotY = ui.getCursorY() + 22

  ui.offsetCursorX(12)

  local historyMenu
  if ui.iconButton(ui.Icons.ArrowLeft, addressBarButtonSize, 6, true, tab:canGoBack() and 0 or ui.ButtonFlags.Disabled) then
    tab:navigate('back')
  end
  if ui.itemHovered() then
    ui.setTooltip('Back (Alt+←)')
  end
  if tab:canGoBack() and ui.itemClicked(ui.MouseButton.Right, true) then historyMenu = 'back' end
  ui.sameLine(0, 0)
  if ui.iconButton(ui.Icons.ArrowRight, addressBarButtonSize, 6, true, tab:canGoForward() and 0 or ui.ButtonFlags.Disabled) then
    tab:navigate('forward') 
  end
  if ui.itemHovered() then
    ui.setTooltip('Forward (Alt+→)')
  end
  if tab:canGoForward() and ui.itemClicked(ui.MouseButton.Right, true) then historyMenu = 'forward' end
  if historyMenu then
    local data = {} ---@type WebBrowser.NavigationEntry[]
    tab:getNavigationEntriesAsync(historyMenu, function (d) data = d end)
    Utils.popup(function ()
      if data == false then ui.closePopup() end
      if not data then return end
      for i = 1, #data do
        ui.pushID(i)
        ui.setNextItemIcon(FaviconProvider.require(data[i].displayURL))
        if ControlsBasic.menuItem(data[i].title) then ControlsBasic.nativeHyperlinkNavigate(historyMenu..':'..i, tab) end
        ControlsBasic.nativeHyperlinkBehaviour(data[i].displayURL, nil, function ()
          data = false
        end)
        if ui.itemHovered() then ui.setTooltip(data[i].displayURL) end
        ui.popID()
      end
      if #data > 0 then ui.separator() end
      ui.setNextItemIcon(ui.Icons.TimeRewind)
      if ControlsBasic.menuItem('Show full history') then App.selectOrOpen('about:history') end
    end)
  end
  if Storage.settings.homeButton then
    ui.sameLine(0, 0)
    if ui.iconButton(ui.Icons.Home, addressBarButtonSize, 6) then
      tab:navigate(Storage.settings.homePage == '' and WebBrowser.blankURL('newtab') or Storage.settings.homePage)
    end
    if ui.itemHovered() then
      ui.setTooltip('Home')
    end
    if ui.itemClicked(ui.MouseButton.Right, true) then
      Utils.popup(function ()
        if ControlsBasic.menuItem('Set current URL as a new home page') then
          Storage.settings.homePage = tab:url()
        end
        if ControlsBasic.menuItem('Hide home button') then
          Storage.settings.homeButton = false
        end
        if ui.itemHovered() then
          ui.setTooltip('Can be reenabled in visual settings')
        end
      end)
    end
  end
  ui.sameLine(0, 0)
  if ui.iconButton(tab:loading() and ui.Icons.Cancel or ui.Icons.Restart, addressBarButtonSize, 7, true) then 
    if tab:loading() then
      tab:stop()
    else
      tab:reload(ac.getUI().ctrlDown)
    end
  end
  if ui.itemHovered() then
    ui.setTooltip(tab:loading() and 'Stop loading' or 'Refresh (Ctrl+R)')
  end
  ui.sameLine(0, 0)
  ui.pushStyleColor(ui.StyleColor.ButtonHovered, rgbm.colors.transparent)
  ui.pushStyleColor(ui.StyleColor.ButtonActive, rgbm.colors.transparent)

  local x = ui.getCursorX()
  local pageState = tab:pageState()
  local addressIcon
  if not pageState or tab:url():sub(1, 4) ~= 'http' then
    addressIcon = tab:blank() and 'icon.png' or ui.Icons.Info
  elseif pageState.secure then
    addressIcon = ui.Icons.Padlock
  else
    addressIcon = ui.Icons.Warning
  end
  if ui.iconButton(addressIcon, 22, ColAddressStatus, 7) then
    websitePrivacyMenu(tab, {position = ui.windowPos() + vec2(x, ui.getCursorY()), pivot = vec2()})
  end
  ui.popStyleColor(2)
  tabVec1:set(ui.itemRectMin())
  tabVec2:set(ui.itemRectMax())
  if ui.itemHovered() then
    ui.drawCircleFilled(tabVec3:set(tabVec1):add(tabVec2):scale(0.5), 9, ColTabCloseHovered)
  end
  ui.sameLine(0, 0)
  ui.offsetCursorX(-4)

  if #App.activeDownloads > 0 then
    showDownloadsIcon = true
  end

  local showBookmarksIcon = tab:url() ~= ''
  local buttonsCount = showDownloadsIcon and 2 or 1

  if addressActive then
    local c = ui.getCursor()
    tabVec3:set(c)
    tabVec3.x, tabVec3.y = tabVec3.x + ui.availableSpaceX() - 22 * buttonsCount - 12, tabVec3.y + 22
    ui.drawRectFilled(c, tabVec3, ui.styleColor(ui.StyleColor.PopupBg))
  end

  if showBookmarksIcon then buttonsCount = buttonsCount + 1 end
  if tab.attributes.passwordToSave then buttonsCount = buttonsCount + 1 end
  ui.setNextItemWidth(-22 * buttonsCount - 12)

  local currentURL = tab:url()
  local newURL, _, enterPressed = ui.inputText(SearchProvider.introduction(), currentURL, ui.InputTextFlags.Placeholder)
  addressActive = ui.itemActive()
  if App.focusNext == 'address' then
    App.focusNext = nil
    ui.activateItem(ui.getLastID())
  end
  ControlsInputFeatures.inputContextMenu(tab, searchProviderSelector, urlInputExtraContextItems)

  if not tab.attributes.anonymous then
    local selected = addressSuggestions(newURL, enterPressed)
    if selected then
      if type(selected) == 'table' then
        App.selectTab(selected, true)
        enterPressed = false
      else
        newURL = selected
        enterPressed = true
        App.focusNext = 'browser'
      end
    end
  end

  if not ui.itemActive() then
    local t1, t2 = ui.itemRect()
    local protocolPart = currentURL:match('^%w*://') or currentURL:match('^about:')
    if protocolPart then
      local endX = t2.x
      t2.x = t1.x + ui.measureText(protocolPart).x + 8
      ui.drawRectFilled(t1, t2, ColAddressCover)

      local pathStartIndex = currentURL:find('/', #protocolPart + 1, true)
      if pathStartIndex then
        local domainWidth = ui.measureText(currentURL:sub(1, pathStartIndex - 1)).x
        t2.x = endX
        t1.x = t1.x + domainWidth + 8
        ui.drawRectFilled(t1, t2, ColAddressCover)
      end
    end
  end
  if enterPressed then
    tab:navigate(SearchProvider.userInputToURL(newURL))
    App.focusNext = 'browser'
  end

  if tab.attributes.passwordToSave then 
    if os.time() > tab.attributes.timeOfPasswordToSave + 30 then
      tab.attributes.passwordToSave = nil
    end
    ui.sameLine(0, 0)
    passwordMenuPivotX = ui.getCursorX() + 22
    ui.pushStyleColor(ui.StyleColor.ButtonHovered, rgbm.colors.transparent)
    ui.pushStyleColor(ui.StyleColor.ButtonActive, rgbm.colors.transparent)
    if ui.iconButton(ui.Icons.Key, addressBarButtonSize, 6, true, 0) then
      showPasswordMenu(true)
    end
    if ui.itemHovered() or ui.itemActive() then
      ui.drawCircleFilled((ui.itemRectMin() + ui.itemRectMax()) / 2, 11, rgbm(1, 1, 1, ui.itemActive() and 0.2 or 0.1))
    end
    ui.popStyleColor(2)
    if ui.itemHovered() then
      ui.setTooltip(not tab.attributes.savingPassword and 'Saved password found' 
        or tab.attributes.passwordSaved and 'Edit saved password' or 'Save your password')
    end
  end

  if showBookmarksIcon then
    ui.sameLine(0, 0)
    bookmarksMenuPivotX = ui.getCursorX() + 22
    ui.pushStyleColor(ui.StyleColor.ButtonHovered, rgbm.colors.transparent)
    ui.pushStyleColor(ui.StyleColor.ButtonActive, rgbm.colors.transparent)
    if ui.iconButton(tab.attributes.bookmarked and ui.Icons.StarFull or ui.Icons.StarEmpty, addressBarButtonSize, 6, true, 0) then
      showBookmarksMenu(true)
    end
    if ui.itemHovered() or ui.itemActive() then
      ui.drawCircleFilled((ui.itemRectMin() + ui.itemRectMax()) / 2, 11, rgbm(1, 1, 1, ui.itemActive() and 0.2 or 0.1))
    end
    ui.popStyleColor(2)
    if ui.itemHovered() then
      ui.setTooltip(tab.attributes.bookmarked and 'Edit bookmark for this tab (Ctrl+D)' or 'Bookmark this tab (Ctrl+D)')
    end
  end
  
  if showDownloadsIcon then
    ui.sameLine(0, 0)
    downloadsMenuPivotX = ui.getCursorX() + 22
    local hasActiveDownloads = #App.activeDownloads > 0
    local drawIconAnimation, averageProgress = downloadAnimation ~= 0, -1
    if hasActiveDownloads then
      local c = 0
      for i = 1, #App.activeDownloads do
        c = c + ControlsDownload.estimateProgress(App.activeDownloads[i])
        if App.activeDownloads[i].state == 'loading' then
          drawIconAnimation = true
        end
      end
      averageProgress = c / #App.activeDownloads
    end
    -- if ac.isKeyDown(ac.KeyIndex.LeftButton) then drawIconAnimation = true end
    if ui.iconButton(drawIconAnimation and '' or ui.Icons.ArrowDown, addressBarButtonSize, 7, true, 0) then
      showDownloadsMenu(true)
    end
    if drawIconAnimation then
      downloadAnimation = downloadAnimation + ui.deltaTime()
      local v = 0.5 + 2 * math.smoothstep(downloadAnimation)
      ui.addIcon(ui.Icons.ArrowDown, 8, vec2(0.5, v), rgbm.colors.white)
      ui.addIcon(ui.Icons.ArrowDown, 8, vec2(0.5, v - 2), rgbm.colors.white)
      if downloadAnimation > 1 then downloadAnimation = 0 end
    end
    local barFadeTarget = drawIconAnimation and 0 or 1
    if math.abs(barFadeTarget - downloadBarFade) > 0.01 or not downloadBarIcon then
      downloadBarFade = math.applyLag(downloadBarFade, drawIconAnimation and 0 or 1, 0.8, ui.deltaTime())
      downloadBarIcon = string.format('vs:_%.2f,1.2,%.2f,1.2,1', 0.5 - 0.5 * downloadBarFade, 0.5 + 0.5 * downloadBarFade)
    end
    ui.addIcon(downloadBarIcon, 8, 0.5, rgbm.colors.white)
    if averageProgress ~= -1 then
      averageProgress = math.saturateN(averageProgress)
      ui.drawCircle((ui.itemRectMin() + ui.itemRectMax()) / 2, 8, rgbm(0, 0, 0, 0.3), 40, 1)
      ui.pathArcTo((ui.itemRectMin() + ui.itemRectMax()) / 2, 8, -math.pi / 2, -math.pi / 2 + averageProgress * math.pi * 2, 40)
      ui.pathStroke(rgbm.colors.white, false, 1)
    end
    if ui.itemHovered() then
      ui.setTooltip('Downloads (Ctrl+J)')
    end
  end
  ui.sameLine(0, 0)
  appMenuPivotX = ui.getCursorX() + 22
  if ui.iconButton(ui.Icons.Menu, addressBarButtonSize, 7, true, ui.ButtonFlags.PressedOnClick) then
    showAppMenu(true)
  end
  if ui.itemHovered() then
    ui.setTooltip('Settings and more (Alt+F)')
  end
end

local errorMessages = {
  ERR_NAME_NOT_RESOLVED = '%s’s server IP address could not be found.',
  DNS_PROBE_FINISHED_NXDOMAIN = '%s’s server IP address could not be found.',
  ERR_CONNECTION_REFUSED = '%s refused to connect.',
  ERR_ADDRESS_UNREACHABLE = '%s is unreachable.',
  ERR_INTERNET_DISCONNECTED = {false, 'You are offline'},
  ERR_CERT_COMMON_NAME_INVALID = {'%s’s SSL certificate is misconfigured.', 'Your connection is not private', 'ssl'},
  ERR_CERT_DATE_INVALID = {'%s’s SSL certificate is misconfigured.', 'Your connection is not private', 'ssl'},
  ERR_SSL_PROTOCOL_ERROR = {'%s sent an invalid response.', 'This site can’t provide a secure connection'},
  ERR_SSL_FALLBACK_BEYOND_MINIMUM_VERSION = {'%s sent an invalid response.', 'This site can’t provide a secure connection'},
  ERR_SSL_VERSION_OR_CIPHER_MISMATCH = {'%s uses an unsupported protocol.', 'This site can’t provide a secure connection'},
  ERR_BAD_SSL_CLIENT_AUTH_CERT = {'%s didn’t accept your login certificate, or one may not have been provided.', 'This site can’t provide a secure connection'},
  ERR_TIMED_OUT = '%s took too long to respond.',
  ERR_CONNECTION_TIMED_OUT = '%s took too long to respond.',
  ERR_CONNECTION_RESET = 'The connection was reset.',
  ERR_NETWORK_CHANGED = {'A network change was detected.', 'Your connection was interrupted'},
  ERR_EMPTY_RESPONSE = {'%s didn’t send any data.', 'This page isn’t working'},
  ERR_TOO_MANY_REDIRECTS = {'%s redirected you too many times.', 'This page isn’t working'},
  ERR_CACHE_MISS = {'You might need to redo that form you just filled.', 'Form resubmission issue'},

  ERR_ACEF_BOOTLOOP = {false, false, 'reinstall'},
  ERR_ACEF_FAILED_TO_START = {false, false, 'reinstall'},
  ERR_ACEF_INSTALLATION_ERROR = {false, false, 'reinstall'},
}

---@param p1 vec2
---@param p2 vec2
---@param loadError WebBrowser.LoadError|WebBrowser.Crash|nil
---@param tab WebBrowser
local function drawErrorMessage(p1, p2, loadError, tab)
  Themes.drawThemedBg(p1, p2, 0.5)
  Themes.beginColumnGroup(p1, p2, 400)

  local action, title, message, status
  if not loadError then
    title, message, status = 'Oh no!', 'Something went wrong while displaying this webpage.', 'EMPTY_ERROR'
  else
    local key = loadError.errorText
    if key:startsWith('NET::') then key = key:sub(6) end
    local i = errorMessages[key]
    if type(i) == 'table' then
      title, message = i[2], i[1]
      action = i[3]
    else
      message = i
    end
    if not title then
      title = tab:crash() and 'Oh no!' or 'This site can’t be reached'
    end
    message = loadError.errorDetails or message and string.format(message, tab:domain()) 
      or tab:crash() and 'Something went wrong while displaying this webpage2.' or 'Check your internet connection.'
    status = loadError.errorText
  end

  ui.offsetCursorY(math.max(0, (p2.y - p1.y) / 2 - 200))
  ui.pushFont(ui.Font.Title)
  ui.text(title)
  ui.popFont()
  ui.offsetCursorY(20)
  local i = message:find(tab:domain(), nil, true)
  if i then
    ui.setNextTextSpanStyle(i, i + #tab:domain() - 1, nil, true)
  end
  ui.textWrapped(message)
  ui.offsetCursorY(4)
  ui.textColored(status, rgbm.colors.gray)
  if ui.itemHovered() then
    ui.setMouseCursor(ui.MouseCursor.Hand)
    if ui.itemClicked(ui.MouseButton.Left, true) then
      ui.setClipboardText(status)
      ui.toast(ui.Icons.Copy, 'Error code “%s” is copied to the clipboard' % status)
    end
  end
  local c = ui.getCursor()
  ui.setItemAllowOverlap()
  ui.pushStyleVar(ui.StyleVar.FrameRounding, 2)
  ui.offsetCursorY(20)
  ac.debug('Load error', loadError)
  if action == 'ssl' then
    ui.setNextItemIcon(ui.Icons.Warning, rgbm.colors.orange)
    ui.setNextTextSpanStyle(1, math.huge, rgbm.colors.orange)
    if ui.button('Proceed anyway', vec2(ui.availableSpaceX() / 2 - 2, 28)) then
      App.ignoreSSLIssues(tab:domain())
      tab:reload(true)
    end
    ui.sameLine(0, 4)
  elseif action == 'reinstall' then
    ui.setNextItemIcon(ui.Icons.Wrench, rgbm.colors.orange)
    ui.setNextTextSpanStyle(1, math.huge, rgbm.colors.orange)
    if ui.button('Reinstall CEF', vec2(ui.availableSpaceX() / 2 - 2, 28)) then
      WebBrowser.restartProcess(true)
    end
    ui.sameLine(0, 4)
  end
  ui.setNextItemIcon(ui.Icons.Restart)
  if ui.button(tab:crash() and 'Restart' or 'Reload', vec2(-0.1, 28)) then
    tab:reload(true)
  end
  ui.popStyleVar()
  ui.setCursor(c)
end

local v1 = vec2()
local v2 = vec2()
local v3 = vec2()
local sim = ac.getSim()

---@param p1 vec2
---@param p2 vec2
---@param tab WebBrowser
local function drawLoading(p1, p2, tab)
  ui.drawRectFilled(p1, p2, tab:backgroundColor())
  v1:set(p1):add(p2):scale(0.5)
  local p = tab:installing()
  -- if not p then p = { message = 'Loading…', progress = 0.5 } end
  if p then
    v1.x, v1.y = v1.x - 80, v1.y + 20
    ui.setCursor(v1)
    ui.progressBar(p.progress, v2:set(160, 2), ' ')
    if p.progress <= 0 then
      for i = 1, 5 do
        local v = (sim.gameTime + i * 0.12) % 1
        v = math.lerp(v, math.smootherstep(v), v)
        local s = v * 1.02 - 0.01
        if math.abs(s - 0.5) < 0.5 then
          v2.x, v2.y = v1.x + 158 * s, v1.y
          ui.drawRectFilled(v2, v3:set(2, 2):add(v2), tab:contentColor())
        end
      end
    end
    ui.drawTextClipped(p.message, p1, p2, tab:contentColor(), 0.5)
  else    
    v1.x, v1.y = v1.x - 40, v1.y - 40
    v2.x, v2.y = v1.x + 80, v1.y + 80
    ui.drawLoadingSpinner(v1, v2, tab:contentColor())
  end
end

return {
  update = update,
  menuItem = menuItem,
  tabsBar = tabsBar,
  addressBar = addressBar,
  addressBarBackgroundColor = ColTabSelected,
  showAppMenu = showAppMenu,
  showDownloadsMenu = showDownloadsMenu,
  showBookmarksMenu = showBookmarksMenu,
  showTabsMenu = showTabsMenu,
  drawErrorMessage = drawErrorMessage,
  drawLoading = drawLoading,
  offerToSavePassword = function (tab, popupContent)
    tab.attributes.savingPassword = true
    tab.attributes.passwordToSave = popupContent
    tab.attributes.timeOfPasswordToSave = os.time()
    showPasswordMenu(false)
  end
}