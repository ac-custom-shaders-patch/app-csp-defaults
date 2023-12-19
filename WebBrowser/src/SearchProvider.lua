local Storage = require('src/Storage')

---@type {id: string, name: string, icon: string, searchURL: (fun(query: string): string), suggestionsAsync: fun(query: string, callback: fun(items: string[]))}[]
local impl = {
  {
    id = 'ddg',
    name = 'DuckDuckGo',
    icon = 'https://duckduckgo.com/favicon.png',
    searchURL = function (query)
      return 'https://duckduckgo.com/?q='..query:urlEncode()
    end,
    suggestions = function (query, callback)
      web.get(string.format('https://duckduckgo.com/ac/?q=%s&type=list', string.urlEncode(query)), function (err, response)
        callback(JSON.parse(response.body)[2])
      end)
    end
  },
  {
    id = 'google',
    name = 'Google',
    icon = 'https://google.com/favicon.ico',
    searchURL = function (query)
      return 'https://www.google.com/search?q='..query:urlEncode()
    end,
    suggestions = function (query, callback)
      web.get('http://suggestqueries.google.com/complete/search?client=chrome&q='..string.urlEncode(query), function (err, response)
        callback(JSON.parse(response.body)[2])
      end)
    end
  },
  {
    id = 'bing',
    name = 'Bing',
    icon = 'https://bing.com/favicon.ico',
    searchURL = function (query)
      return 'https://www.bing.com/search?q='..query:urlEncode()
    end,
    suggestions = function (query, callback)
      web.get('https://api.bing.com/osjson.aspx?query='..string.urlEncode(query), function (err, response)
        callback(JSON.parse(response.body)[2])
      end)
    end
  },
  {
    id = 'ecosia',
    name = 'Ecosia',
    icon = 'https://ecosia.org/favicon.ico',
    searchURL = function (query)
      return 'https://www.ecosia.org/search?q='..query:urlEncode()
    end,
    suggestions = function (query, callback)
      web.get('https://ac.ecosia.org/?q='..string.urlEncode(query), function (err, response)
        callback(JSON.parse(response.body).suggestions)
      end)
    end
  }
}

local assoc = table.map(impl, function (item) return item, item.id end)
local suggestionsCache = {}
local suggestionsLastTime = -1
local suggestionsLastIndex = 0

local function cur()
  return assoc[Storage.settings.searchProviderID] or impl[1]
end

---@param query string
---@param callback fun(items: string[])
local function suggestions(query, callback)
  if suggestionsCache[query] then
    callback(suggestionsCache[query])
  else
    local index = suggestionsLastIndex + 1
    suggestionsLastIndex = index
    local timePassed = os.preciseClock() - suggestionsLastTime
    if timePassed < 0.1 then
      setTimeout(function ()
        if suggestionsLastIndex ~= index then
          return
        end
        suggestions(query, callback)
      end, 0.1 - timePassed)
    else
      suggestionsLastTime = os.preciseClock()
      cur().suggestions(query, function (data)
        suggestionsCache[query] = data
        callback(data)
      end)
    end
  end
end

local urlRegex = '^(?:(?:javascript|about|ac|https?):|\\w(?:[\\w-]*\\w)?\\.\\w(?:[\\w.-]*\\w)?(?:/.*|$))'

return {
  list = impl,

  introduction = function ()
    return string.format('Search %s or type a URL', cur().name)
  end,

  selected = function ()
    return cur()
  end,

  ---@param query string
  ---@return string
  url = function (query)
    return cur().searchURL(query)
  end,

  suggestions = suggestions,

  ---@param input string
  ---@param forceSearch boolean
  ---@return string
  userInputToURL = function (input, forceSearch)
    if input:byte(1) == 4 then return input:sub(2) end
    if input:byte(1) == 5 then
      forceSearch = true
      input = input:sub(2)
    end
    ac.log('Input: %s, seems like URL: %s' % {input, input:regfind(urlRegex) and 'yes' or 'no'})
    return not forceSearch and input:regfind(urlRegex) and input or cur().searchURL(input)
  end
}