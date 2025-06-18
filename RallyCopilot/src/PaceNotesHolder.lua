local PaceNotes = require('src/PaceNotes')
local RouteItem = require('src/RouteItem')
local AppConfig = require('src/AppConfig')

local selectedKey = '.selected:'..ac.getTrackFullID(':')
local generated ---@type PaceNotes?
local beingEdited ---@type PaceNotes?
local current ---@type PaceNotes
local pns ---@type PaceNotes[]?
local dir = ac.getFolder(ac.FolderID.ScriptConfig)..'\\'..ac.getTrackFullID('-')

local PaceNotesHolder = {}

local function getGeneratedNotes()
  if not generated then
    generated = PaceNotes.generate()
  end
  return generated
end

local previouslySelected = ac.storage[selectedKey]
if previouslySelected and io.fileExists(previouslySelected) then
  current = PaceNotes(previouslySelected)
  if current.metadata.error then
    ac.warn('Pacenotes are damaged: %s' % current.metadata.error)
    current = PaceNotes.generate()
  end
else
  current = getGeneratedNotes()
end

local function loadNotes(filename)
  local item = (filename or ''):lower() == (current.filename or ''):lower() and current or PaceNotes(filename)
  if current.metadata.error then
    ac.warn('Pacenotes are damaged: %s' % current.metadata.error)
  elseif pns then
    table.insert(pns, item)
  end
end

---@return PaceNotes[]
function PaceNotesHolder.list()
  if not pns then
    pns = {getGeneratedNotes()}
    if io.dirExists(dir) then
      io.scanDir(dir, '*.rc-notes', function (id, attrs)
        if not attrs.isDirectory then
          loadNotes(dir..'\\'..id)
        end
      end)
    end
    local trackDir = ac.getFolder(ac.FolderID.CurrentTrackLayout)..'\\data'
    if io.dirExists(trackDir) then
      io.scanDir(trackDir, '*.rc-notes', function (id, attrs)
        if not attrs.isDirectory then
          loadNotes(dir..'\\'..id)
        end
      end)
    end
  end
  return pns
end

---@return PaceNotes[]
function PaceNotesHolder.loaded()
  if not pns then
    return {current}
  end
  return pns
end

---@param pn PaceNotes
function PaceNotesHolder.select(pn)
  if not pn then return end
  if pns and not table.contains(pns, pn) then
    pn = getGeneratedNotes()
  end
  current = pn
  ac.storage[selectedKey] = pn.filename
end

---@param pn PaceNotes
function PaceNotesHolder.delete(pn)
  if not pn or pn:generated() then return end
  PaceNotesHolder.list()
  if not pns then error() end
  local data = io.load(pn.filename)
  local pos = table.indexOf(pns, pn)
  io.deleteFile(pn.filename)
  table.remove(pns, pos)
  ui.toast(ui.Icons.Trash, 'Pacenotes removed', data and function ()
    io.save(pn.filename, data)
    table.insert(pns, pos or #pns + 1, pn)
  end)
  if pn == current then
    PaceNotesHolder.select(getGeneratedNotes())
  end
end

local function getUniqueFilename()
  for i = 1, 1e4 do
    local candidate = '%s\\%d.rc-notes' % {dir, i}
    if not io.fileExists(candidate) then
      return candidate
    end
  end
  error('Too many pacenotes')
end

local function getUniqueName()
  for i = 1, 1e4 do
    local candidate = 'Pacenotes #%d' % i
    if pns and not table.some(pns, function (item) return item.metadata.name == candidate end) then
      return candidate
    end
  end
  return 'Pacenotes'
end

---@param data binary
---@param remoteTrackID string?
---@return PaceNotes
function PaceNotesHolder.add(data, remoteTrackID)
  PaceNotesHolder.list()
  if not pns then error() end
  local dst = '%s\\r-%s.rc-notes' % {ac.getFolder(ac.FolderID.ScriptConfig)..'\\'..string.replace(remoteTrackID or AppState.exchangeTrackID, ':', '-'), bit.tohex(ac.checksumXXH(data))}
  if io.fileExists(dst) then
    return table.findFirst(pns, function (item)
      return item.filename == dst
    end) or error('Unexpected state')
  else
    io.save(dst, data)
    table.insert(pns, PaceNotes(dst))
    return pns[#pns]
  end
end

---@param pn PaceNotes
---@param newName string?
---@return PaceNotes
function PaceNotesHolder.clone(pn, newName)
  PaceNotesHolder.list()
  if not pns then error() end
  table.insert(pns, PaceNotes(getUniqueFilename(), table.map(pn.items, RouteItem.clone), {name = newName or getUniqueName(), author = AppConfig.userName, canBeShared = true}))
  pns[#pns].new = true
  return pns[#pns]
end

---@param pn PaceNotes?
function PaceNotesHolder.edit(pn)
  PaceNotesHolder.list()
  if not pns then error() end
  if not pn then
    pn = PaceNotes(getUniqueFilename(), {}, {name = getUniqueName(), author = AppConfig.userName, canBeShared = true})
    pn.new = true
    table.insert(pns, pn)
  elseif pn:generated() or not pn.metadata.canBeShared then
    pn = PaceNotesHolder.clone(pn, not pn:generated() and (pn.metadata.name:endsWith(' (edit)') and pn.metadata.name or pn.metadata.name..' (edit)') or nil)
  end
  beingEdited = pn
  PaceNotesHolder.select(pn)
end

function PaceNotesHolder.generated()
  return getGeneratedNotes()
end

function PaceNotesHolder.current()
  return current
end

function PaceNotesHolder.edited()
  return beingEdited
end

return PaceNotesHolder