local AppState  = require('src/AppState')

local car = ac.getCar(0) or error()
local sim = ac.getSim()
local con = AppState.connection

---@param root ac.SceneReference
local function setupCopilotMotion(root)
  ---@param name string
  ---@return fun(mat: mat4x4)
  local function motion(name)
    local node = root:findNodes(name)
    if #node == 0 then
      ac.warn('Node is missing: %s' % name)
    end
    local neckTransform = node and node:getTransformationRaw()
    local neckOriginal = neckTransform ~= nil and neckTransform:clone()
    return neckOriginal and function (mat)
      neckTransform:set(mat):mulSelf(neckOriginal)
    end or function () end
  end

  local cfg = ac.INIConfig.carConfig(0)
  local gf1 = vec3()
  local gf2 = vec3()
  local dn1 = con.raceState % 2 == 1 and 1 or 0

  local neck = motion('CODRIVER:RIG_Nek')
  local armL, armR = motion('CODRIVER:RIG_Arm_L'), motion('CODRIVER:RIG_Arm_R')
  local mHandL, mHandR = motion('CODRIVER:RIG_HAND_L'), motion('CODRIVER:RIG_HAND_R')
  local forearmL, forearmR = motion('CODRIVER:RIG_ForeArm_L'), motion('CODRIVER:RIG_ForeArm_R')

  local function averageMatrices(mat1, mat2)
    local r = mat4x4()
    r.row1:set(mat1.row1):add(mat2.row1):scale(0.5)
    r.row2:set(mat1.row2):add(mat2.row2):scale(0.5)
    r.row3:set(mat1.row3):add(mat2.row3):scale(0.5)
    r.row4:set(mat1.row4):add(mat2.row4):scale(0.5)
    return r
  end

  local bookEntries = {}
  local books = root:findNodes(cfg:get('EXT_RALLY_COPILOT', 'BOOK_NODES', '{ Book? }'))
  local handL = root:findNodes('CODRIVER:RIG_HAND_L')
  local handR = root:findNodes('CODRIVER:RIG_HAND_R')
  if #handL == 1 and #handR == 1 then
    for i = 1, #books do
      local e = books:at(i)
      local bookParent = e:getParent()
      if e:class() == ac.ObjectClass.Node and #bookParent == 1 then
        table.insert(bookEntries, {
          transform = e:getTransformationRaw(),
          parent = bookParent,
          offset = e:getWorldTransformationRaw():mul(averageMatrices(handL:getWorldTransformationRaw(), handR:getWorldTransformationRaw()):inverseSelf())
        })
      end
    end
  end

  local mouth = root:applyHumanMaterials(root:findNodes('CODRIVER:RIG_Nek'), cfg:get('EXT_RALLY_COPILOT', 'BASE_DRIVER_MODEL', 'driver_fedora.kn5'), 0)
  local voicePeak = 0
  -- ac.broadcastSharedEvent('app.RallyCopilot', {extraPhraseID = 'start_getready'})
  -- ac.broadcastSharedEvent('app.RallyCopilot', {extraPhraseID = 'start_getready'})
  -- ac.broadcastSharedEvent('app.RallyCopilot', {extraPhraseID = 'start_getready'})

  setInterval(function ()
    voicePeak = math.applyLag(voicePeak, con.speechPeak * 0.8, 0.8, sim.dt)
    local offsetX, offsetY = mouth(voicePeak)

    -- dn1 = math.applyLag(dn1, math.saturateN(con.distanceToNextHint / 100 - 0.5), 0.97, sim.dt) -- looks weird
    dn1 = math.applyLag(dn1, con.raceState % 2 == 1 and 1 or 0, 0.97, sim.dt)

    local acc = math.clamp(car.acceleration * -0.009, vec3(-0.5, -0.5, -0.5), vec3(0.5, 0.5, 0.5))
    gf1 = math.applyLag(gf1, acc, 0.9, sim.dt)
    gf2 = math.applyLag(gf2, acc * 0.3, 0.92, sim.dt)

    neck(mat4x4.translation(gf1)
      :mulSelf(mat4x4.rotation(gf1.z * 10 - 0.05 * dn1 + offsetX, vec3(1, 0, 0)))
      :mulSelf(mat4x4.rotation(gf1.x * 10 + offsetY, vec3(0, 0, 1))))

    local h = mat4x4.translation(gf2)
      :mulSelf(mat4x4.rotation(gf2.x * 10, vec3(0, 0, 1)))
      :mulSelf(mat4x4.rotation(gf2.z * 10 + 0.23 * dn1, vec3(1, 0, 0)))
    armL(h)
    armR(h)
    forearmL(h)
    forearmR(h)

    local h2 = mat4x4.rotation(-0.2 * dn1, vec3(1, 0, 0))
    mHandL(h2)
    mHandR(h2)

    local booksAvg = averageMatrices(handL:getWorldTransformationRaw(), handR:getWorldTransformationRaw())
    for _, e in ipairs(bookEntries) do
        e.transform:set(e.offset):mulSelf(booksAvg):mulSelf(e.parent:getWorldTransformationRaw():inverse())
    end
  end)
end

local function loadCopilotModel()
  local copilotFilename = '%s\\%s\\codriver.kn5' % {ac.getFolder(ac.FolderID.ContentCars), ac.getCarID(0)}
  ac.debug('copilotFilename', copilotFilename)
  if not io.fileExists(copilotFilename) then return end
  local lodsINI = ac.INIConfig.carData(0, 'lods.ini')
  for _, section in lodsINI:iterate('LOD') do
    if lodsINI:get(section, 'FILE', ''):lower() == 'codriver.kn5' then
      return
    end
  end
  ac.findNodes('carRoot:0'):findNodes('BODYTR'):at(1):loadKN5Async(copilotFilename, function (err, loaded)
    if err then
      ac.warn('Failed to load copilot model: %s' % err)
    else
      ac.log('Copilot model is loaded and ready')
      setupCopilotMotion(loaded)
    end
  end)
end

try(loadCopilotModel, function (err)
  ac.warn('Failed to load copilot: %s' % err)
end)
