local M = {}

M.if_nil = function(a, b)
  return a == nil and b or a
end

M.is_str = function(s)
  return type(s) == "string"
end

M.is_tbl = function(t)
  return type(t) == "table"
end

M.is_boolean = function(t)
  return type(t) == "boolean"
end

M.is_userdata = function(t)
  return type(t) == "userdata"
end

M.is_nested = function(t)
  return t and type(t[1]) == "table" or false
end

M.okeys = function(t)
  local r = {}
  for k in M.opairs(t) do
    r[#r + 1] = k
  end
  return r
end

M.opairs = (function()
  local __gen_order_index = function(t)
    local orderedIndex = {}
    for key in pairs(t) do
      table.insert(orderedIndex, key)
    end
    table.sort(orderedIndex)
    return orderedIndex
  end

  local nextpair = function(t, state)
    local key
    if state == nil then
      -- the first time, generate the index
      t.__orderedIndex = __gen_order_index(t)
      key = t.__orderedIndex[1]
    else
      -- fetch the next value
      for i = 1, table.getn(t.__orderedIndex) do
        if t.__orderedIndex[i] == state then
          key = t.__orderedIndex[i + 1]
        end
      end
    end

    if key then
      return key, t[key]
    end

    -- no more value to return, cleanup
    t.__orderedIndex = nil
    return
  end

  return function(t)
    return nextpair, t, nil
  end
end)()

M.all = function(iterable, fn)
  for k, v in pairs(iterable) do
    if not fn(k, v) then
      return false
    end
  end

  return true
end

M.keys = function(t)
  local r = {}
  for k in pairs(t) do
    r[#r + 1] = k
  end
  return r
end

M.values = function(t)
  local r = {}
  for _, v in pairs(t) do
    r[#r + 1] = v
  end
  return r
end

M.map = function(t, f)
  local _t = {}
  for i, value in pairs(t) do
    local k, kv, v = i, f(value, i)
    _t[v and kv or k] = v or kv
  end
  return _t
end

M.foreachv = function(t, f)
  for i, v in M.opairs(t) do
    f(i, v)
  end
end

M.foreach = function(t, f)
  for k, v in pairs(t) do
    f(k, v)
  end
end

M.mapv = function(t, f)
  local _t = {}
  for i, value in M.opairs(t) do
    local _, kv, v = i, f(value, i)
    table.insert(_t, v or kv)
  end
  return _t
end

M.join = function(l, s)
  return table.concat(M.map(l, tostring), s, 1)
end

-- Flatten taken from: https://github.com/premake/premake-core/blob/master/src/base/table.lua
M.flatten = function(tbl)
  local result = {}
  local function flatten(arr)
    local n = #arr
    for i = 1, n do
      local v = arr[i]
      if type(v) == "table" then
        flatten(v)
      elseif v then
        table.insert(result, v)
      end
    end
  end
  flatten(tbl)

  return result
end

return M
