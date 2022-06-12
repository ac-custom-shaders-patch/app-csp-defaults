--[[
  Simplest client for exchanging setups with comments and likes.
]]

local json = require 'lib/json'
local endpoint = 'http://se.api.acstuff.ru'
-- local endpoint = 'http://127.0.0.1:12016'
local temporaryName = ac.getFolder(ac.FolderID.AppDataLocal)..'/Temp/ac-se-shared.ini'
local temporaryBackupName = ac.getFolder(ac.FolderID.AppDataLocal)..'/Temp/ac-se-backup.ini'
local userKey = ac.checksumSHA256('LB83XurHhTPhpmTc'..ac.uniqueMachineKey())

local function rest(method, url, data, callback, errorHandler)
  if method == 'GET' and data then
    local f = true
    for k, v in pairs(data) do
      url = url..(f and '?' or '&')..k..'='..v
      f = false
    end
  end

  if not callback then callback = function (response) ac.log('Successfully executed: '..url..', response: '..stringify(response)) end end
  if not errorHandler then errorHandler = function (err) ac.warn(err) end end

  web.request(method, endpoint..'/'..url, { ['Content-Type'] = 'application/json', ['X-User-Key'] = userKey }, method ~= 'GET' and json.encode(data) or nil, function (err, response)
    if err then return errorHandler(err) end
    if response.status >= 400 then
      local parsed = try(function ()
        return json.decode(response.body)
      end, function () end)
      if parsed and parsed.error then err = parsed.error else err = response.body end
      return errorHandler(err)
    end

    try(function()
      callback(json.decode(response.body))
    end, errorHandler)
  end)
end

local limit = 20

