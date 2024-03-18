require("src/settings")
require("src/classes/control_binding")
require("src/classes/control_tabbar")

local bindSectionKeyDefaults = {
	NAME = "",
	TAB = "Generic",
	ORDER = 0,
	REQUIRED = 0,
	ACTIVATION = 0,
	POS = 0,
	DN = 0,
	UP = 0,
	DN_LABEL = "Decrease",
	UP_LABEL = "Increase",
	POS_LABEL_OFFSET = 0,
	POS_LABEL = "Position",
	POS_UNIT = "",
	HOLD_MODE = 0,
	EXT_PHYSICS = 0,
	LUA = 0,
	HELP = "",
}

local function controlsINIDefaults(bind, bindSection, key, default, isCMBind)
	if not bindSection[key] or bindSection[key][1] == "" or bindSection[key][1] == nil then
		local initialValue = bindSection[key] and bindSection[key][1] or nil

		if key == "NAME" then
			default = bind
		end

		bindSection[key] = { default }

		if initialValue ~= "" and not isCMBind and SETTINGS.developerMode then
			ac.log("[" .. bind .. "] Section is missing " .. key .. " key: Default value: " .. default)
		end
	end

	bindSection[key] = bindSection[key][1]
end

local function loadControls(name, controlsINI)
	local controlsTabBar = ControlsTabBar(name)
	for _i, key in controlsINI:iterateValues("TAB_ORDER", "TAB", true) do
		controlsTabBar:addTab(controlsINI.sections["TAB_ORDER"][key][1])
	end

	for bind, _v in pairs(controlsINI.sections) do
		if bind ~= "TAB_ORDER" then
			local bindSection = controlsINI.sections[bind]

			for key, value in pairs(bindSectionKeyDefaults) do
				controlsINIDefaults(bind, bindSection, key, value)
			end

			local controlBinding = ControlBinding(
				bind,
				bindSection.NAME,
				bindSection.TAB,
				tonumber(bindSection.ORDER),
				tonumber(bindSection.LUA) == 1,
				tonumber(bindSection.EXT_PHYSICS) == 1,
				bindSection.HELP,
				tonumber(bindSection.ACTIVATION) == 1,
				bindSection.ACTIVATION_LABEL,
				tonumber(bindSection.HOLD_MODE) == 1,
				tonumber(bindSection.DN) ~= 0 and tonumber(bindSection.UP) ~= 0,
				bindSection.DN,
				bindSection.DN_LABEL,
				bindSection.UP,
				bindSection.UP_LABEL,
				tonumber(bindSection.POS) > 0,
				tonumber(bindSection.POS_LABEL_OFFSET),
				bindSection.POS_LABEL,
				bindSection.POS_UNIT,
				tonumber(bindSection.POS)
			)

			controlsTabBar:addControl(controlBinding)
		end
	end

	return controlsTabBar
end

local function getCarControls()
	local carControlsFile = ac.getFolder(ac.FolderID.ContentCars)
		.. "\\"
		.. ac.getCarID(0)
		.. "\\extension\\ext_car_controls.ini"

	if not io.fileExists(carControlsFile) then
		carControlsFile = ac.dirname() .. "\\cfg\\car_controls.ini"
	end

	local carControlsINI = ac.INIConfig.load(carControlsFile)

	return loadControls("Car", carControlsINI)
end

local function getAppControls()
	local luaDirectory = ac.getFolder(ac.FolderID.ACApps) .. "\\lua"

	local appControls = {}
	io.scanDir(luaDirectory, function(fileName, fileAttributes, callbackData)
		local appDirectory = luaDirectory .. "\\" .. fileName

		if not io.dirExists(appDirectory) then
			return
		end

		local appControlsFile = appDirectory .. "\\ext_app_controls.ini"

		if not io.fileExists(appControlsFile) then
			return
		end

		local appControlsINI = ac.INIConfig.load(appControlsFile)

		local appManifestFile = appDirectory .. "\\manifest.ini"
		local appManifestINI = ac.INIConfig.load(appManifestFile, ac.INIFormat.Extended)
		local appName = appManifestINI:get("ABOUT", "NAME", fileName)

		table.insert(appControls, loadControls(appName, appControlsINI))
	end)

	return appControls
end

local function getContentManagerControls()
	local contentManagerControlsFile = ac.dirname() .. "\\cfg\\cm_controls.ini"
	local contentManagerControlsINI = ac.INIConfig.load(contentManagerControlsFile)

	return loadControls("Content Manager", contentManagerControlsINI)
end

function initializeControls()
	return getContentManagerControls(), getAppControls(), getCarControls()
end
