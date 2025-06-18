local sim = ac.getSim()

---@alias CarInfo {state: ac.StateCar, rpmUp: number, rpmDown: number, fuelWarning: number}
---@type CarInfo[]
local carInfo = {}

local function getCarInfo(carIndex)
  carIndex = math.max(carIndex, 0)
  local ret = carInfo[carIndex + 1]
  if not ret then
    local aiIni = ac.INIConfig.carData(carIndex, 'ai.ini')
    local carIni = ac.INIConfig.carData(carIndex, 'car.ini')
    ret = {
      state = ac.getCar(carIndex),
      rpmUp = aiIni:get('GEARS', 'UP', 9000),
      rpmDown = math.max(aiIni:get('GEARS', 'DOWN', 6000), aiIni:get('GEARS', 'UP', 9000) / 2),
      fuelWarning = carIni:get('GRAPHICS', 'FUEL_LIGHT_MIN_LITERS', 0)
    }
    carInfo[carIndex] = ret
  end
  return ret
end

local sceneColorsNeeded, sceneCanvas = 0, nil
local sceneColors = {
  scene = {
    rgbm(), -- forward
    rgbm(), -- backwards
    rgbm(), -- left
    rgbm(), -- right
    rgbm(), -- top
    rgbm(), -- bottom
    rgbm(), -- top (world-space)
    rgbm(), -- bottom (world-space)
  },
  mirror = {
    rgbm(), -- left
    rgbm(), -- middle
    rgbm(), -- right
  },
}
render.onSceneReady(function()
  if sceneColorsNeeded > sim.frame then
    if not sceneCanvas then
      sceneCanvas = ui.ExtraCanvas(vec2(8, 2), 1, render.TextureFormat.R8G8B8A8.UNorm)
    end
    if sceneCanvas:updateSceneWithShader({ textures = { txMirror = 'dynamic::mirror::raw' }, async = true, shader = [[
        float4 main(PS_IN pin) {
          float4 ldr = 0;
          if (pin.PosH.y < 1) {
            float3 dir = gCameraDirLook;
            if (floor(pin.PosH.x) == 1) dir = -gCameraDirLook;
            if (floor(pin.PosH.x) == 2) dir = cross(gCameraDirUp, gCameraDirLook);
            if (floor(pin.PosH.x) == 3) dir = -cross(gCameraDirUp, gCameraDirLook);
            if (floor(pin.PosH.x) == 4) dir = gCameraDirUp;
            if (floor(pin.PosH.x) == 5) dir = -gCameraDirUp;
            if (floor(pin.PosH.x) == 6) dir = float3(0, 1, 0);
            if (floor(pin.PosH.x) == 7) dir = float3(0, -1, 0);
            ldr = txReflectionCubemap.SampleLevel(samLinearSimple, dir * float3(-1, 1, 1), 10);
          } else {
            ldr = txMirror.SampleLevel(samLinearClamp, float2(1 - floor(pin.PosH.x) / 2, 0.5), 20);
          }
          ldr = max(ldr, 0);
          ldr = convertHDR(ldr, false);
          ldr.xyz = ldr.xyz * (1 + ldr.xyz * 0.1) / (1 + dot(ldr.xyz, 1./3));
          return ldr;
        }
      ]] }) then
      sceneCanvas:accessData(function(err, data)
        for i = 0, 7 do
          data:colorTo(sceneColors.scene[i + 1], i, 0)
        end
        for i = 0, 2 do
          data:colorTo(sceneColors.mirror[i + 1], i, 1)
        end
      end)
    end
  end
end)

local function getSceneColors()
  sceneColorsNeeded = sim.frame + 2
  return sceneColors
end

local knownColors = {}

local function getCarColor(carIndex)
  if carIndex < 0 then
    return nil
  end
  if knownColors[carIndex] == nil then
    knownColors[carIndex] = false
    ui.ExtraCanvas(2):copyFrom('car0::special::theme'):accessData(function (err, data)
      knownColors[carIndex] = {data:color(0, 0), data:color(1, 0), data:color(0, 1)}
    end)
  end
  local r = knownColors[carIndex]
  if r then
    return r[1].rgb, r[2].rgb, r[3].rgb
  end
  return rgb.colors.black
end

return {
  getCarInfo = getCarInfo,
  getCarColor = getCarColor,
  getSceneColors = getSceneColors
}
