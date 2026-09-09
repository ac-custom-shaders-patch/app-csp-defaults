local controls = require("controls")

local registerBuiltinControls = {}

function registerBuiltinControls.run()
        controls:registerCarControl({
                id = "APP_TEST_CONTROL",
                bind = "APP_TEST_CONTROL",

                name = "App Test Control",
                tab = "Testing",
                order = 10,

                luaControlled = true,

                activation = {
                        label = "Activate",
                },
        })
end

return registerBuiltinControls
