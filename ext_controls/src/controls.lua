local ControlBinding = require("src.classes.control_binding")
local ControlDefinition = require("src.controls.control_definition")
local ControlRegistryBus = require("src.controls.control_registry_bus")
local ControlsTabBar = require("src.classes.control_tab_bar")
local settings = require("settings")

local controls = {}

local function playerCarID() return ac.getCarID(0) or "" end

local function isPlayerCarPayload(payload)
        if type(payload) ~= "table" then return false end

        if payload.carIndex ~= nil and payload.carIndex ~= 0 then return false end

        if payload.carID ~= nil and payload.carID ~= "" and payload.carID ~= playerCarID() then return false end

        return true
end

local function copyDefinitions(destination, source)
        for id, definition in pairs(source or {}) do
                destination[id] = definition
        end
end

local function isEmpty(value) return value == nil or next(value) == nil end

local function disposeAll(disposables)
        for _, disposable in ipairs(disposables or {}) do
                if disposable then disposable() end
        end
end

local function normalizeDynamicDefinition(rawDefinition, source)
        local success, result = pcall(ControlDefinition.normalize, rawDefinition)

        if success then return result end

        ac.log(string.format("[Controls] Invalid %s control definition: %s", source or "dynamic", tostring(result)))

        return nil
end

local function createDynamicBinding(definition)
        if ControlBinding.fromDefinition then return ControlBinding.fromDefinition(definition) end

        return ControlBinding(definition)
end

