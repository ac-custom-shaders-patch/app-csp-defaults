local ControlRegistryBus = {}

ControlRegistryBus.Events = {
        request = "ext_controls.registry.v1.request",
        snapshot = "ext_controls.registry.v1.snapshot",
        upsert = "ext_controls.registry.v1.upsert",
        remove = "ext_controls.registry.v1.remove",
        clear = "ext_controls.registry.v1.clear",
}

local function encode(payload) return stringify(payload, true) end

local function decode(payload)
        if type(payload) == "table" then return payload end

        if type(payload) ~= "string" then return nil end

        return stringify.tryParse(payload, nil, nil)
end

function ControlRegistryBus.send(eventName, payload) return ac.broadcastSharedEvent(eventName, encode(payload)) end

function ControlRegistryBus.listen(eventName, callback)
        return ac.onSharedEvent(eventName, function(data, senderName, senderType, senderID)
                local payload = decode(data)

                if type(payload) ~= "table" then return end

                callback(payload, senderName, senderType, senderID)
        end, true)
end

return ControlRegistryBus
