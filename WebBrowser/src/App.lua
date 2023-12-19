-- App state shared across all the files
local db = require('src/DbBackedStorage')
io.createDir(ac.getFolder(ac.FolderID.ScriptConfig))
db.configure(ac.getFolder(ac.FolderID.ScriptConfig)..'/db_storage.bin')
-- db.configure()

local FaviconsProvider = require('src/FaviconsProvider')
local Storage = require('src/Storage')

local App

---@alias ExtraTabTweaks {backgroundColor: rgbm?}
---@type fun(url: string?, attributes: table?, extraTweaks: ExtraTabTweaks?): WebBrowser
local factoryFn

local ignoreSSLIssuesList, ignoreSSLIssuesRegex = {}, nil

---@type DbDictionaryStorage<string|{url: string, title: string, scroll: number, pinned: boolean?, muted: boolean?}>
local tabsStorage = db.Dictionary('tabs')

---@param tab WebBrowser
local function getTabState(tab)
  tab.attributes.savedScrollY = tab:scroll().y
  return {
    url = tab:url(), 
    title = tab:title(), 
    scroll = tab.attributes.savedScrollY, 
    pinned = tab.attributes.pinned or nil,
    muted = tab:muted() or nil, 
    time = tab.attributes.lastFocusTime
  }
end

local savingNow = false
local function saveTabs()
  if savingNow then return end
  savingNow = true
  setTimeout(function ()
    savingNow = false
    local j = 0
    for i = 1, #App.tabs do
      local tab = App.tabs[i]
      if not tab.attributes.anonymous then
        tab.attributes.saving = false
        j = j + 1
        tab.attributes.saveKey = tostring(j)
        tabsStorage:set(tab.attributes.saveKey, getTabState(tab))
      end
    end
    tabsStorage:set('count', tostring(j))
  end, 0.1)
end

---@param tab WebBrowser
local function updatedSavedTabInformation(tab)
  if tab.attributes.saving then return end
  tab.attributes.saving = true
  setTimeout(function ()
    if not tab.attributes.saving or tab:suspended() or tab:disposed() then return end
    tab.attributes.saving = false
    if tab.attributes.saveKey and tab:url() ~= '' and tonumber(tab.attributes.saveKey) then
      tabsStorage:set(tab.attributes.saveKey, getTabState(tab))
    end
  end, 0.5)
end

local blankFn
local lazyOverrides = {
  loading = function () return false end,
  favicon = function () return nil end,
  url = function (s) return s.__loaded.url end,
  domain = function (s) return WebBrowser.getDomainName(s.__loaded.url) end,
  title = function (s, d) return d and s.__loaded.title == '' and WebBrowser.getDomainName(s.__loaded.url) or s.__loaded.title end,
  muted = function (s) return not not s.__loaded.muted end,
  zoom = function (s) return 0 end,
  playingAudio = function (s) return false end,
  fullscreen = function (s) return false end,
  initializing = function (s) return false end,
  audioPeak = function (s) return 0 end,
  scroll = function (s) return vec2(0, s.__loaded.scroll) or vec2() end,
  setColorScheme = function (s) return s end,
  setBackgroundColor = function (s) return s end,
  restart = function () end,
  settings = function () return {} end,
  loadError = function () return nil end,
  height = function () return 200 end,
  width = function () return 320 end,
  blank = function (s) if not blankFn then blankFn = require('src/Blanks').blankHandlerByResultingURL end return blankFn(s.__loaded.url) end,
  draw = function (s, p1, p2) ui.drawIcon(ui.Icons.Earth, (p1 + p2) / 2 - 16, (p1 + p2) / 2 + 16) end,
  downloads = function () return {} end,
  dispose = function () return {} end,
  tryClose = function (s) 
    App.finalizeClosingTab(s)
  end,
}

---@param tab WebBrowser
local function loadDomainZoom(tab)
  if not tab:url():startsWith('http') then return end
  local domain = tab:domain()
  local saved = App.zoomByDomain:get(domain)
  if saved then
    tab:setZoom(saved.zoom)
    tab.attributes.lastZoom = tab:zoom()
  end
end