local function sortedSectionNames(controlsINI)
        local result = {}

        for sectionName in pairs(controlsINI.sections or {}) do
                if sectionName ~= "TAB_ORDER" then result[#result + 1] = sectionName end
        end

        table.sort(result)

        return result
end

local function loadControls(name, controlsINI)
        local controlsTabBar = ControlsTabBar(name)

        for _, key in controlsINI:iterateValues("TAB_ORDER", "TAB", true) do
                local tabDefinition = controlsINI.sections["TAB_ORDER"]

                local tabName = tabDefinition and tabDefinition[key] and tabDefinition[key][1]

                if tabName and tabName ~= "" then controlsTabBar:addTab(tabName) end
        end

        for _, sectionName in ipairs(sortedSectionNames(controlsINI)) do
                local controlBinding = ControlBinding.fromINI(controlsINI, sectionName, settings.developerMode)

                if controlBinding then controlsTabBar:addControl(controlBinding) end
        end

        return controlsTabBar
end

local function getCarControls()
        local carControlsFile = ac.getFolder(ac.FolderID.ContentCars)
                .. "\\"
                .. playerCarID()
                .. "\\extension\\ext_car_controls.ini"

        if not io.fileExists(carControlsFile) then carControlsFile = ac.dirname() .. "\\cfg\\car_controls.ini" end

        local carControlsINI = ac.INIConfig.load(carControlsFile)

        return loadControls("Car", carControlsINI)
end

local function getAppControls()
        local luaDirectory = ac.getFolder(ac.FolderID.ACApps) .. "\\lua"

        local appControls = {}

        io.scanDir(luaDirectory, function(fileName)
                local appDirectory = luaDirectory .. "\\" .. fileName

                if not io.dirExists(appDirectory) then return end

                local appControlsFile = appDirectory .. "\\ext_app_controls.ini"

                if not io.fileExists(appControlsFile) then return end

                local appControlsINI = ac.INIConfig.load(appControlsFile)

                local appManifestFile = appDirectory .. "\\manifest.ini"

                local appManifestINI = ac.INIConfig.load(appManifestFile, ac.INIFormat.Extended)

                local appName = appManifestINI:get("ABOUT", "NAME", fileName)

                appControls[#appControls + 1] = loadControls(appName, appControlsINI)
        end)

        table.sort(appControls, function(a, b) return tostring(a.name) < tostring(b.name) end)

        return appControls
end

local function getContentManagerControls()
        local contentManagerControlsFile = ac.dirname() .. "\\cfg\\cm_controls.ini"

        local contentManagerControlsINI = ac.INIConfig.load(contentManagerControlsFile)

        return loadControls("Content Manager", contentManagerControlsINI)
end

function controls:initialize()
        if self.initialized then return end

        self.initialized = true

        ----------------------------------------------------------------
        -- Existing app-side INI loading
        ----------------------------------------------------------------

        self.cmControls = getContentManagerControls()

        self.appControls = getAppControls()

        self.legacyCarControls = getCarControls()

        self.carControls = self.legacyCarControls

        ----------------------------------------------------------------
        -- Dynamic car-control registration
        ----------------------------------------------------------------

        self.remoteCarDefinitions = {}
        self.localCarDefinitions = {}

        self.remoteRegistryActive = false
        self.dynamicListeners = {}

        self:_listenForDynamicCarControls()

        ac.store("EXT_CONTROLS_AVAILABLE", 1)
end

function controls:_shouldUseDynamicCarControls()
        return self.remoteRegistryActive or not isEmpty(self.localCarDefinitions)
end

function controls:_combinedDynamicDefinitions()
        local combined = {}

        copyDefinitions(combined, self.remoteCarDefinitions)

        -- Controls registered directly by this app take priority.
        copyDefinitions(combined, self.localCarDefinitions)

        return combined
end

function controls:_refreshCarControls()
        if not self:_shouldUseDynamicCarControls() then
                self.carControls = self.legacyCarControls

                return
        end

        self:_rebuildDynamicCarControls()
end

function controls:_rebuildDynamicCarControls()
        local definitions = self:_combinedDynamicDefinitions()

        local ordered = {}

        for _, definition in pairs(definitions) do
                ordered[#ordered + 1] = definition
        end

        table.sort(ordered, function(a, b)
                local aTab = tostring(a.tab or "Generic")
                local bTab = tostring(b.tab or "Generic")

                if aTab ~= bTab then return aTab < bTab end

                local aOrder = tonumber(a.order) or 0
                local bOrder = tonumber(b.order) or 0

                if aOrder ~= bOrder then return aOrder < bOrder end

                local aName = tostring(a.name or a.id)

                local bName = tostring(b.name or b.id)

                if aName ~= bName then return aName < bName end

                return tostring(a.id) < tostring(b.id)
        end)

        local tabBar = ControlsTabBar("Car")
        local addedTabs = {}

        for _, definition in ipairs(ordered) do
                local tabName = definition.tab or "Generic"

                if not addedTabs[tabName] then
                        tabBar:addTab(tabName)
                        addedTabs[tabName] = true
                end
        end

        for _, definition in ipairs(ordered) do
                local controlBinding = createDynamicBinding(definition)

                if controlBinding then tabBar:addControl(controlBinding) end
        end

        self.carControls = tabBar
end

----------------------------------------------------------------
-- Controls registered directly by this app
----------------------------------------------------------------

function controls:registerCarControl(rawDefinition)
        assert(self.initialized, "Controls must be initialized before registering controls")

        local definition = normalizeDynamicDefinition(rawDefinition, "local")

        if not definition then return nil end

        self.localCarDefinitions[definition.id] = definition

        self:_refreshCarControls()

        return definition
end

function controls:registerCarControls(rawDefinitions)
        assert(self.initialized, "Controls must be initialized before registering controls")

        local registered = {}

        for _, rawDefinition in ipairs(rawDefinitions or {}) do
                local definition = normalizeDynamicDefinition(rawDefinition, "local")

                if definition then
                        self.localCarDefinitions[definition.id] = definition

                        registered[#registered + 1] = definition
                end
        end

        self:_refreshCarControls()

        return registered
end

function controls:unregisterCarControl(id)
        if self.localCarDefinitions[id] == nil then return false end

        self.localCarDefinitions[id] = nil

        self:_refreshCarControls()

        return true
end

function controls:clearRegisteredCarControls()
        self.localCarDefinitions = {}

        self:_refreshCarControls()
end

----------------------------------------------------------------
-- Controls received from the active car script
----------------------------------------------------------------

function controls:_applyRemoteSnapshot(payload)
        if not isPlayerCarPayload(payload) then return end

        local definitions = {}

        for _, rawDefinition in ipairs(payload.controls or {}) do
                local definition = normalizeDynamicDefinition(rawDefinition, "remote")

                if definition then definitions[definition.id] = definition end
        end

        self.remoteCarDefinitions = definitions

        -- Receiving a snapshot means this car explicitly uses the
        -- dynamic registry, even if it declares zero controls.
        self.remoteRegistryActive = true

        self:_refreshCarControls()
end

function controls:_applyRemoteUpsert(payload)
        if not isPlayerCarPayload(payload) then return end

        if type(payload.control) ~= "table" then return end

        local definition = normalizeDynamicDefinition(payload.control, "remote")

        if not definition then return end

        self.remoteCarDefinitions[definition.id] = definition

        self.remoteRegistryActive = true

        self:_refreshCarControls()
end

function controls:_applyRemoteRemove(payload)
        if not isPlayerCarPayload(payload) then return end

        if type(payload.id) ~= "string" or payload.id == "" then return end

        self.remoteCarDefinitions[payload.id] = nil
        self.remoteRegistryActive = true

        self:_refreshCarControls()
end

function controls:_applyRemoteClear(payload)
        if not isPlayerCarPayload(payload) then return end

        self.remoteCarDefinitions = {}
        self.remoteRegistryActive = true

        self:_refreshCarControls()
end

function controls:_applyRemoteUnavailable(payload)
        if not isPlayerCarPayload(payload) then return end

        self.remoteCarDefinitions = {}
        self.remoteRegistryActive = false

        -- Restores the legacy INI controls unless the app has
        -- registered local dynamic controls.
        self:_refreshCarControls()
end

function controls:_listenForDynamicCarControls()
        self.dynamicListeners[#self.dynamicListeners + 1] = ControlRegistryBus.listen(
                ControlRegistryBus.Events.snapshot,
                function(payload) self:_applyRemoteSnapshot(payload) end
        )

        self.dynamicListeners[#self.dynamicListeners + 1] = ControlRegistryBus.listen(
                ControlRegistryBus.Events.upsert,
                function(payload) self:_applyRemoteUpsert(payload) end
        )

        self.dynamicListeners[#self.dynamicListeners + 1] = ControlRegistryBus.listen(
                ControlRegistryBus.Events.remove,
                function(payload) self:_applyRemoteRemove(payload) end
        )

        self.dynamicListeners[#self.dynamicListeners + 1] = ControlRegistryBus.listen(
                ControlRegistryBus.Events.clear,
                function(payload) self:_applyRemoteClear(payload) end
        )

        if ControlRegistryBus.Events.unavailable then
                self.dynamicListeners[#self.dynamicListeners + 1] = ControlRegistryBus.listen(
                        ControlRegistryBus.Events.unavailable,
                        function(payload) self:_applyRemoteUnavailable(payload) end
                )
        end

        ControlRegistryBus.send(ControlRegistryBus.Events.request, {
                protocol = 1,
                carIndex = 0,
                carID = playerCarID(),
        })
end

function controls:dispose()
        disposeAll(self.dynamicListeners)

        self.dynamicListeners = {}
        self.remoteCarDefinitions = {}
        self.localCarDefinitions = {}

        self.remoteRegistryActive = false

        self.carControls = self.legacyCarControls

        self.initialized = false

        ac.store("EXT_CONTROLS_AVAILABLE", nil)
end

return controls
