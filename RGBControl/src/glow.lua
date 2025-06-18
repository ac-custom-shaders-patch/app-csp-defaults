local sim = ac.getSim()
local data = require('src/data')

---@alias GlowAttributes {key: string, name: string, description: string}
---@alias Glow<T> {condition: string?, baseDescription: string, defaults: T, settings: fun(cfg: T)?, accessor: (fun(cfg: T): rgb?, rgb?, rgb?, number?)}|GlowAttributes
---@alias Condition<T> {defaults: T, group: string, settings: fun(cfg: T)?, condition: (fun(cfg: T): boolean), resolveName: fun(cfg: T): string}|GlowAttributes

---@type Glow<any>[]
local glows = {}
local glowsByKey = {}

---@type Condition<any>[]
local conditions = {}
local conditionsByKey = {}

setTimeout(function ()
  table.sort(glows, function (a, b) return a.name:lower() < b.name:lower() end)
  table.sort(conditions, function (a, b) return a.name:lower() < b.name:lower() end)
end)

---@generic T : table
---@param attributes GlowAttributes|{condition: string?}
---@param defaults T
---@param settings fun(cfg: T)?
---@param accessor fun(cfg: T, info: CarInfo): rgb?, rgb?, rgb?, number?
local function registerGlow(attributes, defaults, settings, accessor)
  local c = table.assign({key = attributes.name, defaults = defaults, settings = settings, accessor = function (cfg)
    return accessor(cfg, data.getCarInfo(sim.focusedCar))
  end}, attributes)
  c.baseDescription = attributes.description
  c.description = attributes.description..(attributes.condition and '.\n\nActivates with: %s.' % attributes.condition or '.\n\nAlways active.')
  table.insert(glows, c)
  if glowsByKey[c.key] then error('Key %s is used' % conditionsByKey[c.key]) end
  glowsByKey[c.key] = c
end

---@generic T : table
---@param attributes GlowAttributes
---@param defaults T
---@param settings fun(cfg: T)?
---@param condition fun(cfg: T, info: CarInfo): boolean
---@param filler nil|fun(cfg: T): string?
local function registerCondition(attributes, defaults, settings, condition, filler)
  local c = table.assign({key = attributes.name, defaults = defaults, settings = settings, condition = function (cfg)
    return condition(cfg, data.getCarInfo(sim.focusedCar))
  end, resolveName = function (cfg)    
    local n = attributes.name
    if filler and n:endsWith('…') then
      local p = filler(cfg)
      if p then
        n = n:replace('…', ' '..p)
      end
    end
    return n
  end}, attributes)
  table.insert(conditions, c)
  if conditionsByKey[c.key] then error('Key %s is used' % c.key) end
  conditionsByKey[c.key] = c
end

local fallbackCondition = { name = '<unknown condition>', description = 'Condition is missing', defaults = {}, condition = function () return false end, resolveName = function () return '<unknown condition>' end }

---@return Glow<any>
local function getGlowByKey(key)
  return glowsByKey[key]
end

---@return Condition<any>
local function getConditionByKey(key)
  return conditionsByKey[key] or fallbackCondition
end

return {
  glows = glows,
  conditions = conditions,
  registerGlow = registerGlow,
  registerCondition = registerCondition,
  ---@param entry Glow<any>|Condition<any>
  instatiate = function (entry)
    if not entry then return nil end
    return table.assign({ key = entry.key }, table.clone(entry.defaults, 'full'))
  end,
  getGlowByKey = getGlowByKey,
  getConditionByKey = getConditionByKey,
}