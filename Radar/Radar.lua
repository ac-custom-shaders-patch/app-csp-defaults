local sim = ac.getSim()
local distanceCap = 20

local config = ac.storage{
  tilt = 0.7,
  fov = 0,
  range = 0.5,
  pit = true,
  track = true,
  subtle = false,
  blue = true,
  yellow = true,
  introduction = true,
  shading = 3,
  colorOwn = rgb(0.2, 0.2, 0.2),
}

local carTextures = {}

---@param car ac.StateCar
local function getCarTexture(car)
  local found = carTextures[car.index]
  if not found then
    local shot = ac.GeometryShot(ac.findNodes('carRoot:%d' % car.index), 256, 4, true)
    shot:setShadersType(render.ShadersType.Simplified)
    shot:setTransparentPass(true)
    shot:setOrthogonalParams(vec2(car.aabbSize.x, car.aabbSize.z), 100)
    shot:update(car.position + car.up * 50, -car.up, car.look, 0)

    found = ui.ExtraCanvas(128, 3):copyFrom(shot)
    shot:dispose()
    carTextures[car.index] = found
  end
  return found
end

local drawMesh_track = { mesh = ac.SimpleMesh.trackLine(0, 0, 1), values = { gSize = vec2() }, shader = 'res/track.fx' }
local drawMesh_pits = { mesh = ac.SimpleMesh.trackLine(1, 0, 4), values = { gSize = vec2() }, shader = 'res/track.fx' }

local focusedCar ---@type ac.StateCar
local colorOther = rgb(1, 1, 1)
local colorFar = rgb(1, 1, 1)

local COLOR_DIST_1 = 4
local COLOR_DIST_2 = 6
local COLOR_DIST_3 = 8

---@type fun(car: ac.StateCar, alpha: number)[]
local drawCall_car = {
  (function (params, car, alpha) ---@param car ac.StateCar
    params.mesh = ac.SimpleMesh.carShape(car.index, true)
    if focusedCar == car then
      params.values.gColor = config.colorOwn
    else
      local d = focusedCar.position:distanceSquared(car.position)
      if d < COLOR_DIST_3 * COLOR_DIST_3 then 
        colorOther.g = math.lerpInvSat(d, COLOR_DIST_1 * COLOR_DIST_1, COLOR_DIST_2 * COLOR_DIST_2)
        colorOther.b = math.lerpInvSat(d, COLOR_DIST_2 * COLOR_DIST_2, COLOR_DIST_3 * COLOR_DIST_3)
        params.values.gColor = colorOther
      else
        params.values.gColor = colorFar
      end
    end
    params.values.gSizeX = 2 / car.aabbSize.x
    params.values.gSizeZ = -2 / car.aabbSize.z
    params.values.gAlpha = alpha ^ 2
    params.textures.txLivery = 'car%d::special::livery' % car.index
    render.mesh(params)
  end):bind({ transform = 'original', textures = {}, values = {}, defines = { MODE = 1 }, shader = 'res/car.fx', cacheKey = 1 }),
  (function (params, car, alpha) ---@param car ac.StateCar
    params.mesh = ac.SimpleMesh.carShape(car.index, true)
    params.values.gSizeX = 2 / car.aabbSize.x
    params.values.gSizeZ = -2 / car.aabbSize.z
    params.values.gAlpha = alpha ^ 2
    params.textures.txLivery = 'car%d::special::livery' % car.index
    render.mesh(params)
  end):bind({ transform = 'original', textures = {}, values = {}, defines = { MODE = 2 }, shader = 'res/car.fx', cacheKey = 2 }),
  (function (params, car, alpha) ---@param car ac.StateCar
    params.mesh = ac.SimpleMesh.carShape(car.index, true)
    params.values.gSizeX = 2 / car.aabbSize.x
    params.values.gSizeZ = -2 / car.aabbSize.z
    params.values.gAlpha = alpha ^ 2
    params.textures.txLivery = getCarTexture(car)
    render.mesh(params)
  end):bind({ transform = 'original', textures = {}, values = {}, defines = { MODE = 3 }, shader = 'res/car.fx', cacheKey = 3 }),
}

---@type fun(car: ac.StateCar, alpha: number)
local drawCall_pit = (function (params, car, alpha) ---@param car ac.StateCar
  params.mesh = ac.SimpleMesh.carCollider(car.index)
  params.values.gAlpha = alpha ^ 2
  local t = params.transform ---@type mat4x4
  t:set(car.pitTransform)
  t:mulSelf(mat4x4.scaling(vec3(1, 0, 1)))
  t:mulSelf(mat4x4.translation(vec3(0, car.pitTransform.position.y, 0)))
  render.mesh(params)
end):bind({ transform = mat4x4(), textures = {}, values = {}, shader = 'res/pit.fx' })

---@type fun(mesh: ac.SceneReference)
local drawCall_brakes = (function (params, mesh)
  params.mesh = mesh
  render.mesh(params)
end):bind({ transform = 'original', shader = 'res/brakes.fx' })