local dummyFunction = function (s) return s end
local lazyTabMt = {
  __index = function (o, k)
    if not o.__b then
      local f = lazyOverrides[k]
      if f then return f end
      -- if k == 'awake' and not ac.isWindowOpen('main') then return end
      if not ac.isWindowOpen('main') then
        if k == 'awake' then return dummyFunction end
        error('Should wait further', 2)
      end
      ac.warn('Sleepy tab (%s) initialized because of access to “%s”' % {o:domain(), k})
      o.__b = factoryFn(o.__loaded.url, o.attributes)
      if o.__loaded.scroll and o.__loaded.scroll ~= 0 then o.__b:scrollTo(0, o.__loaded.scroll) end
      if o.__loaded.muted then o.__b:mute(true) end
      loadDomainZoom(o)
      local i = table.indexOf(App.tabs, o)
      if i then
        App.tabs[i] = o.__b
      else
        ac.error('Failed to swap dummy WebBrowser with the real thing')
      end
    end
    return o.__b[k]
  end
}

local function factoryWrapped(url, anonymous, scroll, animateIn, extraTweaks)
  local br = factoryFn(url, {
    anonymous = not not anonymous,
    emptySoFar = true,
    pinned = false,
    search = {text = '', active = false}, 
    savedScrollY = scroll or 0,
    loadStart = os.time(),
    lastFocusTime = os.time(),
    tabOffset = animateIn and -40 or 0,
    fullscreen = false, -- separate from `:fullscreen()` in that browser method is about fullscreen videos, while this one is for F11
    selectedQueue = {}, -- queue of things to execute once the tab becomes selected again
  }, extraTweaks)
  if scroll and scroll ~= 0 then
    br:scrollTo(0, scroll)
  end
  loadDomainZoom(br)
  return br
end

local function createLazyTab(packedState)
  return setmetatable({__b = false, __loaded = packedState, attributes = {
    anonymous = false,
    pinned = packedState.pinned or false,
    search = {text = '', active = false}, 
    savedScrollY = packedState.scroll,
    loadStart = packedState.time or os.time(),
    lastFocusTime = os.time(),
    tabOffset = 0,
    fullscreen = false,
    selectedQueue = {},
  }}, lazyTabMt)
end

ac.onRelease(function ()
  Storage.settings.lastCloseTime = os.time()
end)

local function markSavedPagesAsClosed()
  local c = tonumber(tabsStorage:get('count')) or 0
  local t = Storage.settings.lastCloseTime
  if t < 0 then
    t = os.time()
  end
  for i = 1, c do
    local loaded = tabsStorage:get(tostring(i))
    if type(loaded) == 'table' then
      App.closedTabs:add({ url = loaded.url, title = loaded.title, scroll = loaded.scroll, closedTime = t })
    end
  end
end

local function selectTabByIndex(index)
  local tab = App.tabs[index]
  if not tab then
    index, tab = 1, App.tabs[1]
  end
  App.selected = index
  tabsStorage:set('selected', tostring(index))
  if tab then tab:awake() end
end

