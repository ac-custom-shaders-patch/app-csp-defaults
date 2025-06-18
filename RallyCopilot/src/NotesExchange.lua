--[[
  Most of this code is copied from Setup Exchange because why not.
]]

local AppState = require('src/AppState')
local AppConfig = require('src/AppConfig')
local PaceNotesHolder = require('src/PaceNotesHolder')

local mainTrackID = AppState.exchangeTrackID
local endpoint = AppState.exchangeEndpoint
ac.log('mainTrackID', mainTrackID)

local trackNames = {}
do
  local cfg = ac.INIConfig.load(ac.getFolder(ac.FolderID.ExtCfgSys)..'/data_track_params.ini', ac.INIFormat.Extended)
  for k, v in pairs(cfg.sections) do
    if v.NAME then
      trackNames[k] = v.NAME[1]
    end
  end
end

---@param callback fun(err: string?, sessionData: {sessionID: string, userID: string, likes: string, dislikes: string}?, userKey: string?)
local function createSession(callback)
  ac.uniqueMachineKeyAsync(function (err, data)
    if err then
      callback(err)
      return
    end

    local userID = ac.checksumSHA256('LB83XurHhTPhpmTc'..data)
    web.request('POST', endpoint..'/session', {['X-Session-ID'] = '0'}, JSON.stringify{userID = userID}, function (err, response)
      if err then
        callback(err)
      else
        local parsed = JSON.parse(response.body)
        if type(parsed) == 'table' and parsed.key then
          require('shared/utils/signing').blob('{UniqueMachineKeyChecksum}', parsed.key, function (signature, header)
            web.request('PATCH', endpoint..'/session', {['X-Session-ID'] = '0'}, JSON.stringify{
              userID = userID,
              header = ac.encodeBase64(header),
              signature = ac.encodeBase64(signature),
              carID = ac.getCarID(0),
              carName = ac.getCarName(0),
              trackID = mainTrackID,
              trackName = ac.getTrackName()
            }, function (err, response)
              if err then
                callback(err)
              else
                local parsed = JSON.parse(response.body)
                if type(parsed) == 'table' and parsed.sessionID and parsed.userID then
                  callback(nil, parsed)
                else
                  callback('Server is not working correctly')
                end
              end
            end)
          end)
        else
          callback('Server is not working correctly')
        end
      end
    end)
  end)
end

local ownUserID
local likedSetups, dislikedSetups = {}, {}

---@type string?, string?, number
local sessionID, sessionError, sessionCooldown = nil, nil, 0
local function tryRecreateSession()
  if os.preciseClock() < sessionCooldown then
    return
  end
  sessionCooldown = os.preciseClock() + 2
  createSession(function (err, session)
    if err then
      sessionError, sessionID = tostring(err), nil
      ac.error('Failed to create a session: '..tostring(err))
    else
      sessionError, sessionID, ownUserID = nil, session.sessionID, session.userID
      ac.log('New session: '..session.sessionID..', user ID: '..ownUserID)
      table.clear(likedSetups)
      table.clear(dislikedSetups)
      for i, v in ipairs(session.likes:split(';', nil, false, true)) do
        likedSetups[i] = tonumber(v, 36)
      end
      for i, v in ipairs(session.dislikes:split(';', nil, false, true)) do
        dislikedSetups[i] = tonumber(v, 36)
      end
    end
  end)
end

tryRecreateSession()

