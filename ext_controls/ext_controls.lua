package.add("src")

local commonPage = require("ui.pages.common")
local mainPage = require("ui.pages.main")
local sdkPage = require("ui.pages.sdk")
local settingsPage = require("ui.pages.settings")

local app = require("app")
local settings = require("settings")
local utils = require("utils")

local requiredBindsIntervalID = nil
requiredBindsIntervalID = setInterval(function()
        if settings.disableForcedBinds then return end

        if ac.load("__EXT_CAR_MISSING_BINDS") == 1 then
                if not ac.isWindowOpen("main") then ac.setAppOpen("ext_controls") end
        elseif ac.load("__EXT_CAR_MISSING_BINDS") == 0 then
                clearInterval(requiredBindsIntervalID)
        end
end, 1, "CriticalBindsExtControls")

function script.main()
        commonPage:draw(false)

        if app.state.pages.showDev then
                sdkPage:draw()
        elseif app.state.pages.showSettings then
                settingsPage:draw()
        else
                mainPage:draw()
        end
end
