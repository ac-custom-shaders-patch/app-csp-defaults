require("src/utils/utils_generic")

ControlBinding = class("ControlBinding")

function ControlBinding:initialize(
	bind,
	name,
	tab,
	order,
	isLuaControlled,
	isExtendedPhysics,
	helpString,
	isActivationBind,
	activationLabel,
	activationHoldMode,
	isSequentialBind,
	sequentialDownBind,
	sequentialDownLabel,
	sequentialUpBind,
	sequentialUpLabel,
	isMultiPositionSwitchBind,
	multiPositionSwitchIndexOffset,
	multiPositionSwitchLabel,
	multiPositionSwitchLabelUnit,
	multiPositionSwitchCount
)
	self.bind = bind

	if self.bind == nil or self.bind == "" then
		return nil
	end

	self.name = name and name or self.bind
	self.tab = tab and tab or -1
	self.order = order and order or -1
	self.isActivationBind = isActivationBind and isActivationBind or false
	self.isSequentialBind = isSequentialBind and isSequentialBind or false
	self.isMultiPositionSwitchBind = isMultiPositionSwitchBind and isMultiPositionSwitchBind or false
	self.isLuaControlled = isLuaControlled and isLuaControlled or false
	self.isExtendedPhysics = isExtendedPhysics and isExtendedPhysics or false
	self.help = helpString and helpString or ""

	if self.isActivationBind then
		self:bindActivation(activationLabel, activationHoldMode)
		return self
	end

	if self.isSequentialBind then
		self:bindSequential(bind, sequentialDownBind, sequentialDownLabel, sequentialUpBind, sequentialUpLabel)
	end

	if self.isMultiPositionSwitchBind then
		self:bindMultiPositionSwitch(
			bind,
			multiPositionSwitchCount,
			multiPositionSwitchIndexOffset,
			multiPositionSwitchLabel,
			multiPositionSwitchLabelUnit
		)
	end

	return self
end

function ControlBinding:bindActivation(label, holdMode)
	if not string.startsWith(self.bind, "__EXT_LIGHT_") and self.isLuaControlled then
		self.bind = "__EXT_CAR_" .. self.bind
	end

	self.activationLabel = label and label or "Activate"
	self.button = ac.ControlButton(self.bind, { hold = holdMode and holdMode or nil })
end

function ControlBinding:bindSequential(bind, downBind, downLabel, upBind, upLabel)
	if string.startsWith(bind, "__EXT_LIGHT_") then
		self.buttonDown = ac.ControlButton("__EXT_LIGHT_" .. downBind)
		self.buttonUp = ac.ControlButton("__EXT_LIGHT_" .. upBind)
	elseif self.isLuaControlled then
		self.buttonDown = ac.ControlButton("__EXT_CAR_" .. bind .. downBind)
		self.buttonUp = ac.ControlButton("__EXT_CAR_" .. bind .. upBind)
	else
		self.buttonDown = ac.ControlButton(bind .. downBind)
		self.buttonUp = ac.ControlButton(bind .. upBind)
	end

	self.buttonDownLabel = not isempty(downLabel) and downLabel or "Decrease"
	self.buttonUpLabel = not isempty(upLabel) and upLabel or "Increase"
end

function ControlBinding:bindMultiPositionSwitch(bind, switchCount, switchIndexOffset, switchLabel, switchLabelUnit)
	self.mpsToggle = self.buttonUp:disabled() and self.buttonDown:disabled()
	self.multiPositionSwitchCount = switchCount and switchCount or 0
	self.multiPositionSwitchIndex = switchIndexOffset

	self.buttonPosition = {}
	self.buttonPositionLabel = {}
	self.buttonPositionLabelExplicit = false

	if string.find(switchLabel, ",") then
		switchLabel = string.split(switchLabel, ",")
		self.buttonPositionLabelExplicit = true
	end

	for i = 1, self.multiPositionSwitchCount do
		if self.isLuaControlled then
			self.buttonPosition[i] = ac.ControlButton("__EXT_CAR_" .. bind .. "_" .. i)
		else
			self.buttonPosition[i] = ac.ControlButton(bind .. "_" .. i)
		end

		if self.mpsToggle then
			self.buttonPosition[i]:setDisabled(false)
		else
			self.buttonPosition[i]:setDisabled(true)
		end

		self.buttonPositionLabel[i] = self.buttonPositionLabelExplicit and switchLabel[i] .. switchLabelUnit
			or (
				(not isempty(switchLabel) and switchLabel or "Position")
				.. " "
				.. i + self.multiPositionSwitchIndex
				.. " "
				.. switchLabelUnit
			)
	end

	if self.mpsToggle then
		self.buttonDown:setDisabled(true)
		self.buttonUp:setDisabled(true)
	else
		self.buttonDown:setDisabled(false)
		self.buttonUp:setDisabled(false)
	end
end

function ControlBinding:toggleMPS()
	self.mpsToggle = not self.mpsToggle

	for i = 1, self.multiPositionSwitchCount do
		if self.mpsToggle then
			self.buttonPosition[i]:setDisabled(false)
		else
			self.buttonPosition[i]:setDisabled(true)
		end
	end

	if self.mpsToggle then
		self.buttonDown:setDisabled(true)
		self.buttonUp:setDisabled(true)
	else
		self.buttonDown:setDisabled(false)
		self.buttonUp:setDisabled(false)
	end
end
