local PaceNotesHolder = require "src/PaceNotesHolder"
---@diagnostic disable: duplicate-set-field
if not ui.beginMIPBias then
  ui.beginMIPBias = function () end
  ui.endMIPBias = function (bias) end
end

local AppState = require('src/AppState')
local AppConfig = require('src/AppConfig')

if #AppConfig.userName == 0 then
  AppConfig.userName = ac.getDriverName(0) or 'User'
end

local GameUI = require('src/GameUI')
local VoicesHolder = require('src/VoicesHolder')

if AppState.connection.raceState ~= 0 then
  require('src/Codriver')
end

script.windowMain = GameUI.windowMain
script.windowSettings = GameUI.windowSettings

function script.update(dt)
  GameUI.update()
  VoicesHolder.update(dt)
end

local EditorUI, VoicesUI, NotesExchange

local function getEditorUI()
  if not EditorUI then
    EditorUI = require('src/EditorUI')
  end
  return EditorUI
end

local function getVoicesUI()
  if not VoicesUI then
    VoicesUI = require('src/VoicesUI')
  end
  return VoicesUI
end

local function getNotesExchange()
  if not NotesExchange then
    NotesExchange = require('src/NotesExchange')
  end
  return NotesExchange
end

function script.windowEditorOpened()
  getEditorUI().onEditorOpened()
end

function script.windowEditorClosed()
  if EditorUI then EditorUI.onEditorClosed() end
end

function script.windowEditor()
  getEditorUI().windowEditor()
end

function script.windowVoicesOpened()
  getVoicesUI().onVoicesOpened()
end

function script.windowVoicesClosed()
  if VoicesUI then VoicesUI.onVoicesClosed() end
end

function script.windowVoices()
  getVoicesUI().windowVoices()
end

function script.windowNotesExchange()
  getNotesExchange().windowNotesExchange()
end

local function anyUnsavedChanges()
  if not EditorUI then
    return false
  end
  for i, v in ipairs(PaceNotesHolder.loaded()) do
    if v:hasUnsavedChanges() then
      return true
    end
  end
  return false
end

if AppState.connection.raceState == 0 then
  setInterval(function ()
    if not AppState.editorActive and not AppState.voicesMappedActive and not anyUnsavedChanges() then
      ac.unloadApp()
    end
  end, 1)
end
