---@class SectorRecord
---@field state binary
---@field name string
---@field filename string
---@field startingPoint number
---@field finishingPoint number
---@field history number[]
---@field totalRuns integer
local SectorRecord = class('SectorRecord')

---@param state binary
---@param startingPoint number
---@param finishingPoint number
---@return SectorRecord
---@overload fun(filename: string): SectorRecord
function SectorRecord.allocate(filename, state, startingPoint, finishingPoint)
  if not state then
    local data = stringify.binary.tryParse(io.load(filename))
    return data or {}
  end
  local name1 = ac.getTrackSectorName(math.lerp(startingPoint, finishingPoint, 0.25))
  local name2 = ac.getTrackSectorName(math.lerp(startingPoint, finishingPoint, 0.75))
  return {
    state = state,
    name = name1 ~= '' and name1 == name2 and name1 or 'From %.0f m to %.0f m' % {startingPoint * ac.getSim().trackLengthM, finishingPoint * ac.getSim().trackLengthM},
    filename = filename,
    startingPoint = startingPoint,
    finishingPoint = finishingPoint,
    bestTime = {time = math.huge, measure = {}},
    prevTime = {time = math.huge, measure = {}},
    history = {},
    totalRuns = 1,
  }
end

function SectorRecord:export()
  return {
    state = self.state,
    name = self.name,
    startingPoint = self.startingPoint,
    finishingPoint = self.finishingPoint,
    bestTime = self.bestTime,
    prevTime = self.prevTime,
    history = self.history,
    totalRuns = self.totalRuns,
  }
end

local function computeDelta(runTotalTime, runTotalPos, pts)
  if #pts > 1 then
    local pos = math.max(1, table.findLeftOfIndex(pts, function (item) return item[1] > runTotalPos end))
    local expectedTime
    if pos == 0 then
      expectedTime = pts[1][2] + (pts[2][2] - pts[1][2]) /  (pts[2][1] - pts[1][1]) * (runTotalPos - pts[1][1])
    elseif pos == #pts then
      expectedTime = pts[#pts][2] + (pts[#pts - 1][2] - pts[#pts][2]) /  (pts[#pts - 1][1] - pts[#pts][1]) * (runTotalPos - pts[#pts][1])
    else
      local p1, p2 = pts[pos], pts[pos + 1]
      expectedTime = math.lerp(p1[2], p2[2], math.saturateN(math.lerpInvSat(runTotalPos, p1[1], p2[1] + 1e-6)))
    end
    return runTotalTime - expectedTime
  else
    return nil
  end
end

function SectorRecord:deltas(time, pos)
  return {
    best = computeDelta(time, pos, self.bestTime.measure),
    prev = computeDelta(time, pos, self.prevTime.measure),
  }
end

function SectorRecord:register(time, measure)
  local ret = {time = time}
  ac.log('New entry: %.03f (%.03f)%s' % {time / 1e3, measure[#measure][2] / 1e3, time < self.bestTime.time and ', best' or ''})
  if self.bestTime.time < 1e30 then ret.deltaBest = time - self.bestTime.time end
  if self.prevTime.time < 1e30 then ret.deltaPrev = time - self.prevTime.time end
  if time < self.bestTime.time then self.bestTime = {time = time, measure = measure} end
  self.prevTime = {time = time, measure = measure}
  if #self.history >= 99 then
    table.remove(self.history, 1)
  end
  self.history[#self.history + 1] = time
  self.totalRuns = self.totalRuns + 1
  if self.saveRecord then
    self:save()
  end
  return ret
end

function SectorRecord:save()
  io.createFileDir(self.filename)
  io.saveAsync(self.filename, stringify.binary(self:export()))
  self.saveRecord = true
end

return class.emmy(SectorRecord, SectorRecord.allocate)