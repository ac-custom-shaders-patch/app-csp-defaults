---@class VoiceMode
---@field private phrases string[]
---@field private ids string[]
---@field private idToIndices table<string, integer>
---@field private routeItemToPhrasesConverter fun(type: RouteItemType, modifier: integer, hints: RouteItemHint[], tags: string[], continuation: boolean): integer[]|nil
---@field private phraseIconAccessor fun(phraseIndex: integer): ui.ImageSource|nil
---@field private preloadChecker nil|fun(phraseIndex: integer): boolean
local VoiceMode = class('VoiceMode')

---@param phrases string[]
---@param routeItemToPhrasesConverter fun(type: RouteItemType, modifier: integer, hints: RouteItemHint[], tags: string[], continuation: boolean): integer[]|nil
---@param phraseIconAccessor fun(phraseIndex: integer): ui.ImageSource|nil
---@param preloadChecker nil|fun(phraseIndex: integer): boolean
---@return VoiceMode
function VoiceMode.allocate(phrases, routeItemToPhrasesConverter, phraseIconAccessor, preloadChecker)
  return {
    phrases = phrases,
    ids = table.map(phrases, string.lower),
    idToIndices = table.map(phrases, function (name, index)
      return index, string.lower(name)
    end),
    routeItemToPhrasesConverter = routeItemToPhrasesConverter,
    phraseIconAccessor = phraseIconAccessor,
    preloadChecker = preloadChecker,
  }
end

---@return integer
function VoiceMode:size()
  return #self.phrases
end

---@return string[]
function VoiceMode:list()
  return self.phrases
end

local emptyArray = {}

---@param type RouteItemType
---@param modifier integer
---@param hints RouteItemHint[]
---@param tags string[]?
---@param continuation boolean
---@return integer[]
function VoiceMode:convert(type, modifier, hints, tags, continuation)
  return self.routeItemToPhrasesConverter(type, modifier, hints, tags or emptyArray, continuation) or emptyArray
end

---@param type RouteItemType
---@return ui.ImageSource|nil
function VoiceMode:icon(type)
  return self.phraseIconAccessor(type)
end

---@param index integer
---@return string
function VoiceMode:label(index)
  return self.phrases[index] or ''
end

---@param index integer
---@return string
function VoiceMode:indexToID(index)
  return self.ids[index] or 'none'
end

---@param id string
---@return integer
function VoiceMode:idToIndex(id)
  return self.idToIndices[id] or 1
end

---@param index integer
---@return boolean
function VoiceMode:needsPreload(index)
  return not self.preloadChecker or self.preloadChecker(index)
end

return class.emmy(VoiceMode, VoiceMode.allocate)