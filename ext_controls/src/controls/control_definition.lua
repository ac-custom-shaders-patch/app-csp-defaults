local ControlDefinition = {}

local EXT_PREFIX = "__EXT_"
local CAR_PREFIX = "__EXT_CAR_"
local LIGHT_PREFIX = "__EXT_LIGHT_"

local function trim(value) return tostring(value or ""):match("^%s*(.-)%s*$") end

local function optionalString(value)
        local result = trim(value)

        if result == "" then return nil end

        return result
end

local function startsWith(value, prefix) return value:sub(1, #prefix) == prefix end

local function normalizeBoolean(value) return value == true or value == 1 or value == "1" or value == "true" end

local function resolveBaseID(bind, luaControlled)
        if startsWith(bind, EXT_PREFIX) then return bind end

        if luaControlled then return CAR_PREFIX .. bind end

        return bind
end

local function resolveChildID(bind, child, luaControlled)
        child = optionalString(child)

        if child == nil or child == "0" then return nil end

        if startsWith(child, EXT_PREFIX) then return child end
        if startsWith(bind, LIGHT_PREFIX) then return LIGHT_PREFIX .. child end
        if startsWith(child, bind) then return child end

        return resolveBaseID(bind, luaControlled) .. child
end

local function splitLabels(value)
        if type(value) == "table" then
                local result = {}

                for i = 1, #value do
                        local label = optionalString(value[i])

                        if label then result[#result + 1] = label end
                end

                return result
        end

        local result = {}

        for item in tostring(value or ""):gmatch("([^,]+)") do
                local label = optionalString(item)

                if label then result[#result + 1] = label end
        end

        return result
end

local function normalizeActivation(raw, bind, luaControlled)
        if raw == nil or raw == false then return nil end

        if raw == true then raw = {} end

        assert(type(raw) == "table", "Control activation definition must be a table")

        return {
                id = optionalString(raw.id) or resolveBaseID(bind, luaControlled),

                label = optionalString(raw.label) or "Activate",

                hold = normalizeBoolean(raw.hold),
        }
end

local function normalizeSequential(raw, bind, luaControlled)
        if raw == nil or raw == false then return nil end

        assert(type(raw) == "table", "Sequential control definition must be a table")

        local rawDown = raw.down
        local rawUp = raw.up

        if type(rawDown) ~= "table" then
                rawDown = {
                        suffix = rawDown,
                        label = raw.downLabel,
                }
        end

        if type(rawUp) ~= "table" then
                rawUp = {
                        suffix = rawUp,
                        label = raw.upLabel,
                }
        end

        local downID = resolveChildID(bind, rawDown.id or rawDown.suffix, luaControlled)

        local upID = resolveChildID(bind, rawUp.id or rawUp.suffix, luaControlled)

        assert(
                (downID == nil) == (upID == nil),
                string.format("[%s] Sequential controls require both down and up IDs", bind)
        )

        if downID == nil then return nil end

        return {
                down = {
                        id = downID,

                        label = optionalString(rawDown.label) or "Decrease",
                },

                up = {
                        id = upID,

                        label = optionalString(rawUp.label) or "Increase",
                },
        }
end

local function normalizePositions(raw, bind, luaControlled)
        if raw == nil or raw == false then return nil end

        assert(type(raw) == "table", "Position control definition must be a table")

        if type(raw.rows) == "table" and #raw.rows > 0 then
                local rows = {}

                for index, rawRow in ipairs(raw.rows) do
                        assert(
                                type(rawRow) == "table",
                                string.format("[%s] Position row %d must be a table", bind, index)
                        )

                        local id = optionalString(rawRow.id)

                        assert(id ~= nil, string.format("[%s] Position row %d is missing an ID", bind, index))

                        rows[index] = {
                                index = tonumber(rawRow.index) or index,

                                id = id,

                                label = optionalString(rawRow.label) or string.format("Position %d", index),
                        }
                end

                return {
                        count = #rows,

                        indexOffset = tonumber(raw.indexOffset) or 0,

                        rows = rows,
                }
        end

        ----------------------------------------------------------------
        -- Raw registration definition.
        ----------------------------------------------------------------

        local count = math.max(0, math.floor(tonumber(raw.count) or 0))

        if count == 0 then return nil end

        local baseID = resolveBaseID(bind, luaControlled)

        local indexOffset = tonumber(raw.indexOffset) or 0

        local genericLabel = optionalString(raw.label) or "Position"

        local explicitLabels = splitLabels(raw.labels)

        local explicitIDs = raw.ids or {}

        if #explicitLabels > 0 and #explicitLabels ~= count then
                error(string.format("[%s] Expected %d position labels, got %d", bind, count, #explicitLabels))
        end

        local unit = optionalString(raw.unit)

        local suffix = unit and (" " .. unit) or ""

        local rows = {}

        for index = 1, count do
                local id = optionalString(explicitIDs[index]) or string.format("%s_%d", baseID, index)

                local label

                if #explicitLabels == count then
                        label = explicitLabels[index] .. suffix
                else
                        label = string.format("%s %d%s", genericLabel, index + indexOffset, suffix)
                end

                rows[index] = {
                        index = index,
                        id = id,
                        label = label,
                }
        end

        return {
                count = count,
                indexOffset = indexOffset,
                rows = rows,
        }
end

function ControlDefinition.normalize(raw)
        assert(type(raw) == "table", "Control definition must be a table")

        local bind = optionalString(raw.bind or raw.id)

        assert(bind ~= nil, "Control definition requires 'bind' or 'id'")

        local id = optionalString(raw.id) or bind
        local luaControlled = normalizeBoolean(raw.luaControlled)

        local activation = normalizeActivation(raw.activation, bind, luaControlled)

        local sequential = normalizeSequential(raw.sequential, bind, luaControlled)

        local positions = normalizePositions(raw.positions, bind, luaControlled)

        assert(
                not activation or (not sequential and not positions),
                string.format("[%s] Activation controls cannot also be sequential or positional", bind)
        )

        return {
                id = id,
                bind = bind,

                name = optionalString(raw.name) or bind,
                tab = optionalString(raw.tab) or "Generic",
                order = tonumber(raw.order) or 0,

                required = normalizeBoolean(raw.required),
                luaControlled = luaControlled,
                extendedPhysics = normalizeBoolean(raw.extendedPhysics),

                help = optionalString(raw.help) or "",

                activation = activation,
                sequential = sequential,
                positions = positions,
        }
end

return ControlDefinition
