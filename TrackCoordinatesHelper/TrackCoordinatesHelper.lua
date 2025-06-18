---@alias GeoPoint {lng: number, lat: number}
---@alias GeoFactory fun(pos: vec3): GeoPoint
---@alias DataPoint {geo: GeoPoint, world: vec3, url: string, zoom: number}

local state = ac.storage({ showSearch = true })
local mapSize = vec2(500, 500)
local pointsRef = {}
local hoveredPoint

---@type GeoPoint
local geoBase = {lng = ac.getTrackCoordinatesDeg().y, lat = ac.getTrackCoordinatesDeg().x}

---@param pos vec3
---@param geo GeoPoint
---@param angle number
---@return GeoPoint
local function worldToGeo(pos, geo, angle)
  local xMult = math.cos(math.rad(geo.lat))
  local pos2 = mat4x4.rotation(math.rad(-angle), vec3(0, 1, 0)):transformPoint(pos)
  return {lng = geo.lng + pos2.x / 111320 / xMult, lat = geo.lat - pos2.z / 111320}
end

---@param geo1 GeoPoint
---@param geo2 GeoPoint
---@return number
local function distanceBetweenGeo(geo1, geo2)
  local xMult = math.cos(math.rad(geo1.lat))
  return #vec2((geo1.lng - geo2.lng) * 111320 * xMult, (geo1.lat - geo2.lat) * 111320)
end

---@type DbDictionaryStorage<string>
local timezonesStorage
local timezonesLoading = {}

---@param point GeoPoint
local function computeTimezone(point)
  local key = math.round(point.lat * 10)..';'..math.round(point.lng * 10)
  if not timezonesStorage then
    local db = require('shared/utils/dbstorage')
    db.configure(ac.getFolder(ac.FolderID.AppDataTemp)..'/ac_timezone_cache.db')
    timezonesStorage = db.Dictionary('timezones')
  end
  local cached = timezonesStorage:get(key)
  if cached then
    return cached
  end
  if not timezonesLoading[key] then
    timezonesLoading[key] = true
    local url = 'https://api.geotimezone.com/public/timezone?latitude=%s&longitude=%s' % {point.lat, point.lng}
    print('Loading timezone: %s, %s' % {point.lng, point.lat})
    web.get(url, function (err, response)
      local data = not err and response and JSON.parse(response.body)
      if data and data.iana_timezone then
        timezonesStorage:set(key, data.iana_timezone)
      end
    end)
  end
  return nil
end

---@param points DataPoint[]
---@return string?, GeoFactory?, number
local function computeValues(points, geoYRef, except)
  local xMult = math.cos(math.rad(geoYRef or points[1].geo.lat))

  local headingA, weightA = 0, 0
  for i = 2, #points do
    if points[i] ~= except then
      local weight = points[i].world:distance(points[1].world)
      local gameA = math.atan2(points[i].world.z - points[1].world.z, points[i].world.x - points[1].world.x)
      local geoA = math.atan2(-(points[i].geo.lat - points[1].geo.lat), (points[i].geo.lng - points[1].geo.lng) * xMult)
      local newValue = math.deg(geoA - gameA)
      local curValue = headingA / weightA
      if math.abs(curValue - newValue) > 180 then
        newValue = newValue < curValue and newValue + 360 or newValue - 360
      end
      headingA = headingA + weight * newValue
      weightA = weightA + weight
    end
  end
  headingA = headingA / weightA
  if headingA < -180 then headingA = headingA + 360 end

  local headingM = mat4x4.rotation(math.rad(-headingA), vec3(0, 1, 0))
  local coords, count = {lat = 0, lng = 0}, 0
  for i = 1, #points do
    if points[i] ~= except then
      local rotated = headingM:transformPoint(points[i].world)
      coords.lng = coords.lng + (points[i].geo.lng - rotated.x / 111320 / xMult)
      coords.lat = coords.lat + (points[i].geo.lat + rotated.z / 111320)
      count = count + 1
    end
  end
  coords.lng = coords.lng / count
  coords.lat = coords.lat / count
  if not geoYRef then
    return computeValues(points, coords.lat, except)
  end
  local approximateError = 0
  for i = 1, #points do
    if points[i] ~= except then
      approximateError = math.max(approximateError, distanceBetweenGeo(worldToGeo(points[i].world, coords, headingA), points[i].geo))
    end
  end
  if except then
    return nil, nil, approximateError
  end
  local timezone = approximateError < 100 and computeTimezone(coords) or nil
  return '[WEATHER_FX]\nHEADING_ANGLE=%f\nLONGITUDE=%s\nLATITUDE=%s%s' % {headingA, coords.lng, coords.lat, timezone and '\nTIMEZONE=%s' % timezone or ''},
    function(pos) return worldToGeo(pos, coords, headingA) end,
    approximateError
