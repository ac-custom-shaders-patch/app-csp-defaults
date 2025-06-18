--[[
  An example of CEF integration, a basic web browser. A bit messy, but seems to work. Still missing things
  like proper drag-n-drop support, but that first would need to be added to AC’s IMGUI. Other than that,
  other features I personally would expect from a web browser should work.
]]

WebBrowser = require('shared/web/browser')

require('src/CompatibilityPatches')

local Storage = require('src/Storage')
WebBrowser.configure({
  useCEFLoop = Storage.settings.useCEFLoop, -- compatibility with CEFv1
  skipProxyServer = Storage.settings.skipProxyServer,
  targetFPS = Storage.settings.targetFPS,
})

local WebUI = require('shared/web/ui')
local ControlsBasic = require('src/ControlsBasic')

local App = require('src/App')
local Blanks = require('src/Blanks')
local Controls = require('src/Controls')
local ControlsBookmarks = require('src/ControlsBookmarks')
local ControlsOverlays = require('src/ControlsOverlays')
local PasswordsManager = require('src/PasswordsManager')
local Handlers = require('src/Handlers')
local Hotkeys = require('src/Hotkeys')
local Pinned = require('src/Pinned')
local Themes = require('src/Themes')
local Utils = require('src/Utils')

---For browser in Android Auto
ac.store('.WebBrowser.searchProvider', Storage.settings.searchProviderID)

---Last known tab size (helps to skip resizing step for new tabs).
local lastSize = vec2(320, 240)

local function bookmarkSearch(item, _, u)
  return item.url == u
end

