---@class BetterShuffle
---@field private next integer
---@field private shuffled integer[]
local BetterShuffle = class('BetterShuffle')

local function shuffle(list)
  for i = #list, 2, -1 do
    local r = math.random(i)
    list[i], list[r] = list[r], list[i]
  end
  return list
end

---@return BetterShuffle
function BetterShuffle.allocate()
  return {
    shuffled = {},
    next = 1
  }
end

local function rangeCallback(index)
  return index
end

---@generic T
---@param items T[]
---@return T?
function BetterShuffle:get(items)
  local n, size = self.next, #self.shuffled
  local targetSize = #items
  if targetSize ~= size then
    n, size = 1, targetSize
    self.next, self.shuffled = 1, shuffle(table.range(targetSize, rangeCallback))
  end
  if n > size then
    if not size then return nil end
    local last = self.shuffled[size]
    shuffle(self.shuffled)
    if last == self.shuffled[1] and size > 1 then
      local s = math.random(2, size)
      self.shuffled[1], self.shuffled[s] = self.shuffled[s], self.shuffled[1]
    end
    self.next, n = 2, 1
  else
    self.next = n + 1
  end
  return items[self.shuffled[n]]
end

function BetterShuffle.test()
  do
    math.randomseed(math.randomKey())
    local r = BetterShuffle()
    for i = 1, 40 do
      local v = r:get({1, 2, 3, 4})
      for j = 1, 10 do
        ac.debug('bs', v)
      end
    end
  end  
end

return class.emmy(BetterShuffle, BetterShuffle.allocate)

