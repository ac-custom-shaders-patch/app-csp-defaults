local App = require('src/App')
local ControlsBasic = require('src/ControlsBasic')
local ControlsInputFeatures = require('src/ControlsInputFeatures')
local SearchProvider = require('src/SearchProvider')
local FaviconsProvider = require('src/FaviconsProvider')
local Pinned = require('src/Pinned')
local Storage = require('src/Storage')
local Themes = require('src/Themes')

local ControlsBookmarks = require('src/ControlsBookmarks')
local ControlsHistory = require('src/ControlsHistory')
local ControlsDownloads = require('src/ControlsDownloads')
local ControlsSettings = require('src/ControlsSettings')

local function focusBrowser()
  App.focusNext = 'browser'
end

local uv1 = vec2()
local uv2 = vec2(1, 1)
local version

local searchSuggestions = ControlsInputFeatures.inputSuggestions(function (query, callback)
  SearchProvider.suggestions(query, callback)
end, true)

---@param p1 vec2
---@param p2 vec2
---@param tab WebBrowser
local function drawAboutTab(p1, p2, tab)
  if not version then
    version = ac.INIConfig.load(__dirname..'\\manifest.ini', ac.INIFormat.Extended):get('ABOUT', 'VERSION', '1.0')
  end
  Themes.drawThemedBg(p1, p2)
  ui.beginOutline()
  local p = p1 + (p1 + p2) * vec2(0.25, 0.25)
  ui.drawImage('gui/ac_logo_0.png', p - 64, p + 64)
  ui.drawImage('gui/ac_logo_1.png', p - 64, p + 64)
  ui.pushFont(ui.Font.Huge)
  local x = ui.drawText('Web Browser', p + vec2(100, -72))
  ui.popFont()
  ui.pushFont(ui.Font.Title)
  ui.drawText('v'..version, vec2(x + 8, p.y - 40), rgbm(1, 1, 1, 0.7))
  ui.drawText('Made possible by OBS Project.', p + vec2(100, 0))
  ui.popFont()
  ui.endOutline(rgbm(0, 0, 0, 0.1), 2)
end