---@type fun(mesh: ac.SceneReference)
local drawCall_tyres = (function (params, mesh)
  params.mesh = mesh
  render.mesh(params)
end):bind({ transform = 'original', shader = 'res/tyres.fx' })

local brakeMeshes = {}
local tyreMeshes = {}

local function findCarBrakeLights(car)
  return ac.findNodes('carRoot:%d' % car.index):findMeshes('{ actsAsBrakeLights:yes & lod:A }')
end

local function findCarTyres(car)
  return ac.findNodes('carRoot:%d' % car.index):findNodes('{ (WHEEL_LF, WHEEL_RF) & lod:A }')
    :findMeshes('{ shader:ksTyres? }')
end

local vecUp = vec3(0, 1, 0)
local canvasScene = {
  opaque = function ()
    -- ac.perfBegin('track')
    if config.track then
      render.setDepthMode(render.DepthMode.Off)
      render.mesh(drawMesh_pits)
      render.mesh(drawMesh_track)
    end
    -- ac.perfEnd('track')

    -- ac.perfBegin('pit')
    render.setDepthMode(render.DepthMode.Normal)
    if config.pit and focusedCar.pitTransform.position:closerToThan(focusedCar.position, distanceCap) then
      local alpha = 1 - focusedCar.pitTransform.position:distanceSquared(focusedCar.position) / (distanceCap * distanceCap)
      alpha = math.lerpInvSat(alpha, 0, 0.5)
      drawCall_pit(focusedCar, alpha)
    end
    -- ac.perfBegin('pit')

    local fn = drawCall_car[config.shading]
    for _, c in ac.iterateCars.ordered() do
      if not c.position:closerToThan(focusedCar.position, distanceCap * 2) then
        return
      end

      local alpha = 1 - c.position:distanceSquared(focusedCar.position) / (distanceCap * distanceCap)
      alpha = math.lerpInvSat(alpha, 0, 0.5)

      -- ac.perfBegin('car:%d' % c.index)
      if sim.raceFlagCause == c.index then
        if sim.raceFlagType == ac.FlagType.Caution and config.yellow then
          render.circle(c.position, vecUp, 2.4, rgbm.colors.transparent, rgbm.colors.yellow)
        elseif sim.raceFlagType == ac.FlagType.FasterCar and config.blue then
          render.circle(c.position, vecUp, 2.4, rgbm.colors.transparent, rgbm.colors.cyan)
        end
      end

      fn(c, alpha)
      -- ac.perfEnd('car:%d' % c.index)
      -- ac.perfBegin('car tyres:%d' % c.index)
      if c.activeLOD == 0 then
        if c.brakeLightsActive then
          drawCall_brakes(table.getOrCreate(brakeMeshes, c.index, findCarBrakeLights, c))
        end
        if alpha == 1 and math.abs(c.steer) > 1 then
          drawCall_tyres(table.getOrCreate(tyreMeshes, c.index, findCarTyres, c))
        end
      end
      -- ac.perfEnd('car tyres:%d' % c.index)
    end
  end
}

local cameraDistanceThreshold = 40
local function distanceToNextCar()
  local m = math.huge
  for _, c in ac.iterateCars.ordered() do
    if c ~= focusedCar then
      m = math.min(m, c.position:distanceSquared(focusedCar.position))
      if not focusedCar.position:closerToThan(c.position, cameraDistanceThreshold) then
        return m
      end
    end
  end
  return m
end

local canvas ---@type ac.GeometryShot
local camDir = vec3()
local camPos = vec3()
local active = false
local fading = 1
local lastPos = vec2(1e9)
local lastSizeKey = 0
local actualFOV = 0
local actualDistance = 0

local function updateValues()
  distanceCap = math.lerp(5, 15, config.range ^ 2) * math.lerp(1.4, 2.2, config.tilt)
  actualFOV = 5 + 40 * config.fov
  actualDistance = -math.lerp(5, 15, config.range ^ 2) * math.lerp(1.6, 1, config.tilt) / math.tan(math.rad(actualFOV) / 2)
end

updateValues()

local outputCommand = {
  p1 = vec2(),
  p2 = vec2(),
  blendMode = render.BlendMode.AlphaBlend,
  textures = { txImage = '' },
  values = { gAlpha = 1 },
  shader = 'res/output.fx'
}

