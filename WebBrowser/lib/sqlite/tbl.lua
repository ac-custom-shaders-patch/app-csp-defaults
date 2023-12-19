---@brief [[
---Abstraction to produce more readable code.
---<pre>
--- ```lua
--- local tbl = require'sqlite.tbl'
--- ```
---</pre>
---@brief ]]
---@tag sqlite.tbl.lua

local u = require "sqlite.utils"
local h = require "sqlite.helpers"

local sqlite = {}

---@class sqlite_tbl @Main sql table class
---@field db sqlite_db: sqlite.lua database object.
---@field name string: table name.
sqlite.tbl = {}
sqlite.tbl.__index = sqlite.tbl

---Create new |sqlite_tbl| object. This object encouraged to be extend and
---modified by the user. overwritten method can be still accessed via
---pre-appending `__`  e.g. redefining |sqlite_tbl:get|, result in
---`sqlite_tbl:__get` available as a backup. This object can be instantiated
---without a {db}, in which case, it requires 'sqlite.tbl:set_db' is called.
---
---Common use case might be to define tables in separate files and then require them in
---file that export db object (TODO: support tbl reuse in different dbs).
---
---<pre>
---```lua
--- local t = tbl("todos", { --- or tbl.new
---   id = true, -- same as { "integer", required = true, primary = true }
---   title = "text",
---   since = { "date", default = sqlite.lib.strftime("%s", "now") },
---   category = {
---     type = "text",
---     reference = "category.id",
---     on_update = "cascade", -- means when category get updated update
---     on_delete = "null", -- means when category get deleted, set to null
---   },
--- }, db)
--- --- overwrite
--- t.get = function() return t:__get({ where = {...}, select = {...} })[1] end
---```
---</pre>
---@param name string: table name
---@param schema sqlite_schema_dict
---@param db sqlite_db|nil : if nil, then for it to work, it needs setting with sqlite.tbl:set_db().
---@return sqlite_tbl
function sqlite.tbl.new(name, schema, db)
  schema = schema or {}

  local t = setmetatable({
    db = db,
    name = name,
    tbl_schema = u.if_nil(schema.schema, schema),
  }, sqlite.tbl)

  if db then
    h.run(function() end, t)
  end

  return setmetatable({}, {
    __index = function(_, key, ...)
      if type(key) == "string" then
        key = key:sub(1, 2) == "__" and key:sub(3, -1) or key
        if t[key] then
          return t[key]
        end
      end
    end,
  })
end

---Create or change table schema. If no {schema} is given,
---then it return current the used schema if it exists or empty table otherwise.
---On change schema it returns boolean indecting success.
---
---<pre>
---```lua
--- local projects = sqlite.tbl:new("", {...})
--- --- get project table schema.
--- projects:schema()
--- --- mutate project table schema with droping content if not schema.ensure
--- projects:schema {...}
---```
---</pre>
---@param schema sqlite_schema_dict
---@return sqlite_schema_dict | boolean
function sqlite.tbl:schema(schema)
  return h.run(function()
    local exists = self.db:exists(self.name)
    if not schema then -- TODO: or table is empty
      return exists and self.db:schema(self.name) or {}
    end
    if not exists or schema.ensure then
      self.tbl_exists = self.db:create(self.name, schema)
      return self.tbl_exists
    end
    if not schema.ensure then -- TODO: use alter
      local res = exists and self.db:drop(self.name) or true
      res = res and self.db:create(self.name, schema) or false
      self.tbl_schema = schema
      return res
    end
  end, self)
end

---Remove table from database, if the table is already drooped then it returns false.
---
---<pre>
---```lua
--- --- drop todos table content.
--- todos:drop()
---```
---</pre>
---@see sqlite.db:drop
---@return boolean
function sqlite.tbl:drop()
  return h.run(function()
    if not self.db:exists(self.name) then
      return false
    end

    local res = self.db:drop(self.name)
    if res then
      self.tbl_exists = false
      self.tbl_schema = nil
    end
    return res
  end, self)
end

---Predicate that returns true if the table is empty.
---
---<pre>
---```lua
--- if todos:empty() then
---   print "no more todos, we are free :D"
--- end
---```
---</pre>
---@return boolean
function sqlite.tbl:empty()
  return h.run(function()
    if self.db:exists(self.name) then
      return self.db:eval("select count(*) from " .. self.name)[1]["count(*)"] == 0
    end
  end, self)
