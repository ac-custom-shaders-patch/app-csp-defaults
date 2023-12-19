require('shared/utils/sqlite')
package.add('lib')
local sqlite = require('lib/sqlite/db')
local tbl = require('lib/sqlite/tbl')
local db

---@class DbDictionaryStorage<T>: {get: (fun(self: DbDictionaryStorage, key: string): T?), set: (fun(self: DbDictionaryStorage, key: string, value: T)), remove: (fun(self: DbDictionaryStorage, key: string)), clear: (fun(self: DbDictionaryStorage): self), removeAged: (fun(self: DbDictionaryStorage, time: integer, removeNewer: boolean?): self)}

local dictStorage = class('DbDictionaryStorage')

function dictStorage:initialize(tableKey, maxAge)
  if not db then
    error('Call DbBackedStorage.configure first')
  end
  self.entries = tbl(tableKey, {key = {'text', required = true, primary = true}, data = {'blob', required = true}, time = maxAge and {'integer', required = true}})
  self.entries:set_db(db)
  self.cache = setmetatable({}, {__mode = 'kv'})
  if maxAge then
    self.timeLimited = true
    self.entries:remove({ where = { time = '<%d' % (os.time() - maxAge) }})
  end
end

function dictStorage:removeAged(threshold, removeNewer)
  self.cache = setmetatable({}, {__mode = 'kv'})
  self.entries:remove({ where = { time = string.format(removeNewer and '>%d' or '<%d', threshold) }})
end

function dictStorage:get(key)
  local c = self.cache[key]
  if c then return c end
  local r = self.entries:get({where = {key = key}}, {'data'})
  c = r and r[1] and r[1].data
  self.cache[key] = c
  if self.timeLimited then
    self.entries:update({where = {key = key}, set = {time = os.time()}})
  end
  return c
end

function dictStorage:set(key, value)
  if type(value) ~= 'table' and self.cache[key] == value then
    return
  end
  if self.timeLimited then
    self.entries:insert({key = key, data = value, time = os.time()}, ' ON CONFLICT(key) DO UPDATE SET data=excluded.data, time=excluded.time')
  else
    self.entries:insert({key = key, data = value}, ' ON CONFLICT(key) DO UPDATE SET data=excluded.data')
  end
  self.cache[key] = value
end

function dictStorage:remove(key)
  self.entries:remove({key = key})
  self.cache[key] = nil
end

function dictStorage:clear()
  self.entries:remove()
  self.cache = setmetatable({}, {__mode = 'kv'})
end

---@class DbListStorage<T>: {at: (fun(self: DbListStorage, i: integer): T), loaded: (fun(self: DbListStorage): T[], integer), list: (fun(self: DbListStorage): T[], integer), alive: (fun(self: DbListStorage): integer), purge: (fun(self: DbListStorage): self), add: (fun(self: DbListStorage, item: T): self), update: (fun(self: DbListStorage, item: T): self), remove: (fun(self: DbListStorage, item: T): self), restore: (fun(self: DbListStorage, item: T): self), swap: (fun(self: DbListStorage, item1: T, item2: T): self), clear: (fun(self: DbListStorage): self)}

local listStorage = class('DbListStorage')

local function decode(item, _, self)
  if self.purged[item.id] then
    return self.purged[item.id]
  end
  if self.wrapper then
    item.data = self.wrapper.decode(item.data, item.key)
  end
  item.data['\1'] = item.id
  return item.data
end

function listStorage:initialize(tableKey, entriesLimit, wrapper)
  if not db then
    error('Call DbBackedStorage.configure first')
  end
  self.entries = tbl(tableKey, {id = true, data = {'blob', required = true}, key = wrapper and wrapper.key and {'text', unique = true, required = true, primary = false} or nil})
  self.entries:set_db(db)
  self.wrapper = wrapper
  self.rows = wrapper and wrapper.key and {'id', 'data', 'key'} or {'id', 'data'}
  self.count = self.entries:count()
  if self.count > entriesLimit then
    db:execute(string.format('delete from %s where id in (select id from %s order by id asc limit %d)', tableKey, tableKey, self.count - entriesLimit))
    self.count = entriesLimit
  end
  self.live = {}
  self.liveN = 0
  self.purged = {}
  if wrapper and wrapper.key then
    db:execute(string.format('CREATE UNIQUE INDEX IF NOT EXISTS idx_%s ON %s (key)', tableKey, tableKey))
  end
end

function listStorage:at(i)
  if not i or i < 1 or i > self.count then return nil end 
  local missing = self.count - self.liveN
  if i > missing then return self.live[i - missing] end
  local itemsToGet = 1 + missing - i
  local got = self.entries:get({limit = {itemsToGet, self.count - self.liveN - itemsToGet}, order_by = {asc = 'id'}}, self.rows)
  if #got == 1 then
    table.insert(self.live, 1, decode(got[1], nil, self))
  else
    self.live = table.chain(table.map(got, decode, self), self.live)
  end
  self.liveN = self.liveN + #got
  return self.live[i - (self.count - self.liveN)]
