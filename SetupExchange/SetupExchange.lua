--[[
  Simplest client for exchanging setups with comments and likes.
]]

local mainCarID = ac.getCarID(0)
local v2 = const(ac.getPatchVersionCode() >= 3044)
local v3 = const(ac.getPatchVersionCode() >= 3050)
local endpoint = require('Config').endpoint
-- local endpoint = 'http://127.0.0.1:12016'
local temporaryName = ac.getFolder(ac.FolderID.AppDataLocal)..'/Temp/ac-se-shared.ini'
local temporaryBackupName = ac.getFolder(ac.FolderID.AppDataLocal)..'/Temp/ac-se-backup.ini'
 
if not v2 then
  local json = require 'lib/json'
  JSON = {
    stringify = json.encode,
    parse = json.decode
  }
end

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
    if not v3 then
      callback(nil, nil, userID)
      return
    end
  
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
              carID = mainCarID,
              carName = ac.getCarName(0),
              trackID = ac.getTrackID(),
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

---@type string? string?, string?, number
local userKey, sessionID, sessionError, sessionCooldown = nil, nil, nil, 0
local function tryRecreateSession()
  if os.preciseClock() < sessionCooldown then
    return
  end
  sessionCooldown = os.preciseClock() + 2
  createSession(function (err, session, newUserKey)
    if newUserKey then
      userKey = newUserKey
    elseif err then
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

if not string.urlEncode then
  string.urlEncode = function (str)
    str = string.gsub(str, "([^%w%.%- ])", function(c)
      return string.format("%%%02X", string.byte(c))
    end)
    str = string.gsub(str, " ", "+")
    return str
  end
end

local function rest(method, url, data, callback, errorHandler)
  if not sessionID and not userKey and (method ~= 'GET' or url ~= 'setups') then
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
    [userKey and 'X-User-Key' or 'X-Session-ID'] = userKey or sessionID or '0',
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

local stored = ac.storage{
  introduced = false,
  userName = '',
  setupsFilterTrack = true,
  setupsOrder = 1
}

if #stored.userName == 0 then
  stored.userName = ac.getDriverName(0) or 'User'
end

local authorUsernameFilter = ''
local searchFilter = ''
local listOfSetups, listOfComments
local listOfSetupsPrev, listOfCommentsPrev
local likedComments, dislikedComments = {}, {}
local downloadedSetups = {}
local initializing = false
local currentlyApplying = false
local currentlySubmittingComment = false
local itemSize = vec2(100, 130)
local commentSize = vec2(100, 130)
local discussingItem
local discussingComments = {}
local setupTooltips = {}
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
    local name = 'generic/loaded-'..setupInfo.name..'.ini'
    local filename = ac.getFolder(ac.FolderID.UserSetups)..'/'..(setupInfo.carID or mainCarID)..'/'..name
    io.save(filename, data)
    ac.refreshSetups()
    ui.toast(ui.Icons.Confirm, 'Setup loaded as “'..name..'”', function ()
      io.deleteFile(filename)
      ac.refreshSetups()
      downloadedAsFiles[setupInfo.setupID] = false
    end)
    downloadedAsFiles[setupInfo.setupID] = true
  end)
end

local knownNames = {
  ['FUEL'] = function (v) return string.format('Fuel set to %s L', v) end,
  ['BRAKE_POWER_MULT'] = function (v) return string.format('Brake power set to %s%%', v) end,
  ['ENGINE_LIMITER'] = function (v) return string.format('Engine limiter set to %s%%', v) end,
  ['FRONT_BIAS'] = function (v) return string.format('Brake bias set to %s%%', v) end,
  ['FINAL_RATIO'] = 'Final gear ratio',
  ['GEARSET'] = 'Gear set',
  ['ARB_FRONT'] = 'ARB (front)',
  ['ARB_REAR'] = 'ARB (rear)',
}