end

local WebBrowser = require('shared/web/browser')
local tab = WebBrowser({
    spoofGeolocation = true,
    injectJavaScript = 'Number.prototype.toFixed=function(){return this.toString()};AC.onReceive("show-search", v => document.body.classList.toggle("show-search", v))'
  })
  :blockURLs(WebBrowser.adsFilter())
  :onDrawEmpty('message')
  :setZoom(-2)
  :setPixelDensity(1.2)
  :setMobileMode('landscape')
  :injectStyle({ ['google\\.com/maps'] = 'body:not(.show-search) #omnibox-container,#vasquette,#settings,#layer-switcher,.scene-footer-container,.app-horizontal-widget-holder,#google-hats-survey,#watermark{display:none}' })
  :onLoadEnd(function (browser, data)    
    browser:sendAsync('show-search', state.showSearch)
  end)

local function createMapView(size)
  local ratio = size.y / size.x
  local pos, scale, dirty = ac.getCar(0).pitTransform.position, 0, true
  local scene = {
    reference = ac.findNodes('sceneRoot:yes'),
    opaque = function ()
      render.setDepthMode(render.DepthMode.Off)
      render.setCullMode(render.CullMode.None)
      render.setBlendMode(render.BlendMode.AlphaBlend)
      for _, v in ipairs(pointsRef) do
        render.circle(v, vec3(0, 1, 0), 30 * math.pow(2, scale), rgbm.colors.transparent, hoveredPoint == v and rgbm.colors.yellow or rgbm.colors.lime)
      end
    end
  } 
  local view = ac.GeometryShot(scene, size, 1, false, render.AntialiasingMode.FXAA)
    :setTransparentPass(true):setOpaqueAlphaFix(true):clear(rgbm.colors.black):setShadersType(render.ShadersType.Simplest)
  local function viewRange() return 1500 * math.pow(2, scale) end
  return {
    draw = function (newPos, newScale)    
      if newPos and (math.abs(newPos.x - pos.x) > 0.1 or math.abs(newPos.z - pos.z) > 0.1) or newScale and math.abs(newScale - scale) > 0.001 or dirty then 
        pos, scale, dirty = newPos or pos, newScale or scale, false
        view:setOrthogonalParams(vec2(1, ratio):scale(viewRange()), 1000):update(pos + vec3(0, 100, 0), vec3(0, -1, 0), vec3(0, 0, -1), 0)
      end
      return view
    end,
    resize = function (size)
      ratio = size.y / size.x
      view = ac.GeometryShot(scene, size, 1, false, render.AntialiasingMode.FXAA)
        :setOpaqueAlphaFix(true):clear(rgbm.colors.black):setShadersType(render.ShadersType.Simplest)
        dirty = true
    end,
    dirty = function () dirty = true end,
    getPos = function () return pos end,
    getScale = function () return scale end,
    shift = function (deltaX, deltaY) pos, dirty = pos + vec3(-deltaX, 0, -deltaY):scale(viewRange()), true end,
    zoom = function (delta) scale, dirty = scale - delta * 0.4, true end,
    setCamera = function ()
      ac.setCurrentCamera(ac.CameraMode.Free)
      ac.setCameraPosition(pos + vec3(0, 20, 0))
      ac.setCameraDirection(vec3(0, -1, 0), vec3(0, 0, 1))      
    end
  }
end

---@param pos vec3
local function updateURL(pos)
  local baseCoords = worldToGeo(pos, geoBase, 0)
  tab:navigate('https://www.google.com/maps/@%f,%f,18z/data=!3m1!1e3' % {baseCoords.lat, baseCoords.lng})
end

-- tab:devToolsPopup()

