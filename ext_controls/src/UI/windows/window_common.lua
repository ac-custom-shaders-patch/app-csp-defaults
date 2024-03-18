local appDirectoryPath = ac.dirname()
local appManifest = ac.INIConfig.load(appDirectoryPath .. "\\manifest.ini", ac.INIFormat.Extended)
local appVersion = appManifest:get("ABOUT", "VERSION", "")

local function warningText()
	ui.textAligned(
		"This app has a minimum CSP version requirement of v0.2.0 (2651)",
		vec2(0.5, 0.5),
		vec2(ui.availableSpaceX(), 34)
	)
end

local function windowTitle()
	ui.pushFont(ui.Font.Title)
	ui.textAligned("Extended Controls", vec2(0.5, 1.3), vec2(ui.windowWidth(), 34))
	ui.popFont()

	if SETTINGS.showAppVersion then
		ui.pushFont(ui.Font.Small)
		ui.pushStyleColor(ui.StyleColor.Text, rgbm(1, 1, 1, 0.5))
		ui.textAligned(
			"v" .. appVersion .. ", CSP: " .. ac.getPatchVersion() .. " (" .. ac.getPatchVersionCode() .. ")",
			vec2(0.5, 0.5),
			vec2(ui.windowWidth(), 12)
		)
		ui.popStyleColor(1)
		ui.popFont()
	end

	ui.setCursorY(70)
end

local function windowControls(isSetupMenu)
	ui.pushStyleColor(ui.StyleColor.Button, rgbm.colors.transparent)
	ui.setCursorY(5)
	ui.setCursorX(5)
	if ui.iconButton(ui.Icons.Menu, vec2(22, 22)) then
		WINDOWS.showSettingsWindow = not WINDOWS.showSettingsWindow
		WINDOWS.showDeveloperWindow = false
	end
	ui.sameLine()
	ui.offsetCursorX(-5)

	if SETTINGS.developerMode then
		if ui.iconButton(ui.Icons.Code, vec2(22, 22)) then
			WINDOWS.showDeveloperWindow = not WINDOWS.showDeveloperWindow
			WINDOWS.showSettingsWindow = false
		end
	end

	if not isSetupMenu then
		ui.sameLine(425)
		if ui.iconButton(ui.Icons.Cancel, vec2(22, 22)) then
			ac.setWindowOpen("main", false)
		end
	else
		ui.newLine()
	end

	ui.popStyleColor(1)
	ui.offsetCursorY(-20)
end

function windowCommon(isSetupMenu)
	windowControls(isSetupMenu)
	windowTitle()
	if ac.getPatchVersionCode() < 2651 then
		warningText()
		return
	end
end
