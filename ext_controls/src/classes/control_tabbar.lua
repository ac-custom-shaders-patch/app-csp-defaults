ControlsTabBar = class("ControlsTabBar")

TabBarType = {
	ContentManager = 0,
	Car = 1,
	App = 2,
}

function ControlsTabBar:initialize(name, tabs, tabOrder)
	self.name = name
end

function ControlsTabBar:addTab(name)
	if not self.tabs then
		self.tabs = {}
		self.tabOrder = {}
	end

	table.insert(self.tabs, ControlsTab(name))
	table.insert(self.tabOrder, name)
end

function ControlsTabBar:addControl(controlBinding)
	if controlBinding ~= nil then
		local tab = controlBinding.tab
		local tabIndex = table.indexOf(self.tabOrder, tab)

		if controlBinding.order ~= 0 then
			self.tabs[tabIndex].content[controlBinding.order] = controlBinding
		else
			table.insert(self.tabs[tabIndex].content, controlBinding)
		end
	end
end

ControlsTab = class("ControlsTab")

function ControlsTab:initialize(name)
	self.name = name
	self.content = {}

	return self
end

function ControlsTab:addContent() end