function script.windowMain(dt)
  local windowFading = ac.windowFading()

  if config.introduction then
    ac.forceFadingIn()
  end

  if not focusedCar or focusedCar.index ~= sim.closelyFocusedCar then
    focusedCar = ac.getCar(sim.focusedCar) or ac.getCar(0)
    if focusedCar.distanceToCamera > 10 then
      cameraDistanceThreshold = focusedCar.distanceToCamera + 40
    else
      cameraDistanceThreshold = 40
    end
  end

  if config.subtle then
    local distance
    if focusedCar.isInPitlane then
      distance = focusedCar.isInPit and 1e3 or 0
    else
      distance = distanceToNextCar()
    end

    if not active then
      if distance < distanceCap * distanceCap * 0.8 then
        active = true
      end
    else
      if distance > distanceCap * distanceCap then
        active = false
      end
    end

    fading = math.applyLag(fading, active and 1 or 0, 0.9, dt)
    if fading < 0.01 then
      if windowFading < 1 then
        ui.pushStyleVarAlpha(1 - windowFading)
        ui.textAligned('No cars nearby', 0.5, ui.availableSpace())
        ui.popStyleVar()
      end
      return
    end
  else
    fading = 1
  end

  local c = ui.getCursor()
  local s = ui.availableSpace()
  if lastSizeKey ~= s.x * 1e4 + s.y then
    lastSizeKey = s.x * 1e4 + s.y

    if canvas then canvas:dispose() end
    local size = s:clone():scale(2)
    canvas = ac.GeometryShot(canvasScene, size, 1, true, render.AntialiasingMode.None)
    canvas:setShadersType(render.ShadersType.SampleColor)
    canvas:setClippingPlanes(1, 1000)
    drawMesh_track.values.gSize = 2 / size
    drawMesh_pits.values.gSize = 2 / size
    outputCommand.textures.txImage = canvas
  end

  local car = focusedCar
  camDir:setScaled(car.up, -1):addScaled(car.look, config.tilt)
  camPos:set(car.position):addScaled(camDir, actualDistance)
  canvas:update(camPos, camDir, car.look, actualFOV)

  outputCommand.p1:set(c)
  outputCommand.p2:set(c):add(s)
  outputCommand.values.gAlpha = fading
  ui.renderShader(outputCommand)

  if windowFading > 0.99 then return end
  local cur = ui.windowPos()
  if not lastPos:closerToThan(cur, 1) then
    if lastPos.x ~= 1e9 then
      config.introduction = false
    end
    lastPos:set(cur)
  end
  ui.pushStyleVarAlpha(1 - windowFading)
  ui.beginOutline()
  for x = 0, 1 do
    for y = 0, 1 do
      local p = vec2(c.x + x * s.x, c.y + s.y * y)
      ui.pathLineTo(p + vec2(x == 0 and 20 or -20, 0))
      ui.pathLineTo(p)
      ui.pathLineTo(p + vec2(0, y == 0 and 20 or -20))
      ui.pathStroke(rgbm.colors.white, false, 1)
    end
  end
  if config.introduction then
    ui.drawTextClipped('\tPosition and size this window to\nthe place you’d like your radar to be', c, c + s, rgbm.colors.white, 0.5)
  end
  ui.endOutline(rgbm.colors.black, 1 - windowFading)
  ui.popStyleVar()
end

function script.windowSettings(dt)
  ui.header('Behaviour')
  if ui.checkbox('Hide if there are no cars nearby', config.subtle) then
    config.subtle = not config.subtle
  end
  if ui.itemHovered() then
    ui.setTooltip('Hide everything (including your car) if there are no cars nearby')
  end
  if ui.checkbox('Highlight blue flagged', config.blue) then
    config.blue = not config.blue
  end
  if ui.itemHovered() then
    ui.setTooltip('Highlight car you should let pass and not overtake with blue circle')
  end
  if ui.checkbox('Highlight yellow flagged', config.yellow) then
    config.yellow = not config.yellow
  end
  if ui.itemHovered() then
    ui.setTooltip('Highlight stuck car with yellow circle')
  end
  if ui.checkbox('Show pit position', config.pit) then
    config.pit = not config.pit
  end
  if ui.itemHovered() then
    ui.setTooltip('Add a subtle highlight to pits area for easier parking')
  end
  if ui.checkbox('Show track borders', config.track) then
    config.track = not config.track
  end
  if ui.itemHovered() then
    ui.setTooltip('Add subtle track outline')
  end
  ui.offsetCursorY(12)
  ui.header('Camera')
  config.tilt = ui.slider('##tilt', config.tilt * 100, 0, 100, 'Tilt: %.0f%%') / 100
  config.fov = ui.slider('##fov', config.fov * 100, 0, 100, 'FOV: %.0f%%') / 100
  config.range = ui.slider('##range', config.range * 100, 0, 100, 'Range: %.0f%%') / 100
  ui.offsetCursorY(12)
  ui.header('Style')
  config.shading = ui.combo('##style', config.shading, ui.ComboFlags.None, {
    'Color based on distance',
    'Livery color',
    'Livery in detail',
  })
  if config.shading == 1 then
    ui.alignTextToFramePadding()
    ui.text('Own color:')
    ui.sameLine(222)
    local editedColor = config.colorOwn:clone()
    ui.colorButton('##ownColor', editedColor, ui.ColorPickerFlags.PickerHueBar)
    if editedColor ~= config.colorOwn then
      config.colorOwn = editedColor
    end
  end
  updateValues()
end

if ac.getPatchVersionCode() <= 2425 then
  script.windowMain = function(dt)
    ui.textAligned('CSP v0.1.80-preview280 or above is required.', 0.5, -0.1)
  end
end