---@return GeoPoint?
local function getCoordinates()
  local x, y = string.regmatch(tab:url(), [[/@(-?\d+\.\d+),(-?\d+\.\d+),]])
  if x and y then return {lng = tonumber(y), lat = tonumber(x)} end
end

local nextCoordsUpdate = -1

---@param fn GeoFactory
local function pushCoordinates(fn)
  if os.preciseClock() > nextCoordsUpdate then
    nextCoordsUpdate = os.preciseClock() + 1
    local coords = fn(ac.getSim().cameraPosition)
    tab:setGeolocation(coords.lat, coords.lng)
  end
end

local mainMap
local previewMap

local function drawCrosshair(p1, p2)
  local center = (p1 + p2) / 2
  ui.beginOutline()
  ui.drawCircle(center, 30, rgbm.colors.yellow, 30)
  ui.drawCircleFilled(center, 1, rgbm.colors.yellow)
  ui.drawSimpleLine(center + vec2(20, 0), center + vec2(40, 0), rgbm.colors.yellow)
  ui.drawSimpleLine(center - vec2(20, 0), center - vec2(40, 0), rgbm.colors.yellow)
  ui.drawSimpleLine(center + vec2(0, 20), center + vec2(0, 40), rgbm.colors.yellow)
  ui.drawSimpleLine(center - vec2(0, 20), center - vec2(0, 40), rgbm.colors.yellow)
  ui.endOutline(rgbm.colors.black)
end

local key = 'points_'..ac.getTrackID()

---@type DataPoint[]
local points
local lastComputedError

local function onPointsChanged(noSave)
  if not noSave then
    ac.storage[key] = stringify(points, true)
  end
  mainMap.dirty()
  pointsRef = table.map(points, function (item)
    return item.world
  end)
end

