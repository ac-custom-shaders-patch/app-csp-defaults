---@ext

local config = require("Config")

local system = {}

local debugMode = const(config.script:get("__DEBUG_MODE", "ACTIVE", 0)) == 1
local debugLogLevel = const(config.script:get("__DEBUG_MODE", "LEVEL", 5))

local perfLoggers = {}

ac.perfBegin = function(name) perfLoggers[name] = os.preciseClock() end

ac.perfEnd = function(name) ac.debug(name, (os.preciseClock() - perfLoggers[name]) * 1000) end

function system:setMessage(msg, description, type, time)
        if car.isAIControlled then return end
        ac.setMessage(msg, description, type, time)
end

function system.log(section, message, level)
        if level < debugLogLevel then return end
        ac.log(string.format("[%s]: %s", section, message))
end

function system.warn(section, message, level)
        if level < debugLogLevel then return end
        ac.warn(string.format("[%s]: %s", section, message))
end

function system.error(section, message, level)
        if level < debugLogLevel then return end
        ac.error(string.format("[%s]: %s", section, message))
end

function system.debugger(label, value) ac.debug(label, value) end

if not debugMode then
        system.log = function() end
        system.warn = function() end
        system.error = function() end
        system.debugger = function() end
end

system.log("SYSTEM", "Initialized", 1)

return system
