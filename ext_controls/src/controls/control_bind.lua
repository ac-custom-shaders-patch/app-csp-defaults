local ControlBind = class("ControlBind")

local function createButton(id, defaults)
        assert(type(id) == "string" and id ~= "", "Control button ID cannot be empty")

        local button

        if defaults then
                button = ac.ControlButton(id, defaults)
        else
                button = ac.ControlButton(id)
        end

        assert(button ~= nil, string.format("Failed to create control button: %s", id))

        return button
end

function ControlBind:initialize(definition)
        assert(type(definition) == "table", "ControlBind requires a normalized definition")

        self.definition = definition

        self.id = definition.id
        self.bind = definition.bind

        self.button = nil
        self.buttonDown = nil
        self.buttonUp = nil

        self.buttonPosition = {}
        self.multiPositionSwitchCount = 0

        if definition.activation then
                local defaults = nil

                if definition.activation.hold then
                        defaults = {
                                hold = true,
                        }
                end

                self.button = createButton(definition.activation.id, defaults)
        end

        if definition.sequential then
                self.buttonDown = createButton(definition.sequential.down.id)

                self.buttonUp = createButton(definition.sequential.up.id)
        end

        if definition.positions then
                self.multiPositionSwitchCount = #definition.positions.rows

                for i, row in ipairs(definition.positions.rows) do
                        self.buttonPosition[i] = createButton(row.id)
                end
        end
end

return ControlBind
