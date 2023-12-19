local App = require('src/App')
local Utils = require('src/Utils')
local ControlsBasic = require('src/ControlsBasic')
local FaviconsProvider = require('src/FaviconsProvider')
local SearchProvider = require('src/SearchProvider')

local vAlign = vec2(0, 0.5)
local function findTabByURL(item, _, url) return item:url() == url end

local function stylizeText(result, input, text, highlight, favicon)
  if not text then
    text = result
  end
  local bolds = {}
  local s, l = 1, #input
  for _ = 1, 3 do
    local x = text:findIgnoreCase(input, s)
    if not x then break end
    bolds[#bolds + 1] = {x, x + l - 1}
    s = x + l
  end
  return {
    text = result,
    stylized = text,
    highlight = highlight,
    bolds = bolds,
    favicon = favicon
  }
end

---@param v string
---@param input string
---@return table
local function parseSuggestionItem(v, input)
  if v:byte(1) == 1 then
    local url = v:sub(2)
    local tab = table.findFirst(App.tabs, findTabByURL, url)
    if tab then
      return stylizeText(url, input, string.format('%s • %s • switch to tab', tab:title(), url), #tab:title(), tab)
    else
      ac.warn('Tab is missing: '..url)
      return stylizeText(url, input)
    end
  elseif v:byte(1) == 2 then
    local pieces = v:split('\2', 3, false, false)
    if pieces[3] == '' then pieces[3] = WebBrowser.getDomainName(pieces[2]) end
    return stylizeText(pieces[2], input, string.format('%s • %s • bookmark', pieces[3], pieces[2]), #pieces[3], true)
  elseif v:byte(1) == 3 then
    local pieces = v:split('\3', 3, false, false)
    if pieces[3] == '' then pieces[3] = WebBrowser.getDomainName(pieces[2]) end
    local r = stylizeText(pieces[2], input, string.format('%s • %s • visited', pieces[3], pieces[2]), #pieces[3], true)
    r.remove = function ()
      App.storedHistory:remove(table.findFirst(App.storedHistory:loaded(), function (item, index, callbackData)
        return item.url == pieces[2]
      end))
    end
    return r
  elseif v:byte(1) == 4 then
    local r = stylizeText(v, input, v:sub(2), #v - 1, ui.Icons.Earth)
    r.direct = true
    return r
  elseif v:byte(1) == 5 then
    local query = v:sub(2)
    return {
      text = v,
      stylized = string.format('%s • %s search', query, SearchProvider.selected().name),
      highlight = #query,
      bolds = {},
      favicon = ui.Icons.Search,
      direct = true
    }
  else
    return stylizeText(v, input)
  end
end

local function drawSuggestionItem(p, i1, i2, h)
  if p.favicon then
    ui.drawIcon(p.direct and p.favicon or FaviconsProvider.get(p.text), i1 + 4, i1 + (h - 4))
    i1.x = i1.x + 24
  end
  if p.highlight then
    ui.setNextTextSpanStyle(1, p.highlight, rgbm.colors.white)
    if p.direct and p.favicon == ui.Icons.Earth then
      ui.setNextTextSpanStyle(1, p.highlight, rgbm(0, 0.5, 1, 1))
    end
  end
  for _, v in ipairs(p.bolds) do ui.setNextTextSpanStyle(v[1], v[2], nil, true) end
  i1.x = ui.drawTextClipped(p.stylized, i1, i2, p.highlight and rgbm.colors.gray or nil, vAlign, false)
end

---A bit stange contraption adding a nice dropdown list with suggestions to `ui.inputText()`. Also adds some inline suggestion to
---try and act more like Chromium search bar.
---@param provider fun(input: string, callback: fun(replies: string[]))
---@return fun(input: string, enterPressed: boolean): string|WebBrowser?, true?
local function inputSuggestions(provider, search)
  local lastInput = ''
  local setInput
  local forceFocus = 0
  local suggestionsClosed = false
  local suggestions = {} ---@type {text: string, favicon: WebBrowser|string?, url: string?, direct: boolean?}[]
  local selected = 0
  local lastOffer
  local lastBaseInputLen = 0
  local disableOffers = false
  local stayAlive = 0
  local lastOpened = -1
  local ignoringEscape = false
  local providerCallID = 0
  -- local blockedUntil = -1

  local function selectionMade()
    ui.clearActiveID()
    App.focusNext = 'browser'
    setTimeout(function ()
      App.focusNext = 'browser'
    end)
    -- ui.inputTextCommand('keepStateOnEscape', 'false')
    -- blockedUntil = ui.frameCount() + 4
  end

  return function (input, enterPressed)
    -- if ui.frameCount() < blockedUntil then
    --   App.focusNext = 'browser'
    --   return
    -- end

    local popupOpened = lastOpened + 2 >= ui.frameCount()
    if popupOpened then
      ui.inputTextCommand('keepStateOnEscape', 'full')
      ignoringEscape = true
    elseif ignoringEscape then
      ui.inputTextCommand('keepStateOnEscape', 'false', false)
      ignoringEscape = false
    end

    if search and not ignoringEscape and ui.keyPressed(ui.Key.Escape) then
      -- search bar clears up if escape is pressed twice
      ui.inputTextCommand('setText', '')
    end

    if ui.itemActive() then
      stayAlive = 2
    elseif stayAlive > 0 then
      stayAlive = stayAlive - 1
    elseif not enterPressed then
      selected = 0
      lastInput = ''
      setInput = nil
      if App.focusOnSearch == 2 then App.focusOnSearch = nil end
      return
    end

    if ui.hotkeyShift() and ui.keyPressed(ui.Key.Delete) and suggestions[selected] and not suggestions[selected].direct then
      -- shift+delete removes history entries
      local s = table.remove(suggestions, selected)
      if s and s.remove then s.remove() end
    end

    if enterPressed then
      -- if caller asked for currently selected result, returning
      if not popupOpened then return end
      local s = suggestions[selected]
      if s and s.direct then return s.text:sub(1, 1)..input end
      if s and type(s.favicon) == 'table' then return s.favicon end -- returning tab
      if s and s.text:findIgnoreCase(input) == 1 and disableOffers then return nil end
      -- ui.closePopup()
      selectionMade()
      return s and s.text
    end

    local changed = ui.itemEdited()
    if setInput then
      -- if a popup wants to set certain text, applying it here
      changed = false
      input, setInput = setInput, nil
      ui.inputTextCommand('setText', input)
      if ui.mouseReleased(ui.MouseButton.Left) then
        selectionMade()
        return input
      end
    end

    input = ui.inputTextCommand('getText') or input
    if #input ~= lastBaseInputLen then
      -- if a new character is typed or inserted, reactivate offers and suggestions 
      if #input > lastBaseInputLen then
        disableOffers = false
        suggestionsClosed = false
      end
      lastBaseInputLen = #input
    end

    if not disableOffers and input ~= '' then
      local offer = suggestions[selected] and not suggestions[selected].favicon and suggestions[selected].text or nil
      if offer then
        if suggestions[selected].favicon then offer = nil
        elseif not offer:startsWith(input) then offer = nil else offer = offer:sub(#input + 1) end
      end
      if offer ~= lastOffer then
        lastOffer = offer
        ui.inputTextCommand('suggest', offer)
      end
    end

    if ui.itemActive() or popupOpened then
      local moved, previouslySelected = false, selected
      if popupOpened and ui.keyPressed(ui.Key.Up) then
        selected = selected <= 1 and #suggestions or math.max(0, selected - 1)
        disableOffers, moved = false, true
        App.focusOnSearch = nil
      end
      if popupOpened and ui.keyPressed(ui.Key.Down) then 
        selected = selected == #suggestions and 1 or math.min(#suggestions, selected + 1)
        disableOffers, moved = false, true
        App.focusOnSearch = nil
      end
      if moved and suggestions[selected] then
        if suggestions[selected].favicon then
          local replacement = suggestions[selected].direct and suggestions[selected].text:sub(2) or suggestions[selected].text
          if replacement then
            input, lastInput = replacement, replacement
            ui.inputTextCommand('setText', replacement)
          end
        elseif suggestions[previouslySelected] then
          local previous = suggestions[previouslySelected].direct and suggestions[previouslySelected].text:sub(2) or suggestions[previouslySelected].text
          if input == previous then
            local replacement = suggestions[selected].direct and suggestions[selected].text:sub(2) or suggestions[selected].text
            input, lastInput = replacement, replacement
            ui.inputTextCommand('setText', replacement)
          end
        end
      end
      if popupOpened and ui.keyPressed(ui.Key.Backspace) or ui.keyPressed(ui.Key.Delete) then
        disableOffers = true
      end
      if (not suggestionsClosed or input ~= '') and ui.keyPressed(ui.Key.Escape) then
        suggestionsClosed = true
        return nil
      end
    end

    if forceFocus ~= 0 then
      ui.setKeyboardFocusHere(-1)
      forceFocus = math.max(0, forceFocus - 1)
    elseif not ui.itemActive() or input == '' then
      if not ui.itemActive() then suggestionsClosed = false end
      lastInput = ''
      return nil
    elseif suggestionsClosed then
      return nil
    end

    local ret, opened
    if lastInput ~= input and (changed or lastInput == '') then
      lastInput = input
      if #input > 0 then
        providerCallID = providerCallID + 1
        local curCallID = providerCallID
        provider(input, function (items)
          if curCallID ~= providerCallID then return end
          if not items then items = {} end
          local oldSuggestion = suggestions[selected] and suggestions[selected].text
          if not App.focusOnSearch then selected = 0 else App.focusOnSearch = 2 end
          table.clear(suggestions)
          for _, v in ipairs(items) do
            suggestions[#suggestions + 1] = parseSuggestionItem(v, input)
            if v == oldSuggestion and not App.focusOnSearch then selected = #suggestions end
            if #suggestions > 30 then break end
          end
        end)
      else
        table.clear(suggestions)
      end
    end

    if #suggestions > 0 then
      lastOpened = ui.frameCount()
      opened = true

      if App.focusOnSearch then
        selected = suggestions[1].favicon and 2 or 1
      end
      selected = math.clamp(selected, 0, #suggestions)

      local r1 = ui.itemRectMin()
      local r2 = ui.itemRectMax()
      if search then
        r1.x = r1.x - 4
        r2.x = r2.x + 85
        r2.y = r2.y + 4
      end
      ui.backupCursor()
      ui.setCursorX(r1.x)
      ui.setNextWindowPosition(ui.windowPos():add(vec2(r1.x, r2.y)))

      local h = ui.measureText('!').y + 8
      if ui.beginChild('popup', vec2(r2.x - r1.x, math.min(220, #suggestions * h)), false, 
          bit.bor(ui.WindowFlags.NoScrollbar, search and ui.WindowFlags.NoBackground or 0, 33554432)) then
        if ui.windowFocused() or ui.windowHovered() then
          forceFocus = 1
        end

        local c1 = vec2(0, ui.getScrollY())
        ui.pushClipRect(c1, ui.windowSize():add(c1), false)
        if search then
          ui.drawRectFilled(c1, ui.windowSize():add(c1), rgbm(0, 0, 0, 0.8), 4, ui.CornerFlags.Bottom)
          -- ui.drawRect(c1, ui.windowSize():add(c1), rgbm(1, 1, 1, 0.5), 4, ui.CornerFlags.Bottom)
        end
        ui.thinScrollbarBegin(true)

        local w = ui.windowWidth()
        local i1 = vec2(0, 0)
        local i2 = vec2(w, 0 + h)
        for i = 1, #suggestions do
          i1.x, i2.x = 0, w
          local hovered = ui.rectHovered(i1, i2, true)
          if hovered or i == selected then
            ui.drawRectFilled(i1, i2, rgbm(1, 1, 1, 0.1))
            if i == selected then
              ui.drawRectFilled(i1, vec2(i1.x + 2, i2.y), rgbm.colors.white)
              if (i1.y < ui.getScrollY() or i2.y > ui.getScrollY() + ui.windowHeight()) 
                  and (ui.keyPressed(ui.Key.Up) or ui.keyPressed(ui.Key.Down)) then
                if i2.y > ui.getScrollY() + ui.windowHeight() then
                  ui.setScrollY(i2.y - ui.windowHeight(), false, true)
                else
                  ui.setScrollY(i1.y, false, true)
                end
              end
            end
          end
          i1.x, i2.x = i1.x + 8, i2.x - 8        
          if search then i1.x = i1.x + 4 end
          local p = suggestions[i]
          drawSuggestionItem(p, i1, i2, h)
          if hovered and ui.mouseDown(ui.MouseButton.Left) then
            setInput = p.text
            selected = i
            App.focusOnSearch = nil
          end
          i1.y, i2.y = i1.y + h, i2.y + h
        end

        ui.setMaxCursorY(i1.y)
        ui.thinScrollbarEnd()
        ui.popClipRect()
        ui.endChild()
      end

      ui.restoreCursor()
    end
    return ret, opened
  end
end

local contextMenuInputTextTarget
local focusOnText
local showActive

---@param hintTab WebBrowser?
---@param extraItems fun()?
---@param extraCommandItems fun()?
local function inputContextMenu(hintTab, extraItems, extraCommandItems)
  local i = ui.getLastID()
  if i == contextMenuInputTextTarget then
    if focusOnText then
      focusOnText = false
      ui.setKeyboardFocusHere(-1)
    end

    if showActive then
      ui.inputTextCommand(showActive)
      showActive = false
    end
  end

  -- Note: if you want to add context menu to your text input controls, this is the best way to do it, with no delay. Make sure to call
  -- `ui.inputTextCommand('')` so that CSP would know you are doing context menu (I’m going to add context menus to all other input texts
  -- a bit later).
  if ui.itemClicked(ui.MouseButton.Right, true) then
    contextMenuInputTextTarget = i
    local input = ui.inputTextCommand('getSelected')
    ui.inputTextCommand('')
    Utils.popup(function ()
      showActive = ''
      if input and App.canOpenMoreTabs() then
        local l, u = Utils.searchSelectedHelper(input)
        if ControlsBasic.menuItem(l) then App.addAndSelectTab(u, nil, nil, hintTab) end
        ui.separator()
      end

      if ControlsBasic.menuItem('Undo', 'Ctrl+Z') then showActive = 'undo' end
      if ControlsBasic.menuItem('Redo', 'Ctrl+Y') then showActive = 'redo' end
      ui.separator()
      if not input then ui.pushDisabled() end
      if ControlsBasic.menuItem('Copy', 'Ctrl+C') then showActive = 'copy' end
      if ControlsBasic.menuItem('Cut', 'Ctrl+X') then showActive = 'cut' end
      if not input then ui.popDisabled() end
      if ControlsBasic.menuItem('Paste', 'Ctrl+V') then showActive = 'paste' end
      if extraCommandItems then extraCommandItems() end
      if ControlsBasic.menuItem('Select all', 'Ctrl+A') then showActive = 'selectAll' end
      if extraItems then
        extraItems()
      end
    end, { onClose = function () focusOnText = true end })
  end
end

return {
  inputSuggestions = inputSuggestions,
  inputContextMenu = inputContextMenu,
}