local RouteItemHint = require "src/RouteItemHint"
---@alias RouteItemType 
---| `RouteItemType.TurnLeft` @Param: caution from 1 to 6.
---| `RouteItemType.TurnRight` @Param: caution from 1 to 6.
---| `RouteItemType.KeepLeft` @Param: none.
---| `RouteItemType.KeepRight` @Param: none.
---| `RouteItemType.Straight` @Param: distance, index of one of `knownStraightIntervals`.
---| `RouteItemType.Jump` @Param: type from 1 (big jump) to 3 (overcrest).
---| `RouteItemType.Narrows` @Param: none. 
---| `RouteItemType.OverBridge` @Param: none.
---| `RouteItemType.SurfaceType` @Param: 1 for tarmac, 2 for gravel, 3 for sand, 4 for asphalt.

local RouteItemType = const({
  TurnLeft = 1, ---@type RouteItemType
  TurnRight = 2, ---@type RouteItemType
  KeepLeft = 3, ---@type RouteItemType
  KeepRight = 4, ---@type RouteItemType
  Straight = 5, ---@type RouteItemType
  Jump = 6, ---@type RouteItemType
  Narrows = 7, ---@type RouteItemType
  OverBridge = 8, ---@type RouteItemType
  SurfaceType = 9, ---@type RouteItemType
  Extra = 100, ---@type RouteItemType
})

local typeNames = {
  'Turn left',
  'Turn right',
  'Keep left',
  'Keep right',
  'Straight',
  'Jump',
  'Narrows',
  'Over bridge',
  'On…',
}

local knownStraightIntervals = {20, 30, 40, 50, 70, 100, 200, 300, 400, 500}
local iconTurnModifiers = table.range(6, function (i) return i == 1 and 'Hairpin' or '%s out of 6' % i end)
local iconJumpModifiers = {'Big jump', 'Jump', 'Overcrest'}
local iconSurfaceTypeModifiers = {'Tarmac', 'Gravel', 'Sand', 'Asphalt'}
local iconStraightModifiers = table.map(knownStraightIntervals, function (x) return '%.0f m' % x end)
local straightIconsCache = {}
local hintedIconsCache = {}
local iconsCache = {}
local defaultColor = rgb(0.8, 0.8, 0.8)

---@return table<RouteItemType, string>
function RouteItemType.names()
  return typeNames
end

---@param type RouteItemType
---@return string
function RouteItemType.name(type)
  return typeNames[type] or 'Unknown'
end

local colors = {
  rgb.new('#80101D'):scale(1.6),
  rgb.new('#D7331E'),
  rgb.new('#C66117'),
  rgb.new('#E4BA11'),
  rgb.new('#72BE04'),
  rgb.new('#2EC273'),
}

---@param type RouteItemType
---@param modifier integer?
---@param uiMode boolean?
---@return rgb
function RouteItemType.color(type, modifier, uiMode)
  local fallback = uiMode and rgb.colors.white or defaultColor
  if type == RouteItemType.Jump then
    return colors[modifier + 2] or fallback
  end
  if type ~= RouteItemType.TurnLeft and type ~= RouteItemType.TurnRight and type >= 1 then
    return fallback
  end
  return colors[modifier] or fallback
end

---@param type RouteItemType
---@param modifier integer?
---@param hintsCount integer
local function iconTextureBase(type, modifier, hintsCount)
  if type < RouteItemType.TurnLeft then
    return 'res/icons/hint-caution.png'
  end
  if type == RouteItemType.TurnLeft then
    if modifier == 1 then
      return 'res/icons/type-uturn-left.png'
    end
    return 'res/icons/type-turn-left.png'
  end
  if type == RouteItemType.TurnRight then
    if modifier == 1 then
      return 'res/icons/type-uturn-right.png'
    end
    return 'res/icons/type-turn-right.png'
  end
  if type == RouteItemType.KeepLeft then
    return 'res/icons/type-keep-left.png'
  end
  if type == RouteItemType.KeepRight then
    return 'res/icons/type-keep-right.png'
  end
  if type == RouteItemType.Straight then
    if modifier and knownStraightIntervals[modifier] then
      local key = modifier..';'..hintsCount
      local withInterval = straightIconsCache[key]
      if not withInterval then
        withInterval = ui.ExtraCanvas(256, 4)
        withInterval:update(function ()
          ui.beginMIPBias()
          ui.drawImage('res/icons/type-forward.png', vec2(), vec2(256, 0.67 * 256), vec2(), vec2(1, 0.67), nil)
          ui.endMIPBias(-0.8)
          ui.pushDWriteFont('@System;Weight=Bold')
          ui.dwriteDrawTextClipped('%.0f m' % knownStraightIntervals[modifier], 64, vec2(0, 192), vec2(256, 256), 
            ui.Alignment.Center, ui.Alignment.Center, false, rgbm.colors.black)
          ui.popDWriteFont()
        end)
        straightIconsCache[key] = withInterval
      end
      return withInterval
    end
    return 'res/icons/type-forward.png'
  end
  if type == RouteItemType.Jump then
    return 'res/icons/type-jump.png'
  end
  if type == RouteItemType.Narrows then
    return 'res/icons/type-narrows.png'
  end
  if type == RouteItemType.OverBridge then
    return 'res/icons/type-bridge.png'
  end
  if type == RouteItemType.SurfaceType then
    return 'res/icons/type-surface.png'
  end
  return 'color::#000000'
end

---@param type RouteItemType
---@param hintsCount integer
local function computeIconOffset(type, modifier, hintsCount)
  if type == RouteItemType.TurnRight and modifier > 1 then
    return 20 + 15 * hintsCount
  end
  if type == RouteItemType.TurnLeft then
    return 10 + 5 * hintsCount
  end
  return 0
