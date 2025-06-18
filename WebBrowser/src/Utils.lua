local App = require('src/App')
local SearchProvider = require('src/SearchProvider')
local Storage = require('src/Storage')

local doNotTrackHeaders = {
  [''] = {
    ['DNT'] = '1',
    ['Sec-GPC'] = '1',
  }
}

---@param day string
---@param time integer
---@return string
local function readableDay(day, time)
  local daysAgo = (os.time() - time) / (24 * 60 * 60)
  if daysAgo < 7 then
    if day == os.date('%Y-%m-%d', os.time()) then
      return 'Today'
    elseif daysAgo < 1 then
      return 'Yesterday'
    else
      return tostring(os.date('%A', time))
    end
  else
    return tostring(os.date('%B %d, %Y', time))
  end  
end

---@param tab WebBrowser
local function openFromFile(tab)
  os.openFileDialog({
    defaultFolder = ac.getFolder(ac.FolderID.Documents),
    fileTypes = {
      {
        name = 'Webpages',
        mask = '*.htm;*.html'
      }
    },
    addAllFilesFileType = true,
  }, function (err, filename)
    if filename then
      tab:navigate('file:///'..filename:replace('\\', '/'))
    end
  end)
end

---@param tab WebBrowser
local function saveWebpage(tab)
  tab:getPageHTMLAsync(function (reply)
    if reply then
      os.saveFileDialog({
        defaultFolder = ac.getFolder(ac.FolderID.Documents),
        fileTypes = {
          {
            name = 'Webpages',
            mask = '*.htm;*.html'
          }
        },
        defaultExtension = 'html',
        addAllFilesFileType = true
      }, function (err, filename)
        if filename then
          io.save(filename, reply)
        end
      end)
    end
  end)
end

---@param tab WebBrowser
local function toggleFullscreen(tab)
  if tab:fullscreen() or tab.attributes.fullscreen then
    tab:exitFullscreen()
    tab.attributes.fullscreen = false
  else
    tab.attributes.fullscreen = not tab.attributes.fullscreen
    if tab.attributes.fullscreen then
      ui.toast(ui.Icons.Earth, 'Switched to wider mode, press F11 again to switch back', function ()
        tab.attributes.fullscreen = false
      end)
    end
  end  
  App.focusNext = 'browser'
end

---@param tab WebBrowser
---@param findNext boolean
---@param findBack boolean
---@param closeOnly boolean?
local function toggleSearch(tab, findNext, findBack, closeOnly)
  if closeOnly and not tab.attributes.search.active then return end
  if not findNext or not tab.attributes.search.active then
    tab.attributes.search.found = nil
    if tab.attributes.search.active then
      tab:find(nil, true, false, false)
      tab.attributes.search.active = false
      return
    end
    tab.attributes.search.active = true
  end
  if #tab.attributes.search.text > 0 then
    tab:find(tab.attributes.search.text, not findBack, tab.attributes.search.case, findNext)
  end
  App.focusNext = 'search'
end

---@param tab WebBrowser
local function stopSearch(tab)
  if tab.attributes.search.active then
    tab:find(nil, true, false, false)
    tab.attributes.search.active = false
    tab.attributes.search.found = nil
  end
end

local function popupToggle()
  local state = 0
  return {
    toggle = function (active)
      if not active or state < ui.frameCount() then
        state = 0
        return false
      end
      state = -1
      return true
    end,
    update = function ()
      if state == -1 then
        ui.closePopup()
      else
        state = ui.frameCount() + 1
      end
    end
  }
end

local lastPopupFrame = -1

local function noteActivePopup()
  lastPopupFrame = ui.frameCount() + 4
end

local function anyActivePopup()
  return lastPopupFrame >= ui.frameCount()
end

local function popupJustClosed()
  return lastPopupFrame == ui.frameCount()
end

local function maxPopupHeight()
  return ac.getUI().windowSize.y * 0.7
end

---@param callback fun()
---@param params {onClose: fun()?, position: vec2?, pivot: vec2?, size: vec2|{min: vec2?, max: vec2?}?, padding: vec2?, flags: ui.WindowFlags?}?
local function popup(callback, params)
  App.pauseEvents()
  local m = 0.7
  ui.popup(function ()
    if ui.isWindowAppearing() then m = 0.7 else m = math.applyLag(m, 1, 0.6, ui.deltaTime()) end
    App.pauseEvents()
    noteActivePopup()
    local s = vec2(0, ui.getScrollY())
    ui.pushClipRect(s, ui.windowSize():add(s), false)
    callback()
    ui.popClipRect()
    if ui.keyPressed(ui.Key.Escape) then
      ui.closePopup()
    end
    ui.setMaxCursorY(ui.getMaxCursorY() * m)
  end, table.assign({size = {max = vec2(math.huge, maxPopupHeight())}},  params))
