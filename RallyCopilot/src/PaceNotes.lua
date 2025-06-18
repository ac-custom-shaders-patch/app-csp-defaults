local AppState = require('src/AppState')
local RouteItem = require('src/RouteItem')
local RouteItemType = require('src/RouteItemType')
local RouteItemHint = require('src/RouteItemHint')
local AppConfig = require('src/AppConfig')

---@alias PaceNotesMetadata {name: string, author: string, canBeShared: boolean?, error: string?}

---@class PaceNotes
---@field filename string?
---@field items RouteItem[]
---@field metadata PaceNotesMetadata
---@field new boolean
---@field private associatedEditor Editor?
local PaceNotes = class('PaceNotes')

---@param filename string
---@return RouteItem[], PaceNotesMetadata
local function loadItems(filename)
  local items = {}
  local data = stringify.tryParse(io.load(filename), {RouteItem = function (...) return {...} end})
  if type(data) ~= 'table' or type(data.items) ~= 'table' or type(data.metadata) ~= 'table' then
    ac.error('File damaged: %s' % filename)
    return {}, {name = io.getFileName(filename), author = '?', error = 'File is damaged'}
  end
  if data.version == 2 then
    for _, v in ipairs(data.items) do
      RouteItem.upgrade(v, data.version)
    end
  elseif data.version ~= 3 and not data.metadata then
    ac.error('Unknown version: %s' % data.version)
    return {}, table.assign(data.metadata, {error = 'Unknown version: %s' % data.version})
  end
  for i, v in ipairs(data.items) do
    items[i] = RouteItem(table.unpack(v))
  end
  return items, data.metadata
end

function PaceNotes:sort()
  table.sort(self.items, function (a, b)
    return a.pos < b.pos
  end)
end

function PaceNotes:editor()
  if self:generated() then
    error('Automatically generated pacenotes can’t be edited')
  end
  if not self.associatedEditor then
    self.associatedEditor = require('src/Editor')(self)
  end
  return self.associatedEditor
end

function PaceNotes:generated()
  return not self.filename
end

function PaceNotes:hasUnsavedChanges()
  return self.associatedEditor and self.associatedEditor.unsavedChanges and self.associatedEditor.state:canUndo() or self.new
end

function PaceNotes:save()
  if self:generated() then
    error('Not available for these pacenotes')
  end
  self:sort()
  io.createFileDir(self.filename)
  io.save(self.filename, stringify({version = 3, items = self.items, metadata = self.metadata}, true))
  self.new = false
end

function PaceNotes:export(name)
  if self:generated() then
    error('Not available for these pacenotes')
  end
  self:sort()
  return stringify({version = 3, items = self.items, metadata = {name = name, author = AppConfig.userName}}, true)
end

---@param filename string?
---@param items RouteItem[]?
---@param metadata PaceNotesMetadata?
---@return PaceNotes
function PaceNotes.allocate(filename, items, metadata)
  if not items and filename then
    items, metadata = loadItems(filename)
  end
  return {filename = filename, items = items, metadata = metadata, new = false}
end

