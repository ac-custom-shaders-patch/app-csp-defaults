local controls = require("controls")
local cui = require("ui.cui")
local settings = require("settings")

local vec2Temp1 = vec2()
local vec2Temp2 = vec2()

controls:initialize()

local mainPage = {}

local LAYOUT = {
        infoHeight = 30,
        footerHeight = 30,

        bindingRowWidth = 315,
        bindingRowHeight = 32,
        bindingLabelWidth = 80,

        modeToggleSize = 20,
        modeToggleMargin = 5,
        modeToggleWidth = 76,

        sectionSpacing = 5,
}

local TAB_BAR_FLAGS = bit.bor(ui.TabBarFlags.TabListPopupButton, ui.TabBarFlags.FittingPolicyScroll)

local LIGHT_CONTROL_PREFIX = "__EXT_LIGHT_"

local presetInfo = {
        enabled = false,
        name = "",
}

local function startsWith(value, prefix) return type(value) == "string" and value:sub(1, #prefix) == prefix end

local function refreshPresetInfo()
        local ini = ac.INIConfig.controlsConfig()

        local presetName = ini:get("__LAUNCHER_CM", "PRESET_NAME", "")

        presetInfo.enabled = ini:get("__LAUNCHER_CM", "PRESET_CHANGED", -1) == 0

        presetInfo.name = tostring(presetName or ""):gsub("^savedSetups[\\/]", ""):gsub("%.ini$", "")
end

refreshPresetInfo()

local _controlSettingsListener = ac.onControlSettingsChanged(refreshPresetInfo)

local function getControlButtonFlags()
        local flags = ui.ControlButtonControlFlags.None

        if settings.disableBindDeactivation then
                flags = bit.bor(flags, ui.ControlButtonControlFlags.NoDeleteUnbound)
        end

        return flags
end

local function orderedBindings(content)
        local result = {}

        for _, binding in pairs(content or {}) do
                result[#result + 1] = binding
        end

        table.sort(result, function(a, b)
                local aOrder = tonumber(a.order) or 0
                local bOrder = tonumber(b.order) or 0

                if aOrder ~= bOrder then return aOrder < bOrder end

                return tostring(a.name) < tostring(b.name)
        end)

        return result
end

local function drawPresetInfo()
        local text = ""

        if presetInfo.enabled and presetInfo.name ~= "" then text = "Car-Specific Controls: " .. presetInfo.name end

        ui.textAligned(text, vec2Temp1:set(0.5, 0.5), vec2Temp2:set(ui.availableSpaceX(), LAYOUT.infoHeight))
end

local function drawMetadataIcons(binding)
        if binding.help and binding.help ~= "" then
                ui.sameLine()
                ui.offsetCursorX(-5)

                ui.pushStyleColor(ui.StyleColor.Button, rgbm(0, 0, 0, 0))

                ui.iconButton(ui.Icons.Info, vec2Temp1:set(12, 12), rgbm.colors.white, nil, 1)

                if ui.itemHovered(ui.HoveredFlags.AllowWhenBlockedByActiveItem) then
                        ui.tooltip(function() ui.textWrapped(binding.help, 200) end)
                end

                ui.popStyleColor(1)
        end

        if binding.isExtendedPhysics then
                ui.sameLine()
                ui.offsetCursorX(-5)

                ui.icon(ui.Icons.Speedometer, vec2Temp1:set(12, 12), rgbm.colors.white, nil, 1)
        end

        if binding.isLuaControlled then
                ui.sameLine()
                ui.offsetCursorX(-5)

                ui.icon(ui.Icons.Lua, vec2Temp1:set(12, 12), rgbm.colors.white, nil, 1)
        end
end

local function drawInputModeToggle(binding)
        if not binding:canToggleInputMode() then return end

        local toggleSize = LAYOUT.modeToggleSize

        ui.sameLine(ui.windowWidth() - LAYOUT.modeToggleWidth)

        ui.textAligned("MPS", vec2Temp1:set(0, 0.5), vec2Temp2:set(30, toggleSize))

        ui.sameLine()
        ui.setCursorY(ui.getCursorY() + 2)

        local x = ui.getCursorX()
        local y = ui.getCursorY()

        ui.drawRectFilled(
                vec2Temp1:set(x, y),
                vec2Temp2:set(x + toggleSize, y + toggleSize),
                rgbm(0.175, 0.175, 0.175, 1)
        )

        if ui.modernButton("##input-mode", vec2Temp1:set(toggleSize, toggleSize), ui.ButtonFlags.None) then
                binding:toggleInputMode()
        end

        if binding:isDirectInputMode() then
                local margin = LAYOUT.modeToggleMargin

                ui.drawRectFilled(
                        vec2Temp1:set(x + margin, y + margin),
                        vec2Temp2:set(x + toggleSize - margin, y + toggleSize - margin),
                        rgbm.colors.white
                )
        end

        if ui.itemHovered(ui.HoveredFlags.AllowWhenBlockedByActiveItem) then
                local currentMode = binding:isDirectInputMode() and "direct position" or "sequential"

                ui.tooltip(
                        function() ui.text(string.format("Current mode: %s\nClick to switch input modes", currentMode)) end
                )
        end
end

local function drawBindingHeader(binding)
        ui.setCursorX(cui.windowMargin)

        ui.pushFont(ui.Font.Title)
        ui.text(binding.name)
        ui.popFont()

        drawMetadataIcons(binding)
        drawInputModeToggle(binding)

        ui.drawSimpleLine(
                vec2Temp1:set(cui.windowMargin, ui.getCursorY() - 1),
                vec2Temp2:set(ui.windowWidth() - 18, ui.getCursorY() - 1),
                rgbm.colors.gray,
                2
        )
end

local function simulateLightCommand(commandID)
        ac.simulateCustomHotkeyPress(commandID)
        ac.trySimKeyPressCommand(commandID)
end

local function drawRowLabel(row)
        local size = vec2Temp1:set(LAYOUT.bindingLabelWidth, LAYOUT.bindingRowHeight)

        if startsWith(row.commandID, LIGHT_CONTROL_PREFIX) then
                ui.button(row.label, size, ui.ButtonFlags.None)

                if ui.itemActive() then simulateLightCommand(row.commandID) end

                return
        end

        ui.textAligned(row.label .. ":", vec2Temp2:set(1, 0.5), size)
end

local function drawBindingRow(row, index)
        if row.button == nil then return end

        ui.pushID(index)

        ui.setCursorX(cui.windowMargin)

        drawRowLabel(row)

        ui.sameLine()

        row.button:control(
                vec2Temp1:set(LAYOUT.bindingRowWidth, LAYOUT.bindingRowHeight),
                getControlButtonFlags(),
                "Click to assign"
        )

        ui.popID()
end

local function drawBinding(binding)
        ui.pushID(binding.bind)

        ui.newLine(-LAYOUT.sectionSpacing)

        drawBindingHeader(binding)

        local rows = binding:getVisibleRows()

        if #rows == 0 then
                ui.setCursorX(cui.windowMargin)
                ui.textDisabled("No configurable inputs")
        else
                for index, row in ipairs(rows) do
                        drawBindingRow(row, index)
                end
        end

        ui.popID()
end

local function drawCenteredMessage(text)
        ui.setCursorY(math.max(ui.getCursorY(), ui.windowHeight() * 0.5 - 12))

        ui.textAligned(text, vec2Temp1:set(0.5, 0.5), vec2Temp2:set(ui.availableSpaceX(), 24))
end

local function tabContentHeight()
        local footerReserve = settings.showIconLegend and LAYOUT.footerHeight or 4

        return math.max(ui.windowHeight() - ui.getCursorY() - footerReserve, 0)
end

local function drawTabContents(tab, scopeID)
        ui.childWindow(
                string.format("controls-content##%s:%s", scopeID, tab.name),
                vec2Temp1:set(ui.availableSpaceX(), tabContentHeight()),
                function()
                        local bindings = orderedBindings(tab.content)

                        if #bindings == 0 then
                                drawCenteredMessage("No controls in this tab")

                                return
                        end

                        for _, binding in ipairs(bindings) do
                                drawBinding(binding)
                        end
                end
        )
end

local function drawControlsTabBar(id, tabBar, scopeID)
        if tabBar == nil or tabBar.tabs == nil or #tabBar.tabs == 0 then
                drawCenteredMessage("No controls available")

                return
        end

        ui.tabBar(id, TAB_BAR_FLAGS, function()
                for index, tab in ipairs(tabBar.tabs) do
                        ui.tabItem(
                                string.format("%s##%s:%d", tab.name, scopeID, index),
                                function() drawTabContents(tab, scopeID) end
                        )
                end
        end)
end

local function drawCarControls() drawControlsTabBar("car-controls-tabs", controls.carControls, "car") end

local function drawAppControls()
        local appControls = controls.appControls or {}

        ui.tabBar("app-source-tabs", TAB_BAR_FLAGS, function()
                for appIndex, app in ipairs(appControls) do
                        ui.tabItem(
                                string.format("%s##app:%d", app.name, appIndex),
                                function()
                                        drawControlsTabBar("app-controls-tabs##" .. appIndex, app, "app:" .. appIndex)
                                end
                        )
                end
        end)
end

local function drawMainTabs()
        local contentManagerControls = controls.cmControls

        local carControls = controls.carControls

        local appControls = controls.appControls or {}

        if contentManagerControls == nil then
                ui.setCursorX(ui.windowWidth() * 0.5 - 25)

                ui.setCursorY(ui.windowHeight() * 0.5 - 25)

                ui.icon(ui.Icons.LoadingSpinner, vec2Temp1:set(50, 50))

                return
        end

        ui.tabBar("control-source-tabs", TAB_BAR_FLAGS, function()
                if carControls ~= nil and carControls.tabs ~= nil and #carControls.tabs > 0 then
                        ui.tabItem("Car##source:car", drawCarControls)
                end

                if #appControls > 0 then ui.tabItem("Apps##source:apps", drawAppControls) end

                for index, tab in ipairs(contentManagerControls.tabs or {}) do
                        ui.tabItem(
                                string.format("%s##cm:%d", tab.name, index),
                                function() drawTabContents(tab, "cm") end
                        )
                end
        end)
end
local function drawLegendItem(icon, label)
        ui.icon(icon, vec2Temp1:set(12, 12), rgbm.colors.white, nil, 1)

        ui.sameLine()
        ui.text(label)
end

local function drawFooter()
        local estimatedWidth = 310

        ui.setCursorY(ui.windowHeight() - LAYOUT.footerHeight + 5)

        ui.setCursorX(math.max(0, (ui.windowWidth() - estimatedWidth) * 0.5))

        drawLegendItem(ui.Icons.Info, "Info")

        ui.sameLine(0, 20)
        drawLegendItem(ui.Icons.Speedometer, "Extended Physics")

        ui.sameLine(0, 20)
        drawLegendItem(ui.Icons.Lua, "Lua")
end

function mainPage:draw(_dt)
        drawPresetInfo()

        pushButtonStyle()
        drawMainTabs()

        if settings.showIconLegend then drawFooter() end

        popButtonStyle()
end

return mainPage
