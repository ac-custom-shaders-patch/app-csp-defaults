local App = require('src/App')
local Controls = require('src/Controls')
local Storage = require('src/Storage')
local Utils = require('src/Utils')

local Ctrl = const(1)
local Shift = const(2)
local Alt = const(4)
local uis = ac.getUI()

---@type table<integer, table<integer, fun(tab: WebBrowser)>>
local browserHotkeys = {
  [ui.KeyIndex.Escape] = {
    [0] = function (tab)
      Utils.toggleSearch(tab, false, false, true)
    end,
  },
  [ui.KeyIndex.Left] = {
    [Alt] = function (tab) tab:navigate('back') end,
  },
  [ui.KeyIndex.Right] = {
    [Alt] = function (tab) tab:navigate('forward') end,
  },
  [ui.KeyIndex.OemMinus] = {
    [Ctrl] = function (tab) tab:setZoom(tab:zoom() - 0.5) end
  },
  [ui.KeyIndex.OemPlus] = {
    [Ctrl] = function (tab) tab:setZoom(tab:zoom() + 0.5) end
  },
  [ui.KeyIndex.Tab] = {
    [Ctrl] = function () App.selectTabByIndex(App.selected % #App.tabs + 1) end,
    [Ctrl + Shift] = function () App.selectTabByIndex((App.selected + (#App.tabs - 2)) % #App.tabs + 1) end,
  },
  [ui.KeyIndex.F3] = {
    [0] = function (tab)
      Utils.toggleSearch(tab, true, false, false)
    end,
    [Shift] = function (tab)
      Utils.toggleSearch(tab, true, true, false)
    end
  },
  [ui.KeyIndex.F4] = {
    [Ctrl] = function (tab) App.closeTab(tab) end
  },
  [ui.KeyIndex.F5] = {
    [0] = function (tab) tab:reload() end,
    [Ctrl] = function (tab) tab:reload(true) end
  },
  [ui.KeyIndex.F6] = {
    [0] = function (tab) App.focusNext = 'address' end
  },
  [ui.KeyIndex.F11] = {
    [0] = Utils.toggleFullscreen,
  },
  [ui.KeyIndex.F12] = {
    [0] = function (tab) Utils.openDevTools(tab, true) end,
  },
  [ui.KeyIndex.A] = {
    [Ctrl + Shift] = function (tab) Controls.showTabsMenu(true) end
  },
  [ui.KeyIndex.B] = {
    [Ctrl + Shift] = function (tab) Storage.settings.bookmarksBar = not Storage.settings.bookmarksBar end
  },
  [ui.KeyIndex.D] = {
    [Ctrl] = function (tab) Controls.showBookmarksMenu(true) end
  },
  [ui.KeyIndex.E] = {
    [Ctrl] = function (tab) App.focusNext, App.focusOnSearch = 'address', true end
  },
  [ui.KeyIndex.F] = {
    [Ctrl] = function (tab)
      Utils.toggleSearch(tab, false, false, false)
    end,
    [Alt] = function (tab)
      Controls.showAppMenu(true)
    end,
  },
  [ui.KeyIndex.G] = {
    [Ctrl] = function (tab)
      Utils.toggleSearch(tab, true, false, false)
    end,
    [Ctrl + Shift] = function (tab)
      Utils.toggleSearch(tab, true, true, false)
    end
  },
  [ui.KeyIndex.H] = {
    [Ctrl] = function (tab) App.selectOrOpen('about:history') end,
  },
  [ui.KeyIndex.J] = {
    [Ctrl] = function (tab) Controls.showDownloadsMenu(true) end,
    [Ctrl + Shift] = function (tab) App.selectOrOpen('about:downloads') end,
  },
  [ui.KeyIndex.K] = {
    [Ctrl] = function (tab) App.focusNext, App.focusOnSearch = 'address', true end
  },
  [ui.KeyIndex.L] = {
    [Ctrl] = function (tab) App.focusNext = 'address' end
  },
  [ui.KeyIndex.N] = {
    [Ctrl] = function () if App.canOpenMoreTabs() then App.addAndSelectTab() end end,
    [Ctrl + Shift] = function () if App.canOpenMoreTabs() then App.addAndSelectTab(nil, true) end end
  },
  [ui.KeyIndex.O] = {
    [Ctrl] = function (tab) Utils.openFromFile(tab) end,
    [Ctrl + Shift] = function (tab) App.selectOrOpen('about:bookmarks') end,
  },
  [ui.KeyIndex.P] = {
    [Ctrl] = function (tab) tab:command('print') end,
  },
  [ui.KeyIndex.R] = {
    [Ctrl] = function (tab) tab:reload() end,
    [Ctrl + Shift] = function (tab) tab:reload(true) end
  },
  [ui.KeyIndex.S] = {
    [Ctrl] = function (tab) Utils.saveWebpage(tab) end,
  },
  [ui.KeyIndex.T] = {
    [Ctrl] = function () if App.canOpenMoreTabs() then App.addAndSelectTab() end end,
    [Ctrl + Shift] = function () if App.canOpenMoreTabs() then App.restoreClosedTab() end end
  },
  [ui.KeyIndex.U] = {
    [Ctrl] = function (tab) if not App.selectedTab():blank() then App.addAndSelectTab(WebBrowser.sourceURL(tab:url()), nil, nil, tab) end end
  },
  [ui.KeyIndex.W] = {
    [Ctrl] = function (tab) App.closeTab(tab) end
  },
}

for i = 1, 9 do
  browserHotkeys[ui.KeyIndex.D1 + (i - 1)] = {
    [Ctrl] = function (tab) if i <= #App.tabs or i == 9 then App.selectTabByIndex(math.min(i, #App.tabs)) end end
  }
end

---@param tab WebBrowser
---@param keyboardState ui.CapturedKeyboard
local function processHotkeys(tab, keyboardState)
  -- Instead of relying on tab:shortcuts(), let’s implement a new approach which would support more shortcuts in a more
  -- organized way. Most of use cases won’t need that many shortcuts though.

  if ui.mouseClicked(ui.MouseButton.Extra1) then
    tab:navigate('back')
  elseif ui.mouseClicked(ui.MouseButton.Extra2) then
    tab:navigate('forward')
  end

  local m = (uis.ctrlDown and 1 or 0) + (uis.shiftDown and 2 or 0) + (uis.altDown and 4 or 0)
  for i = 0, keyboardState.pressedCount - 1 do
    local k = browserHotkeys[keyboardState.pressed[i]]
    if k ~= nil then
      local f = k[m]
      if f then
        f(tab)
      end
    end
  end
end

return {
  processHotkeys = processHotkeys
}
