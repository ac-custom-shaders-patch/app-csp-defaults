local ControlDefinition = require("src.controls.control_definition")

local ControlBinding = class("ControlBinding")

ControlBinding.InputMode = {
        Sequential = "sequential",
        Direct = "direct",
}

local EXT_PREFIX = "__EXT_"
local CAR_PREFIX = "__EXT_CAR_"
local LIGHT_PREFIX = "__EXT_LIGHT_"

local function trim(value) return tostring(value or ""):match("^%s*(.-)%s*$") end

local function optionalString(value)
        local result = trim(value)
        return result ~= "" and result or nil
end

local function optionalControlID(value)
        local result = optionalString(value)

        if result == nil or result == "0" then return nil end

        return result
end

local function startsWith(value, prefix) return value:sub(1, #prefix) == prefix end

local function splitLabels(value)
        local result = {}

        if type(value) == "table" then
                for i = 1, #value do
                        local label = optionalString(value[i])

                        if label then result[#result + 1] = label end
                end

                return result
        end

        for item in tostring(value or ""):gmatch("([^,]+)") do
                local label = optionalString(item)

                if label then result[#result + 1] = label end
        end

        return result
end

local function unitSuffix(unit)
        unit = trim(unit)

        if unit == "" then return "" end

        return " " .. unit
end

local function createButton(id, defaults)
        assert(id ~= nil and id ~= "", "Control button ID cannot be empty")

        local button

        if defaults then
                button = ac.ControlButton(id, defaults)
        else
                button = ac.ControlButton(id)
        end

        assert(button ~= nil, string.format("Failed to create control button: %s", id))

        return button
end

local function resolveBaseControlID(bind, isLuaControlled)
        if startsWith(bind, EXT_PREFIX) then return bind end

        if isLuaControlled then return CAR_PREFIX .. bind end

        return bind
end

local function resolveSequentialControlID(bind, token, isLuaControlled)
        if startsWith(token, EXT_PREFIX) then return token end

        if startsWith(bind, LIGHT_PREFIX) then return LIGHT_PREFIX .. token end

        return resolveBaseControlID(bind, isLuaControlled) .. token
end

local function resolvePositionControlID(bind, position, isLuaControlled)
        return resolveBaseControlID(bind, isLuaControlled) .. "_" .. position
end

local function normalizeDefinition(definition)
        assert(type(definition) == "table", "ControlBinding requires a definition table")

        local bind = optionalControlID(definition.bind or definition.id)

        assert(bind ~= nil, "ControlBinding definition is missing 'bind'")

        return {
                id = optionalControlID(definition.id) or bind,
                bind = bind,
                name = optionalString(definition.name) or bind,
                tab = optionalString(definition.tab) or "Generic",
                order = tonumber(definition.order) or 0,
                required = definition.required == true,
                luaControlled = definition.luaControlled == true,
                extendedPhysics = definition.extendedPhysics == true,
                help = optionalString(definition.help) or "",
                activation = definition.activation,
                sequential = definition.sequential,
                positions = definition.positions,
                selector = definition.selector,
        }
end

function ControlBinding:initialize(definition)
        definition = normalizeDefinition(definition)

        self.definition = definition

        self.bind = definition.bind
        self.name = definition.name
        self.tab = definition.tab
        self.order = definition.order
        self.required = definition.required
        self.help = definition.help

        self.isLuaControlled = definition.luaControlled
        self.isExtendedPhysics = definition.extendedPhysics

        self.isActivationBind = false
        self.isSequentialBind = false
        self.isMultiPositionSwitchBind = false

        self.inputMode = nil
        self.mpsToggle = false

        self.button = nil
        self.buttonDown = nil
        self.buttonUp = nil
        self.buttonPosition = {}

        self.activationLabel = nil
        self.buttonDownLabel = nil
        self.buttonUpLabel = nil
        self.buttonPositionLabel = {}
        self.buttonPositionLabelExplicit = false

        self.multiPositionSwitchCount = 0
        self.multiPositionSwitchIndex = 0

        self.activationRows = {}
        self.sequentialRows = {}
        self.positionRows = {}

        self:_createActivationBinding(definition.activation)

        if definition.selector then
                self:_bindSelector(definition.selector)
        else
                self:_createSequentialBinding(definition.sequential)
                self:_createPositionBindings(definition.positions)
                self:_selectInitialInputMode()
        end
end

function ControlBinding:_selectInitialInputMode()
        if self.isSequentialBind and self.isMultiPositionSwitchBind then
                if self.buttonUp:disabled() and self.buttonDown:disabled() then
                        self:setInputMode(ControlBinding.InputMode.Direct)
                else
                        self:setInputMode(ControlBinding.InputMode.Sequential)
                end
        elseif self.isSequentialBind then
                self:setInputMode(ControlBinding.InputMode.Sequential)

                return
        elseif self.isMultiPositionSwitchBind then
                self:setInputMode(ControlBinding.InputMode.Direct)
        end
end

function ControlBinding:_createActivationBinding(definition)
        if definition == nil then return end

        local buttonID = optionalControlID(definition.id)

        assert(buttonID ~= nil, string.format("[%s] Activation button ID is missing", self.bind))

        self.isActivationBind = true

        self.activationLabel = optionalString(definition.label) or "Activate"

        local defaults = nil

        if definition.hold == true then defaults = {
                hold = true,
        } end

        self.button = createButton(buttonID, defaults)

        self.activationRows[1] = {
                label = self.activationLabel,
                button = self.button,
                commandID = buttonID,
        }
end

function ControlBinding:_createSequentialBinding(definition)
        if definition == nil then return end

        assert(
                definition.down and definition.down.id,
                string.format("[%s] Sequential down definition is missing", tostring(self.bind))
        )

        assert(
                definition.up and definition.up.id,
                string.format("[%s] Sequential up definition is missing", tostring(self.bind))
        )

        self.isSequentialBind = true

        self.buttonDown = ac.ControlButton(definition.down.id)

        self.buttonUp = ac.ControlButton(definition.up.id)

        self.buttonDownLabel = definition.down.label or "Decrease"

        self.buttonUpLabel = definition.up.label or "Increase"

        self.sequentialRows[1] = {
                label = self.buttonUpLabel,
                button = self.buttonUp,
                commandID = definition.up.id,
        }

        self.sequentialRows[2] = {
                label = self.buttonDownLabel,
                button = self.buttonDown,
                commandID = definition.down.id,
        }
end

function ControlBinding:_createPositionBindings(definition)
        if definition == nil then return end

        self.isMultiPositionSwitchBind = true
        self.multiPositionSwitchCount = #definition.rows
        self.multiPositionSwitchIndex = definition.indexOffset or 0

        for index, row in ipairs(definition.rows) do
                local button = ac.ControlButton(row.id)

                self.buttonPosition[index] = button

                self.buttonPositionLabel[index] = row.label

                self.positionRows[index] = {
                        label = row.label,
                        button = button,
                        commandID = row.id,
                }
        end
end

function ControlBinding:_bindSelector(definition)
        local downDefinition = definition.down
        local upDefinition = definition.up

        local downID = downDefinition and optionalControlID(downDefinition.id) or nil

        local upID = upDefinition and optionalControlID(upDefinition.id) or nil

        if (downID == nil) ~= (upID == nil) then
                ac.warn(
                        string.format(
                                "[%s] Sequential input requires both down and up controls; sequential input disabled",
                                self.bind
                        )
                )

                downID = nil
                upID = nil
        end

        if downID and upID then
                self.isSequentialBind = true

                self.buttonDown = createButton(downID)
                self.buttonUp = createButton(upID)

                self.buttonDownLabel = optionalString(downDefinition.label) or "Decrease"

                self.buttonUpLabel = optionalString(upDefinition.label) or "Increase"
        end

        self:_bindPositions(definition.positions)

        local requestedMode = definition.initialInputMode

        if
                requestedMode ~= ControlBinding.InputMode.Direct
                and requestedMode ~= ControlBinding.InputMode.Sequential
        then
                requestedMode = nil
        end

        if self.isSequentialBind and self.isMultiPositionSwitchBind then
                if requestedMode == nil then
                        local sequentialDisabled = self.buttonDown:disabled() and self.buttonUp:disabled()

                        requestedMode = sequentialDisabled and ControlBinding.InputMode.Direct
                                or ControlBinding.InputMode.Sequential
                end
        elseif self.isMultiPositionSwitchBind then
                requestedMode = ControlBinding.InputMode.Direct
        elseif self.isSequentialBind then
                requestedMode = ControlBinding.InputMode.Sequential
        end

        if requestedMode then self:setInputMode(requestedMode) end

        self.sequentialRows = {
                {
                        label = self.buttonUpLabel,
                        button = self.buttonUp,
                        commandID = upID,
                },
                {
                        label = self.buttonDownLabel,
                        button = self.buttonDown,
                        commandID = downID,
                },
        }
end

function ControlBinding:_bindPositions(definition)
        if not definition then return end

        local count = math.max(0, math.floor(tonumber(definition.count) or 0))

        if count == 0 then return end

        assert(
                type(definition.idForIndex) == "function",
                string.format("[%s] Position controls require an idForIndex function", self.bind)
        )

        self.isMultiPositionSwitchBind = true
        self.multiPositionSwitchCount = count
        self.multiPositionSwitchIndex = tonumber(definition.indexOffset) or 0

        local explicitLabels = splitLabels(definition.labels)
        local genericLabel = optionalString(definition.label) or "Position"

        local suffix = unitSuffix(definition.unit)

        self.buttonPositionLabelExplicit = #explicitLabels > 1

        for i = 1, count do
                local buttonID = optionalControlID(definition.idForIndex(i))

                assert(buttonID ~= nil, string.format("[%s] Position %d produced an invalid control ID", self.bind, i))

                self.buttonPosition[i] = createButton(buttonID)

                local explicitLabel = explicitLabels[i]

                if self.buttonPositionLabelExplicit then
                        self.buttonPositionLabel[i] = explicitLabel .. suffix
                else
                        local displayedIndex = i + self.multiPositionSwitchIndex

                        self.buttonPositionLabel[i] = string.format("%s %d%s", genericLabel, displayedIndex, suffix)
                end

                self.positionRows[i] = {
                        label = self.buttonPositionLabel[i],
                        button = self.buttonPosition[i],
                        commandID = buttonID,
                }
        end
end

function ControlBinding:setInputMode(mode)
        if mode == ControlBinding.InputMode.Direct then
                if not self.isMultiPositionSwitchBind then return false end
        elseif mode == ControlBinding.InputMode.Sequential then
                if not self.isSequentialBind then return false end
        else
                error("Invalid control input mode: " .. tostring(mode))
        end

        self.inputMode = mode

        local directEnabled = mode == ControlBinding.InputMode.Direct

        for i = 1, self.multiPositionSwitchCount do
                self.buttonPosition[i]:setDisabled(not directEnabled)
        end

        if self.buttonDown then self.buttonDown:setDisabled(directEnabled) end

        if self.buttonUp then self.buttonUp:setDisabled(directEnabled) end

        self.mpsToggle = directEnabled

        return true
end

function ControlBinding:toggleInputMode()
        if not self.isSequentialBind or not self.isMultiPositionSwitchBind then return false end

        local nextMode = self.inputMode == ControlBinding.InputMode.Direct and ControlBinding.InputMode.Sequential
                or ControlBinding.InputMode.Direct

        return self:setInputMode(nextMode)
end

function ControlBinding:toggleMPS() return self:toggleInputMode() end

local function getINIDefaults(sectionName)
        return {
                NAME = sectionName,
                TAB = "Generic",
                ORDER = 0,
                REQUIRED = false,

                ACTIVATION = false,
                ACTIVATION_LABEL = "Activate",
                HOLD_MODE = false,

                DN = "",
                UP = "",
                DN_LABEL = "Decrease",
                UP_LABEL = "Increase",

                POS = 0,
                POS_LABEL_OFFSET = 0,
                POS_LABEL = "Position",
                POS_UNIT = "",

                EXT_PHYSICS = false,
                LUA = false,

                HELP = "",
        }
end

local function mapINISection(ini, sectionName)
        local defaults = getINIDefaults(sectionName)
        local values = ini:mapSection(sectionName, defaults)
        local rawSection = ini.sections[sectionName] or {}

        for key, defaultValue in pairs(defaults) do
                local rawValues = rawSection[key]

                if rawValues == nil or rawValues[1] == nil or rawValues[1] == "" then values[key] = defaultValue end
        end

        return values
end

function ControlBinding.fromDefinition(rawDefinition) return ControlBinding(ControlDefinition.normalize(rawDefinition)) end

function ControlBinding.fromINI(ini, sectionName, developerMode)
        local values = mapINISection(ini, sectionName)

        local downToken = optionalControlID(values.DN)
        local upToken = optionalControlID(values.UP)

        local positionCount = math.max(0, math.floor(tonumber(values.POS) or 0))

        local hasSelectorDefinition = downToken ~= nil or upToken ~= nil or positionCount > 0

        if developerMode and values.ACTIVATION and hasSelectorDefinition then
                ac.warn(
                        string.format(
                                "[%s] ACTIVATION is enabled; DN, UP and POS settings will be ignored",
                                sectionName
                        )
                )
        end

        local activation = nil
        local selector = nil

        if values.ACTIVATION then
                activation = {
                        id = resolveBaseControlID(sectionName, values.LUA),
                        label = values.ACTIVATION_LABEL,
                        hold = values.HOLD_MODE,
                }
        elseif hasSelectorDefinition then
                selector = {
                        down = downToken
                                        and {
                                                id = resolveSequentialControlID(sectionName, downToken, values.LUA),
                                                label = values.DN_LABEL,
                                        }
                                or nil,

                        up = upToken
                                        and {
                                                id = resolveSequentialControlID(sectionName, upToken, values.LUA),
                                                label = values.UP_LABEL,
                                        }
                                or nil,

                        positions = positionCount > 0 and {
                                count = positionCount,
                                indexOffset = values.POS_LABEL_OFFSET,
                                label = values.POS_LABEL,
                                labels = values.POS_LABEL,
                                unit = values.POS_UNIT,

                                idForIndex = function(index)
                                        return resolvePositionControlID(sectionName, index, values.LUA)
                                end,
                        } or nil,
                }
        end

        return ControlBinding({
                bind = sectionName,
                name = values.NAME,
                tab = values.TAB,
                order = values.ORDER,

                required = values.REQUIRED,
                luaControlled = values.LUA,
                extendedPhysics = values.EXT_PHYSICS,

                help = values.HELP,

                activation = activation,
                selector = selector,
        })
end

function ControlBinding:canToggleInputMode() return self.isSequentialBind and self.isMultiPositionSwitchBind end

function ControlBinding:isDirectInputMode() return self.inputMode == ControlBinding.InputMode.Direct end

function ControlBinding:getVisibleRows()
        if self.isActivationBind then return self.activationRows end

        if self:isDirectInputMode() then return self.positionRows end

        if self.isSequentialBind then return self.sequentialRows end

        return {}
end

return ControlBinding
