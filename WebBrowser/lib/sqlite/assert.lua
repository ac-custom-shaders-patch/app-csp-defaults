local M = {}
local u = require "sqlite.utils"

--- Functions for asseting and erroring out :D

local errors = {
  not_sqltbl = "can not execute %s, %s doesn't exists.",
  close_fail = "database connection didn't get closed, ERRMSG: %s",
  eval_fail = "eval has failed to execute statement, ERRMSG: %s",
  failed_ops = "operation failed, ERRMSG: %s",
  missing_req_key = "(insert) missing a required key: %s",
  missing_db_object = "%s's db object is not set. set it with `%s:set_db(db)` and try again.",
  outdated_schema = "`%s` does not exists in {`%s`}, schema is outdateset `self.db.tbl_schemas[table_name]` or reload",
  auto_alter_more_less_keys = "schema defined ~= db schema. Please drop `%s` table first or set ensure to false.",
}

for key, value in pairs(errors) do
  errors[key] = "sqlite.lua: " .. value
end

---Check if a given ret table length is more then 0
---This because in update we insert and expect some value
---returned 'let me id or 'boolean.
---When the ret values < 0 then the function didn't do anything.
---@param status sqlite_db_status
---@return boolean
M.should_modify = function(status)
  assert(status.code == 0, errors.failed_ops:format(status.msg))
  return true
end

M.missing_req_key = function(val, key)
  assert(val ~= nil, errors.missing_req_key:format(key))
  return false
end

M.should_have_column_def = function(column_def, k, schema)
  if not column_def then
    error(errors.outdated_schema:format(k, u.join(u.keys(schema), ", ")))
  end
end

M.should_have_db_object = function(db, name)
  assert(db ~= nil, errors.missing_db_object:format(name, name))
  return true
end

M.auto_alter_should_have_equal_len = function(len_new, len_old, tname)
  if len_new - len_old ~= 0 then
    error(errors.auto_alter_more_less_keys:format(tname))
  end
end

return M
