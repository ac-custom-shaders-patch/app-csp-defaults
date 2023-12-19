---@type fun(peak: number): ui.ExtraCanvas
local getTalkingIcon = (function ()
  local cache = table.range(32, function () return false end)
  return function (value)
    local key = 1 + math.floor(value * 31.999)
    local ret = cache[key]
    if not ret then
      ret = ui.ExtraCanvas(64, 3)
      ret:updateWithShader({
        textures = { txIcon = 'res/speaker.png' },
        values = { gPos = math.saturateN(((key - 1) / 32) * 1.3 - 0.1) },
        shader = 'res/speaker.fx',
        cacheKey = 0
      })
      cache[key] = ret
    end
    return ret
  end
end)()

return {
  Cancel = 'vs:_0,0,1,1,1;_0,1,1,0,1',
  Pause = 'vs:_0.2,0,0.2,1,1;_0.8,0,0.8,1,1',
  -- Resume = 'vs:_0.1,0,1,0.5,0.9;_0.1,1,1,0.5,0.9;_0.1,0,0.1,1,1',
  Resume = ui.Icons.Play,
  Stop = 'vs:_0.05,0.1,0.95,0.1,1;_0.05,0.9,0.95,0.9,1;_0.1,0.1,0.1,0.9,1;_0.9,0.1,0.9,0.9,1',
  Atlas = ui.atlasIcons('res/icons.png', 4, 1, {
    VolumeMuted = {1, 1},
  }),
  talkingIcon = getTalkingIcon
}