end

---Predicate that returns true if the table exists.
---
---<pre>
---```lua
--- if goals:exists() then
---   error("I'm disappointed in you :D")
--- end
---```
---</pre>
---@return boolean
function sqlite.tbl:exists()
  return h.run(function()
    return self.db:exists(self.name)
  end, self)
end

---Get the current number of rows in the table
---
---<pre>
---```lua
--- if notes:count() == 0 then
---   print("no more notes")
--- end
---```
---@return number
function sqlite.tbl:count(filter)
  return h.run(function()
    if not self.db:exists(self.name) then
      return 0
    end
    local res = self.db:eval("select count(*) from " .. self.name)
    return res[1]["count(*)"]
  end, self)
end

---Query the table and return results.
---
---<pre>
---```lua
--- --- get everything
--- todos:get()
--- --- get row with id of 1
--- todos:get { where = { id = 1 } }
--- --- select a set of keys with computed one
--- timestamps:get {
---   select = {
---     age = (strftime("%s", "now") - strftime("%s", "timestamp")) * 24 * 60,
---     "id",
---     "timestamp",
---     "entry",
---     },
---   }
---```
---</pre>
---@param query sqlite_query_select
---@return table
---@see sqlite.db:select
function sqlite.tbl:get(query)
  return h.run(function()
    local res = self.db:select(self.name, query, self.db_schema)
    return res
  end, self)
end

---Insert rows into a table.
---
---<pre>
---```lua
--- --- single item.
--- todos:insert { title = "new todo" }
--- --- insert multiple items, using todos table as first param
--- tbl.insert(todos, "items", {  { name = "a"}, { name = "b" }, { name = "c" } })
---```
---</pre>
---@param rows table: a row or a group of rows
---@see sqlite.db:insert
---@usage `todos:insert { title = "stop writing examples :D" }` insert single item.
---@usage `todos:insert { { ... }, { ... } }` insert multiple items
---@return integer: last inserted id
function sqlite.tbl:insert(rows, modifier)
  return h.run(function()
    local succ, last_rowid = self.db:insert(self.name, rows, self.db_schema, modifier)
    -- ac.log('succ=%s, lri=%s' % {succ, last_rowid})
    return succ and last_rowid
  end, self)
end

---Delete a rows/row or table content based on {where} closure. If {where == nil}
---then clear table content.
---
---<pre>
---```lua
--- --- delete todos table content
--- todos:remove()
--- --- delete row that has id as 1
--- todos:remove { id = 1 }
--- --- delete all rows that has value of id 1 or 2 or 3
--- todos:remove { id = {1,2,3} }
--- --- matching ids or greater than 5
--- todos:remove { id = {"<", 5} } -- or {id = "<5"}
---```
---</pre>
---@param where sqlite_query_delete
---@see sqlite.db:delete
---@return boolean
function sqlite.tbl:remove(where)
  return h.run(function()
    return self.db:delete(self.name, where)
  end, self)
end

---Update table row with where closure and list of values
---returns true incase the table was updated successfully.
---
---<pre>
---```lua
--- --- update todos status linked to project "lua-hello-world" or "rewrite-neoivm-in-rust"
--- todos:update {
---   where = { project = {"lua-hello-world", "rewrite-neoivm-in-rust"} },
---   set = { status = "later" }
--- }
--- --- pass custom statement and boolean
--- ts:update {
---   where = { id = "<" .. 4 }, -- mimcs WHERE id < 4
---   set = { seen = true } -- will be converted to 0.
--- }
---```
---</pre>
---@param specs sqlite_query_update
---@see sqlite.db:update
---@see sqlite_query_update
---@return boolean
function sqlite.tbl:update(specs)
  return h.run(function()
    return self.db:update(self.name, specs, self.db_schema)
  end, self)
end

---Changes the db object to which the sqlite_tbl correspond to. If the object is
---going to be passed to |sqlite.new|, then it will be set automatically at
---definition.
---@param db sqlite_db
function sqlite.tbl:set_db(db)
  self.db = db
end

sqlite.tbl = setmetatable(sqlite.tbl, {
  __call = function(_, ...)
    return sqlite.tbl.new(...)
  end,
})

return sqlite.tbl