end

---@param type RouteItemType
---@param modifier integer?
---@param hints RouteItemHint[]?
---@return ui.ImageSource
function RouteItemType.iconTexture(type, modifier, hints)
  if hints and #hints > 0 then
    local baseIcon = iconTextureBase(type, modifier, #hints)
    local hintsKey = tostring(baseIcon)..'!'..#hints
    local hinted = hintedIconsCache[hintsKey]
    if not hinted then
      hinted = ui.ExtraCanvas(256, 4)
      hinted:update(function ()
        local offset = computeIconOffset(type, modifier, #hints)
        ui.drawImage(baseIcon, vec2(-offset, 0), vec2(256 - offset, 256))
      end)
      hintedIconsCache[hintsKey] = hinted
    end
    return hinted
  end
  return iconTextureBase(type, modifier, 0)
end

---@param type RouteItemType
---@param modifier integer?
---@param hints RouteItemHint[]?
---@return ui.ImageSource
function RouteItemType.iconOverlay(type, modifier, hints)
  if hints and #hints > 0 then
    local baseIcon = iconTextureBase(type, modifier, #hints)
    local hintsKey = tostring(baseIcon)..table.concat(hints, '.')
    local hinted = hintedIconsCache[hintsKey]
    if not hinted then
      hinted = ui.ExtraCanvas(256, 4)
      hinted:update(function ()
        ui.beginMIPBias()
        for i = 1, math.min(#hints, 3) do
          local m, r = vec2(256 * 0.82, 256 * (0.82 - (i - 1) * 0.32)), 0.15 * 256
          if type ~= RouteItemType.TurnLeft and type ~= RouteItemType.TurnRight then
            m.x, m.y = m.y, m.x
          end
          ui.drawCircleFilled(m, r, rgbm.colors.white, 48)
          ui.drawImage(RouteItemHint.icon(hints[i]), m - r, m + r)
        end
        ui.endMIPBias(-0.8)
      end)
      hintedIconsCache[hintsKey] = hinted
    end
    return hinted
  else
    return 'color::#00000000'
  end
end

---@param type RouteItemType
---@param modifier integer?
---@param hints RouteItemHint[]?
---@param uiMode boolean?
---@return ui.ImageSource
function RouteItemType.icon(type, modifier, hints, uiMode)
  if not modifier then
    modifier = -1
  end
  local key = type * 1000 + modifier
  if uiMode then
    key = key + 500
  end
  if hints then
    for i = 1, #hints do
      key = key + bit.lshift(1, hints[i] + 16)
    end
  end
  local ret = iconsCache[key]
  if not ret then
    ret = ui.ExtraCanvas(48, 2)
    ret:updateWithShader({
      blendMode = render.BlendMode.BlendAccurate, 
      textures = {
        txIcon = RouteItemType.iconTexture(type, modifier, hints),
        txOverlay = RouteItemType.iconOverlay(type, modifier, hints)
      },
      values = {
        gColor = modifier < 0 and rgb.colors.white or RouteItemType.color(type, modifier, uiMode),
        gBlackAsTransparent = uiMode == true and 1 or 0
      },
      shader = [[
        float4 main(PS_IN pin) {
          pin.Tex = pin.Tex * 1.4 - 0.2;
          float2 texNrm = pin.Tex * 2 - 1;
          float2 texRem = max(0, abs(texNrm) * 7 - 6);
          if (any(length(texRem) > 3)) discard;
          float4 tx = txIcon.Sample(samLinearBorder0, pin.Tex);
          float4 txOv = txOverlay.SampleBias(samLinearBorder0, pin.Tex * 0.84 + 0.08, -0.5);
          tx = lerp(tx, txOv, txOv.w);
          float4 bg = float4(gColor, 1);
          if (gBlackAsTransparent) bg = float4(bg.rgb, 1 - pow(tx.w, 4));
          else bg.rgb = lerp(bg.rgb, tx.rgb, tx.w);
          return bg;
        }
      ]]
    })
    iconsCache[key] = ret
  end
  return ret
end

---@param distance number
---@return integer?
function RouteItemType.straightDistanceToModifier(distance)
  if distance < 20 then
    return nil
  end
  local candidate, minDifference = -1, math.huge
  for _, g in ipairs(knownStraightIntervals) do
    local difference = math.abs(g - distance)
    if difference < minDifference then
      candidate, minDifference = _, difference
    end
  end
  return candidate
end

---@param type RouteItemType
---@param value integer
---@return integer
function RouteItemType.fitModifier(type, value)
  if type == RouteItemType.TurnLeft or type == RouteItemType.TurnRight then
    return math.clamp(math.round(value), 1, 6)
  elseif type == RouteItemType.Jump then
    return math.clamp(math.round(value), 1, 3)
  elseif type == RouteItemType.SurfaceType then
    return math.clamp(math.round(value), 1, 4)
  elseif type == RouteItemType.Straight then
    return math.clamp(math.round(value), 1, #knownStraightIntervals)
  else
    return -1
  end
end

---@param type RouteItemType
---@return string?, string[]?
function RouteItemType.modifiers(type)
  if type == RouteItemType.TurnLeft or type == RouteItemType.TurnRight then
    return 'Caution', iconTurnModifiers
  elseif type == RouteItemType.Jump then
    return 'Type', iconJumpModifiers
  elseif type == RouteItemType.Straight then
    return 'Distance', iconStraightModifiers
  elseif type == RouteItemType.SurfaceType then
    return 'Surface', iconSurfaceTypeModifiers
  else
    return nil
  end
end

return RouteItemType