end

local function uniquePopup()
  local tgl = popupToggle()
  ---@param toggle boolean
  ---@param callback fun()
  ---@param params {onClose: fun()?, position: vec2?, pivot: vec2?, size: vec2|{min: vec2?, max: vec2?}?, padding: vec2?, flags: ui.WindowFlags?}
  return function (toggle, callback, params)
    if tgl.toggle(toggle) then return end
  
    App.pauseEvents()
    local m = 0.7
    ui.popup(function ()
      if ui.isWindowAppearing() then m = 0.7 else m = math.applyLag(m, 1, 0.6, ui.deltaTime()) end
      tgl.update()
      App.pauseEvents()
      noteActivePopup()
      local s = vec2(0, ui.getScrollY())
      ui.pushClipRect(s, ui.windowSize():add(s), false)
      callback()
      ui.popClipRect()
      if ui.keyPressed(ui.Key.Escape) then
        ui.closePopup()
      end
      ui.setMaxCursorY(ui.getMaxCursorY() * m)
    end, table.assign({size = {max = vec2(math.huge, maxPopupHeight())}},  params))
  end
end

---@param selected string
---@return string @Label
---@return string @URL
local function searchSelectedHelper(selected)
  local s = selected:reggsub('\\s+', ' '):trim()
  local u = s
  if #s > 20 then
    u = string.sub(s, 1, 20)
    s = u:trim()..'…'
  end
  return string.format('Search for %s', s), SearchProvider.url(u)
end

local function fmtPluralizing(fmt, value)
  value = math.round(value)
  return string.format(fmt, value, value == 1 and '' or 's')
end

local function readableAge(finishedTime)
  local timePassed = os.time() - finishedTime
  if timePassed < 60 then
    return fmtPluralizing('%.0f second%s ago', timePassed)
  elseif timePassed < 60 * 60 then
    return fmtPluralizing('%.0f minute%s ago', (timePassed / 60))
  elseif timePassed < 24 * 60 * 60 then
    return fmtPluralizing('%.0f hour%s ago', (timePassed / (60 * 60)))
  elseif timePassed < 7 * 24 * 60 * 60 then
    return fmtPluralizing('%.0f day%s ago', (timePassed / (24 * 60 * 60)))
  else
    return fmtPluralizing('%.0f week%s ago', (timePassed / (7 * 24 * 60 * 60)))
  end
end

local function readableETA(time)
  if time < 60 then
    return fmtPluralizing('%.0f second%s left', time)
  elseif time < 60 * 60 then
    return fmtPluralizing('%.0f minute%s left', (time / 60))
  elseif time < 24 * 60 * 60 then
    return fmtPluralizing('%.0f hour%s left', (time / (60 * 60)))
  elseif time < 7 * 24 * 60 * 60 then
    return fmtPluralizing('%.0f day%s left', (time / (24 * 60 * 60)))
  elseif time < math.huge then
    return fmtPluralizing('%.0f week%s left', (time / (7 * 24 * 60 * 60)))
  else
    return 'too long left'
  end
end

---@param filename string
---@param callback fun(color: rgbm?)
local function estimateAccentColor(filename, callback)
  local c1, c2 = ui.ExtraCanvas(64):copyFrom(filename), ui.ExtraCanvas(8)
  c2:updateWithShader({
    textures = {txIn = c1},
    shader = [[float4 main(PS_IN pin){
float4 s = 0;for (int x = -4; x < 4; ++x)for (int y = -4; y < 4; ++y){
float4 c = txIn.Load(int3(pin.PosH.xy * 8 + float2(x, y), 0));
float a = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
s += float4(c.rgb * saturate(a * 20 - 0.5), 1) * (c.w * (dot(c.rgb, 1) + pow(a, 2) * 1000));
}return s/s.w;}]]
  })
  c2:accessData(function (err, data)
    if not data then callback(nil) return end
    local ret, can, sat = rgbm(), rgbm(), -1
    for y = 0, 7 do
      for x = 0, 7 do
        data:colorTo(can, x, y)
        local s = can.rgb:saturation()
        if s > sat then ret, can, sat = can, ret, s end
      end
    end

    ac.debug('Accent color', ret.rgb)
    if ret.rgb:value() < 0.2 then callback(nil) return end
    ret.rgb:scale(3 - ret.rgb:value() ^ 0.5 * 2)
    ret.rgb:adjustSaturation(3 - sat ^ 0.5 * 2) 
    callback(ret)
  end)
  c1:dispose()
  c2:dispose()
end

