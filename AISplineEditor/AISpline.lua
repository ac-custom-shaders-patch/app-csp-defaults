local binaryUtils = require('shared/utils/binary')

local splinePoint = ac.StructItem.combine({
  ac.StructItem.explicit(),
  pos = ac.StructItem.vec3(),
  length = ac.StructItem.float(),
  payloadIndex = ac.StructItem.int32(),
})

local splinePayload = ac.StructItem.combine({
  ac.StructItem.explicit(),
  speed = ac.StructItem.float(),
  gas = ac.StructItem.float(),
  brake = ac.StructItem.float(),
  obsoleteLatG = ac.StructItem.float(),
  radius = ac.StructItem.float(),
  sideLeft = ac.StructItem.float(),
  sideRight = ac.StructItem.float(),
  camber = ac.StructItem.float(),
  direction = ac.StructItem.float(),
  normal = ac.StructItem.vec3(),
  length = ac.StructItem.float(),
  forwardVector = ac.StructItem.vec3(),
  tag = ac.StructItem.float(),
  grade = ac.StructItem.float(),
})

---@class AISpline
---@field dirty boolean
---@field sideLeft vec3[]
---@field sideRight vec3[]
---@field extras table
local splineMt = {}

---@param reader binaryUtils.BinaryReader
function splineMt:decode(reader)
  if reader:int32() ~= 7 then error('Unknown version: '..reader:seek(0):int32(), 2) end
  local pointsCount = reader:int32()
  self.points = reader:skip(8):array(splinePoint, pointsCount)
  self.payloads = reader:array(splinePayload)
  reader:dispose()
  self.payloads = table.map(self.points, function (p, j)
    local i = p.payloadIndex
    p.payloadIndex = j - 1
    return self.payloads[i + 1]
  end)
  self.closed = self.points[1].pos:closerToThan(self.points[#self.points].pos, 75)
  self.length = self.points[#self.points].length + (self.closed and self.points[1].pos:distance(self.points[#self.points].pos) or 0)
  self.hasSides = table.some(self.payloads, function (item)
    return item.sideLeft ~= 0 or item.sideRight ~= 0
  end)
end

function splineMt:encode()
  self:finalize()
  return binaryUtils.writeData()
    :int32(7):int32(#self.points):int64(0)
    :array(self.points)
    :array(self.payloads, true)
    :int32(0) -- no grid data
end

function splineMt:load(filename)
  try(function ()
    self:decode(binaryUtils.readFile(filename))
  end, function (err)
    ac.error('Failed to read spline: %s' % err)
    self.points = {}
    self.payloads = {}
    self.closed = false
    self.length = 0
    self.hasSides = false
  end)
end

function splineMt:save(filename)
  try(function ()
    self:encode():commit(filename):dispose()
  end, function (err)
    ac.error('Failed to save spline: %s' % err)
  end)
end

local vUp = vec3(0, 1, 0)
local vDown = vec3(0, -1, 0)
local v1 = vec3()

function splineMt:snapToTrackSurface(pointIndex, gap)
  local p = self.points[pointIndex].pos
  physics.raycastTrack(v1:set(0, 10, 0):add(p), vDown, 20, p, self.payloads[pointIndex].normal)
  p.y = p.y + (gap or 0.3)
  self.dirty = true
end

function splineMt:distanceBetween(pointIndex1, pointIndex2)
  local d = math.abs(self.points[pointIndex1].length - self.points[pointIndex2].length)
  if self.closed and d > self.length / 2 then
    d = self.length - d
  end
  return d
end

function splineMt:resize(size)
  if #self.points == size then
    return
  end
  while #self.points > size do
    table.remove(self.points)
    table.remove(self.payloads)
  end
  while #self.points < size do
    self.points[#self.points + 1] = ffi.new(splinePoint)
    self.payloads[#self.payloads + 1] = ffi.new(splinePayload)
  end
  self.dirty = true
end

function splineMt:finalize()
  if not self.dirty then return end
  self.dirty = false
  local totalLength = 0
  for i = 1, #self.points do
    local cur, next = self.points[i], i == #self.points and self.points[1] or self.points[i + 1]
    local distance = cur.pos:distance(next.pos)
    self.payloads[i].forwardVector:set(next.pos):sub(cur.pos):scale(1 / distance)
    local o = v1:setCrossNormalized(self.payloads[i].forwardVector, vUp)
    self.sideLeft[i] = cur.pos + o * self.payloads[i].sideLeft
    self.sideRight[i] = cur.pos - o * self.payloads[i].sideRight
    self.points[i].length = totalLength
    self.points[i].payloadIndex = i - 1
    self.payloads[i].length = distance
    totalLength = totalLength + cur.pos:distance(next.pos)
  end
end

---@param filename string
---@return AISpline
local function AISpline(filename)
  local ret = setmetatable({dirty = true, sideLeft = {}, sideRight = {}, extras = {}}, {__index = splineMt})
  ret:load(filename)
  ret:finalize()
  return ret
end

return AISpline