local RouteItemType = require('src/RouteItemType')
local RouteItemHint = require('src/RouteItemHint')
local tts = require('shared/utils/tts')

local knownStraightIntervals = {20, 30, 40, 50, 70, 100, 200, 300, 400, 500}

local TTS = {}

---@param type RouteItemType
---@param modifier integer
---@param hints RouteItemHint[]
---@param tags string[]
---@return string?
local function getText(type, modifier, hints, tags)
  if type == RouteItemType.TurnLeft or type == RouteItemType.TurnRight then
    local d = type == RouteItemType.TurnLeft and 'left' or 'right'
    return '%s %s' % {modifier == 1 and 'Hairpin' or tostring(modifier), d}
  end
  if type == RouteItemType.Straight and knownStraightIntervals[modifier] then
    return tostring(knownStraightIntervals[modifier])
  end
  if type == RouteItemType.Narrows then
    return 'Narrows'
  end
  if type == RouteItemType.OverBridge then
    return 'Over bridge'
  end
  if type == RouteItemType.KeepLeft or type == RouteItemType.KeepRight then
    return type == RouteItemType.KeepLeft and 'Keep left' or 'Keep right'
  end
  if type == RouteItemType.Jump then
    return modifier == 1 and 'Big jump' or modifier == 2 and 'Jump' or 'Overcrest'
  end
  if type == RouteItemType.SurfaceType then
    return modifier == 1 and 'On tarmac' or modifier == 2 and 'On gravel' or modifier == 3 and 'On sand' or 'On asphalt'
  end
end

---@param hint RouteItemHint
---@return string?
local function getHintText(hint)
  if hint == RouteItemHint.Caution then return 'caution' end
  if hint == RouteItemHint.Cut then return 'cut' end
  if hint == RouteItemHint.DoNotCut then return 'don\'t cut' end
  if hint == RouteItemHint.KeepLeft then return 'keep left' end
  if hint == RouteItemHint.KeepRight then return 'keep right' end
  if hint == RouteItemHint.Long then return 'long' end
  if hint == RouteItemHint.Open then return 'open' end
  if hint == RouteItemHint.Tightens then return 'tightens' end
  if hint == RouteItemHint.VeryLong then return 'very long' end
end

local queue

local function sayNext(text)
  if not text then
    queue = nil
    return
  end
  tts.say(text, function ()    
    sayNext(table.remove(queue, 1))
  end)
end

---@param type RouteItemType
---@param modifier integer
---@param hints RouteItemHint[]
---@param tags string[]
---@return boolean
function TTS.enqueue(type, modifier, hints, tags)
  local text = getText(type, modifier, hints, tags)
  if not text then return false end
  for _, h in ipairs(hints) do
    local m = getHintText(h)
    if m then
      text = '%s, %s' % {text, m}
    end
  end
  if queue then
    table.insert(queue, text)
  else
    queue = {}
    sayNext(text)
  end
  return true
end

---@param type RouteItemType
---@param modifier integer
function TTS.supports(type, modifier)
  return true
end

---@param dt number
function TTS.update(dt, volume)
end

function TTS.dispose()
end

return TTS