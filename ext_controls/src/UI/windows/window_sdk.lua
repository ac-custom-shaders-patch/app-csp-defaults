local function sdkText()
	ui.pushFont(ui.Font.Title)
	ui.textAligned("SDK", vec2(0.5, 0.5), vec2(ui.availableSpaceX(), 30))
	ui.popFont()
end

local function sdkWindow()
	ui.childWindow("sdkWindow", vec2(451, 398), function()
		ui.pushFont(ui.Font.Small)

		ui.setCursorX(WINDOW_MARGIN)
		ui.header("Parameters for ext_car_controls.ini")
		ui.drawSimpleLine(
			vec2(WINDOW_MARGIN, ui.getCursorY()),
			vec2(ui.windowWidth() - WINDOW_MARGIN - 1, ui.getCursorY()),
			rgbm.colors.gray
		)
		ui.newLine()
		ui.setCursorX(WINDOW_MARGIN)

		ui.setNextItemWidth()
		ui.copyable([[

[BALANCE] # Section name corresponds controls.ini section (without UP/DN)
TAB=Brakes # Name of the tab this control will be under
NAME=Brake Bias # Display name of the control
DN=DN # Combines with the section name to form sequential controls.
UP=UP # Combines with the section name to form sequential controls.
DN_LABEL=Move to Rear # Label for sequential down control
UP_LABEL=Move to Front # Label for sequential up control
POS=0 # Number of multi-positional switch steps available
POS_LABEL= # Label of position steps
ACTIVATION=0 # Takes priority over sequential and MPS
HOLD_MODE=0 # Allows for the control to be either toggle or hold
EXT_PHYSICS=0 # Adds a flag to represent if the control is for Extended Physics
LUA=0 # Adds a flag to represent a button that triggers a lua event
HELP= # Adds a flag that can be hovered over to add a description of the control

]])
		ui.newLine()

		ui.setCursorX(WINDOW_MARGIN)
		ui.header("Parameters for ext_app_controls.ini")
		ui.drawSimpleLine(
			vec2(WINDOW_MARGIN, ui.getCursorY()),
			vec2(ui.windowWidth() - WINDOW_MARGIN - 1, ui.getCursorY()),
			rgbm.colors.gray
		)
		ui.newLine()
		ui.setCursorX(WINDOW_MARGIN)

		ui.setNextItemWidth()
		ui.copyable([[

[BALANCE] # Section name corresponds controls.ini section (without UP/DN)
TAB=Brakes # Name of the tab this control will be under
NAME=Brake Bias # Display name of the control
DN=DN # Combines with the section name to form sequential controls.
UP=UP # Combines with the section name to form sequential controls.
DN_LABEL=Move to Rear # Label for sequential down control
UP_LABEL=Move to Front # Label for sequential up control
POS=0 # Number of multi-positional switch steps available
POS_LABEL= # Label of position steps
ACTIVATION=0 # Takes priority over sequential and MPS
HOLD_MODE=0 # Allows for the control to be either toggle or hold
HELP= # Adds a flag that can be hovered over to add a description of the control

]])
		ui.newLine()

		ui.setCursorX(WINDOW_MARGIN)
		ui.header("Example: Setting up an activation button for an Extra Option")
		ui.drawSimpleLine(
			vec2(WINDOW_MARGIN, ui.getCursorY()),
			vec2(ui.windowWidth() - WINDOW_MARGIN - 1, ui.getCursorY()),
			rgbm.colors.gray
		)
		ui.newLine()
		ui.setCursorX(WINDOW_MARGIN)

		ui.copyable([[

[__EXT_LIGHT_A]
TAB=Critical
NAME=Ignition
ACTIVATION=1
HELP=Toggles the ignition state. Press to toggle on, hold to toggle off.

]])
		ui.newLine()

		ui.setCursorX(WINDOW_MARGIN)
		ui.header("Example: Setting up sequential buttons for 2 Extra Options")
		ui.drawSimpleLine(
			vec2(WINDOW_MARGIN, ui.getCursorY()),
			vec2(ui.windowWidth() - WINDOW_MARGIN - 1, ui.getCursorY()),
			rgbm.colors.gray
		)
		ui.newLine()
		ui.setCursorX(WINDOW_MARGIN)

		ui.text([[
"EXT_LIGHT" bindings can have anything after that text in order to denote
what it does. The UP/DN sections represent the 2 letters that correspond to
the Extra Options letters.
In this case Extra E is the down button and Extra F is the up button.

]])
		ui.setCursorX(WINDOW_MARGIN)
		ui.copyable([[

[__EXT_LIGHT_DISPLAY]
TAB=Display
NAME=Display Page
DN=E
UP=F
DN_LABEL=Page down
UP_LABEL=Page up
ACTIVATION=0
HELP=

]])

		ui.newLine()

		ui.setCursorX(WINDOW_MARGIN)
		ui.header("The Tab Order section will arrange the Car tabs in the defined order")
		ui.drawSimpleLine(
			vec2(WINDOW_MARGIN, ui.getCursorY()),
			vec2(ui.windowWidth() - WINDOW_MARGIN - 1, ui.getCursorY()),
			rgbm.colors.gray
		)

		ui.newLine()
		ui.setCursorX(WINDOW_MARGIN)
		ui.text("If no tab order is defined, the tabs in the sections will be ordered alphabetically")

		ui.setCursorX(WINDOW_MARGIN)
		ui.copyable([[

[TAB_ORDER]
TAB_1=Critical
TAB_2=Gearbox
TAB_3=Brakes
TAB_4=Suspension
TAB_5=Lights
TAB_6=Display
TAB_7=Misc.

]])

		ui.newLine()

		ui.setCursorX(WINDOW_MARGIN)
		ui.header("Lua Car Script")
		ui.drawSimpleLine(
			vec2(WINDOW_MARGIN, ui.getCursorY()),
			vec2(ui.windowWidth() - WINDOW_MARGIN - 1, ui.getCursorY()),
			rgbm.colors.gray
		)
		ui.newLine()
		ui.setCursorX(WINDOW_MARGIN)

		ui.text([[
Lua controls are defined by assigning by setting LUA=1.
"__EXT_CAR_" will be prefixed to the section name in the ext_car_controls.ini file.

An example for setting up an event listener in a car/physics:

]])

		ui.setCursorX(WINDOW_MARGIN)
		ui.copyable([[

	local helloButton = ac.ControlButton("__EXT_CAR_HELLO")
	helloButton:onPressed(function()
		ac.log("Hello there")
	end)

]])
		ui.setCursorX(WINDOW_MARGIN)
		ui.text([[

The above example will print "Hello there" to the log
only upon pressing the bound HELLO button.

For any control that is created to be used within lua, ensure that you have the
LUA key set to LUA=1, this will help prevent collisions with other AC/CM controls.
]])

		ui.newLine()

		ui.setCursorX(WINDOW_MARGIN)
		ui.header("Debug")
		ui.drawSimpleLine(
			vec2(WINDOW_MARGIN, ui.getCursorY()),
			vec2(ui.windowWidth() - WINDOW_MARGIN - 1, ui.getCursorY()),
			rgbm.colors.gray
		)
		ui.newLine()
		ui.setCursorX(WINDOW_MARGIN)

		ui.text([[
Missing keys will be printed in the log along with the default value that gets set.
The ext_car_controls.ini file needs to be in the car's extension folder.
If no ext_car_controls.ini file is found, a default file will be loaded
with all of the available car controls in CM.

]])
		ui.popFont()
	end)
end

function windowDeveloper()
	sdkText()

	ui.setCursorY(105)
	ui.drawSimpleLine(vec2(0, ui.getCursorY()), vec2(ui.windowWidth(), ui.getCursorY()), rgbm.colors.red)
	ui.newLine()

	sdkWindow()
end