---@param tab WebBrowser
local function updateHistoryEntryLater(tab)
  if not tab.attributes.savingHistory then
    tab.attributes.savingHistory = setTimeout(function ()
      if not tab:disposed() and not tab:blank() and not tab:url():startsWith('about:') then
        local url = tab:url()
        if url:byte(#url) == const(string.byte('/')) then url = url:sub(1, #url - 1) end
        tab.attributes.savingHistory = nil
        App.storedHistory:add({title = tab:title(), url = url, time = os.time()})
      end
    end, 1)
  end
end

local drawLoadError = ControlsBasic.drawThumbnailHelper(function (p1, p2, tab) return Controls.drawErrorMessage(p1, p2, tab:loadError(), tab) end,
  function (tab) return tab:loadError().errorText end)
local drawCrash = ControlsBasic.drawThumbnailHelper(function (p1, p2, tab) return Controls.drawErrorMessage(p1, p2, tab:crash(), tab) end,
  function (tab) return tab:crash().errorText end)
local drawLoading = ControlsBasic.drawThumbnailHelper(function (p1, p2, tab) return Controls.drawLoading(p1, p2, tab) end,
  function (tab) return nil end)

App.registerTabFactory(function(url, attributes, extraTweaks)
  local created = WebBrowser({
    backgroundColor = extraTweaks and extraTweaks.backgroundColor 
      or Storage.settings.contentStyle ~= 0 and rgbm.colors.black or rgbm.colors.white,
    size = lastSize,
    dataKey = not attributes.anonymous and '' or nil,
    directRender = not Storage.settings.safeMode, -- compatibility with CEFv1
    softwareRendering = Storage.settings.softwareRendering,
    redirectAudio = Storage.settings.fmodAudio,
    attributes = attributes,
  })

  if Storage.settings.filtering then created:blockURLs(Utils.webFilter) end
  if Storage.settings.doNotTrack then created:setHeaders(Utils.doNotTrackHeaders) end

  if not attributes.anonymous then
    created:collectFormData(PasswordsManager.onFormData)
  end
 
  -- require('src/_FilterTest')(created)   
  
  return created
    :setColorScheme(Storage.settings.contentStyle == 2 and 'dark-auto' or Storage.settings.contentStyle ~= 0 and 'dark' or 'light')
    :onPermissionRequest(function (tab, args, callback)
      if tab ~= App.selectedTab() then
        callback(nil)
      else
        Controls.showPermissionPopup(args.originURL, args.permissions, callback)
      end
    end)
    :onDrawEmpty(function (p1, p2, tab, key)
      if key == 'loadError' then
        drawLoadError(p1, p2, tab)
      elseif key == 'crash' then
        drawCrash(p1, p2, tab)
      elseif key == 'loading' then
        drawLoading(p1, p2, tab)
      else
        ui.drawRectFilled(p1, p2, tab:backgroundColor())
      end
    end)
    :onURLChange(function (tab)
      tab.attributes.bookmarked = table.findFirst(App.storedBookmarks:list(), bookmarkSearch, tab:url())
      updateHistoryEntryLater(tab)
      App.updatedSavedTabInformation(tab)
    end)
    :onTitleChange(function (tab)
      if tab.attributes.loadStart + 15 > os.time() or tab:loading() then
        updateHistoryEntryLater(tab)
        App.updatedSavedTabInformation(tab)
      end
    end)
    :onDownload(Handlers.onDownload)
    :onDownloadStarted(Handlers.onDownloadStarted)
    :onDownloadUpdated(function (tab, item)
      App.storedDownloads:update(item)
    end)
    :onDownloadFinished(Handlers.onDownloadFinished)
    :onFileDialog(WebUI.DefaultHandlers.onFileDialog)
    :onAuthCredentials(Handlers.onAuthCredentials)
    :onJavaScriptDialog(Handlers.onJavaScriptDialog)
    :onContextMenu(Handlers.onContextMenu)
    :onFormResubmission(Handlers.onFormResubmission)
    :onLoadStart(function (tab)
      PasswordsManager.formProcessReset(tab)
      tab.attributes.loadStart = os.time()
      tab.attributes.emptySoFar = false
    end)
    :onLoadEnd(function (tab)
      tab.attributes.emptySoFar = false
      if not tab.attributes.anonymous and not tab:blank() then
        App.storedHistory:add({title = tab:title(), url = tab:url(), time = os.time()})
        PasswordsManager.formProcessFill(tab)
      end
    end)
    :preventNavigation('^(?:acmanager|ts|mumble)://', Handlers.onPreventedNavigation)
    :setBlankHandler(Blanks.blankHandler)
    :navigate(url and url ~= '' and url or WebBrowser.blankURL('newtab'))
    :onPopup(function (tab, data)
      -- Happens when website wants to open a popup
      if data.userGesture and not data.userGesture then -- proceed only if it was a user gesture triggering the event
        App.addTab(data.targetURL)
      end
    end)
    :onOpen(function (tab, data)
      -- Happens when browser thinks it would be a good idea to open a thing in a new tab (like with a middle click)
      if not data.userGesture then return end
      if tab.attributes.windowTab then
        tab:navigate(data.targetURL)
      else
        App.addTab(data.targetURL)
      end
    end)
    :onFoundResult(function (tab, found)
      if tab.attributes.search.active then
        tab.attributes.search.found = found
      end
    end)
    :onVirtualKeyboardRequest(function (tab, data)
      ac.log('Virtual keyboard', data)
    end)
    :onClose(function (browser)
      setTimeout(function () -- adding a frame delay so that tabs removed from App.tabs wouldn’t break unexpected things
        App.finalizeClosingTab(browser)
      end)
    end)
end)

local tooltipPrevious
local tooltipCounter = 0
local uis = ac.getUI()
local mouseButtons = {false, false, false}
local pauseMouseInputs = 0

local function getMouseButtons()
  mouseButtons[1] = uis.isMouseLeftKeyDown
  mouseButtons[2] = uis.isMouseRightKeyDown
  mouseButtons[3] = uis.isMouseMiddleKeyDown
  return mouseButtons
end

---@param tab WebBrowser
---@param size vec2
---@param forceActive boolean
---@param windowFocused boolean
local function browserBlock(tab, size, forceActive, windowFocused)
  local keyboardState
  if tab:interactive() then
    keyboardState = ui.interactiveArea('browser', size)
  else
    ui.dummy(size)
  end

  local hovered = ui.itemHovered()
  if (App.focusNext == 'browser' or Utils.popupJustClosed() and ui.windowFocused(ui.FocusedFlags.RootAndChildWindows)) 
      and not uis.isMouseLeftKeyDown and not tab.attributes.windowTab or uis.mouseWheel ~= 0 and hovered then
    App.focusNext = nil
    ui.activateItem(ui.getLastID())
  end

  App.processZoom(tab)

  -- Report new size to browser if needed:
  local p1, p2 = ui.itemRect()
  local w, h = p2.x - p1.x, p2.y - p1.y
  if w ~= lastSize.x or h ~= lastSize.y then
    lastSize:set(w, h)
  end
  tab:resize(lastSize)
   
  local alive = ui.frameCount() > App.pauseEventsUntil
  local mouseActive
  if pauseMouseInputs <= 0 then
    if alive then
      if windowFocused then
        tab:focus(keyboardState ~= nil) -- update browser focused state
      end
      if keyboardState then
        if not ControlsOverlays.isMouseBlocked(p1, p2, tab) then
          mouseActive = true
          tab:mouseInput(ui.mouseLocalPos():sub(p1):div(lastSize), getMouseButtons(), uis.mouseWheel, uis.ctrlDown)
          -- if ui.mouseDown() then
          --   tab:drawTouches(rgbm.colors.red)
          --   tab:touchInput({ui.mouseLocalPos():sub(p1):div(lastSize)})
          -- else
          --   tab:touchInput({})
          -- end
        end
        tab:keyboard(keyboardState)
      end
    end

    if not mouseActive and tab.attributes.devTools and ui.windowHovered(ui.HoveredFlags.RootAndChildWindows) then
      tab:mouseInput(ui.mouseLocalPos():sub(p1):div(lastSize), false, 0, false)
    end
  else
    pauseMouseInputs = pauseMouseInputs - 1
  end

  local state = tab:draw(p1, p2, true)
  if not state then
    -- Regular webpage is drawn
    if math.abs(tab:scroll().y - tab.attributes.savedScrollY) > 10 then
      App.updatedSavedTabInformation(tab)
    end
    if hovered then
      ui.setMouseCursor(tab:mouseCursor())

      local status = tab:status()
      if status ~= '' and pauseMouseInputs <= 0 then ControlsOverlays.drawPageStatus(p1, p2, status) end

      local t = tab:tooltip()
      if t ~= tooltipPrevious then
        tooltipPrevious = t
        tooltipCounter = 0
      end
      tooltipCounter = tooltipCounter + ui.deltaTime()
      if tooltipCounter > 1 and tooltipPrevious ~= '' then ui.setTooltip(tooltipPrevious) end
    end
    if tab.attributes.search.active and ControlsOverlays.drawPageSearch(p1, p2, tab) then
      forceActive = true
    end
  else
    -- Something else is drawn with IMGUI
    Utils.stopSearch(tab)    
    if App.nativeStatus then
      ControlsOverlays.drawPageStatus(p1, p2, App.nativeStatus)
      App.nativeStatus = nil
    end
  end

  if not keyboardState and (forceActive or windowFocused or not alive) then
    keyboardState = ui.captureKeyboard(true, true)
  end

  if not tab.attributes.windowTab then
    Controls.update(keyboardState ~= nil or not alive)
  end
  if keyboardState then
    Hotkeys.processHotkeys(tab, keyboardState)
  end
end

Pinned.registerBrowserBlockDraw(function (tab, size)
  browserBlock(tab, size, false, ui.windowFocused(ui.FocusedFlags.RootAndChildWindows))
end)

local function drawDevToolsTab(dtab, focus, targetSize)
  local keyboardState = ui.interactiveArea('devTools', targetSize or ui.availableSpace())
  if focus then ui.activateItem(ui.getLastID()) end
  local p1, p2 = ui.itemRect()
  local size = p2:clone():sub(p1)
  dtab:resize(size)

  local alive = ui.frameCount() > App.pauseEventsUntil
  if alive then
    if ui.windowFocused() then
      dtab:focus(keyboardState ~= nil) -- update browser focused state
    end
    if keyboardState then
      dtab:mouseInput(ui.mouseLocalPos():sub(p1):div(size), getMouseButtons(), uis.mouseWheel, uis.ctrlDown)
      dtab:keyboard(keyboardState)
    end
  end

  dtab:draw(p1, p2, true)
  return keyboardState, alive
end

Utils.registerDevToolsDraw(function (tab, focus)
  ui.pushClipRectFullScreen()
  ui.backupCursor()
  ui.setCursor(vec2(ui.windowWidth() - (ui.windowPinned() and 44 or 66), 0))
  ui.pushStyleColor(ui.StyleColor.Button, rgbm.colors.transparent)
  if ui.iconButton(ui.Icons.AppWindow, 22, 5) then
    ac.setWindowOpen('main', true)
    App.selectTab(tab, true)
  end
  if ui.itemHovered() then ui.setTooltip('Return to the tab') end
  ui.popStyleColor()
  ui.popClipRect()
  ui.restoreCursor()

  local dtab = tab.attributes.devTools
  local keyboardState, alive = drawDevToolsTab(dtab, focus)

  if not keyboardState and ui.windowFocused(ui.FocusedFlags.RootAndChildWindows) and not ui.isWindowAppearing() then
    keyboardState = ui.captureKeyboard(true, true)
  end

  Controls.update(keyboardState ~= nil or not alive)
  if keyboardState then
    Hotkeys.processHotkeys(tab, keyboardState)
  end
end)

local splits = ac.storage{x = 0.3, y = 0.5}
local resizingActive
local exclusiveHUDListener
local showExitButton = 0
local exitButtonPos = 0

local function onExclusiveHUD(mode)
  if mode == 'game' or mode == 'replay' then
    local tab = App.selectedTab()
    if tab and (tab:fullscreen() or tab.attributes.fullscreen) then
      ui.setCursor(0)
      Controls.fullscreenBarLayout()
      ui.childWindow('##tab', ui.windowSize(), function ()      
        browserBlock(tab, ui.availableSpace(), false, true)
      end)
      if ui.mousePos().y < 1 then
        showExitButton = 1
      elseif showExitButton > 0 then
        showExitButton = showExitButton - ui.deltaTime()
      end

      exitButtonPos = math.applyLag(exitButtonPos, showExitButton > 0 and 1 or 0, 0.7, ui.deltaTime())
      if exitButtonPos > 0.001 then
        ui.setCursor(vec2(ui.windowWidth() / 2 - 80, math.round(50 * (exitButtonPos - 0.5))))
        ui.setItemAllowOverlap()
        ui.childWindow('##close', vec2(160, 25), function ()
          ui.setItemAllowOverlap()
          ui.setNextItemIcon(ui.Icons.Exit)
          ui.button('Exit fullscreen', vec2(-0.1, -0.1))
          if ui.itemHovered() then
            showExitButton = 1
            pauseMouseInputs = 3
            if ui.itemClicked(ui.MouseButton.Left, true) then
              Utils.toggleFullscreen(tab)
            end
          end
        end)
      end
      return 'finalize'
    end
  end
end

function script.windowMain()
  App.update()

  local theme = Themes.accentOverride()
  if theme then ui.configureStyle(theme, false, false, 1) end

  local windowFocused = ui.windowFocused(ui.FocusedFlags.RootAndChildWindows) or App.focusNext ~= nil
  local tab = App.selectedTab()
  if not tab then
    tab = App.tabs[1]
    if not tab then
      App.addAndSelectTab()
      tab = App.tabs[1]
    end
  end
  tab.attributes.lastFocusTime = os.time()

  -- if not _G.devToolsDebug then
  --   _G.devToolsDebug = true
  --   Utils.openDevTools(tab, true)
  -- end

  if tab:fullscreen() or tab.attributes.fullscreen then
    if not exclusiveHUDListener and Storage.settings.properFullscreen and ui.onExclusiveHUD ~= nil then
      showExitButton, exitButtonPos = 0, 0
      exclusiveHUDListener = ui.onExclusiveHUD(onExclusiveHUD)
    end
    browserBlock(tab, ui.availableSpace(), false, windowFocused)
    ControlsBookmarks.setBookmarksBarVisible(false)
  else
    if exclusiveHUDListener then
      exclusiveHUDListener()
      exclusiveHUDListener = nil
    end

    local showBookmarksBar = #App.storedBookmarks > 0 and (tab:blank() and tab:blank().url == '' or Storage.settings.bookmarksBar)
    ControlsBookmarks.setBookmarksBarVisible(showBookmarksBar)

    ui.beginGroup()
    ui.pushClipRect(0, ui.windowSize(), false)
    local integratedTabs = Storage.settings.integratedTabs and ui.windowWidth() > 400
    if integratedTabs then
      ui.offsetCursorY(-22)
      ui.offsetCursorX(66 + 22)
      ui.beginGroup(ui.availableSpaceX() - (ui.windowPinned() and 22 or 44))
    else
      ui.beginGroup(ui.availableSpaceX())
    end
    Controls.tabsBar()
    ui.endGroup()
    ui.popClipRect()
    local barsHeight = (integratedTabs and 44 or 66) + 8 + (showBookmarksBar and 22 or 0)
    ui.drawRectFilled(vec2(0, integratedTabs and 22 or 44), vec2(ui.windowWidth(), barsHeight), Controls.addressBarBackgroundColor)  
    ui.pushStyleColor(ui.StyleColor.Button, rgbm.colors.transparent)
    ui.pushStyleColor(ui.StyleColor.FrameBg, rgbm.colors.transparent)
    ui.setCursorY(integratedTabs and 22 + 4 or 44 + 4)
    ui.pushID(App.selected)
    Controls.addressBar(tab)
    ui.popID()
    if showBookmarksBar then
      ControlsBookmarks.drawBookmarksBar()
    end
    ui.popStyleColor(2)
    ui.endGroup()
    ui.setCursorY(barsHeight)

    -- Actual browser: interactive area to capture button presses and get focused/unfocused behaviour:
    local devTools = tab.attributes.devTools ---@type WebBrowser?
    if devTools and Storage.settings.developerToolsDock ~= 1 then
      local space = ui.availableSpace()
      local forceActive = ui.itemActive()
      local focus = (tab.attributes.developerToolsFocused or 0) < ui.frameCount()
      tab.attributes.developerToolsFocused = ui.frameCount() + 2
      if Storage.settings.developerToolsDock == 2 then
        drawDevToolsTab(devTools, focus, space * vec2(splits.x, 1))
        ui.sameLine(0, 0)
        ui.button('###', vec2(8, space.y))
        resizingActive = resizingActive and ui.mouseDown() or ui.itemHovered() and ui.mouseClicked()
        if resizingActive then splits.x = math.clamp(splits.x + ui.mouseDelta().x / space.x, 0.01, 0.99) end
        if resizingActive or ui.itemHovered() then ui.setMouseCursor(ui.MouseCursor.ResizeEW) end
        ui.sameLine(0, 0)
        browserBlock(tab, ui.availableSpace(), forceActive, windowFocused)
      elseif Storage.settings.developerToolsDock == 4 then
        browserBlock(tab, space * vec2(1 - splits.x, 1), forceActive, windowFocused)
        ui.sameLine(0, 0)
        ui.button('###', vec2(8, space.y))
        resizingActive = resizingActive and ui.mouseDown() or ui.itemHovered() and ui.mouseClicked()
        if resizingActive then splits.x = math.clamp(splits.x - ui.mouseDelta().x / space.x, 0.01, 0.99) end
        if resizingActive or ui.itemHovered() then ui.setMouseCursor(ui.MouseCursor.ResizeEW) end
        ui.sameLine(0, 0)
        drawDevToolsTab(devTools, focus)
      else
        browserBlock(tab, space * vec2(1, splits.y), forceActive, windowFocused)
        ui.offsetCursorY(-4)
        ui.button('###', vec2(-0.1, 8))
        resizingActive = resizingActive and ui.mouseDown() or ui.itemHovered() and ui.mouseClicked()
        if resizingActive then splits.y = math.clamp(splits.y + ui.mouseDelta().y / space.y, 0.01, 0.99) end
        if resizingActive or ui.itemHovered() then ui.setMouseCursor(ui.MouseCursor.ResizeNS) end
        ui.offsetCursorY(-4)
        drawDevToolsTab(devTools, focus)
      end
    else
      local forceActive = ui.itemActive()
      browserBlock(tab, ui.availableSpace(), forceActive, windowFocused)
    end
  end
end

local function tryUnloadLater()
  setTimeout(function ()
    if Pinned.canUnload() then
      ac.store('.WebBrowser.unloaded', 1)
      ac.unloadApp()
    end
  end, 1)
end

function script.windowMenu()
  App.pauseEvents()
  if ui.menuItem('New tab', false, ui.SelectableFlags.None, 'Ctrl+T') then
    App.addAndSelectTab()
  end
  if #App.closedTabs > 0 then
    if ui.menuItem('Reopen closed tab', false, ui.SelectableFlags.None, 'Ctrl+Shift+T') then
      App.restoreClosedTab()
    end
  end
  ui.separator()
end

function script.onHideWindowMain()
  if not Storage.settings.keepRunning then
    tryUnloadLater()
  end
end

Pinned.onUnload(function ()
  if not Storage.settings.keepRunning then
    tryUnloadLater()
  end
end)

tryUnloadLater()

os.onURL('^(https?)://', function (url)
  if Storage.settings.interceptURLs and not ac.getSim().isInMainMenu then
    ac.setWindowOpen('main', true)
    App.addAndSelectTab(url, nil, nil, nil)
    return true
  else
    return false
  end
end, -1000)