---@param p1 vec2
---@param p2 vec2
---@param tab WebBrowser
local function drawNewTab(p1, p2, tab)
  local bgFix = not Storage.settings.bookmarksBar and ControlsBookmarks.isBookmarksBarVisible()
  if bgFix then
    ui.pushClipRect(p1, p2, true)
    p1 = vec2(p1.x, p1.y - 22)
  end

  if tab.attributes.anonymous then
    ui.setShadingOffset(0, 0, 0, 1)
    ui.drawRectFilled(p1, p2, rgbm.colors.gray)
    ui.drawImage('dynamic::screen', p1, p2, rgbm.colors.black, uv1, uv2, ui.ImageFit.Fill)
    ui.resetShadingOffset()
    -- ui.drawImage('dynamic::screen', p1, p2, ColSaturationHint, 0, 1, ui.ImageFit.Fill)
    ui.drawRectFilledMultiColor(p1, p2, rgbm.colors.transparent, rgbm.colors.transparent, rgbm.colors.black, rgbm.colors.black)
    if ui.rectHovered(p1, p2, true) and ui.windowHovered() and ui.mouseReleased(ui.MouseButton.Right) then
      tab:triggerContextMenu()
    end
  else
    Themes.drawThemedBg(p1, p2)
  end

  ui.drawImage('gui/ac_logo_0.png', (p1 + p2) / 2 - 64, (p1 + p2) / 2 + 64)
  ui.drawImage('gui/ac_logo_1.png', (p1 + p2) / 2 - 64, (p1 + p2) / 2 + 64)

  if p2.y - p1.y > 400 and p2.x - p1.x > 440 then
    if not tab.attributes.randomID then
      tab.attributes.randomID = math.randomKey()
    end
    ui.pushID(tab.attributes.randomID)
    local s0 = (p1 + p2) / 2 + vec2(-200, 100)
    ui.setCursor(s0)
    local _, enterPressed
    ui.pushFont(ui.Font.Title)
    ui.pushStyleColor(ui.StyleColor.FrameBg, rgbm.colors.transparent)
    ui.pushStyleColor(ui.StyleColor.Button, rgbm.colors.transparent)
    ui.pushStyleColor(ui.StyleColor.ButtonHovered, rgbm.colors.transparent)
    ui.pushStyleColor(ui.StyleColor.ButtonActive, rgbm.colors.transparent)
    local needsFocus = tab.attributes.searchQuery == nil
    local f0 = s0 - 4
    local f1 = s0 + vec2(400 + 4, 32 + 4)
    ui.setItemAllowOverlap()
    ui.setNextItemWidth(400 - 80)
    tab.attributes.searchQuery, _, enterPressed = ui.inputText('##search', tab.attributes.searchQuery or '')
    if needsFocus and not ui.isAnyMouseDown() then ui.setKeyboardFocusHere(-1) end
    ControlsInputFeatures.inputContextMenu(tab)

    local suggestionsOpened, forceSearch
    if not tab.attributes.anonymous then
      local selected
      selected, suggestionsOpened = searchSuggestions(tab.attributes.searchQuery, enterPressed)
      if selected then
        tab.attributes.searchQuery = selected
        enterPressed = true
        forceSearch = true
      end
    end

    ui.setCursor(f1 - vec2(40, 40))
    if ui.iconButton('###search', vec2(40, 40), 12) then enterPressed = true end
    if ui.itemHovered() or ui.itemActive() or #tab.attributes.searchQuery > 0 then
      ui.drawRectFilled(f1 - vec2(40, 40), f1, ui.itemActive() and rgbm.colors.white or Themes.accentOverride() or ui.styleColor(ui.StyleColor.ButtonActive, 0), 4, suggestionsOpened and ui.CornerFlags.TopRight or ui.CornerFlags.Right)
    end
    ui.addIcon(ui.Icons.Search, 16, 0.5, ui.itemActive() and rgbm.colors.black or rgbm.colors.white)

    if #tab.attributes.searchQuery > 0 then
      ui.setCursor(f1 - vec2(80, 40))
      if ui.iconButton(ui.Icons.Cancel, vec2(40, 40), 14, true, ui.ButtonFlags.PressedOnClick) then
        tab.attributes.searchQuery = nil
      end
      if ui.itemHovered() or ui.itemActive() then
        ui.drawRectFilled(f1 - vec2(80, 40), f1 - vec2(40, 0), rgbm(1, 1, 1, ui.itemActive() and 0.2 or 0.1), 4, suggestionsOpened and ui.CornerFlags.TopRight or ui.CornerFlags.Right)
      end
    end

    ui.drawRect(f0, f1, rgbm.colors.white, 4, suggestionsOpened and ui.CornerFlags.Top)
    ui.popStyleColor(4)
    ui.popFont()
    if enterPressed then
      tab:navigate(SearchProvider.userInputToURL(tab.attributes.searchQuery, forceSearch))
      tab.attributes.searchQuery = nil
    end
    ui.popID()
  end

  if bgFix then
    ui.popClipRect()
  end
end

-- local snapshotURL
-- local lastCanvas ---@type ui.ExtraCanvas
-- local function drawResizeHelper(fn)
--   ---@type fun(p1: vec2, p2: vec2, tab: WebBrowser)
--   return function (p1, p2, tab)
--     local w = p2.x - p1.x
--     if w ~= tab:width() then
--       local newSize = vec2(tab:width(), math.round(tab:width() * (p2.y - p1.y) / (p2.x - p1.x)))
--       if not lastCanvas or lastCanvas:size() ~= newSize then
--         if lastCanvas then lastCanvas:dispose() end
--         lastCanvas, snapshotURL = ui.ExtraCanvas(newSize, 4), nil
--       end
--       if snapshotURL ~= tab:url() then
--         lastCanvas:update(function ()
--           local theme = Themes.accentOverride()
--           if theme then ui.configureStyle(theme, false, false, 1) end
--           fn(vec2(), newSize, tab)
--         end)
--       end
--       ui.drawImage(lastCanvas, p1, p2)
--     else
--       fn(p1, p2, tab)
--     end
--   end
-- end