local function loadTabs()
  local r, selected = {}, 1
  if Storage.settings.startupMode == 1 then
    markSavedPagesAsClosed()
    r[1] = factoryWrapped(nil, false, nil, false)
    r[1].attributes.saveKey = 1
    tabsStorage:set('count', tostring(1))
  elseif Storage.settings.startupMode == 2 then
    markSavedPagesAsClosed()
    r[1] = factoryWrapped(Storage.settings.homePage ~= '' and Storage.settings.homePage or nil, false, nil, false)
    r[1].attributes.saveKey = 1
    tabsStorage:set('count', tostring(1))
  else
    local c = tonumber(tabsStorage:get('count')) or 0
    for i = 1, c do
      local loaded = tabsStorage:get(tostring(i))
      if type(loaded) == 'table' then
        local loadedTab = createLazyTab(loaded)
        loadedTab.attributes.saveKey = tostring(i)
        r[#r + 1] = loadedTab
      end
    end
    if #r == 0 then
      r[1] = factoryWrapped(nil, false, nil, false)
      r[1].attributes.saveKey = 1
      tabsStorage:set('count', tostring(1))
    end
    selected = math.clamp(tonumber(tabsStorage:get('selected')) or 1, 1, #r)
  end
  return r, selected
end

local lastSelected = -1
local lastZoom = 1
local stopClosingTabs = false
local closedAliveTabs = {} ---@type ClosedTab[]

  ---@param tab WebBrowser
local function goodbyeTab(tab)
  for _, v in ipairs(App.recentDownloads) do
    if v.attributes.browser == tab then
      v.attributes.browser = nil
    end
  end
  tab:dispose()
  setTimeout(collectgarbage)  -- releases MMF when possible
end

local function ensureAliveTabsAreWorthy()
  if #closedAliveTabs < 10 then return end

  for i = 1, #closedAliveTabs do
    local t = closedAliveTabs[i]
    if not t or #closedAliveTabs < 10 then return end
    if not t.tab or not next(t.tab:downloads()) then
      if t.tab then
        goodbyeTab(t.tab)
        ac.log('Disposing closed tab', t.url)
      end
      table.remove(closedAliveTabs, i)
    elseif t.tab then
      ac.log('Leaving closed tab be waiting for download to end', t.url)
    end
  end
end

---@param info ClosedTab
local function trackAliveTab(info)
  if info.tab then
    closedAliveTabs[#closedAliveTabs + 1] = info
  end
  ensureAliveTabsAreWorthy()
end

local function updateAliveTabs()
  for i = 1, #closedAliveTabs do
    local t = closedAliveTabs[i]
    if t then t.tab:sync() end
  end
end

---@param info ClosedTab
local function stopTrackingAliveTab(info)
  table.removeItem(closedAliveTabs, info)
end

App = {
  ---Real limit is closer to 250, but I’m pretty sure things would get way too buggy way before that.
  tabsLimit = 40,

  ---List of active tabs.
  ---@type WebBrowser[]
  tabs = {},

  ---Index of a selected tab.
  selected = 1,

  ---@return WebBrowser
  selectedTab = function ()
    return App.tabs[App.selected]
  end,

  selectTabByIndex = selectTabByIndex,

  ---@param tab WebBrowser
  ---@param focus boolean
  selectTab = function (tab, focus)
    selectTabByIndex(table.indexOf(App.tabs, tab) or App.selected)
    if focus then App.focusNext = 'browser' end
  end,

  ---Focus behaviour.
  ---@type nil|'address'|'browser'|'search'
  focusNext = 'browser',

  ---Pause events from being sent to CEF until this time
  pauseEventsUntil = -1,

  update = function ()
    local nowSelected = App.selected
    local current = App.tabs[nowSelected]
    if not current then
      nowSelected = 1
      selectTabByIndex(1)
      current = App.tabs[1]
    end
    if nowSelected ~= lastSelected then
      if lastSelected ~= -1 then
        local previous = App.tabs[lastSelected]
        if previous ~= current then
          if previous then
            previous:focus(false)
            if previous.attributes.fullscreen then
              if current then current.attributes.fullscreen = true end
              previous.attributes.fullscreen = false
            elseif previous:fullscreen() then
              previous:exitFullscreen()
            end
          end
          if current then
            for i = 1, #current.attributes.selectedQueue do
              current.attributes.selectedQueue[i]()
            end
            table.clear(current.attributes.selectedQueue)
          end
        end
      end
      lastSelected = nowSelected
    end

    updateAliveTabs()
  end,

  ---This function adds a new tab to the list.
  ---@param url string? @URL to navigate. Default value: `'chrome://version/'`.
  ---@param anonymous boolean?
  ---@param scroll number?
  ---@param insertAfter integer|WebBrowser?
  ---@return integer @Index of an added tab.
  addTab = function(url, anonymous, scroll, insertAfter)
    local first = #App.tabs == 0
    saveTabs()
    local created = factoryWrapped(url, anonymous, scroll, not first)
    if ignoreSSLIssuesRegex then
      created:ignoreCertificateErrors(ignoreSSLIssuesRegex)
    end
    if insertAfter then
      local d = type(insertAfter) == 'number' and math.clamp(math.round(insertAfter), 1, #App.tabs) or (table.indexOf(App.tabs, insertAfter) or #App.tabs) + 1
      table.insert(App.tabs, d, created)
      return App.verifyTabPosition(App.tabs[d])
    else
      App.tabs[#App.tabs + 1] = created
      return #App.tabs
    end
  end,

  ---This function adds a new tab to the list.
  ---@param url string? @URL to navigate. Default value: `'chrome://version/'`.
  ---@param anonymous boolean?
  ---@param scroll number?
  ---@param insertAfter integer|WebBrowser?
  ---@return integer @Index of an added tab.
  addAndSelectTab = function (url, anonymous, scroll, insertAfter)
    selectTabByIndex(App.addTab(url, anonymous, scroll, insertAfter))
    App.focusNext = 'browser'
    return App.selected
  end,

---This function creates a new tab. Just, like, creates a new `WebBrowser()` instance, sets URL and then adds some
---listeners and URL filtering.
---@param url string? @URL to navigate. If empty, opens a new tab with starting page.
---@param anonymous boolean?
---@param scroll number?
---@return WebBrowser @Newly created tab.
  createTab = function (url, anonymous, scroll)
    saveTabs()
    return factoryWrapped(url, anonymous, scroll, false)
  end,

---@param url string? @URL to navigate. If empty, opens a new tab with starting page.
---@param params ExtraTabTweaks?
---@return WebBrowser @Newly created tab.
  createWindowTab = function (url, params)
    local r = factoryWrapped(url, false, nil, false, params)
    r.attributes.windowTab = true
    return r
  end,

  ---@param tab WebBrowser
  closeTab = function (tab)
    if tab.attributes.anonymous and next(tab:downloads()) then
      if stopClosingTabs then return end
      stopClosingTabs = true
      -- Anonymous tabs won’t stay in memory some time after closing, so the downloads will be cancelled.
      setTimeout(function ()
        ui.modalPopup('Close tab', 'Closing anonymous tab will cancel active download%. Are you sure?' % (#tab:downloads() == 1 and '' or 's'), function (okPressed)
          if okPressed then
            tab:tryClose()
          end
        end)
        stopClosingTabs = false
      end, 0.3)
      return
    end
    tab:tryClose()
  end,

  ---@param tab WebBrowser
  finalizeClosingTab = function (tab)
    local index = table.indexOf(App.tabs, tab)
    local lazyTab = tab.__loaded ~= nil
    if not tab.attributes.anonymous then
      local closed = {
        url = tab:url(),
        title = tab:title(),
        favicon = FaviconsProvider.get(tab, true),
        scroll = tab:scroll().y,
        position = index,
        closedTime = os.time(),
      }
      if not lazyTab then
        if tab:working() then
          trackAliveTab(closed)
          closed.tab = tab
        else
          ac.log('Instantly disposing closed tab: '..tab:url())
          goodbyeTab(tab)
        end
      end
      App.closedTabs:add(closed)
    else
      goodbyeTab(tab)
    end
    if tab.attributes.onClose then
      tab.attributes.onClose(tab)
    end
    if index then
      table.remove(App.tabs, index)
    end
    if #App.tabs == 0 then
      selectTabByIndex(App.addTab())
    elseif index and App.selected >= index then
      selectTabByIndex(math.max(App.selected - 1, 1))
    end
    App.focusNext = 'browser'
    App.saveTabs()
  end,

  saveTabs = saveTabs,
  updatedSavedTabInformation = updatedSavedTabInformation,

  ---@param tab WebBrowser
  ---@return integer
  verifyTabPosition = function (tab)
    local i = table.indexOf(App.tabs, tab) or 1
    local j = i
    if tab.attributes.pinned then
      while App.tabs[i - 1] and not App.tabs[i - 1].attributes.pinned do
        App.tabs[i - 1].attributes.tabOffset = -40
        App.tabs[i], App.tabs[i - 1], i = App.tabs[i - 1], App.tabs[i], i - 1
      end
    else
      while App.tabs[i + 1] and App.tabs[i + 1].attributes.pinned do
        App.tabs[i + 1].attributes.tabOffset = 40
        App.tabs[i], App.tabs[i + 1], i = App.tabs[i + 1], App.tabs[i], i + 1
      end
    end
    if i ~= j then App.tabs[i].attributes.tabOffset = math.sign(i - j) * -40 end
    if j == App.selected then selectTabByIndex(i) end
    return i
  end,

  pauseEvents = function ()
    App.pauseEventsUntil = os.preciseClock()
  end,

  ---@param fn fun(url: string, attributes: table, extraTweaks: ExtraTabTweaks?): WebBrowser
  registerTabFactory = function (fn)
    factoryFn = fn
    App.tabs, App.selected = loadTabs()
    App.tabs[App.selected]:awake()
  end,

  ---@param fn fun(tab: WebBrowser)
  iterateAllTabs = function (fn)
    for i = 1, #App.tabs do
      fn(App.tabs[i])
    end
    require('src/Pinned').iteratePinnedTabs(fn)
  end,

  ---@param domain string
  ignoreSSLIssues = function(domain)
    if not domain or domain == '' then
      return
    end
    if table.contains(ignoreSSLIssuesList, domain) then
      ac.error('Already added to SSL ignore list', domain)
      return
    end
    table.insert(ignoreSSLIssuesList, domain)
    ignoreSSLIssuesRegex = table.concat(table.map(ignoreSSLIssuesList, function (d)
      return '^https://(?:\\w+\\.)*'..string.replace(d, '.', '\\.')..'(?:$|/)'
    end), '|')
    ac.log('SSL ignore', ignoreSSLIssuesRegex)
    App.iterateAllTabs(function (tab)
      tab:ignoreCertificateErrors(ignoreSSLIssuesRegex)
    end)
  end,

  ---@param url string
  ---@param parentTab WebBrowser?
  selectOrOpen = function (url, parentTab)
    local _, i = table.findFirst(App.tabs, function (item) return item:url() == url end) 
    selectTabByIndex(i or App.addTab(url, nil, nil, parentTab or App.selectedTab()))
  end,

  ---@type WebBrowser.DownloadItem[]
  recentDownloads = {},

  ---@type WebBrowser.DownloadItem[]
  activeDownloads = {},

  ensureAliveTabsAreWorthy = ensureAliveTabsAreWorthy,

  ---@alias ClosedTab {url: string, title: string, favicon?: string, scroll: number, position: integer?, closedTime: integer, tab: WebBrowser?}
  ---@param closed ClosedTab?
  ---@param inBackground boolean?
  restoreClosedTab = function (closed, inBackground)
    local info = closed or App.closedTabs:at(#App.closedTabs)
    if info then
      stopTrackingAliveTab(info)
      App.closedTabs:remove(info)
      if info.tab then
        table.insert(App.tabs, info.position, info.tab)
        info.tab:suspend(false):scrollTo(0, info.scroll)
        if not inBackground then App.selectTab(info.tab, true) end
        saveTabs()
      elseif inBackground then
        App.addTab(info.url, false, info.scroll, info.position)
      else
        App.addAndSelectTab(info.url, false, info.scroll, info.position)
      end
    end
  end,

  canOpenMoreTabs = function ()
    return #App.tabs < App.tabsLimit
  end,

  ---@param info ClosedTab
  dumpClosedTab = function (info)
    if info.tab then
      if not next(info.tab:downloads()) then
        stopTrackingAliveTab(info)
        info.tab:dispose()
      else
        info.tab.attributes.disposeOnceDownloadsAreReady = true
      end
    end
    App.closedTabs:remove(info)
  end,

  ---List of recently closed tabs, newest closed added at the bottom.
  ---@type DbListStorage<ClosedTab>
  closedTabs = db.List('closedTabs', 80, {
    encode = function (d)
      return {t = d.title, s = d.scroll, p = d.position, m = d.closedTime}, d.url
    end,
    decode = function (p, key)
      return {url = key, title = p.t, scroll = p.s, position = p.p, closedTime = p.m}
    end,
    key = true
  }),

  ---@type DbListStorage<WebBrowser.DownloadItem>
  storedDownloads = db.List('downloads', 4000, {
    encode = function (d) ---@param d WebBrowser.DownloadItem
      return {tf = d.attributes.finishedTime, ts = d.attributes.startedTime, d = d.destination, u = d.downloadURL, o = d.originalURL, r = d.receivedBytes, s = (d.state == 'loading' or d.state == 'paused') and 'cancelled' or d.state, t = d.totalBytes}
    end,
    decode = function (p)
      return {attributes = {finishedTime = p.tf, startedTime = p.ts}, currentSpeed = 0, destination = p.d, downloadURL = p.u, originalURL = p.o, receivedBytes = p.r, state = p.s, totalBytes = p.t}
    end
  }),

  ---@type DbListStorage<{title: string, url: string}>
  storedBookmarks = db.List('bookmarks', math.huge),

  ---@type DbListStorage<{title: string, url: string, time: integer}>
  storedHistory = db.List('brhistory', 8000, {
    encode = function (d)
      return {t = d.title, i = d.time}, d.url
    end,
    decode = function (p, key)
      return {title = p.t, url = key, time = p.i}
    end,
    key = true
  }),

  ---@alias PasswordEntry {originURL: string, actionURL: string, title: string, key: string, time: integer, data: table<string, string>}
  ---@type DbDictionaryStorage<PasswordEntry>
  passwords = db.Dictionary('storedPasswords', math.huge),

  ---@type DbDictionaryStorage<{allow: boolean}>
  openAppDoNotAskAgain = db.Dictionary('openAppDoNotAskAgain'),

  ---@type DbDictionaryStorage<{zoom: number}>
  zoomByDomain = db.Dictionary('zoomByDomain'),

  ---@param tab WebBrowser
  processZoom = function (tab)
    if not tab:url():startsWith('http') then return end
    local currentDomain = tab:domain()
    if tab.attributes.lastDomain ~= currentDomain then
      tab.attributes.lastDomain = currentDomain
      local saved = App.zoomByDomain:get(currentDomain)
      if saved then
        tab:setZoom(saved.zoom or 0)
        tab.attributes.lastZoom = tab:zoom()
      end
    elseif tab.attributes.lastZoom ~= tab:zoom() then
      tab.attributes.lastZoom = tab:zoom()
      App.zoomByDomain:set(currentDomain, {zoom = tab:zoom()})
    end
  end
}

return App