local function refreshGenList(url, params, callback, offset, resultList)
  if not offset then
    offset, resultList = 0, {}
  end
  rest('GET', url, table.chain(params, {offset = offset}), function (response)
    for _, v in ipairs(response) do table.insert(resultList, v) end
    if #response >= limit then
      refreshGenList(url, params, callback, offset + #response, resultList)
    else
      callback(resultList)
    end
  end, function (err)
    ac.warn('Failed to get list of '..url..': '..err)
    callback(#resultList > 0 and resultList or err)
  end)
end

local setupsOrder = {
  {'Hot', '(statDislikes * 10 - statLikes * 20 - statDownloads - statComments * 2) / max(60, @now - createdDate)'},
  {'Popular', '-statDownloads'},
  {'Liked', 'statDislikes - statLikes * 2'},
  {'Newest', '-createdDate'},
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

local ownUserID
local listOfSetups, listOfComments
local listOfSetupsPrev, listOfCommentsPrev
local likedSetups, dislikedSetups = {}, {}
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
    local filename = ac.getFolder(ac.FolderID.UserSetups)..'/'..ac.getCarID(0)..'/'..name
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
  if hint then return hint end
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
        custom = table.distinct(custom)
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

local function refreshSetups()
  if not listOfSetups then
    local key = math.random()
    listOfSetups = key
    refreshGenList('setups', {carID = ac.getCarID(0), trackID = stored.setupsFilterTrack and ac.getTrackID() or nil, orderBy = setupsOrder[stored.setupsOrder][2]}, function (ret)
      if listOfSetups == key then
        listOfSetups = ret
        listOfSetupsPrev = ret
      end
    end)
  end
  return (type(listOfSetups) == 'table' or type(listOfSetups) == 'string') and listOfSetups or listOfSetupsPrev
end

local function refreshComments()
  if not listOfComments then
    local key = math.random()
    listOfComments = key
    refreshGenList('comments', {setupID = discussingItem.setupID}, function (ret)
      if listOfComments == key then
        listOfComments = ret
        listOfCommentsPrev = ret
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

local function initialLoading()
  if initializing then return end
  initializing = true
  rest('GET', 'user', {carID = ac.getCarID(0), carName = ac.getCarName(0), trackID = ac.getTrackID(), trackName = ac.getTrackName()}, function (response)
    ownUserID = response.userID or error('UserID is missing')
    ac.log('My user ID: '..ownUserID)
  end, function (err)
    ac.warn('Failed to get own user ID: '..err)
  end)
  rest('GET', 'likes', {carID = ac.getCarID(0)}, function (data)
    for _, v in ipairs(data) do
      table.insert(v.direction == 1 and likedSetups or dislikedSetups, v.setupID)
    end
  end)
end

local function removeSetup(id)
  rest('DELETE', 'setups/'..id, nil, function ()
    ui.toast(ui.Icons.Warning, 'Shared setup removed')
    listOfSetups = nil
  end, function (err)
    ui.toast(ui.Icons.Warning, 'Failed to remove shared setup: '..err)
  end)
end

local function removeComment(id)
  rest('DELETE', 'comments/'..id, nil, function ()
    ui.toast(ui.Icons.Warning, 'Comment removed')
    listOfComments = nil
  end, function (err)
    ui.toast(ui.Icons.Warning, 'Failed to remove comment: '..err)
  end)
end

local function shareSetup(name)
  ac.saveCurrentSetup(temporaryName)
  rest('POST', 'setups', {
    carID = ac.getCarID(0),
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
  if ui.button(string.format('Like (%d)', item.statLikes), liked and ui.ButtonFlags.Active or 0) then
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

  ui.sameLine(0, 4)
  if ui.button(string.format('Dislike (%d)', item.statDislikes), disliked and ui.ButtonFlags.Active or 0) then
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
end

function script.windowMainSettings()
  if ui.checkbox('Show window in setup', ac.isWindowOpen('main_setup')) then
    ac.setWindowOpen('main_setup', not ac.isWindowOpen('main_setup'))
  end
end

local function windowGeneric()
  if discussingItem then
    if ui.button('← Back') then
      discussingItem = nil
      listOfComments = nil
      listOfCommentsPrev = nil
      return
    end
    local item = discussingItem
    local comment = discussingComments[item.setupID] or ''
    ui.sameLine()
    ui.text('Comments ('..item.name..' by '..item.userName..')')

    local comments = refreshComments()
    if not comments then
      ui.text('Loading list of comments…')
      return
    end

    if type(comments) == 'string' then
      ui.text('Failed to load comments:')
      ui.text(comments)
      return
    end

    ui.childWindow('commentsScroll', ui.availableSpace() - vec2(0, 40), function ()
      ui.offsetCursorY(8)
      for _, v in ipairs(comments) do
        if ui.areaVisible(commentSize) then
          local y = ui.getCursorY()
          ui.pushID(v.commentID)
          ui.pushFont(ui.Font.Small)
          if v.userID == ownUserID then ui.pushStyleColor(ui.StyleColor.Text, ownColor) end
          ui.text(v.userName)
          if v.userID == ownUserID then ui.popStyleColor() end
          ui.sameLine(0, 0)
          ui.text(string.format(' • %s', os.date('%Y/%m/%d %H:%M', v.createdDate)))
          ui.popFont()

          ui.text(v.data)

          ui.pushFont(ui.Font.Small)
          if ui.button('Reply') then
            comment = '@'..v.userName..' '..comment
          end

          ui.sameLine(0, 4)
          likeButtons('comment-likes', v, likedComments, dislikedComments, v.commentID, {setupID = item.setupID})

          if v.userID == ownUserID then
            ui.sameLine(0, 4)
            if ui.button('Delete') then
              removeComment(v.commentID)
              item.statComments = item.statComments - 1
            end
          end
          ui.popFont()
          
          ui.popID()
          ui.offsetCursorY(12)
          itemSize.y = ui.getCursorY() - y
        else
          ui.offsetCursorY(commentSize.y)
        end
      end
    end)

    local _, submitted
    comment, _, submitted = ui.inputText('Add a comment…', comment, ui.InputTextFlags.Placeholder)
    ui.sameLine(0, 4)
    local canSend = #comment:trim() > 0 and not currentlySubmittingComment
    if (ui.button('Send', vec2(ui.availableSpaceX(), 0), canSend and 0 or ui.ButtonFlags.Disabled) or submitted) and canSend then
      currentlySubmittingComment = true
      rest('POST', 'comments', { setupID = item.setupID, userName = stored.userName, data = comment:trim() }, function (response)
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
    discussingComments[item.setupID] = comment
    return
  end

  local setups = refreshSetups()
  if not setups then
    ui.text('Loading list of setups…')
    initialLoading()
    return
  end

  if type(setups) == 'string' then
    ui.text('Failed to load setups:')
    ui.text(setups)
    return
  end

  ui.alignTextToFramePadding()
  ui.header('Found setups:')

  ui.pushFont(ui.Font.Small)
  ui.sameLine(0, 0)
  ui.offsetCursorX(ui.availableSpaceX() - 144)
  ui.setNextItemWidth(120)
  ui.combo('##sort', setupsOrder[stored.setupsOrder][1], function ()
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
  end)
  ui.sameLine(0, 4)
  ui.button('…')
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
  ui.popFont()

  ui.childWindow('scroll', ui.availableSpace() - vec2(0, 40), function ()
    ui.offsetCursorY(8)
    if #setups == 0 then
      ui.text('<None>')
      return
    end
    for _, v in ipairs(setups) do
      if ui.areaVisible(itemSize) then
        local y = ui.getCursorY()
        ui.pushID(v.setupID)
        ui.beginGroup()

        ui.text(v.name)
        ui.pushFont(ui.Font.Small)
        
        if not stored.setupsFilterTrack then
          ui.text('Track:')
          ui.sameLine(80)
          ui.text(v.trackID)
        end
        
        ui.text('Author:')
        ui.sameLine(80)
        if v.userID == ownUserID then ui.pushStyleColor(ui.StyleColor.Text, ownColor) end
        ui.text(v.userName)
        if v.userID == ownUserID then ui.popStyleColor() end

        ui.text('Created at:')
        ui.sameLine(80)
        ui.text(os.date('%Y/%m/%d %H:%M', v.createdDate))
 
        ui.text('Downloads:')
        ui.sameLine(80)
        ui.text(v.statDownloads)

        ui.endGroup()
        if ui.itemHovered() then
          local tooltip = getSetupTooltip(v)
          if tooltip then
            ui.setTooltip(tooltip)
          end
        end

        if ac.isSetupAvailableToEdit() then
          if ui.button('Apply', not currentlyApplying and 0 or ui.ButtonFlags.Disabled) then
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
          if ui.itemHovered() then
            ui.setTooltip('Setup will be instantly applied (with an option to revert back). To download setup, use context menu.')
          end
          ui.itemPopup(function ()
            if ui.selectable('Download', downloadedAsFiles[v.setupID]) then
              downloadSetupAsFile(v)
            end
          end)
        else
          if ui.button('Download', downloadedAsFiles[v.setupID] and ui.ButtonFlags.Active or not currentlyApplying and 0 or ui.ButtonFlags.Disabled) then
            downloadSetupAsFile(v)
          end
          if ui.itemHovered() then
            ui.setTooltip('Unable to apply setup directly outside of setup menu, but it can be loaded. Use settings to enable Setup Exchange window in setup menu.')
          end
        end

        ui.sameLine(0, 4)
        likeButtons('likes', v, likedSetups, dislikedSetups, v.setupID, {carID = ac.getCarID(0)})

        ui.sameLine(0, 4)
        if ui.button(string.format('Discussion (%d)', v.statComments)) then
          discussingItem = v
        end

        if v.userID == ownUserID then
          ui.sameLine(0, 4)
          if ui.button('Delete') then
            removeSetup(v.setupID)
          end
        end

        ui.popFont()

        ui.offsetCursorY(12)
        ui.popID()
        itemSize.y = ui.getCursorY() - y
      else
        ui.offsetCursorY(itemSize.y)
      end
    end
  end)

  ui.offsetCursorY(12)
  if ui.button('Share current setup', vec2(ui.availableSpaceX(), 0)) then
    ui.modalPrompt('Share setup', 'Name the setup:', nil, 'Share', 'Cancel', nil, nil, function (name)
      if name then
        shareSetup(name)
      end
    end)
  end
  if ui.itemHovered() then
    ui.setTooltip('Your name: '..ac.getDriverName(0))
  end
end

local introHeight = 100

function script.windowMain()
  if not stored.introduced then
    ui.offsetCursorY(ui.availableSpaceY() / 2 - introHeight / 2)
    local y = ui.getCursorY()
    ui.offsetCursorX(ui.availableSpaceX() / 2 - 32)
    ui.image('icon.png', 64)
    ui.offsetCursorY(20)
    ui.textWrapped('Setup Exchange is a service for sharing, downloading and discussing car setups. All shared setups are kept in a public database.\n\n'
      ..'Optionally, there is also a setup menu integration, allowing to apply shared setups directly with a single click. Would you want to enable it? You can always toggle it in app settings.\n\n')
    if ui.button('Yes, enable setup integration', vec2(ui.availableSpaceX(), 0)) then
      stored.introduced = true
      ac.setWindowOpen('main_setup', true)
    end
    if ui.button('OK, keep setup integration disabled', vec2(ui.availableSpaceX(), 0)) then
      stored.introduced = true
    end
    introHeight = ui.getCursorY() - y
  else
    windowGeneric()
  end
end

function script.windowSetup()
  ui.pushFont(ui.Font.Title)
  ui.textAligned('Setup Exchange', vec2(0.5, 0.5), vec2(ui.availableSpaceX(), 34))
  ui.popFont()
  windowGeneric()
end
