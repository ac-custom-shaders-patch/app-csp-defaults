local uis = ac.getUI()

local AppConfig = require('src/AppConfig')
local VoicesHolder = require('src/VoicesHolder')

local VoicesUI = {}

function VoicesUI.windowVoices(dt)
  ui.tabBar('voices', function ()
    for i, v in ipairs(VoicesHolder.list()) do
      if v.editor then
        local m = v:metadata()
        local o = ui.beginTabItem(m.NAME..'###'..i)
        if ui.itemHovered() then
          ui.tooltip(function ()
            local w = 200
            ui.dummy(vec2(400, 1))
            ui.text('Name: %s' % m.NAME)
            ui.sameLine(w)
            ui.text('Version: %s' % m.VERSION)
            ui.text('Author: %s' % m.AUTHOR)
            ui.sameLine(w)
            ui.text('Location: %s' % v:location())
            ui.textWrapped('Description: %s' % m.DESCRIPTION)
          end)
        end
        if o then
          v:editor()
          if v ~= VoicesHolder.current() then
            v:update(uis.dt, ac.getAudioVolume(AppState.volumeKey, nil, 1))
          end
          ui.endTabItem()
        end
      end
    end
  end)
end

function VoicesUI.onVoicesOpened()
  AppState.voicesMappedActive = true
end

function VoicesUI.onVoicesClosed()
  AppState.voicesMappedActive = false
end

return VoicesUI