local function rest(method, url, data, callback, errorHandler)
  if not sessionID and (method ~= 'GET' or url ~= 'setups') then
    setTimeout(function ()
      rest(method, url, data, callback, errorHandler)
    end, 0.5)
    return
  end

  if method == 'GET' and data then
    local f = true
    for k, v in pairs(data) do
      url = url..(f and '?' or '&')..k..'='..string.urlEncode(v)
      f = false
    end
  end

  if not callback then callback = function (response, headers) ac.log('Successfully executed: '..url..', response: '..stringify(response)) end end
  if not errorHandler then errorHandler = function (err) ac.warn(err) end end

  local start = os.preciseClock()
  web.request(method, endpoint..'/'..url, {
    ['Content-Type'] = 'application/json',
    ['X-Session-ID'] = sessionID or '0',
  }, method ~= 'GET' and JSON.stringify(data) or nil, function (err, response)
    ac.log('Request: %s, %.1f ms' % {endpoint..'/'..url, 1e3 * (os.preciseClock() - start)})
    if err then
      return errorHandler(tostring(err))
    end

    if response.status >= 400 then
      local parsed = try(function ()
        return JSON.parse(response.body)
      end, function () end)
      if parsed and parsed.error then err = parsed.error else err = response.body end
      err = tostring(err)
      if err:sub(1, 7) == 'Error: ' then err = err:sub(8) end
      if err == 'Invalid session ID' then
        tryRecreateSession()
      end
      return errorHandler(err)
    end

    try(function()
      callback(JSON.parse(response.body), response.headers)
    end, errorHandler)
  end)
end

local limit = 40