---@return PaceNotes
function PaceNotes.generate()
  ac.perfBegin('Generating pacenotes')

  local sim = ac.getSim()
  local config = require('src/EditorConfig')
  local surfacesAvailable, surfacesLib = pcall(require, 'shared/sim/surfaces')

  -- Number of steps to consider along the track (one point every 2 meters)
  local steps = math.ceil(sim.trackLengthM / config.StepSize)

  -- Helper computing angle between two points (in degrees)
  local d0 = vec3()
  local d1 = vec3()
  local c0 = vec3()
  
  local function computeAngle(p0, p1, p2)
    -- Unlike using :angle(), this version returns sign as well, positive for left and negative for right angles
    d0:set(p1):sub(p0)
    d1:set(p2):sub(p1)
    d0.y, d1.y = 0, 0
    d0:normalize()
    d1:normalize()
    return math.sign(d0:cross(d1, c0).y) * math.deg(math.acos(d0:dot(d1)))
  end

  local k0 = vec2()
  local k1 = vec2()

  local function computeVAngle(p0, p1, p2)
    k0:set(config.StepSize, p1.y - p0.y):normalize()
    k1:set(config.StepSize, p2.y - p1.y):normalize()
    return (p1.y > (p0.y + p2.y) / 2 and 1 or -1) * math.deg(math.acos(math.min(1, k0:dot(k1))))
  end

  local function computeTurnRadius(angleDeg)
    return config.StepSize / (2 * math.sin(math.rad(math.abs(angleDeg)) / 2))
  end

  local function estimateCarSpeed(radius)
    if radius < 10 then return 30 end
    if radius < 30 then return 30 + (radius - 10) * (30 / 20) end
    return math.min(30 + radius, 130)
  end

  ---@param surface nil|'default'|'extraturf'|'grass'|'gravel'|'kerb'|'old'|'sand'|string
  local function surfaceTypeToModifier(surface)
    -- 1 for tarmac, 2 for gravel, 3 for sand, 4 for asphalt.
    if surface == 'default' then return 1 end
    if surface == 'gravel' then return 2 end
    if surface == 'sand' then return 3 end
    if surface == 'old' then return 4 end
    return nil
  end

  local function narrowOnSurfaceChange(from, to, expected)
    if not surfacesAvailable then
      return (from + to) / 2
    end
    for _ = 1, 8 do
      local h = (from + to) / 2
      ac.trackProgressToWorldCoordinateTo(h, c0)
      if surfaceTypeToModifier(surfacesLib.raycastType(c0)) == expected then
        to = h
      else
        from = h
      end
    end
    return from
  end

  local v0 = vec3()
  
  ---@param progress number
  ---@param range number
  ---@param dst vec3
  ---@param dstRaw vec3
  local function trackProgressToWorldCoordinateSmoothTo(progress, range, dst, dstRaw)
    ac.trackProgressToWorldCoordinateTo(progress, dstRaw)
    if range > 0 and false then
      ac.trackProgressToWorldCoordinateTo(progress - range * 0.33, v0)
      dst.x, dst.y, dst.z = dstRaw.x + v0.x, dstRaw.y + v0.y, dstRaw.z + v0.z
      ac.trackProgressToWorldCoordinateTo(progress + range * 0.33, v0)
      dst.x, dst.y, dst.z = (dst.x + v0.x) / 3, (dst.y + v0.y) / 3, (dst.z + v0.z) / 3
    else
      dst.x, dst.y, dst.z = dstRaw.x, dstRaw.y, dstRaw.z
    end
  end

  ---@type RouteItem[]
  local ret = {}

  -- List storing angles along the track 
  ---@type {angle: number, vAngle: number, speed: number, pos: vec3}[]
  local angles = {}

  -- Collecting points along the track into the list
  local prevSurface, candSurface, candSurfaceCounter, candSurfacePos = -1, -1, 0, 0
  do
    local p0 = vec3()
    local p1 = vec3()
    local p1_raw = vec3()
    local p2 = vec3()
    local p2_raw = vec3()
    local smoothRange = config.SmoothingMult / steps
    ac.trackProgressToWorldCoordinateTo(0, p0)
    trackProgressToWorldCoordinateSmoothTo(1 / steps, smoothRange, p1, p1_raw)
    for i = 2, steps do
      trackProgressToWorldCoordinateSmoothTo(i / steps, smoothRange, p2, p2_raw)
      angles[i - 1] = {angle = computeAngle(p0, p1, p2), vAngle = computeVAngle(p0, p1, p2), vAngleUpcoming = 0, speed = 0, pos = p1_raw:clone()}
      
      local surface = surfaceTypeToModifier(surfacesAvailable and surfacesLib.raycastType(p1_raw) or nil)
      if surface then
        if prevSurface == -1 then
          prevSurface = surface
        elseif prevSurface ~= surface then
          if candSurface ~= surface then
            candSurfacePos = (i - 1) / steps
            candSurfaceCounter = 0
            candSurface = surface
          else
            candSurfaceCounter = candSurfaceCounter + 1
            if candSurfaceCounter > 3 then
              ret[#ret + 1] = RouteItem(RouteItemType.SurfaceType, candSurface,
                narrowOnSurfaceChange(candSurfacePos - 1 / steps, candSurfacePos, candSurface), {})
              prevSurface = candSurface
            end
          end
        else
          candSurface = -1
        end
      end
      p0, p1, p2 = p1, p2, p0
      p1_raw, p2_raw = p2_raw, p1_raw
    end
  end

  local speed = 50
  local speedRec = {}
  for i = 3, steps - 3 do
    local r = computeTurnRadius(angles[i].angle)
    speed = math.min(math.lerp(speed, 130, 0.02), estimateCarSpeed(r))
    angles[i].speed = speed
    table.insert(speedRec, {pos = i / steps, speed = speed})
  end
  AppState.speedRec = speedRec

  -- Iterating over collected points to find turns
  local f = 2 -- index of a point starting a corner
  local x = 1 -- index of a point with maximum encountered angle
  local m = 0 -- maximum encountered angle when processing a turn
  local lastEnd = -1
  local exitCounter = 0
  local jumpCooldown = -1
  local jz = 0
  local js = 1
  local jm = 0
  for i = 3, steps - 2 do
    local e = angles[i - 1]

    local finalizeStraight = false
    if e.vAngle < 0 or jumpCooldown > i then
      jz = jz + 1
      if jz > 1 then
        if jm > 1 then
          local jump, debugText = config.JumpComputation(jm, (i - js) * config.StepSize, e.speed)
          if jump and jump >= 1 and jump <= 3 then
            ret[#ret + 1] = RouteItem(RouteItemType.Jump, jump, (js - 0.5) / steps, {})
            if config.DebugMode then
              ret[#ret].debugData = {posMax = (i + js) / 2 / steps, posEnd = i / steps, 
                debugText = 'Angle: %.1f°\nDistance: %.0f m\nDebug: %s' % {jm, (i - js) * config.StepSize, debugText or '?'}}
            end
            jumpCooldown = i + 4
            finalizeStraight = true
          end
        end
        js, jm = i, 0
      end
    elseif e.vAngle > 0.1 then
      jm = jm + e.vAngle
      jz = 0
    end

    if math.abs(m) < config.Nullification.Angle and (i - f) / steps * sim.trackLengthM > config.Nullification.Distance then
      f = i
      m = 0
    end
      
    if math.abs(e.angle) > math.abs(m) and e.angle * m >= 0 then
      -- If angle of a point exceeds current one, keep track of it
      m, x = e.angle, i
      exitCounter = 0
    elseif math.abs(e.angle) < math.abs(m) * config.EndingConditions.AngleFallingBelow or math.sign(e.angle) ~= math.sign(m) then
      -- If angle of a point is less than 1% of maximal encountered angle, or it just looks into 
      -- a different direction, turn is over
      exitCounter = exitCounter + 1
    end
    
    if exitCounter >= config.EndingConditions.CounterThreshold then
      if math.abs(m) > config.CornerRequirements.MaxStepAngleAbove then
        -- If maximum encountered angle is above 0.3°…

        while f < x do
          if math.abs(angles[f].angle) < config.TrimmingAngles.Beginning then
            f = f + 1
          else
            break
          end
        end

        while i > x and i > 3 do
          if math.abs(angles[i].angle) < config.TrimmingAngles.Ending then
            i = i - 1
          else
            break
          end
        end

        -- …finding middle point (optional, comment out to use maximum angle instead)
        if config.SnapCenterToMiddle then
          x = math.round((f + i) / 2)
        end

        local sumFirst, sumLast = 0, 0
        for j = f, x do sumFirst = sumFirst + math.abs(angles[j].angle) end
        for j = x, x * 2 - f do sumLast = sumLast + math.abs(angles[j].angle) end

        -- …computing angle between start, middle and ending points
        local angle = computeAngle(angles[f - 1].pos, angles[x - 1].pos, angles[i - 1].pos)
        local distance = (i - f) / steps * sim.trackLengthM

        if math.abs(angle) > distance * config.CornerRequirements.AngleToDistanceRatio
          or math.abs(angle) > config.CornerRequirements.OrAngleAbove then
          -- If that angle is above 3°, we found a turn

          local distanceFromLast = (f / steps - lastEnd) * sim.trackLengthM
          if lastEnd > 0 and distanceFromLast > config.MinDistanceForStraight then
            -- Adding straight note
            local offsetStraight = 0 / sim.trackLengthM -- offset in meters for straights
            local modifier = RouteItemType.straightDistanceToModifier(distanceFromLast)
            if modifier then
              ret[#ret + 1] = RouteItem(RouteItemType.Straight, modifier, lastEnd - offsetStraight, {})
            end
          end

          local ownType = angle > 0 and RouteItemType.TurnLeft or RouteItemType.TurnRight
          local ownStrength = config.DifficultyComputation(angle, distance, angles[f].speed)
          if distanceFromLast == 0 and (f / steps - ret[#ret].pos) * sim.trackLengthM < 8 
            and (ret[#ret].type == RouteItemType.TurnLeft or ret[#ret].type == RouteItemType.TurnRight)
            and ret[#ret].modifier >= 5 then
            table.remove(ret, #ret)
          else
            if distanceFromLast < config.Merge.DistanceToPreviousCornerBelow and ret[#ret].type == ownType 
                and ownStrength <= config.Merge.OwnDifficultyThreshold 
                and ret[#ret].modifier >= config.Merge.PreviousDifficultyThreshold then
              local prevDistance = (f / steps - ret[#ret].pos) * sim.trackLengthM
              if prevDistance < config.Merge.PreviousCornerDistanceBelow then
                if config.Merge.UniteInsteadOfDropping then
                  f = ret[#ret].pos * steps
                end
                table.remove(ret, #ret)
              end
            end
          end

          -- Adding turn note
          local offsetTurn = 0 / sim.trackLengthM -- offset in meters for corners
          local hints = {}
          if distance > config.Hints.LongDistanceThreshold then
            if distance > config.Hints.VeryLongDistanceThreshold then
              hints[#hints + 1] = RouteItemHint.VeryLong
              if sumFirst * config.Hints.TightensAnglesRatio < sumLast then
                hints[#hints + 1] = RouteItemHint.Tightens
              end
            elseif sumFirst * config.Hints.TightensAnglesRatio < sumLast then
              hints[#hints + 1] = RouteItemHint.Tightens
            else
              hints[#hints + 1] = RouteItemHint.Long
            end
          end
          ret[#ret + 1] = RouteItem(
            angle > 0 and RouteItemType.TurnLeft or RouteItemType.TurnRight,
            ownStrength, f / steps - offsetTurn, hints)

          lastEnd = finalizeStraight and (jumpCooldown - 1) / steps or i / steps
          finalizeStraight = false

          if config.DebugMode and angles[f] then
            ret[#ret].debugData = {posMax = x / steps, posEnd = i / steps, 
              debugText = 'Angle: %.1f°\nDistance: %.0f m\nEntry speed: %.1f km/h' % {angle, distance, angles[f].speed}}
          end
        end
      end

      -- …starting to look for the next turn
      f = i
      m = 0
    end

    if finalizeStraight and jumpCooldown > i then
      local distanceFromLast = (i / steps - lastEnd) * sim.trackLengthM
      if lastEnd > 0 and distanceFromLast > config.MinDistanceForStraight then
        -- Adding straight note
        local offsetStraight = 0 / sim.trackLengthM -- offset in meters for straights
        local modifier = RouteItemType.straightDistanceToModifier(distanceFromLast)
        if modifier then
          ret[#ret + 1] = RouteItem(RouteItemType.Straight, modifier, lastEnd - offsetStraight, {})
        end
      end
      lastEnd = (jumpCooldown - 1) / steps
    end
  end

  ac.perfEnd('Generating pacenotes')

  ---@type PaceNotes
  local created = PaceNotes(nil, ret, {
    name = 'Generated pacenotes',
    author = false
  })
  created:sort()
  return created
end

return class.emmy(PaceNotes, PaceNotes.allocate)