local cui = require("ui.cui")
local gui = ac.getUI()
local settings = require("settings")

local settingsPage = {}

local function settingsItem(label, item, hint)
        local changed = false
        if settings[item] ~= settings["__data__"][item]["default"] then
                ui.pushStyleColor(ui.StyleColor.Text, rgbm.colors.red)
        else
                ui.pushStyleColor(ui.StyleColor.Text, rgbm.colors.white)
        end
        ui.setCursorX(cui.windowMargin)
        if ui.checkbox(label, settings[item]) then
                settings[item] = not settings[item]
                changed = true
        end
        ui.popStyleColor(1)

        if hint then
                if ui.itemHovered(ui.HoveredFlags.AllowWhenBlockedByActiveItem) then
                        ui.tooltip(function() ui.text(hint) end)
                end
        end

        return changed
end

local function settingsText()
        ui.pushFont(ui.Font.Title)
        ui.textAligned("Settings", vec2(0.5, 0.5), vec2(ui.availableSpaceX(), 30))
        ui.popFont()
end

function settingsPage:draw()
        settingsText()

        ui.setCursorY(105)

        ui.drawSimpleLine(vec2(0, ui.getCursorY()), vec2(ui.windowWidth(), ui.getCursorY()), gui.accentColor)
        ui.newLine()

        settingsItem(
                "Show icon legend",
                "showIconLegend",
                "Show Info/Extended Physics/Lua icons at the bottom of the window."
        )
        settingsItem(
                "Save all controls to the current Car-Specific preset",
                "saveAllControlsToPreset",
                "By default, controls outside of the Car tab will save to the main controls."
        )

        settingsItem(
                "Disable forced binds",
                "disableForcedBinds",
                "Disable car scripts from forcing the user to bind certain bindings."
        )
        settingsItem("Show app version", "showAppVersion", "Displays the app version at the top of the window.")

        if ac.getPatchVersionCode() > 2685 then
                settingsItem(
                        "Prevent MPS toggle from disabling binds",
                        "disableBindDeactivation",
                        "By default, when toggling between the Sequential/Multi-Position Switch option,\nthe hidden bindings get disabled to prevent collisions."
                )
        end
        ui.newLine()

        settingsItem(
                "Developer mode",
                "developerMode",
                "Enable Developer Mode. Only needed for creating custom car control files."
        )

        ui.newLine()

        ui.setCursorX(cui.windowMargin)
        if ui.button("RESET", vec2(ui.windowWidth() - cui.windowMargin * 2, 22)) then
                for _k, _v in pairs(settings) do
                        for key, table in pairs(_v) do
                                settings[key] = table["default"]
                        end
                end
        end
end

return settingsPage