local function refreshGenList(uniqueKey, url, params, callback, continuationState)
  ac.log(url, params)
  rest('GET', url, table.chain(params, {offset = continuationState and #continuationState[3] or 0, limit = limit}), function (response, headers)
    local totalCount = tonumber(headers['x-total-count']) or #response
    if callback then
      local continuationState = {#response < totalCount, totalCount, response, table.map(response, function (item) return true, item[uniqueKey] end)}
      callback(response, continuationState[1] and function ()
        if continuationState[1] then
          continuationState[1] = false
          refreshGenList(uniqueKey, url, params, nil, continuationState)
        end 
      end, totalCount)
    elseif continuationState and #response > 0 then
      for _, v in ipairs(response) do 
        if not continuationState[4][v[uniqueKey]] then
          continuationState[4][v[uniqueKey]] = true
          table.insert(continuationState[3], v)
        end
      end
      continuationState[2] = totalCount
      continuationState[1] = #continuationState[3] < continuationState[2]
    end
  end, function (err)
    ac.warn('Failed to get list of '..url..': '..err)
    if callback then callback(err) end
  end)
end

local setupsOrder = {
  {'Hot', '(statDislikes*200-statLikes*20-statDownloads-statComments*2)*1e6/sqrt(max(60.0,@now-createdDate)/60)'},
  {'Popular', '-statDownloads'},
  {'Liked', 'statDislikes-statLikes*2'},
  {'Newest', '-createdDate'},
  {'Title', 'name'},
}

local authorUsernameFilter = ''
local searchFilter = ''
local listOfSetups, listOfComments
local listOfSetupsPrev, listOfCommentsPrev
local likedComments, dislikedComments = {}, {}
local downloadedSetups = {}
local currentlyApplying = false
local currentlySubmittingComment = false
local itemSize = vec2(100, 110)
local commentSize = vec2(100, 130)
local discussingItem
local discussingComments = {}
local downloadedAsFiles = {}
local ownColor = rgbm(1, 1, 0, 1)

local function getSetupData(setupInfo, incrementDownloads, callback)
  local cached = downloadedSetups[setupInfo.setupID]
  if cached and (cached.data or cached.err) then
    if incrementDownloads and not cached.incremented then
      cached.incremented = true
      setupInfo.statDownloads = setupInfo.statDownloads + 1
      rest('POST', 'setup-download-counts/'..setupInfo.setupID)
    end
    callback(cached.err, cached.data)
  elseif cached then
    table.insert(cached, callback)
  else
    downloadedSetups[setupInfo.setupID] = {callback}
    rest('GET', 'setups/'..setupInfo.setupID, nil, function (response)
      if incrementDownloads then
        setupInfo.statDownloads = setupInfo.statDownloads + 1
        rest('POST', 'setup-download-counts/'..setupInfo.setupID)
      end
      local list = downloadedSetups[setupInfo.setupID]
      downloadedSetups[setupInfo.setupID] = {data = response.data, incremented = incrementDownloads}
      for _, v in ipairs(list) do
        v(nil, response.data)
      end
    end, function (err)
      local list = downloadedSetups[setupInfo.setupID]
      downloadedSetups[setupInfo.setupID] = {err = err, incremented = true}
      for _, v in ipairs(list) do
        v(err, nil)
      end
    end)
  end
end

local function downloadSetupAsFile(setupInfo)
  if currentlyApplying or downloadedAsFiles[setupInfo.setupID] then return end
  currentlyApplying = true
  getSetupData(setupInfo, true, function (err, data)
    currentlyApplying = false
    local added = PaceNotesHolder.add(data, setupInfo.trackID)
    ui.toast(ui.Icons.Confirm, 'Pacenotes loaded', function ()
      PaceNotesHolder.delete(added)
      downloadedAsFiles[setupInfo.setupID] = false
    end)
    downloadedAsFiles[setupInfo.setupID] = true
  end)
end

local listOfSetupsContinuation
local setupsTotalCount = 0
local function refreshSetups()
  if not listOfSetups then
    local key = math.random()
    listOfSetups, listOfSetupsContinuation = key, nil
    refreshGenList('setupID', 'setups', {
      trackID = authorUsernameFilter == '' and mainTrackID or nil,
      userName = authorUsernameFilter ~= '' and authorUsernameFilter or nil,
      search = authorUsernameFilter == '' and searchFilter ~= '' and searchFilter or nil,
      orderBy = setupsOrder[AppConfig.setupsOrder][2]
    }, function (ret, continuation, totalCount)
      if listOfSetups == key then
        listOfSetups = ret
        listOfSetupsPrev = ret
        listOfSetupsContinuation = continuation and {ret, continuation}
        setupsTotalCount = totalCount or 0
      end
    end)
  end
  return (type(listOfSetups) == 'table' or type(listOfSetups) == 'string') and listOfSetups or listOfSetupsPrev
end

local function loadMoreSetups()
  if type(listOfSetups) == 'table' and listOfSetupsContinuation and listOfSetupsContinuation[1] == listOfSetups then
    listOfSetupsContinuation[2]()
  end
end

local listOfCommentsContinuation
local commentsTotalCount = 0
local scrollCommentsDown = false
local function refreshComments()
  if not listOfComments then
    local key = math.random()
    listOfComments = key
    refreshGenList('commentID', 'comments', {setupID = discussingItem.setupID}, function (ret, continuation, totalCount)
      if listOfComments == key then
        listOfComments = ret
        listOfCommentsPrev = ret
        scrollCommentsDown = true
        listOfCommentsContinuation = continuation and {ret, continuation}
        commentsTotalCount = totalCount or 0
      end
    end)
    table.clear(likedComments)
    table.clear(dislikedComments)
    rest('GET', 'comment-likes', {setupID = discussingItem.setupID}, function (data)
      for _, v in ipairs(data) do
        table.insert(v.direction == 1 and likedComments or dislikedComments, v.commentID)
      end
    end)
  end
  return (type(listOfComments) == 'table' or type(listOfComments) == 'string') and listOfComments or listOfCommentsPrev
end

local function loadMoreComments()
  if type(listOfComments) == 'table' and listOfCommentsContinuation and listOfCommentsContinuation[1] == listOfComments then
    listOfCommentsContinuation[2]()
  end
end

local removingIDs = {}

local function removeSetup(id, withUndo)
  if removingIDs[id] then return end
  removingIDs[id] = true
  rest('DELETE', 'setups/'..id, nil, function ()
    ui.toast(ui.Icons.Delete, 'Shared setup removed', withUndo and function ()
      rest('POST', 'setups-restore/'..id, nil, function ()
        listOfSetups = nil
      end, function (err)
        ui.toast(ui.Icons.Warning, 'Failed to restore setup: '..err)
      end)
    end or nil)
    listOfSetups = nil
    removingIDs[id] = nil
  end, function (err)
    ui.toast(ui.Icons.Warning, 'Failed to remove setup: '..err)
    removingIDs[id] = nil
  end)
end

local function removeComment(id, withUndo)
  rest('DELETE', 'comments/'..id, nil, function ()
    ui.toast(ui.Icons.Warning, 'Comment removed', withUndo and function ()
      rest('POST', 'comments-restore/'..id, nil, function ()
        listOfComments = nil
      end, function (err)
        ui.toast(ui.Icons.Warning, 'Failed to restore comment: '..err)
      end)
    end or nil)
    listOfComments = nil
  end, function (err)
    ui.toast(ui.Icons.Warning, 'Failed to remove comment: '..err)
  end)
end

local icons = ui.atlasIcons('res/ui.png', 4, 1, {
  Like = {1, 1},
  Dislike = {1, 2},
  Comments = {1, 3},
  Download = {1, 4},
})

local iconSize = vec2(10, 10)
local iconAlign = vec2(0, 0.6)
local iconLikeAlign = vec2(0, 0)
local iconDislikeAlign = vec2(0, 1)

---@param pn PaceNotes
---@param name string
local function shareSetup(pn, name)
  rest('POST', 'setups', {
    carID = ac.getCarID(0),
    trackID = AppState.exchangeTrackID,
    name = name,
    userName = AppConfig.userName,
    data = pn:export(name)
  }, function (response)
    ui.toast(ui.Icons.ListAlt, 'Pacenotes shared', function ()
      removeSetup(response.setupID)
    end)
    listOfSetups = nil
  end, function (err)
    ui.toast(ui.Icons.Warning, 'Failed to share pacenotes: '..err)
  end)
end

local function likeButtons(path, item, likedList, dislikedList, itemID, contextTable)
  local liked = table.contains(likedList, itemID)
  local disliked = table.contains(dislikedList, itemID)
  if ui.button(string.format('     %d##likes', item.statLikes)) then
    if liked then
      item.statLikes = item.statLikes - 1
      table.removeItem(likedList, itemID)
      rest('PATCH', path..'/'..itemID, contextTable)
    else
      item.statLikes = item.statLikes + 1
      table.insert(likedList, itemID)
      rest('PATCH', path..'/'..itemID, table.chain(contextTable, {direction = 1}))
      if disliked then
        item.statDislikes = item.statDislikes - 1
        table.removeItem(dislikedList, itemID)
      end
    end
  end
  ui.addIcon(icons.Like, iconSize, iconLikeAlign, liked and rgbm.colors.lime or rgbm.colors.white)
  if ui.itemHovered() then ui.setTooltip(string.format('Likes: %d', item.statLikes)) end

  ui.sameLine(0, 4)
  if ui.button(string.format('     %d##dislikes', item.statDislikes)) then
    if disliked then
      item.statDislikes = item.statDislikes - 1
      table.removeItem(dislikedList, itemID)
      rest('PATCH', path..'/'..itemID, contextTable)
    else
      item.statDislikes = item.statDislikes + 1
      table.insert(dislikedList, itemID)
      rest('PATCH', path..'/'..itemID, table.chain(contextTable, {direction = -1}))
      if liked then
        item.statLikes = item.statLikes - 1
        table.removeItem(likedList, itemID)
      end
    end
  end
  ui.addIcon(icons.Dislike, iconSize, iconDislikeAlign, disliked and rgbm.colors.red or rgbm.colors.white)
  if ui.itemHovered() then ui.setTooltip(string.format('Dislikes: %d', item.statDislikes)) end
end

local function commentsBlock()
  local item = discussingItem
  local comment = discussingComments[item.setupID] or ''
  local comments = refreshComments()
  if not comments then
    ui.drawLoadingSpinner(ui.windowSize() / 2 - 20, ui.windowSize() / 2 + 20)
    return
  end

  if type(comments) == 'string' then
    ui.text('Failed to load comments:')
    ui.text(comments)
    return
  end

  ui.childWindow('commentsScroll', ui.availableSpace():sub(vec2(0, 40)), function ()
    ui.offsetCursorY(8)
    if #comments == 0 then
      ui.textDisabled('No comments yet')
    end
    for _, v in ipairs(comments) do
      if ui.areaVisible(commentSize) then
        if _ == #comments then
          loadMoreComments()
        end
        local y = ui.getCursorY()
        ui.pushID(v.commentID)
        local disliked = v.statDislikes > v.statLikes + 1
        if disliked then ui.pushStyleVarAlpha(0.5) end
        ui.pushFont(ui.Font.Small)
        if v.userID == ownUserID then ui.pushStyleColor(ui.StyleColor.Text, ownColor) end
        ui.text(v.userName)
        if v.userID == ownUserID then ui.popStyleColor() end
        ui.sameLine(0, 0)
        ui.text(string.format(' • %s', os.date('%Y/%m/%d %H:%M', v.createdDate)))
        ui.popFont()
        ui.offsetCursorY(-2)

        local i = string.find(v.data, '@'..AppConfig.userName, 1, true)
        if i then
          ui.setNextTextSpanStyle(i, i + 1 + #AppConfig.userName, ownColor, true)
        end
        ui.textWrapped(v.data)

        ui.pushFont(ui.Font.Small)
        if ui.button('     Reply') then
          comment = '@'..v.userName..' '..comment
        end
        ui.addIcon(ui.Icons.Undo, iconSize, iconAlign)

        ui.sameLine(0, 4)
        likeButtons('comment-likes', v, likedComments, dislikedComments, v.commentID, {setupID = item.setupID})

        if v.userID == ownUserID then
          ui.sameLine(0, 4)
          if ui.button('     Delete') then
            removeComment(v.commentID, true)
            item.statComments = item.statComments - 1
          end
          ui.addIcon(ui.Icons.Delete, iconSize, iconAlign)
        end
        ui.popFont()
        
        if disliked then ui.popStyleVar() end
        ui.popID()
        ui.offsetCursorY(12)
        itemSize.y = ui.getCursorY() - y
      else
        ui.offsetCursorY(commentSize.y)
      end
    end
    if scrollCommentsDown then
      ui.setScrollY(1e9, false, true)
    end
  end)

  local _, submitted
  comment, _, submitted = ui.inputText('Add a comment…', comment, ui.InputTextFlags.Placeholder)
  if ui.isWindowAppearing() or scrollCommentsDown then
    ui.setKeyboardFocusHere(-1)
    if #comments == commentsTotalCount or ui.windowScrolling() then
      scrollCommentsDown = false
    end
  end
  ui.sameLine(0, 4)
  local canSend = #comment:trim() > 0 and not currentlySubmittingComment and sessionID ~= nil
  if (ui.button('Send', vec2(ui.availableSpaceX(), 0), canSend and 0 or ui.ButtonFlags.Disabled) or submitted) and canSend then
    currentlySubmittingComment = true
    rest('POST', 'comments', {setupID = item.setupID, userName = AppConfig.userName, data = comment:trim()}, function (response)
      currentlySubmittingComment = false
      ui.toast(ui.Icons.Settings, 'Comment posted', function ()
        removeComment(response.commentID)
        item.statComments = item.statComments - 1
      end)
      listOfComments = nil
      discussingComments[item.setupID] = '' 
      item.statComments = item.statComments + 1
    end, function (err)
      currentlySubmittingComment = false
      ui.toast(ui.Icons.Warning, 'Failed to post a comment: '..err)
    end)
  end
  if ui.itemHovered() and sessionID == nil then
    ui.setTooltip(sessionError or 'Connecting…')
  end
  discussingComments[item.setupID] = comment
end

local function windowGeneric()
  local setups = refreshSetups()
  if not setups then
    ui.drawLoadingSpinner(ui.windowSize() / 2 - 20, ui.windowSize() / 2 + 20)
    return
  end

  if type(setups) == 'string' then
    ui.pushAlignment(true)
    ui.text('Failed to load the list:')
    ui.text(setups)
    ui.setNextItemIcon(ui.Icons.Restart)
    if ui.button('Try again', vec2(-0.1, 0)) then
      listOfSetups = nil
    end
    ui.popAlignment()
  end

  ui.alignTextToFramePadding()
  if authorUsernameFilter ~= '' then
    if ui.button('    Back') then
      authorUsernameFilter = ''
      listOfSetups = nil
      return
    end
    ui.addIcon(ui.Icons.ArrowLeft, iconSize, iconAlign, rgbm.colors.white)
    ui.sameLine()
    local n = string.format('%d pacenotes by %s:', setupsTotalCount, authorUsernameFilter)
    if authorUsernameFilter == AppConfig.userName then
      local f = string.find(n, authorUsernameFilter)
      if f then
        ui.setNextTextSpanStyle(f, f + #authorUsernameFilter, ownColor)
      end
    end
    ui.header(n)
  elseif searchFilter ~= '' then
    if ui.button('    Back') then
      searchFilter = ''
      listOfSetups = nil
      return
    end
    ui.addIcon(ui.Icons.ArrowLeft, iconSize, iconAlign, rgbm.colors.white)
    ui.sameLine()
    ui.header(string.format('%d pacenotes matching “%s”:', setupsTotalCount, searchFilter))
  else
    ui.header(string.format('%d fitting pacenotes', setupsTotalCount))
  end

  ui.pushFont(ui.Font.Small)
  ui.sameLine(0, 0)
  if ui.availableSpaceX() < 144 then
    ui.newLine(0)
  end
  ui.offsetCursorX(ui.availableSpaceX() - 144)
  ui.setNextItemWidth(120)
  ui.combo('##sort', setupsOrder[AppConfig.setupsOrder][1], ui.ComboFlags.HeightLarge, function ()
    ui.pushFont(ui.Font.Main)
    ui.header('Sort:')
    ui.offsetCursorY(4)
    for i, v in ipairs(setupsOrder) do
      if ui.selectable(v[1], i == AppConfig.setupsOrder) then
        AppConfig.setupsOrder = i
        listOfSetups = nil
      end
    end
    ui.offsetCursorY(12)
    ui.header('Search:')
    local updated, _, enter = ui.inputText('Name or author', searchFilter, bit.bor(ui.InputTextFlags.Placeholder, ui.InputTextFlags.CtrlEnterForNewLine))
    if enter then
      searchFilter = updated
      listOfSetups = nil
    end
    ui.popFont()
  end)
  ui.sameLine(0, 4)
  if ui.button('…') then
    ui.popup(function ()
      ui.text('Your name: '..AppConfig.userName)
      if ui.selectable('Change name', false) then
        ui.modalPrompt('Change name', 'New name:', AppConfig.userName, function (newName)
          if not newName or #newName:trim() == 0 then return end
          rest('POST', 'user', { userName = newName:trim() }, function ()
            ui.toast(ui.Icons.Confirm, 'Name changed')
            AppConfig.userName = newName:trim()
            listOfSetups = nil
          end, function (err)
            ui.toast(ui.Icons.Warning, 'Couldn’t change name: '..err)
          end)
        end)
      end
      if ui.itemHovered() then
        ui.setTooltip('Changing name would also change it for all published content')
      end
      ui.separator()
      if ui.selectable('Your pacenotes…') then
        authorUsernameFilter = AppConfig.userName
        listOfSetups = nil
      end
    end, {position = ui.windowPos() + ui.itemRectMin() + vec2(0, 20)})
  end
  ui.popFont()

  ui.childWindow('scroll', ui.availableSpace():sub(vec2(0, 40)), function ()
    ui.offsetCursorY(8)
    if #setups == 0 then
      ui.textDisabled('No pacenotes for this track shared yet.')
      return
    end
    local f = 1 + math.floor(ui.getScrollY() / itemSize.y)
    local t = 1 + math.floor((ui.getScrollY() + ui.windowHeight()) / itemSize.y)
    if t > #setups then
      loadMoreSetups()
    end
    for i = f, math.min(t, #setups) do
      local v = setups[i]
      if v then
        ui.setCursorY(itemSize.y * (i - 1))
        local y = ui.getCursorY()
        ui.pushID(v.setupID)

        local disliked = v.statDislikes > v.statLikes + 1
        if disliked then ui.pushStyleVarAlpha(0.5) end

        ui.beginGroup()

        ui.pushFont(ui.Font.Title)
        ui.text(v.name:trim())
        ui.popFont()
        ui.pushFont(ui.Font.Small)

        if authorUsernameFilter == '' then
          ui.sameLine(0, 0)
          ui.offsetCursorY(10)
          ui.text(' by ')
          ui.sameLine(0, 0)
          if v.userID == ownUserID then ui.pushStyleColor(ui.StyleColor.Text, ownColor) end
          ui.text(v.userName)
          if ui.itemHyperlink(v.userID == ownUserID and ownColor or rgbm.colors.white) then
            authorUsernameFilter = v.userName
            listOfSetups = nil
          end
          if v.userID == ownUserID then ui.popStyleColor() end
          ui.offsetCursorY(-10)
        end
        
        if authorUsernameFilter ~= '' then
          ui.text('Track:')
          ui.sameLine(80)
          ui.text(trackNames[v.trackID] or v.trackID)
        end

        ui.text('Posted:')
        ui.sameLine(80)
        ui.text(tostring(os.date('%Y/%m/%d %H:%M', v.createdDate)))
 
        ui.text('Downloads:')
        ui.sameLine(80)
        ui.text(v.statDownloads)

        ui.endGroup()

        if v.trackID == mainTrackID then
          if ui.button('     Apply', not currentlyApplying and 0 or ui.ButtonFlags.Disabled) then
            currentlyApplying = true
            getSetupData(v, true, function (err, data)
              currentlyApplying = false
              if err then
                ui.toast(ui.Icons.Warning, 'Failed to load pacenotes: '..err)
              else
                local added, current = PaceNotesHolder.add(data), PaceNotesHolder.current()
                ui.toast(ui.Icons.Confirm, 'Setup loaded', function ()
                  ui.toast(ui.Icons.Confirm, 'Previous pacenotes restored')
                  PaceNotesHolder.select(current)
                  PaceNotesHolder.delete(added)
                end)
                PaceNotesHolder.select(added)
              end
            end)
          end
          ui.addIcon(icons.Download, iconSize, iconAlign)
          if ui.itemHovered() then
            ui.pushStyleVar(ui.StyleVar.Alpha, 1)
            ui.setTooltip('Pacenotes will be instantly applied (with an option to revert back). To download pacenotes, use context menu.')
            ui.popStyleVar()
          end
          ui.pushStyleVar(ui.StyleVar.Alpha, 1)
          if ui.itemClicked(ui.MouseButton.Right, true) then
            ui.popup(function ()
              if ui.selectable('Download', downloadedAsFiles[v.setupID]) then
                downloadSetupAsFile(v)
              end
            end)
          end
          ui.popStyleVar()
        else
          if ui.button('Download', downloadedAsFiles[v.setupID] and ui.ButtonFlags.Active or not currentlyApplying and 0 or ui.ButtonFlags.Disabled) then
            downloadSetupAsFile(v)
          end
          if ui.itemHovered() then
            ui.pushStyleVar(ui.StyleVar.Alpha, 1)
            ui.setTooltip('These pacenotes are for a different track, but you can download them and use them in the next race.')
            ui.popStyleVar()
          end
        end

        ui.sameLine(0, 4)
        likeButtons('likes', v, likedSetups, dislikedSetups, v.setupID, {trackID = v.trackID})

        ui.sameLine(0, 4)
        if ui.button(string.format('     %d##comments', v.statComments)) then
          if discussingItem == v then
            discussingItem = nil
          else
            discussingItem = v
            listOfComments = nil
            listOfCommentsPrev = nil
            local closeCounter = 0
            ui.popup(function ()
              if discussingItem ~= v or closeCounter > 1 then
                ui.closePopup()
                return
              end
              if not ui.windowFocused() then
                closeCounter = closeCounter + 1
              else
                closeCounter = 0
              end
              commentsBlock()
            end, {
              size = {initial = vec2(400, 280)},
              position = ui.itemRectMin() + ui.windowPos() + vec2(0, 20 - ui.getScrollY()),
              padding = vec2(12, 0),
              title = 'Comments ('..v.name:trim()..' by '..v.userName..')',
              backgroundColor = ui.styleColor(ui.StyleColor.PopupBg),
              flags = ui.WindowFlags.NoCollapse,
              onClose = function ()
                if discussingItem == v then
                  discussingItem = nil
                end
              end
            })
          end
        end
        ui.addIcon(icons.Comments, iconSize, iconAlign)
        if ui.itemHovered() then
          ui.pushStyleVar(ui.StyleVar.Alpha, 1)
          ui.setTooltip(string.format('Comments: %d', v.statComments))
          ui.popStyleVar()
        end

        if v.userID == ownUserID then
          ui.sameLine(0, 4)
          if ui.button('     Delete') then
            removeSetup(v.setupID, true)
          end
          ui.addIcon(ui.Icons.Delete, iconSize, iconAlign)
        end

        ui.popFont()

        if disliked then ui.popStyleVar() end

        ui.offsetCursorY(12)
        ui.popID()
        itemSize.y = ui.getCursorY() - y
      end
    end
    ui.setMaxCursorY(8 + math.max(setupsTotalCount, #setups) * itemSize.y)
  end)

  ui.offsetCursorY(12)
  ui.setNextItemIcon(ui.Icons.ListAlt)
  if ui.button('Share pacenotes', vec2(ui.availableSpaceX(), 0), sessionID ~= nil and 0 or ui.ButtonFlags.Disabled) then    
    local shareable = table.filter(PaceNotesHolder.list(), function (item) return item.metadata.canBeShared end) ---@type PaceNotes[]
    local selected ---@type PaceNotes?
    local name
    ui.modalDialog('Share pacenotes', #shareable == 0 and function ()
      ui.textWrapped('No pacenotes to share. Create new pacenotes using a built-in editor.')
      ui.newLine()
      ui.offsetCursorY(4)
      return ui.modernButton('OK', vec2(-0.1, 40), ui.ButtonFlags.None, ui.Icons.Confirm)
    end or function ()
      if selected then
        ui.text('Share “%s” as:' % selected.metadata.name)
        name = ui.inputText('Name', name, bit.bor(ui.InputTextFlags.Placeholder, ui.InputTextFlags.CtrlEnterForNewLine))
        ui.setItemDefaultFocus()
        if ui.modernButton('Share', vec2(ui.availableSpaceX() / 2 - 4, 40), name == '' and ui.ButtonFlags.Disabled or ui.ButtonFlags.Confirm, ui.Icons.Confirm) then
          shareSetup(selected, name)
          return true
        end
        ui.sameLine(0, 8)
        if ui.modernButton('Back', vec2(-0.1, 40), ui.ButtonFlags.None, ui.Icons.ArrowLeft) then
          selected = nil
        end
      else
        ui.text('Select pacenotes to share:')
        ui.childWindow('##list', vec2(0, 200), function ()
          for i, v in ipairs(shareable) do
            if ui.selectable('• %s##%s' % {v.metadata.name, i}) then
              selected = v
              name = selected.metadata.name
            end
          end
        end)
        return ui.modernButton('Cancel', vec2(-0.1, 40), ui.ButtonFlags.Cancel, ui.Icons.Cancel)
      end
    end, true)
  end
  if ui.itemHovered() and sessionID == nil then
    ui.setTooltip(sessionError or 'Connecting…')
  end
end

local NotesExchange = {}

function NotesExchange.windowNotesExchange()
  windowGeneric()
end

return NotesExchange