local blankOnDrawState = function (tab) return tab:url() end

---Used for drawing some tabs on Lua side (shows up faster this way).
---@type table<string, WebBrowser.BlankOverride>
local Blanks = {
  newTab = {
    title = 'New Tab',
    url = '',
    favicon = ui.Icons.Skip,
    onDraw = ControlsBasic.drawThumbnailHelper(drawNewTab, blankOnDrawState),
    onRelease = focusBrowser,
  },
  incognitoTab = {
    title = 'New Incognito Tab',
    url = '',
    favicon = ui.Icons.TopHat,
    onDraw = ControlsBasic.drawThumbnailHelper(drawNewTab, blankOnDrawState),
    onRelease = focusBrowser,
  },
  downloads = {
    title = 'Downloads',
    url = 'about:downloads',
    favicon = ui.Icons.ArrowDown,
    onDraw = ControlsBasic.drawThumbnailHelper(ControlsDownloads.drawDownloadsTab, blankOnDrawState),
    onRelease = focusBrowser,
  },
  bookmarks = {
    title = 'Bookmarks',
    url = 'about:bookmarks',
    favicon = ui.Icons.StarEmpty,
    onDraw = ControlsBasic.drawThumbnailHelper(ControlsBookmarks.drawBookmarksTab, blankOnDrawState),
    onRelease = focusBrowser,
  },
  history = {
    title = 'History',
    url = 'about:history',
    favicon = ui.Icons.TimeRewind,
    onDraw = ControlsBasic.drawThumbnailHelper(ControlsHistory.drawHistoryTab, blankOnDrawState),
    onRelease = focusBrowser,
  },
  apps = {
    title = 'Apps',
    url = 'about:apps',
    favicon = ui.Icons.Apps,
    onDraw = ControlsBasic.drawThumbnailHelper(Pinned.drawAppsTab, blankOnDrawState),
    onRelease = focusBrowser,
  },
  about = {
    title = 'About',
    url = 'about:about',
    favicon = ui.Icons.Info,
    onDraw = ControlsBasic.drawThumbnailHelper(drawAboutTab, blankOnDrawState),
    onRelease = focusBrowser
  },
}

---@param url string
local function settingsCategoryName(url)
  if #url > 8 then
    local e = url:sub(10)
    return 'Settings - '..e:sub(1, 1):upper()..e:sub(2)
  else
    return 'Settings'
  end
end

---@param tab WebBrowser?
---@param url string?
---@return WebBrowser.BlankOverride?
local function blankHandler(tab, url)
  if not url then return nil end
  if url:startsWith('newtab') then
    return tab and tab.attributes.anonymous and Blanks.incognitoTab or Blanks.newTab
  end
  if url:startsWith('downloads') then
    return Blanks.downloads
  end
  if url:startsWith('bookmarks') then
    return Blanks.bookmarks
  end
  if url:startsWith('history') then
    return Blanks.history
  end
  if url:startsWith('apps') then
    return Blanks.apps
  end
  if url:startsWith('about') then
    return Blanks.about
  end
  if url:startsWith('settings') then
    return {
      title = settingsCategoryName(url),
      url = 'about:' .. url,
      favicon = ui.Icons.Settings,
      onDraw = ControlsBasic.drawThumbnailHelper(ControlsSettings.drawSettingsTab, blankOnDrawState),
      onRelease = focusBrowser
    }
  end
end

local function blankHandlerByResultingURL(url)
  if url == '' then return Blanks.newTab end
  if url:startsWith('about:') then
    local w = url:sub(7):match('%w+')
    return Blanks[w]
  end
  return nil
end

FaviconsProvider.setBlankProvider(function (url)
  if url == '' then return ui.Icons.Skip end
  local blank = blankHandler(nil, WebBrowser.getBlankID(url))
  return blank and blank.favicon
end)

return {
  bookmarksBarShown = false,
  blankHandler = blankHandler,
  blankHandlerByResultingURL = blankHandlerByResultingURL,
}