function script.windowMain(dt)
  if not mainMap then
    mainMap = createMapView(vec2(512, 512))
    previewMap = createMapView(vec2(200, 200))
    updateURL(mainMap.getPos())
    mainMap.setCamera()
    points = stringify.tryParse(ac.storage[key], nil, nil) or {}
    onPointsChanged(true)
  end

  ui.text(#points > 0
    and 'Align more points (the further away, the better the results, more points smooth out errors):'
    or 'Align the same point on both Google Maps and in-game map:')

  local newMapSize = vec2(math.round((ui.availableSpaceX() - 4) / 2), ui.availableSpaceY() - 162)
  if newMapSize ~= mapSize then
    mapSize = newMapSize
    mainMap.resize(mapSize)
  end

  local p1 = ui.getCursor()
  tab:control(mapSize)
  drawCrosshair(p1, p1 + mapSize)

  ui.sameLine(0, 4)
  p1 = ui.getCursor()
  if ui.interactiveArea('map', mapSize) then
    if ui.mouseDown(ui.MouseButton.Left) then mainMap.shift(ui.mouseDelta().x / mapSize.x, ui.mouseDelta().y / mapSize.y) end
    if ui.mouseWheel() ~= 0 then mainMap.zoom(ui.mouseWheel()) end
    mainMap.setCamera()
  end
  ui.setShadingOffset(3, 0, 0, 1)
  ui.drawImage(mainMap.draw(), p1, p1 + mapSize)
  ui.resetShadingOffset()
  drawCrosshair(p1, p1 + mapSize)

  local spaceX = ui.availableSpaceX()
  ui.setNextItemWidth((spaceX - 8) / 3)
  if ui.checkbox('Search bar', state.showSearch) then
    state.showSearch = not state.showSearch
    tab:sendAsync('show-search', state.showSearch)
  end
  ui.sameLine(0, 4)
  local curPos = ac.worldCoordinateToTrackProgress(ac.getSim().cameraPosition)
  ui.setNextItemWidth((spaceX - 8) / 3)
  local progress = ui.slider('##track', curPos * 100, 0, 100, 'Track: %.1f%%')
  if ui.itemActive() then
    ac.setCurrentCamera(ac.CameraMode.Free)
    mainMap.draw(ac.trackProgressToWorldCoordinate(progress / 100))
    mainMap.setCamera()
  end 
  ui.sameLine(0, 4)
  local coords = getCoordinates()
  ui.setNextItemIcon(ui.Icons.Plus)
  if ui.button('Add point', vec2(-0.1, 0), coords and 0 or ui.ButtonFlags.Disabled) then
    table.insert(points, {geo = coords, world = mainMap.getPos(), url = tab:url(), zoom = mainMap.getScale()})
    onPointsChanged()
  end

  local curError = lastComputedError
  lastComputedError = nil

  local curHovered
  if #points > 0 then
    ui.offsetCursorY(8)
    ui.beginGroup(ui.availableSpaceX() / 2 - 4)
    ui.header('Added points%s:' % (curError and ' (max error: %.1f m)' % curError or ''))
    ui.childWindow('points', ui.availableSpace(), function ()
      local outlier, outlierMax = nil, 0
      local errorsWithout = {}
      if #points > 2 and curError then
        for i = 1, #points do
          local _, _, err = computeValues(points, nil, points[i])
          local improveFactor = curError / err
          if improveFactor > outlierMax then
            outlierMax = improveFactor
            outlier = points[i]
          end
          errorsWithout[i] = err
        end
      end

      local toRemove
      for i = 1, #points do
        ui.pushID(i)
        if ui.selectable((outlier == points[i] and outlierMax > 10 and 'Point %d ⚠' or 'Point %d') % i, nil, 0, vec2(ui.availableSpaceX() - 24, 0)) then
          tab:navigate(points[i].url)
          mainMap.draw(points[i].world, points[i].zoom)
          mainMap.setCamera()
        end
        if ui.itemHovered() then
          curHovered = points[i].world
          ui.tooltip(function ()
            ui.setShadingOffset(3, 0, 0, 1)
            ui.image(previewMap.draw(points[i].world, points[i].zoom), 200)
            drawCrosshair(ui.itemRect())
            ui.resetShadingOffset()

            if errorsWithout[i] then
              ui.pushFont(ui.Font.Small)
              if curError > errorsWithout[i] then
                ui.setNextTextSpanStyle(11, 16, rgbm.colors.lime)
              else
                ui.setNextTextSpanStyle(11, 19, rgbm.colors.red)
              end
              ui.text(curError > errorsWithout[i]
                and 'Remove to reduce error by %.2f m.' % (curError - errorsWithout[i])
                or 'Remove to increase error by %.2f m.' % (errorsWithout[i] - curError))
              ui.popFont()
            end
          end)
        end
        ui.sameLine(0, 4)
        ui.offsetCursorY(-3)
        if ui.iconButton(ui.Icons.Delete, 18) then
          toRemove = i
        end
        ui.popID()
      end
      if toRemove then
        local v = table.remove(points, toRemove)
        onPointsChanged()
        ui.toast(ui.Icons.Delete, 'Point removed', function ()
          table.insert(points, v)
          onPointsChanged()
        end)
      end
    end)
    ui.endGroup()
    ui.sameLine(0, 8)
    ui.beginGroup()
    if #points > 1 then
      local cfg, fn, err = computeValues(points)
      lastComputedError = err
      ui.header('Config:')
      ui.pushFont(ui.Font.Monospace)
      ui.copyable(cfg)
      ui.popFont()
      if ui.itemHovered() then
        ui.setTooltip('For best results, add these lines to “surfaces.ini”')
      end
      pushCoordinates(fn)
      ui.offsetCursorY(8)
      ui.pushFont(ui.Font.Small)
      if ui.button('Move maps to camera', vec2(ui.availableSpaceX() / 2 - 2, 0)) then
        mainMap.draw(ac.getSim().cameraPosition)
        local baseCoords = fn(ac.getSim().cameraPosition)
        tab:navigate('https://www.google.com/maps/@%s,%s,18z/data=!3m1!1e3' % {baseCoords.lat, baseCoords.lng})
      end
      ui.sameLine(0, 4)
      if ui.button('Move Google Map to in-game map', vec2(-0.1, 0)) then
        local baseCoords = fn(mainMap.getPos())
        tab:navigate('https://www.google.com/maps/@%s,%s,18z/data=!3m1!1e3' % {baseCoords.lat, baseCoords.lng})
      end
      ui.text('Camera position is passed as geolocation.')
      ui.popFont()
    end
    ui.endGroup()
  end

  if hoveredPoint ~= curHovered then
    hoveredPoint = curHovered
    mainMap.dirty()
  end
end