local function getItemDisplayName(item, value, hint)
  local n = knownNames[item]
  if n then
    return type(n) == 'function' and n(value) or n
  end
  if item:find('PRESSURE_[LR]F') then return 'Tyre pressure (front)' end
  if item:find('PRESSURE_[LR]R') then return 'Tyre pressure (rear)' end
  if item:find('ROD_LENGTH_[LR]F') then return 'Suspension height (front)' end
  if item:find('ROD_LENGTH_[LR]R') then return 'Suspension height (rear)' end
  if item:find('SPRING_RATE_[LR]F') then return 'Suspension wheel rate (front)' end
  if item:find('SPRING_RATE_[LR]R') then return 'Suspension wheel rate (rear)' end
  if item:find('TOE_OUT_[LR]F') then return 'Toe (front)' end
  if item:find('TOE_OUT_[LR]R') then return 'Toe (rear)' end
  if item:find('CAMBER_[LR]F') then return 'Camber (front)' end
  if item:find('CAMBER_[LR]R') then return 'Camber (rear)' end
  if hint then return type(hint) == 'string' and string.replace(hint, ' Gear', ' gear') or hint end
  local id = item:find('WING_(%d)')
  if id then return 'Wing #'..id end
  return item
end

local function getSetupTooltip(setupInfo)
  local known = setupTooltips[setupInfo.setupID]
  if known == nil then
    setupTooltips[setupInfo.setupID] = false
    getSetupData(setupInfo, false, function (err, data)
      if err then
        setupTooltips[setupInfo.setupID] = 'Failed to get setup data: '..err
      else
        local parsed = table.map(ac.INIConfig.parse(data).sections, function (item, index) return item.VALUE and tonumber(item.VALUE[1]), index end)
        local spinners = table.map(ac.getSetupSpinners(), function (i) return i.defaultValue and {i.defaultValue, i.label}, i.name end)
        local custom = {}
        for k, v in pairs(parsed) do
          if spinners[k] and spinners[k][1] ~= v then
            table.insert(custom, getItemDisplayName(k, v, spinners[k][2]))
          end
        end
        custom = table.distinct(table.filter(custom, function (item) return #item > 0 end))
        table.sort(custom)
        if #custom == 0 then
          setupTooltips[setupInfo.setupID] = 'No changes from default setup are detected.'
        else
          setupTooltips[setupInfo.setupID] = 'Changes:\n• '..table.join(custom, ';\n• ')..'.'
        end

        local tyresName = ac.getTyresLongName(0, parsed['TYRES'] or 999)
        if #tyresName > 0 then
          setupTooltips[setupInfo.setupID] = setupTooltips[setupInfo.setupID]..'\n\nTyres: '..ac.getTyresLongName(0, parsed['TYRES'])
        end
      end
    end)
  end
  return setupTooltips[setupInfo.setupID]
end

local listOfSetupsContinuation
local setupsTotalCount = 0
local function refreshSetups()
  if not listOfSetups then
    local key = math.random()
    listOfSetups, listOfSetupsContinuation = key, nil
    refreshGenList('setupID', 'setups', {
      carID = authorUsernameFilter == '' and mainCarID or nil,
      trackID = authorUsernameFilter == '' and stored.setupsFilterTrack and ac.getTrackID() or nil,
      userName = authorUsernameFilter ~= '' and authorUsernameFilter or nil,
      search = authorUsernameFilter == '' and searchFilter ~= '' and searchFilter or nil,
      orderBy = setupsOrder[stored.setupsOrder][2]
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

local function initialLoading()
  if initializing or v3 then return end
  initializing = true
  rest('GET', 'user', {carID = mainCarID, carName = ac.getCarName(0), trackID = ac.getTrackID(), trackName = ac.getTrackName()}, function (response)
    ownUserID = response.userID or error('UserID is missing')
    ac.log('My user ID: '..ownUserID)
  end, function (err)
    ac.warn('Failed to get own user ID: '..err)
  end)
  rest('GET', 'likes', {carID = mainCarID}, function (data)
    for _, v in ipairs(data) do
      table.insert(v.direction == 1 and likedSetups or dislikedSetups, v.setupID)
    end
  end)
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

local icons = ui.atlasIcons('res/icons.png', 4, 1, {
  Like = {1, 1},
  Dislike = {1, 2},
  Comments = {1, 3},
  Download = {1, 4},
})

local iconSize = vec2(10, 10)
local iconAlign = vec2(0, 0.6)
local iconLikeAlign = vec2(0, 0)
local iconDislikeAlign = vec2(0, 1)

local function shareSetup(name)
  ac.saveCurrentSetup(temporaryName)
  rest('POST', 'setups', {
    carID = mainCarID,
    trackID = ac.getTrackID(),
    name = name,
    userName = stored.userName,
    data = io.load(temporaryName)
  }, function (response)
    ui.toast(ui.Icons.Settings, 'Setup shared', function ()
      removeSetup(response.setupID)
    end)
    listOfSetups = nil
  end, function (err)
    ui.toast(ui.Icons.Warning, 'Failed to share setup: '..err)
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

function script.windowMainSettings()
  if ui.checkbox('Show window in setup', ac.isWindowOpen('main_setup')) then
    ac.setWindowOpen('main_setup', not ac.isWindowOpen('main_setup'))
  end
end

local function commentsBlock()
  local item = discussingItem
  local comment = discussingComments[item.setupID] or ''
  local comments = refreshComments()
  if not comments then
    ui.drawLoadingSpinner(ui.windowSize() / 2 - 20, ui.windowSize() / 2 + 20)
    -- ui.text('Loading list of comments…')
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

        if v2 then
          local i = string.find(v.data, '@'..stored.userName, 1, true)
          if i then
            ui.setNextTextSpanStyle(i, i + 1 + #stored.userName, ownColor, true)
          end
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
    rest('POST', 'comments', {setupID = item.setupID, userName = stored.userName, data = comment:trim()}, function (response)
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

local function windowGeneric(paddingDown)
  if discussingItem and not v2 then
    if ui.button('    Back') then
      discussingItem = nil
      listOfComments = nil
      listOfCommentsPrev = nil
      return
    end
    ui.addIcon(ui.Icons.ArrowLeft, iconSize, iconAlign, rgbm.colors.white)

    local item = discussingItem
    ui.sameLine()
    ui.text('Comments ('..item.name..' by '..item.userName..')')
    commentsBlock()
    return
  end

  local setups = refreshSetups()
  if not setups then
    ui.drawLoadingSpinner(ui.windowSize() / 2 - 20, ui.windowSize() / 2 + 20)
    initialLoading()
    return
  end

  if type(setups) == 'string' then
    if v3 then ui.pushAlignment(true) end
    ui.text('Failed to load setups:')
    ui.text(setups)
    ui.setNextItemIcon(ui.Icons.Restart)
    if ui.button('Try again', vec2(-0.1, 0)) then
      listOfSetups = nil
    end
    if v3 then ui.popAlignment() end
    return
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
    local n = string.format('%d setup%s by %s:', setupsTotalCount, setupsTotalCount == 1 and '' or 's', authorUsernameFilter)
    if v2 and authorUsernameFilter == stored.userName then
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
    ui.header(string.format('%d setup%s matching “%s”:', setupsTotalCount, setupsTotalCount == 1 and '' or 's', searchFilter))
  else
    ui.header(string.format('%d fitting setup%s:', setupsTotalCount, setupsTotalCount == 1 and '' or 's'))
  end

  ui.pushFont(ui.Font.Small)
  ui.sameLine(0, 0)
  ui.offsetCursorX(ui.availableSpaceX() - 144)
  if ui.availableSpaceX() < 144 then
    ui.newLine(0)
  end
  ui.setNextItemWidth(120)
  ui.combo('##sort', setupsOrder[stored.setupsOrder][1], ui.ComboFlags.HeightLarge, function ()
    ui.pushFont(ui.Font.Main)
    if ui.checkbox('Show setups for current track only', stored.setupsFilterTrack) then
      stored.setupsFilterTrack = not stored.setupsFilterTrack
      listOfSetups = nil
    end
    ui.offsetCursorY(12)
    ui.header('Sort:')
    ui.offsetCursorY(4)
    for i, v in ipairs(setupsOrder) do
      if ui.selectable(v[1], i == stored.setupsOrder) then
        stored.setupsOrder = i
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
  if ui.button('…') and v2 then
    ui.popup(function ()
      ui.text('Your name: '..stored.userName)
      if ui.selectable('Change name', false) then
        ui.modalPrompt('Change name', 'New name:', stored.userName, function (newName)
          if not newName or #newName:trim() == 0 then return end
          rest('POST', 'user', { userName = newName:trim() }, function ()
            ui.toast(ui.Icons.Confirm, 'Name changed')
            stored.userName = newName:trim()
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
      if ui.selectable('Your setups…') then
        authorUsernameFilter = stored.userName
        listOfSetups = nil
      end
    end, {position = ui.windowPos() + ui.itemRectMin() + vec2(0, 20)})
  end
  if not v2 then
    ui.itemPopup(ui.MouseButton.Left, function ()
      ui.text('Your name: '..stored.userName)
      if ui.selectable('Change name', false) then
        ui.modalPrompt('Change name', 'New name:', stored.userName, function (newName)
          if not newName or #newName:trim() == 0 then return end
          rest('POST', 'user', { userName = newName:trim() }, function ()
            ui.toast(ui.Icons.Confirm, 'Name changed')
            stored.userName = newName:trim()
            listOfSetups = nil
          end, function (err)
            ui.toast(ui.Icons.Warning, 'Couldn’t change name: '..err)
          end)
        end)
      end
      if ui.itemHovered() then
        ui.setTooltip('Changing name would also change it for all published content')
      end
    end)
  end
  ui.popFont()

  ui.childWindow('scroll', ui.availableSpace():sub(vec2(0, paddingDown or 40)), function ()
    ui.offsetCursorY(8)
    if #setups == 0 then
      ui.textDisabled('No fitting setups available yet.')
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
          ui.text('Car:')
          ui.sameLine(80)
          if v.carID == mainCarID then ui.pushStyleColor(ui.StyleColor.Text, ownColor) end
          ui.text(v.carID)
          if v.carID == mainCarID then ui.popStyleColor() end
        end
        
        if authorUsernameFilter ~= '' or not stored.setupsFilterTrack then
          ui.text('Track:')
          ui.sameLine(80)
          ui.text(trackNames[v.trackID] or v.trackID)
        end
        
        -- ui.text('Author:')
        -- ui.sameLine(80)
        -- if v.userID == ownUserID then ui.pushStyleColor(ui.StyleColor.Text, ownColor) end
        -- ui.text(v.userName)
        -- if v.userID == ownUserID then ui.popStyleColor() end

        ui.text('Posted:')
        ui.sameLine(80)
        ui.text(os.date('%Y/%m/%d %H:%M', v.createdDate))
 
        ui.text('Downloads:')
        ui.sameLine(80)
        ui.text(v.statDownloads)

        ui.endGroup()
        if ui.itemHovered() then
          local tooltip = getSetupTooltip(v)
          ui.pushStyleVar(ui.StyleVar.Alpha, 1)
          if tooltip then
            ui.setTooltip(v.name:trim()..'\n\n'..tooltip)
          else
            ui.setTooltip(v.name:trim())
          end
          ui.popStyleVar()
        end

        if ac.isSetupAvailableToEdit() and v.carID == mainCarID then
          if ui.button('     Apply', not currentlyApplying and 0 or ui.ButtonFlags.Disabled) then
            currentlyApplying = true
            getSetupData(v, true, function (err, data)
              currentlyApplying = false
              if err then
                ui.toast(ui.Icons.Warning, 'Failed to load setup: '..err)
              else
                ac.saveCurrentSetup(temporaryBackupName)
                ui.toast(ui.Icons.Confirm, 'Setup loaded', function ()
                  ui.toast(ui.Icons.Confirm, 'Previous setup restored')
                  ac.loadSetup(temporaryBackupName)
                end)
                io.save(temporaryName, data)
                ac.loadSetup(temporaryName)
              end
            end)
          end
          ui.addIcon(icons.Download, iconSize, iconAlign)
          if ui.itemHovered() then
            ui.pushStyleVar(ui.StyleVar.Alpha, 1)
            ui.setTooltip('Setup will be instantly applied (with an option to revert back). To download setup, use context menu.')
            ui.popStyleVar()
          end
          ui.pushStyleVar(ui.StyleVar.Alpha, 1)
          if not v2 then
            ui.itemPopup(function ()
              if ui.selectable('Download', downloadedAsFiles[v.setupID]) then
                downloadSetupAsFile(v)
              end
            end)
          elseif ui.itemClicked(ui.MouseButton.Right, true) then
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
            ui.setTooltip(v.carID == mainCarID 
              and 'Unable to apply setup directly outside of setup menu, but it can be loaded. Use settings to enable Setup Exchange window in setup menu.'
              or 'This setup is for a different car, but you can download it and use it in the next race.')
            ui.popStyleVar()
          end
        end

        ui.sameLine(0, 4)
        likeButtons('likes', v, likedSetups, dislikedSetups, v.setupID, {carID = v.carID})

        ui.sameLine(0, 4)
        if ui.button(string.format('     %d##comments', v.statComments)) then
          if discussingItem == v then
            discussingItem = nil
          else
            discussingItem = v
            if v2 then
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
  if v2 then
    ui.setNextItemIcon(ui.Icons.Settings)
  end
  if ui.button('Share current setup', vec2(ui.availableSpaceX(), 0), sessionID ~= nil and 0 or ui.ButtonFlags.Disabled) then
    ui.modalPrompt('Share setup', 'Name the setup:', nil, 'Share', 'Cancel', nil, nil, function (name)
      if name and #name:trim() > 0 then
        shareSetup(name:trim())
      end
    end)
  end
  if ui.itemHovered() and sessionID == nil then
    ui.setTooltip(sessionError or 'Connecting…')
  end
end

local introHeight = 100

function script.windowMain()
  if not stored.introduced and ac.load('.appShelf.freshlyInstalled.SetupExchange') then
    ui.offsetCursorY(ui.availableSpaceY() / 2 - introHeight / 2)
    local y = ui.getCursorY()
    ui.offsetCursorX(ui.availableSpaceX() / 2 - 32)
    ui.image('icon.png', 64)
    ui.offsetCursorY(20)
    ui.textWrapped('Setup Exchange is a service for sharing, downloading and discussing car setups. All shared setups are kept in a public database.\n\n'
      ..'With this tool, you can access setups from the setup menu as well. Integration is enabled by default, but you can disable it if needed. This option can always be changed in app settings.\n\n')
    ui.setNextItemIcon(ui.Icons.Confirm)
    if ui.button('Keep setup integration enabled', vec2(ui.availableSpaceX(), 0)) then
      stored.introduced = true
      ac.setWindowOpen('main_setup', true)
    end
    ui.setNextItemIcon(ui.Icons.Hide)
    if ui.button('Disable setup integration', vec2(ui.availableSpaceX(), 0)) then
      stored.introduced = true
      ac.setWindowOpen('main_setup', false)
    end
    introHeight = ui.getCursorY() - y
  else
    windowGeneric()
  end
end

function script.windowSetup()
  if ui.windowTitle and string.find(ui.windowTitle(), 'Setups Exchange###', 1, true) == 1 then
    -- A separate window in setup window
    ui.pushFont(ui.Font.Title)
    ui.textAligned('Setup Exchange', vec2(0.5, 0.5), vec2(ui.availableSpaceX(), 34))
    ui.popFont()
    windowGeneric()
  else
    -- Setup window included into new main menu
    windowGeneric()
  end
end
