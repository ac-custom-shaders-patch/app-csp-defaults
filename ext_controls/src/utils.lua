---@ext

local sim = ac.getSim()

local max = math.max
local min = math.min
local isnan = math.isnan
local isinf = math.isinf
local cos = math.cos
local pi = math.pi

local tau = math.tau
local energyConst = const((tau / 60) * (10 ^ -6))
local powerConst = const((60 / tau) * 1000)
local degreeToRadian = const(pi / 180)
local rpmToRad = const(tau / 60)

local utils = {}

function isempty(string) return string == nil or string == "" end

function __genOrderedIndex(t)
        local orderedIndex = {}
        for key in pairs(t) do
                table.insert(orderedIndex, key)
        end
        table.sort(orderedIndex)
        return orderedIndex
end

function orderedNext(t, state)
        local key = nil
        if state == nil then
                t.__orderedIndex = __genOrderedIndex(t)
                key = t.__orderedIndex[1]
        else
                for i = 1, #t.__orderedIndex do
                        if t.__orderedIndex[i] == state then key = t.__orderedIndex[i + 1] end
                end
        end

        if key then return key, t[key] end

        t.__orderedIndex = nil
end

function orderedPairs(t) return orderedNext, t, nil end

function utils.energyConsumptionMJ(dt, torque, rpm) return max(torque * rpm * energyConst * dt, 0) end

function utils.energyDeltaMJ(dt, powerKW) return powerKW * dt * 0.001 end

function utils.powerToTorque(powerKW, rpm)
        if isnan(rpm) or isinf(rpm) then return 0 end
        return (powerConst * powerKW) / max(rpm, 1)
end

function utils.torqueToPower(torque, rpm)
        if rpm == 0 or torque == 0 then return 0 end
        return (torque * rpm) / powerConst
end

function utils.calculateHeadwindSpeed()
        local d = (car.compass - sim.windDirectionDeg) % 360
        d = d > 180 and 360 - d or d
        return -sim.windSpeedKmh * cos(d * degreeToRadian)
end

function utils.rpmToRadS(rpm) return rpm * rpmToRad end

function utils.radsToRPM(rads) return rads / rpmToRad end

-- origin: world-space position of the car (e.g. CarPhysics.position)
-- right, up, look: car basis vectors in WORLD space (e.g. car.right, car.up, car.look)
local function toWorld(localPos, origin, right, up, look)
        return origin + right * localPos.x + up * localPos.y + look * localPos.z
end

function utils.drawLocalBox(p1, p2, origin, right, up, look, color)
        -- local-space min/max
        local minx, maxx = min(p1.x, p2.x), max(p1.x, p2.x)
        local miny, maxy = min(p1.y, p2.y), max(p1.y, p2.y)
        local minz, maxz = min(p1.z, p2.z), max(p1.z, p2.z)

        -- 8 local corners
        local c = {
                vec3(minx, miny, minz),
                vec3(maxx, miny, minz),
                vec3(minx, maxy, minz),
                vec3(maxx, maxy, minz),
                vec3(minx, miny, maxz),
                vec3(maxx, miny, maxz),
                vec3(minx, maxy, maxz),
                vec3(maxx, maxy, maxz),
        }

        -- to world using origin+basis
        for i = 1, 8 do
                c[i] = toWorld(c[i], origin, right, up, look)
        end

        local function edge(a, b) ac.drawDebugLine(c[a], c[b], color) end

        -- bottom
        edge(1, 2)
        edge(2, 4)
        edge(4, 3)
        edge(3, 1)
        -- top
        edge(5, 6)
        edge(6, 8)
        edge(8, 7)
        edge(7, 5)
        -- verticals
        edge(1, 5)
        edge(2, 6)
        edge(3, 7)
        edge(4, 8)
end

function utils.drawLocalBoxCentered(centerLocal, size, origin, right, up, look, color)
        local hx = (size.x or size[1] or 0) * 0.5
        local hy = (size.y or size[2] or 0) * 0.5
        local hz = (size.z or size[3] or 0) * 0.5

        local p1 = vec3(centerLocal.x - hx, centerLocal.y - hy, centerLocal.z - hz)
        local p2 = vec3(centerLocal.x + hx, centerLocal.y + hy, centerLocal.z + hz)

        -- local-space min/max
        local minx, maxx = min(p1.x, p2.x), max(p1.x, p2.x)
        local miny, maxy = min(p1.y, p2.y), max(p1.y, p2.y)
        local minz, maxz = min(p1.z, p2.z), max(p1.z, p2.z)

        -- 8 local corners
        local c = {
                vec3(minx, miny, minz),
                vec3(maxx, miny, minz),
                vec3(minx, maxy, minz),
                vec3(maxx, maxy, minz),
                vec3(minx, miny, maxz),
                vec3(maxx, miny, maxz),
                vec3(minx, maxy, maxz),
                vec3(maxx, maxy, maxz),
        }

        -- to world using origin+basis
        for i = 1, 8 do
                c[i] = toWorld(c[i], origin, right, up, look)
        end

        local function edge(a, b) ac.drawDebugLine(c[a], c[b], color) end

        -- bottom
        edge(1, 2)
        edge(2, 4)
        edge(4, 3)
        edge(3, 1)
        -- top
        edge(5, 6)
        edge(6, 8)
        edge(8, 7)
        edge(7, 5)
        -- verticals
        edge(1, 5)
        edge(2, 6)
        edge(3, 7)
        edge(4, 8)
end

return utils