local function openURLInSystemBrowser(url)
  os.openURL(url, false)
end

local devToolsDraw
local devToolsOpened = 0

---@param tab WebBrowser
---@param toggle boolean|'reuse'|'close'
local function openDevTools(tab, toggle)
  if not WebBrowser.devToolsTabSupported() then
    tab:devToolsPopup()
    return
  end
  if  tab.attributes.devTools and toggle ~= 'reuse' or toggle == 'close' then
    if toggle then
      if tab.attributes.devTools then
        setTimeout(WebBrowser.dispose ^ tab.attributes.devTools)
        tab.attributes.devTools = nil
      end
      App.focusNext = 'browser'
    else
      tab.attributes.devToolsFocus = true
    end
  elseif Storage.settings.developerTools and not tab.attributes.windowTab and not tab:blank() and not tab:loadError() and not tab:crash() or toggle == 'reuse' then
    if not tab.attributes.devTools then
      tab.attributes.devTools = tab:devTools({size = vec2(640, 480)}, tab.attributes.contextMenuMousePosition or tab:mousePosition())
        :onReceive('devtools', function (browser, data)
          if data == 'close' then
            openDevTools(tab, 'close')
          end
        end)
        :onLoadEnd(function (browser)
          setTimeout(function ()
            browser:execute([[
              function $$$(o,n=document.body){const t=[],c=n=>{if(n.nodeType!==Node.ELEMENT_NODE)return;n.matches(o)&&t.push(n);const e=n.children;if(e.length)
              for(const o of e)c(o);const s=n.shadowRoot;if(s){const o=s.children;for(const n of o)c(n)}};return c(n),t}
              $$$('.close-devtools').forEach(x => {
                x.classList.remove('hidden');
                x.style.position = 'relative';
                x.addEventListener('click', () => AC.sendAsync('devtools', 'close'), true);
              });]])
          end, 0.5)
        end)
        
    end

    if Storage.settings.developerToolsDock == 1 then
      devToolsOpened = devToolsOpened + 1
      ui.popup(function ()
        local focus = ui.isWindowAppearing() or tab.attributes.devToolsFocus
        if focus then
          ui.bringWindowToFront()
          tab.attributes.devToolsFocus = false
        end
    
        if not tab.attributes.devTools or Storage.settings.developerToolsDock ~= 1 then
          ui.closePopup()
          return
        end

        if ui.windowFocused(ui.FocusedFlags.RootAndChildWindows) then
          Storage.settings.devToolsPosition = ui.windowPos()
          Storage.settings.devToolsSize = ui.windowSize()
        end

        devToolsDraw(tab, focus)
      end, {
        title = 'Developer tools - '..tab:url(),
        position = Storage.settings.devToolsPosition ~= vec2(-1, -1) and Storage.settings.devToolsPosition + devToolsOpened * 8 or nil,
        size = {initial = Storage.settings.devToolsSize, min = vec2(120, 140)},
        padding = vec2(),
        onClose = function ()
          devToolsOpened = devToolsOpened - 1
          if tab.attributes.devTools and Storage.settings.developerToolsDock == 1 then
            tab.attributes.devTools:dispose()
            tab.attributes.devTools = nil
          end
        end
      })
    end
  end
end

return {
  Paths = {
    -- https://learn.microsoft.com/en-us/dotnet/desktop/winforms/controls/known-folder-guids-for-file-dialog-custom-places
    downloads = function () return ac.getFolder('{374DE290-123F-4565-9164-39C4925E467B}') end,
    pictures = function () return ac.getFolder('{33E28130-4E1E-4676-835A-98395C3BC3BB}') end,
  },
  webFilter = WebBrowser.adsFilter(),
  doNotTrackHeaders = doNotTrackHeaders,
  readableDay = readableDay,
  openFromFile = openFromFile,
  saveWebpage = saveWebpage,
  toggleFullscreen = toggleFullscreen,
  toggleSearch = toggleSearch,
  stopSearch = stopSearch,
  popupToggle = popupToggle,
  popup = popup,
  uniquePopup = uniquePopup,
  searchSelectedHelper = searchSelectedHelper,
  readableAge = readableAge,
  readableETA = readableETA,
  noteActivePopup = noteActivePopup,
  anyActivePopup = anyActivePopup,
  popupJustClosed = popupJustClosed,
  maxPopupHeight = maxPopupHeight,
  estimateAccentColor = estimateAccentColor,
  openURLInSystemBrowser = openURLInSystemBrowser,
  openDevTools = openDevTools,

  ---@param fn fun(tab: WebBrowser, focus: boolean)
  registerDevToolsDraw = function (fn)
    devToolsDraw = fn
  end,
}