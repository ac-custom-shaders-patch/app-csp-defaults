local db = require('src/DbBackedStorage')

---@type DbDictionaryStorage<string>
local storage = db.Dictionary('favicons', 24 * 60 * 60 * 7)

local domainDecoded = {}
local favURLDecoded = {}
local blankProvider
local cache = setmetatable({}, {__mode = 'kv'})

local function getURLFavicon(url)
  local cached = cache[url]
  if cached then
    return cached
  end

  local domain = WebBrowser.getDomainName(url)
  local r = domainDecoded[domain]
  if r == nil then
    if blankProvider and (domain:startsWith('about:') or url == '') then
      cache[url] = r
      return blankProvider(domain) or ui.Icons.Earth
    end
    r = storage:get(domain)
    r = r and ui.decodeImage(r) or ui.Icons.Earth
    domainDecoded[domain] = r
  end
  cache[url] = r
  return r
end

---@param tab WebBrowser
local function getWebFavicon(tab, loadedOnly)
  if tab.__loaded then -- for lazy tab replacements
    return getURLFavicon(tab:url())
  end

  local favicon = tab:favicon()
  if not favicon or tab:showingSourceCode() then
    return getURLFavicon(tab:url())
  end

  local v = favURLDecoded[favicon]
  if not v then
    if loadedOnly then return nil end
    if favicon:startsWith('http') then
      v = getURLFavicon(tab:url())
      local domain = tab:domain()
      tab:downloadImageAsync(favicon, true, 32, function (err, data)
        if err then
          ac.log('Failed to load icon for %s: %s' % {domain, err})
          favURLDecoded[favicon] = ui.Icons.Earth
        else
          local decoded = ui.decodeImage(data)
          ac.log('Icon for %s: %s (size: %s)' % {domain, decoded, ui.imageSize(decoded)})
          if decoded and ui.imageSize(decoded).x > 4 then
            storage:set(domain, data)
            domainDecoded[domain] = decoded
            table.clear(cache)
          end
          favURLDecoded[favicon] = decoded or 'color::#ff0000'
        end
      end)
    else
      v = favicon or ''
    end
    favURLDecoded[favicon] = v
  end
  return v
end

---@param target string|WebBrowser
---@param loadedOnly boolean?
---@param required boolean?
---@return string?
local function get(target, loadedOnly, required)
  if not target then
    return nil
  elseif type(target) == 'string' then
    if target == '' and not required then return nil end
    return getURLFavicon(target)
  elseif type(target) == 'table' then
    return getWebFavicon(target, loadedOnly)
  else
    ac.warn('Unsupported favicon target: '..tostring(target))
  end
end

return {
  get = get,

  ---@param value fun(url: string): string?
  setBlankProvider = function (value)
    blankProvider = value
  end,

  require = function (target)
    return get(target, nil, true) or 'color::#00000000'
  end
}