end

local function listIterator(s, i)
  i = i + 1
  if i <= s.count then return i, s:at(i) end
end

function listStorage:__ipairs()
  return listIterator, self, 0
end

function listStorage:loaded()
  return self.live, self.liveN
end

function listStorage:list()
  self:at(1)
  return self.live, self.liveN
end

function listStorage:__len()
  return self.count
end

function listStorage:alive()
  return self.liveN
end

function listStorage:purge()
  if self.liveN > 0 then
    self.purged = {}
    for i = 1, self.liveN do
      self.purged[self.live[i]['\1']] = self.live[i]
    end
    table.clear(self.live)
    self.count, self.liveN = self.entries:count(), 0
  end
  return self
end

local function encode(value, wrapper, id)
  local key
  if wrapper then
    value, key = wrapper.encode(value)
  end
  return {data = value, id = id, key = key}
end

local function findRestorePosition(item, _, callbackData)
  return item['\1'] > callbackData
end

local function hasItemByID(self, id)
  return self.liveN == self.count or self.live[1] and self.live[1]['\1'] < id
end

function listStorage:add(value)
  local w
  if self.wrapper and self.wrapper.key then
    local v, k = self.wrapper.encode(value)
    local x = self.entries:get({where = {key = k}})
    if #x > 0 then
      self.entries:remove({where = {key = k}})
      if hasItemByID(self, x[1].id) then
        self:purge()
      else
        self.count = self.count - 1
      end
    end
    local s = self.entries:insert({data = v, key = k})
    self.live[self.liveN + 1], self.liveN = value, self.liveN + 1
    self.count = self.count + 1
    if s then value['\1'] = s end
  else
    local s = self.entries:insert(encode(value, self.wrapper))
    self.live[self.liveN + 1], self.liveN = value, self.liveN + 1
    self.count = self.count + 1
    if s then value['\1'] = s end
  end
  return self
end

function listStorage:update(value)
  if value and value['\1'] then 
    self.entries:update({where = {id = value['\1']}, set = encode(value, self.wrapper)})
  else
    self:add(value)
  end
  return self
end

function listStorage:remove(value)
  if not value or not value['\1'] then return end
  self.entries:remove({where = {id = value['\1']}})
  if table.removeItem(self.live, value) then
    self.liveN, self.count = self.liveN - 1, self.count - 1
  else
    ac.warn('Failed to change data inline')
    self:purge()
  end
  return self
end

function listStorage:restore(value)
  if not value or not value['\1'] then return end
  self.entries:insert(encode(value, self.wrapper, value['\1']))
  if hasItemByID(self, value['\1']) then
    local pos = table.findLeftOfIndex(self.live, findRestorePosition, value['\1'])
    table.insert(self.live, pos and pos + 1 or #self.live + 1, value)
    self.liveN, self.count = self.liveN + 1, self.count + 1
  else
    ac.warn('Failed to restore data inline')
  end
  return self
end

function listStorage:swap(value1, value2)
  if not value1 or not value1['\1'] or not value2 or not value2['\1'] then return end
  db:transaction(function ()
    value1['\1'], value2['\1'] = value2['\1'], value1['\1']
    self.entries:update({where = {id = value1['\1']}, set = encode(value1, self.wrapper)})
    self.entries:update({where = {id = value2['\1']}, set = encode(value2, self.wrapper)})
    local i1, i2 = table.indexOf(self.live, value1), table.indexOf(self.live, value2)
    if i1 and i2 then
      self.live[i1], self.live[i2] = self.live[i2], self.live[i1]
    else
      ac.warn('Failed to swap data inline')
      self:purge()
    end
  end)
  return self
end

function listStorage:clear()
  self.entries:remove()
  table.clear(self.live)
  self.count, self.liveN = 0, 0
  return self
end

---@type fun(tableKey: string, maxAge: integer?): DbDictionaryStorage
local dictConstructor = dictStorage.initialize

---@type fun(tableKey: string, entriesLimit: integer, wrapper: {encode: function, decode: function, key: boolean?}?): DbListStorage
local listConstructor = listStorage.initialize

return {
  Dictionary = class.emmy(dictStorage, dictConstructor),
  List = class.emmy(listStorage, listConstructor),

  ---@param filename string? @Database filename.
  configure = function(filename)
    db = sqlite{uri = filename, opts = {keep_open = true, journal_mode = 'WAL'}}
    ac.onRelease(function ()
      db:close()
    end)
  end,
}

-- todo: update time when reading cache
-- todo: option for filtering key for the list (so that old history entries could be removed)