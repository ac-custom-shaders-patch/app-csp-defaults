
local AppConfig = require('src/AppConfig')
local Voice = require('src/Voice')

local current = Voice(AppConfig.voice):preload()
local voices ---@type Voice[]?

local VoicesHolder = {}

---@return Voice[]
function VoicesHolder.list()
  if not voices then
    voices = {}
    io.scanDir(__dirname..'\\voices', function (id, attrs)
      if attrs.isDirectory then
        voices[#voices + 1] = id == AppConfig.voice and current or Voice(id)
      end
    end)
    ac.onFolderChanged(__dirname..'\\voices', nil, false, function ()
      local voicesDictionary = table.map(voices, function (item) return item, item.id end)
      voices = {}
      io.scanDir(__dirname..'\\voices', function (id, attrs)
        if attrs.isDirectory then
          voices[#voices + 1] = voicesDictionary[id] or Voice(id)
        end
      end)
      if not table.contains(voices, current) then
        current = voices[1] or Voice(AppConfig.voice)
      end
    end)
  end
  return voices
end

---@return Voice[]
function VoicesHolder.loaded()
  if not voices then
    return {current}
  end
  return voices
end

---@param voice Voice
function VoicesHolder.select(voice)
  if not voice then return end
  current = voice:preload()
  AppConfig.voice = voice.id
end

function VoicesHolder.current()
  return current
end

function VoicesHolder.update(dt)
  current:update(dt, ac.getAudioVolume(AppState.volumeKey, nil, 1))
end

---@param items RouteItem[]
---@param from number
---@param to number
function VoicesHolder.enqueue(items, from, to)
  for _, v in ipairs(items) do
    if v.pos > from and v.pos <= to then
      current:enqueue(v.type, v.modifier, v.hints, {})
    end
  end
end

return VoicesHolder