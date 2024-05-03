require("src/initialize")
require("src/settings")
require("src/utils/utils_tables")
require("src/UI/ui_helper")
require("src/UI/windows/window_common")
require("src/UI/windows/window_main")
require("src/UI/windows/window_settings")
require("src/UI/windows/window_sdk")

ac.store("EXT_CONTROLS_AVAILABLE", 1)

local requiredBindsIntervalID = nil
requiredBindsIntervalID = setInterval(function()
	if SETTINGS.disableForcedBinds then
		return
	end

	if ac.load("__EXT_CAR_MISSING_BINDS") == 1 then
		if not ac.isWindowOpen("main") then
			ac.setAppOpen("ext_controls")
		end
	elseif ac.load("__EXT_CAR_MISSING_BINDS") == 0 then
		clearInterval(requiredBindsIntervalID)
	end
end, 1, "CriticalBindsExtControls")

function script.main()
	if not SETTINGS.showSetupMenuApp then
		if ac.isWindowOpen("main_setup") then
			ac.setWindowOpen("main_setup", false)
		end
	else
		if not ac.isWindowOpen("main_setup") then
			ac.setWindowOpen("main_setup", true)
		end
	end

	windowCommon(false)

	if WINDOWS.showDeveloperWindow then
		windowDeveloper()
	elseif WINDOWS.showSettingsWindow then
		windowSettings()
	else
		windowMain()
	end
end
