local AudioShape = require('src/AudioShape')
local BetterShuffle = require('src/BetterShuffle')
local VoiceModes = require('src/VoiceModes')
local Utils = require('src/Utils')
local AppConfig = require('src/AppConfig')

local uis = ac.getUI()
local colUsed = rgbm(1, 1, 1, 0.1)
local colTimePoint = rgbm(1, 1, 0, 0.2)
local u1 = vec2()
local u2 = vec2()

---@alias VoiceEntry {tagsRaw: string, file: string, from: number, to: number, debug: boolean?}

---@class Voice
---@field id string
local Voice = class('Voice')

---@param id string
---@return Voice
function Voice.allocate(id)
  return {id = id}
end

---@param self Voice
---@param t number
---@return string
local function timeToDisplay(self, t)
  if t >= 60 * 60 then
    self.anyHours = true
  end
  if t < 0 then
    return self.anyHours and '--:--:--.---' or '--:--.---'
  end
  if self.anyHours then
    return string.format('%02.0f:%02.0f:%02.0f.%03.0f', math.floor(t / (60 * 60)), math.floor(t / 60 % 60), math.floor(t % 60), math.floor(t % 1 * 1e3))
  else
    return string.format('%02.0f:%02.0f.%03.0f', math.floor(t / 60 % 60), math.floor(t % 60), math.floor(t % 1 * 1e3))
  end
end

---@param self Voice
---@param name string
---@return string
local function getAudioFullFilename(self, name)
  return '%s\\%s' % {self:location(), name}
end

local avCache = {}

---@type ac.AudioEvent?
local avGroup

---@param self Voice
---@param name string
---@param eventIndex integer
---@return ac.AudioEvent
local function createAudioEvent(self, name, eventIndex)
  local key = '%s\\%s' % {name, eventIndex}
  local e = avCache[key]
  if not e then
    if not avGroup then
      avGroup = ac.AudioEvent.group({
        use3D = false,
        dsp = AppConfig.useDSP and {
          {index = 0, metering = {input = true}},
          ac.AudioDSP.Distortion,
          ac.AudioDSP.LowPass
        } or {
          {index = 0, metering = {input = true}}
        }
      }, false)
      avGroup.cameraExteriorMultiplier = 1
      avGroup.cameraInteriorMultiplier = 1
      avGroup.cameraTrackMultiplier = 1 
    end

    e = ac.AudioEvent.fromFile({
      group = avGroup,
      filename = getAudioFullFilename(self, name),
      use3D = false,
      loop = true,
    }, false)
    e.cameraExteriorMultiplier = 1
    e.cameraInteriorMultiplier = 1
    e.cameraTrackMultiplier = 1
    e.volume = 0
    avCache[key] = e
  end
  return e
end

function Voice:recreateAudioSamples()
  if self.activeSample then
    self.activeSample:dispose()
    self.activeSample = nil
  end
  if self.evs then
    for _, v in pairs(self.evs) do
      for _, e in ipairs(v) do
        e:dispose()
      end
    end
    self.evs = nil
  end
  if avGroup then
    avGroup:dispose()
    avGroup = nil
  end
  table.clear(avCache)
  collectgarbage('collect')
end

---@param self Voice
local function initActiveSample(self)
  if not self.activeSample and self.activeAudioFile then
    self.activeSample = createAudioEvent(self, self.activeAudioFile, 0)
    self.activeSamplePos = 0
    self.activeSample.volume = 1
    if not self.activeSample:isValid() then
      ac.warn('Failed to load “%s”' % self.activeAudioFile)
    end
  end    
end

---@param self Voice
---@param file string?
local function ensureSamplesAreReady(self, file)
  if not self.evs then
    self.evs = {}
  end
  if not file then
    for k, v in pairs(self.entries) do
      if self.mode:needsPreload(k) then
        for _, e in ipairs(v) do
          ensureSamplesAreReady(self, e.file)
        end
      end
    end
  elseif not self.evs[file] then
    ac.log('Loading sample: '..file)
    self.evs[file] = table.range(2, function (index)
      return createAudioEvent(self, file, index)
    end)
  end
end

function Voice:initialize()
  local desc = '%s/%s.txt' % {self:location(), self.id}
  local lines = (io.load(desc) or ''):split('\n', nil, true, true)
  local phrases = {}
  self.attributes = {}
  for _, v in ipairs(lines) do
    if v:find('^%w') then
      v = v:split('#;', 2, true, false, true)[1]
      local k, n = table.unpack(v:split(':', 2, true, false))
      if n then
        self.attributes[k] = n
      else
        table.insert(phrases, v)
      end
    end
  end

  if not io.fileExists(desc) then
    ac.error('Voice is damaged or missing: %s' % self.id)
    self.attributes.mode = 'lua'
  end

  self.anyHours = false
  self.mode = self.attributes.mode == 'merged' and VoiceModes.merged
    or self.attributes.mode == 'separated' and VoiceModes.separated
    or self.attributes.mode == 'lua' and {}
    or VoiceModes.merged
  self.fade = tonumber(self.attributes.fade) or 1
  self.minLength = math.max(0.01, self.fade * 0.08)

  self.samplesQueue = {} ---@type VoiceEntry[]
  self.samplesDelayedQueue = {} ---@type VoiceEntry[]
  self.lastPlayed = {} ---@type VoiceEntry[]
  self.availableAudioFiles = nil ---@type string[]?
  self.activeAudioFile = nil ---@type string?
  self.activeSample = nil ---@type ac.AudioEvent?
  self.activeSamplePos = 0
  self.beingCreated = nil
  self.watcher = nil

  ---@type table<string, ac.AudioEvent[]>?
  self.evs = nil
  self.mainEvent = nil
  self.mainEventPool = nil
  self.mainEventSource = nil
  self.fadingEvent = nil
  self.fadingEventPool = nil
  self.fadingEventSource = nil
  self.curEvent = 0
  self.hoveredPhrase = nil
  self.hoveredGraphPhrase = nil
  self.phraseBeingEdited = nil
  self.wasPlaying = false
  self.shapeZoom = 0
  self.shapeTargetScroll = -1
  self.markStart = -1
  self.openedGroups = {}
  self.forceOpenedGroups = {}

  if not next(self.mode) then
    local s, impl = pcall(require, 'voices/%s/%s' % {self.id, self.id})
    if s then
      self.save = function () end
      self.preload = function (s) return s end
      self.editor = false
      self.enqueue = function (_, ...) return impl.enqueue(...) end
      self.update = function (_, dt, volume) if impl.update then return impl.update(dt, volume) end end
      self.supports = function (_, ...) if impl.supports then return impl.supports(...) end end
      self.dispose = function (_, ...) if impl.dispose then return impl.dispose(...) end end
    else
      if io.fileExists(desc) then
        ac.error('Scriptable voice is damaged: %s' % self.id)
      end
      self.save = function () end
      self.preload = function (s) return s end
      self.editor = false
      self.enqueue = function (_) return false end
      self.update = function (_) end
      self.supports = function (_) end
      self.dispose = function (_) end
    end
  else
    ---@type table<integer, VoiceEntry[]>
    self.entries = table.range(self.mode:size(), function () return {} end)
  
    ---@type table<integer, BetterShuffle>
    self.shuffles = table.range(self.mode:size(), function () return BetterShuffle() end)
  
    for _, v in ipairs(phrases) do
      local kr = v:split(',', nil, true, false)
      if #kr == 5 then
        local x = self.entries[self.mode:idToIndex(kr[1]:lower())]
        if x then
          table.insert(x, {tagsRaw = kr[2] or '', file = kr[3], from = tonumber(kr[4]) or 0, to = tonumber(kr[5]) or 0})
        else
          ac.error('Unknown type: `%s`' % kr[1])
        end
      else
        ac.error('Malformed: `%s`' % v)
      end
    end
  end
end

function Voice:preload()
  ensureSamplesAreReady(self)
  return self
end

function Voice:save()
  local dst = '%s\\%s.txt' % {self:location(), self.id}
  local data = {}
  for k, v in pairs(self.attributes) do
    data[#data + 1] = '%s: %s' % {k, v}
  end
  for i, v in pairs(self.entries) do
    local p = self.mode:indexToID(i)
    for _, k in ipairs(v) do
      data[#data + 1] = '%s, %s, %s, %s, %s' % {
        p, (k.tagsRaw or ''):trim(), k.file, k.from, k.to
      }
    end
  end
  io.save(dst, table.concat(data, '\n'))
end

function Voice:metadata()
  if not self._metadata then
    self._metadata = ac.INIConfig.load('%s\\manifest.ini' % self:location(), ac.INIFormat.Extended):mapSection('ABOUT', {
      NAME = self.id,
      AUTHOR = '',
      VERSION = '0',
      DESCRIPTION = ''
    })
  end
  return self._metadata
end

function Voice:location()
  return '%s\\voices\\%s' % {__dirname, self.id}
end

---@param self Voice
---@param e VoiceEntry
---@param label string
---@param prop 'from'|'to'
---@param w number
local function timeEditPoint(self, e, label, prop, w)
  local r = false
  ui.pushID(label)
  local s = ui.getCursorX()
  ui.alignTextToFramePadding()
  if w ~= 0 then ui.offsetCursorX(8) end
  ui.interactiveArea('IA', vec2(ui.measureText(label).x, w == 0 and 14 or 22))
  if ui.itemHovered() then
    ui.setMouseCursor(ui.MouseCursor.ResizeEW)
  end
  if ui.itemActive() then
    if uis.mouseDelta.x ~= 0 then
      e[prop] = math.max(e[prop] + uis.mouseDelta.x / (uis.shiftDown and 2000 or 100), 0)
      if prop == 'from' and e[prop] > e.to - self.minLength then
        e.from = e.to - self.minLength
      elseif prop == 'to' and e[prop] < e.from + self.minLength then
        e.to = e.from + self.minLength
      end
      r = true
    end
    if not uis.isMouseLeftKeyDown then
      ui.clearActiveID()
    end
  end
  ui.sameLine(0, 4)
  ui.setCursorX(w == 0 and s or s + 8)
  ui.text(label)
  ui.sameLine(0, 4)
  if w == 0 then
    ui.setNextItemWidth(100)
    local v = ui.inputText('##e', timeToDisplay(self, e[prop]))
    if ui.itemEdited() then
      e[prop] = Utils.displayToTime(v) or e[prop]
      r = true
    end
  else
    ui.setNextItemWidth(w - (ui.getCursorX() - s) - 26)
    local v = ui.inputText('##e', timeToDisplay(self, e[prop]))
    if ui.itemEdited() then
      e[prop] = Utils.displayToTime(v) or e[prop]
    end
    local a = self.activeAudioFile == e.file and self.activeSample and self.activeSamplePos > 0
      and (prop == 'from' and self.activeSamplePos < e.to - self.minLength
        or prop == 'to' and self.activeSamplePos > e.from + self.minLength)
    if not a then ui.pushDisabled() end
    ui.sameLine(0, 4)
    if ui.iconButton(ui.Icons.Crosshair, vec2(22, 22)) and self.activeSample then
      local prev = e[prop]
      e[prop] = self.activeSamplePos
      ui.toast(ui.Icons.Crosshair, 'Time point changed to “%s”' % timeToDisplay(self, e[prop]), function ()
        e[prop] = prev
      end)
    end
    if not a then ui.popDisabled() end
  end
  ui.popID()
  return r
end

---@param self Voice
---@param e VoiceEntry
local function editPhrase(self, e)
  if e.file ~= self.activeAudioFile then
    self.activeAudioFile = e.file
    if self.activeSample then
      self.activeSample:stop()
      self.activeSample = nil
    end
  end
  initActiveSample(self)

  local args = {from = e.from, to = e.to, e = e}
  args.resume = not self.activeSample:isPaused()
  self.beingCreated = args
  self.activeSample:resumeIf(false)
  ui.popup(function ()
    args.hovered = 0
    self.phraseBeingEdited = e
    ui.pushStyleVar(ui.StyleVar.FramePadding, 0)
    ui.beginGroup()
    if timeEditPoint(self, args, 'From:', 'from', 0) then
      table.clear(self.samplesQueue)
    end
    ui.endGroup()
    if ui.itemHovered() or ui.itemActive() then
      args.hovered = 1
    end
    ui.beginGroup()
    if timeEditPoint(self, args, 'To:', 'to', 0) then
      table.clear(self.samplesQueue)
    end
    ui.endGroup()
    if ui.itemHovered() or ui.itemActive() then
      args.hovered = 2
    end
    ui.text('Duration: %s' % timeToDisplay(self, args.to - args.from))
    ui.popStyleVar()
    ui.offsetCursorY(4)

    if #self.samplesQueue < 2 then
      table.insert(self.samplesQueue, {from = args.from, to = args.to, file = self.activeAudioFile, tagsRaw = '', debug = true})
    end

    ui.setNextItemIcon(ui.Icons.Confirm)
    if ui.button('Save', vec2(120, 0)) then
      local bak = {args.e.from, args.e.to}
      args.e.from = args.from
      args.e.to = args.to
      ui.toast(ui.Icons.Edit, 'Phrase changed', function ()
        args.e.from, args.e.to = bak[1], bak[2]
      end)
    end
    ui.sameLine(0, 4)
    ui.setNextItemIcon(ui.Icons.Cancel)
    if ui.button('Cancel', vec2(120, 0)) then
      ui.closePopup()
    end
  end, {
    onClose = function ()
      self.activeSample:resumeIf(args.resume)
      table.clear(self.samplesQueue)
      if self.beingCreated == args then
        self.beingCreated = nil
      end
      self.phraseBeingEdited = nil
    end
  })
end

---@param self Voice
---@param phraseIndex integer
local function editorGroup(self, phraseIndex)
  local w = #self.availableAudioFiles > 1 and (ui.availableSpaceX() - 12 - 26) / 4 or (ui.availableSpaceX() - 8 - 26) / 3
  ui.pushItemWidth(w)
  for _, e in ipairs(self.entries[phraseIndex]) do
    ui.pushID(_)
    ui.beginGroup()
    if self.hoveredGraphPhrase == e or self.phraseBeingEdited == e then
      ui.pushStyleColor(ui.StyleColor.Text, rgbm.colors.yellow)
    end
    if #self.availableAudioFiles > 1 then
      ui.combo('##file', e.file, function ()
        for _, v in ipairs(self.availableAudioFiles) do
          if ui.selectable(v, v == e.file) then
            e.file = v
          end
        end
      end)
      ui.sameLine(0, 4)
    elseif e.file ~= self.availableAudioFiles[1] then
      e.file = self.availableAudioFiles[1]
    end
    timeEditPoint(self, e, 'From:', 'from', 160)
    ui.sameLine(0, 4)
    timeEditPoint(self, e, 'To:', 'to', 160)
    ui.sameLine(0, 4)
    ui.setNextItemWidth(ui.availableSpaceX() - 26 * 2)
    local tags = ui.inputText('Tags', e.tagsRaw, ui.InputTextFlags.Placeholder)
    if ui.itemHovered() then
      ui.setTooltip('Use keywords “!”, “&”, “|” or “,”, “(” and “)” for complex expressions')
    end
    if ui.itemEdited() then
      e.tagsRaw = tags
    end
    ui.sameLine(0, 4)
    if ui.iconButton(ui.Icons.Edit, vec2(22, 22), -1, true, self.beingCreated and self.beingCreated.e == e and ui.ButtonFlags.Active or 0) then
      editPhrase(self, e)
    end
    ui.sameLine(0, 4)
    if ui.iconButton(ui.Icons.Play, vec2(22, 22), -1, true, bit.bor(e == self.mainEventSource and ui.ButtonFlags.Active or 0,
      e.to - e.from >= self.minLength and 0 or ui.ButtonFlags.Disabled)) then
      table.insert(uis.ctrlDown and self.samplesDelayedQueue or self.samplesQueue, e)
    end
    if ui.itemHovered() then ui.setTooltip('Hold Ctrl to delay enqueued samples before the button is released') end
    local x, r = Utils.lastIndexOf(self.samplesQueue, e) or e == self.mainEventSource and -1 or 0, false
    if x == 0 then
      local j = Utils.lastIndexOf(self.samplesDelayedQueue, e)
      if j then
        x, r = j, true
        ui.pushStyleColor(ui.StyleColor.ButtonActive, rgbm.colors.white)
      end
    end
    ui.notificationCounter(x)
    if r then
      ui.popStyleColor()
    end
    ui.endGroup()
    if self.hoveredGraphPhrase == e or self.phraseBeingEdited == e then
      ui.popStyleColor()
    end
    if ui.itemHovered() then
      self.hoveredPhrase = e
    end
    if ui.itemClicked(ui.MouseButton.Right) then
      ui.popup(function ()
        if ui.menuItem('Duplicate') then
          local cloned = table.clone(e)
          table.insert(self.entries[phraseIndex], _ + 1, cloned)
          ui.toast(ui.Icons.Copy, 'Phrase copied###rallyVoiceEditor', function ()
            table.removeItem(self.entries[phraseIndex], cloned)
          end)
        end
        if ui.beginMenu('Duplicate to…') then
          for i, v in ipairs(self.mode:list()) do
            if i ~= phraseIndex and ui.menuItem(v) then
              table.insert(self.entries[i], e)
              ui.toast(ui.Icons.Copy, 'Phrase copied to %s###rallyVoiceEditor' % v, function ()
                table.removeItem(self.entries[i], e)
              end)
            end
          end
          ui.endMenu()
        end
        if ui.beginMenu('Move to…') then
          for i, v in ipairs(self.mode:list()) do
            if i ~= phraseIndex and ui.menuItem(v) then
              table.removeItem(self.entries[phraseIndex], e)
              table.insert(self.entries[i], e)
              ui.toast(ui.Icons.Leave, 'Phrase moved to %s###rallyVoiceEditor' % v, function ()
                table.insert(self.entries[phraseIndex], _, e)
                table.removeItem(self.entries[i], e)
              end)
            end
          end
          ui.endMenu()
        end
        ui.separator()
        if ui.menuItem('Remove') then
          table.removeItem(self.entries[phraseIndex], e)
          ui.toast(ui.Icons.Delete, 'Phrase removed###rallyVoiceEditor', function ()
            table.insert(self.entries[phraseIndex], _, e)
          end)
        end
      end)
    end
    ui.popID()
  end
  ui.popItemWidth()
end

---@param self Voice
local function audioFileDebug(self)
  if #self.availableAudioFiles > 1 then
    ui.setNextItemWidth(-0.1)
    ui.childWindow('##file', vec2(-0.1, 80), false, ui.WindowFlags.None, function ()
      ui.pushStyleVar(ui.StyleVar.SelectablePadding, vec2(6, 0))
      for _, v in ipairs(self.availableAudioFiles) do
        if ui.selectable(v, v == self.activeAudioFile) then
          self.activeAudioFile = v
          if self.activeSample then
            self.activeSample:stop()
            self.activeSample = nil
          end
        end
      end
      ui.popStyleVar()
    end)
  end
  
  initActiveSample(self)
  if not self.activeSample then
    self.activeSamplePos = 0
    ui.setNextTextSpanStyle(1, 8, nil, true)
    ui.text('Warning: no suitable audio files available.')
    return
  end
  local pos = self.activeSample:getTimelinePosition()
  local duration = self.activeSample:getDuration()
  if duration <= 0 then
    self.activeSamplePos = 0
    ui.setNextTextSpanStyle(1, 8, nil, true)
    ui.text('Warning: failed to load audio file.')
    return
  end
  self.activeSamplePos = pos
  local graphHovered = false
  ui.beginGroup()
  ui.childWindow('graph', vec2(-0.1, 120), false, bit.bor(ui.WindowFlags.HorizontalScrollbar, ui.WindowFlags.NoScrollWithMouse), function ()
    graphHovered = ui.windowHovered(ui.HoveredFlags.AllowWhenBlockedByActiveItem)
    local rD = 0
    if self.shapeTargetScroll ~= -1 then
      rD = ui.getScrollX() - self.shapeTargetScroll
      ui.setScrollX(self.shapeTargetScroll, false, false)
      self.shapeTargetScroll = -1
    end
    local sX, sW = ui.getScrollX(), ui.windowWidth()
    if rD == 0 and graphHovered and uis.mouseWheel ~= 0 then
      if uis.ctrlDown then
        self.shapeTargetScroll = ui.getScrollX() + uis.mouseWheel * -100
      else
        local oW = sW * math.pow(2, self.shapeZoom)
        self.shapeZoom = math.max(0, self.shapeZoom + uis.mouseWheel * 0.5)
        local nW = sW * math.pow(2, self.shapeZoom)
        self.shapeTargetScroll = sX + (nW - oW) * math.lerpInvSat(ui.mouseLocalPos().x, sX, sX + sW)
        rD = ui.getScrollX() - self.shapeTargetScroll
      end
    end

    local areaSize = vec2(sW * math.pow(2, self.shapeZoom), ui.windowHeight() - 8)
    local rF, rT = sX, sX + sW

    local r1 = ui.getCursor()
    local r2 = areaSize:clone():add(r1)
    u1:set(r1)
    u2:set(r2)
    u1.y = u1.y + 12
    u2.y = u2.y - 12
    if self.activeAudioFile then
      AudioShape.drawGraph(getAudioFullFilename(self, self.activeAudioFile), u1, u2, rF, rT)
    end

    local visibleSeconds = duration / math.pow(2, self.shapeZoom)
    local timelineSteps = math.pow(10, math.floor(math.log10(visibleSeconds * 0.5)))
    for i = 1, duration, timelineSteps do
      local x = r1.x + i / duration * (r2.x - r1.x)
      if x > rT then
        break
      elseif x > rF then
        ui.drawSimpleLine(u1:set(x, r1.y), u2:set(x, r2.y + 8), colTimePoint)
      end
    end

    local tooltipItem
    local windowHovered = ui.windowHovered(ui.HoveredFlags.RootAndChildWindows)
    for y, v in pairs(self.entries) do
      for _, e in ipairs(v) do
        if e.file == self.activeAudioFile then
          local x0 = r1.x + e.from / duration * (r2.x - r1.x)
          local x1 = r1.x + e.to / duration * (r2.x - r1.x)
          ui.drawRectFilled(u1:set(x0, r1.y), u2:set(x1, r2.y + 8), colUsed)
          if windowHovered and ui.rectHovered(u1, u2) then
            self.hoveredGraphPhrase = e
            tooltipItem = {e, y}
          end
          if e == self.hoveredPhrase then 
            ui.drawSimpleLine(vec2(x0, r1.y), vec2(x0, r2.y + 8), rgbm(1, 1, 1, 0.5), 1)
            ui.drawSimpleLine(vec2(x1, r1.y), vec2(x1, r2.y + 8), rgbm(1, 1, 1, 0.5), 1)
          end
          local i = table.indexOf(self.lastPlayed, e)
          if i then
            for j = 1, i do
              ui.drawSimpleLine(vec2(x0, r2.y - j * 2), vec2(x1, r2.y - j * 2), rgbm(1, 1, 0, 1), 1)
            end
          end
        end
      end
    end

    if self.beingCreated then
      local x0 = r1.x + self.beingCreated.from / duration * (r2.x - r1.x)
      ui.drawSimpleLine(vec2(x0, r1.y), vec2(x0, r2.y + 8), rgbm.colors.yellow, self.beingCreated.hovered == 1 and 2 or 1)
      local x1 = r1.x + self.beingCreated.to / duration * (r2.x - r1.x)
      ui.drawSimpleLine(vec2(x1, r1.y), vec2(x1, r2.y + 8), rgbm.colors.yellow, self.beingCreated.hovered == 2 and 2 or 1)
      ui.drawRectFilled(vec2(x1, r1.y), vec2(x0, r2.y + 8), rgbm(1, 1, 0, 0.2))
    else
      if pos > 0 then
        local x = r1.x + pos / duration * (r2.x - r1.x)
        ui.drawSimpleLine(vec2(x, r1.y), vec2(x, r2.y + 8), rgbm.colors.white)
      end
      if self.markStart >= 0 then
        local x0 = r1.x + self.markStart / duration * (r2.x - r1.x)
        ui.drawSimpleLine(vec2(x0, r1.y), vec2(x0, r2.y + 8), rgbm.colors.yellow)
        local x1 = r1.x + pos / duration * (r2.x - r1.x)
        ui.drawRectFilled(vec2(x1, r1.y), vec2(x0, r2.y + 8), rgbm(1, 1, 0, 0.2))
      end
    end
    if self.evs and self.mainEvent and not self.mainEvent:isPaused() and self.mainEventPool == self.evs[self.activeAudioFile] then
      local x = r1.x + self.mainEvent:getTimelinePosition() / duration * (r2.x - r1.x)
      ui.drawSimpleLine(vec2(x, r1.y), vec2(x, r2.y + 8), rgbm(1, 1, 1, 0.5))
    end

    ui.backupCursor()
    ui.setCursorX(138 + sX + rD)
    ui.setCursorY(8)
    ui.setNextItemIcon(ui.Icons.Copy)
    local showTooltip = true
    if ui.button('Copy') then
      ui.setClipboardText(timeToDisplay(self, pos))
      ui.toast(ui.Icons.Copy, 'Copied: %s' % timeToDisplay(self, pos))
    end
    if ui.itemHovered() then 
      ui.setTooltip('Copy current timestamp (“%s”)' % timeToDisplay(self, pos)) 
      showTooltip = false
    end
    ui.sameLine(0, 4)
    ui.setNextItemIcon(self.activeSample:isPaused() and ui.Icons.Play or ui.Icons.Pause)
    if ui.button(self.activeSample:isPaused() and 'Play' or 'Pause', vec2(100, 0)) or graphHovered and ac.isKeyPressed(ui.KeyIndex.Space) then
      self.activeSample:resumeIf(self.activeSample:isPaused())
    end
    if ui.itemHovered() then 
      ui.setTooltip('Play/pause the playback (Space)') 
      showTooltip = false
    end
    ui.sameLine(0, 4)
    ui.setNextItemIcon(ui.Icons.StopAlt)
    if ui.button('Stop', vec2(100, 0)) then
      self.activeSample:stop()
    end
    if ui.itemHovered() then 
      ui.setTooltip('Stop playback and rewind to the start') 
      showTooltip = false
    end
    ui.sameLine(0, 4)
    ui.offsetCursorX(ui.availableSpaceX() + sX + rD - 108)
    ui.setNextItemIcon(ui.Icons.Save)
    if ui.button('Save', vec2(100, 0)) then
      ui.toast(ui.Icons.Save, 'Changes saved')
      self:save()
    end
    if ui.itemHovered() then 
      ui.setTooltip('Save all the changes to phrases to “%s.txt”' % self.id) 
      showTooltip = false
    end
    ui.restoreCursor()

    ui.invisibleButton('', areaSize)
    local r1, r2 = ui.itemRect()
    r1.x = r1.x + rD
    r2.x = r2.x + rD
    if ui.itemClicked(ui.MouseButton.Left, false) then
      self.wasPlaying = not self.activeSample:isPaused()
      if self.wasPlaying then
        self.activeSample:resumeIf(false)
      end
      self.markStart = ui.hotkeyCtrl() and math.lerpInvSat(ui.mouseLocalPos().x, r1.x, r2.x) * duration or -1
    elseif ui.itemClicked(ui.MouseButton.Left, true) and self.wasPlaying then
      self.activeSample:resume()
      self.wasPlaying = false
    end
    if ui.itemActive() then
      pos = math.lerpInvSat(ui.mouseLocalPos().x, r1.x, r2.x) * duration
      self.activeSample:seek(pos)
    elseif self.markStart ~= -1 then
      if ui.hotkeyCtrl() and pos > self.markStart + 0.01 then
        local args = self.markStart < pos and {from = self.markStart, to = pos} or {from = pos, to = self.markStart}
        args.resume = not self.activeSample:isPaused()
        self.beingCreated = args
        self.activeSample:resumeIf(false)
        ui.popup(function ()
          args.hovered = 0
          ui.pushStyleVar(ui.StyleVar.FramePadding, 0)
          ui.beginGroup()
          if timeEditPoint(self, args, 'From:', 'from', 0) then
            table.clear(self.samplesQueue)
          end
          ui.endGroup()
          if ui.itemHovered() or ui.itemActive() then
            args.hovered = 1
          end
          ui.beginGroup()
          if timeEditPoint(self, args, 'To:', 'to', 0) then
            table.clear(self.samplesQueue)
          end
          ui.endGroup()
          if ui.itemHovered() or ui.itemActive() then
            args.hovered = 2
          end
          ui.text('Duration: %s' % timeToDisplay(self, args.to - args.from))
          ui.popStyleVar()
          ui.offsetCursorY(4)

          if #self.samplesQueue < 2 then
            table.insert(self.samplesQueue, {from = args.from, to = args.to, file = self.activeAudioFile, tagsRaw = '', debug = true})
          end

          ui.separator()
          ui.header('Assign to:')
          local pg, pa = nil, false
          for i = 1, self.mode:size() do
            local cg = self.mode:label(i):match('^%w+')
            if cg ~= pg then
              if pa then ui.endMenu() end
              pg, pa = cg, cg and ui.beginMenu(cg)
            end
            if pa then
              ui.setNextItemIcon(self.mode:icon(i))
              if ui.selectable(self.mode:label(i), false) then
                local targetGroup = self.entries[i]
                local newlyCreated = {from = args.from, to = args.to, file = self.activeAudioFile, tagsRaw = ''}
                table.insert(targetGroup, newlyCreated)
                ui.toast(ui.Icons.New, 'Phrase created###rallyVoiceEditor', function ()
                  table.removeItem(targetGroup, newlyCreated)
                end)
              end
            end
          end
          if pa then ui.endMenu() end
        end, {
          onClose = function ()
            self.activeSample:resumeIf(args.resume)
            table.clear(self.samplesQueue)
            self.beingCreated = nil
          end
        })
      end
      self.markStart = -1
    end

    local hoveredTime = timeToDisplay(self, math.lerpInvSat(ui.mouseLocalPos().x, r1.x, r2.x) * duration)
    if showTooltip and tooltipItem then
      ui.tooltip(function ()
        ui.icon(self.mode:icon(tooltipItem[2]), vec2(14, 14))
        ui.sameLine(0, 4)
        ui.text(self.mode:label(tooltipItem[2]))
        ui.text('Time: %s\nPress right mouse button to quickly edit a phrase' % hoveredTime)
        showTooltip = false
      end)
      if uis.isMouseRightKeyClicked then
        editPhrase(self, tooltipItem[1])
      end
    end

    ui.drawText('%s/%s' % {timeToDisplay(self, pos), timeToDisplay(self, duration)}, vec2(12 + sX + rD, 12):add(r1))
    if showTooltip and ui.itemHovered() then
      ui.setTooltip('Time: %s\nHold Ctrl and drag to mark a new phrase' % hoveredTime)
    end
  end)
end

function Voice:editor()
  self.hoveredGraphPhrase = nil
  if not self.availableAudioFiles then
    if not self.watcher then
      self.watcher = ac.onFolderChanged(self:location(), '`.*\\.(mp3|wav|aiff?|ogg)$`', true, function (changes)
        self.availableAudioFiles = nil
      end)
    end
    self.availableAudioFiles = {}
    local firstDir = self:location()
    local dirs = {firstDir}
    while #dirs > 0 do
      local l = table.remove(dirs, #dirs)
      io.scanDir(l, '*', function (fileName, attr)
        if attr.isDirectory then
          table.insert(dirs, l..'\\'..fileName)
        elseif fileName:regfind('\\.(mp3|wav|aiff?|ogg)$', nil, true) then
          table.insert(self.availableAudioFiles, l == firstDir and fileName or l:sub(#firstDir + 2)..'\\'..fileName)
        end
      end)
    end
    table.sort(self.availableAudioFiles, function (a, b)
      return string.alphanumCompare(a, b) < 0
    end)
    self.activeAudioFile = self.availableAudioFiles[1]
  end
  audioFileDebug(self)
  self.hoveredPhrase = nil
  ui.childWindow('groups', vec2(-0.1, -0.1), function ()
    for i = 1, self.mode:size() do
      ui.setNextItemIcon(self.mode:icon(i))
      if table.contains(self.entries[i], self.hoveredGraphPhrase) then ui.setNextTextSpanStyle(1, 1e6, rgbm.colors.yellow) end
      local edited = self.phraseBeingEdited and table.contains(self.entries[i], self.phraseBeingEdited)
      if edited and not self.forceOpenedGroups[i] then
        self.forceOpenedGroups[i] = true
      end
      local opened = self.openedGroups[i]
      if opened then ui.beginGroup(-26) end
      self.openedGroups[i] = false
      ui.treeNode('%s (%d)###%d' % {self.mode:label(i), #self.entries[i], edited and i or i}, 
        self.forceOpenedGroups[i] and bit.bor(ui.TreeNodeFlags.Framed, ui.TreeNodeFlags.DefaultOpen) or ui.TreeNodeFlags.Framed, 
        function ()
          self.openedGroups[i] = true
          editorGroup(self, i)
        end)
      if opened then
        ui.endGroup()
        ui.sameLine(0, 4)
        if ui.iconButton(ui.Icons.Plus, vec2(22, 22)) then
          local created = { file = self.availableAudioFiles[1], from = 0.5, to = 1, tagsRaw = '' }
          table.insert(self.entries[i], created)
          ui.toast(ui.Icons.New, 'Phrase created###rallyVoiceEditor', function ()
            table.removeItem(self.entries[i], created)
          end)
        end
        if ui.itemHovered() then
          ui.setTooltip('Add new phrase')
        end
      elseif not edited then
        self.forceOpenedGroups[i] = nil
      end
    end
  end)
end

---@param type RouteItemType
---@param modifier integer
---@param hints RouteItemHint[]
---@param tags string[]
---@return boolean
function Voice:enqueue(type, modifier, hints, tags)
  local phraseIndices = self.mode:convert(type, modifier, hints, tags, self.curEvent > 0 or #self.samplesQueue > 0)
  local ret = false
  if phraseIndices then
    for _, v in ipairs(phraseIndices) do
      local t = self.entries[v]
      if t then
        -- TODO: use tags to select a more appropriate variation
        local shuffle = self.shuffles[v]
        self.samplesQueue[#self.samplesQueue + 1] = shuffle and shuffle:get(t) or table.random(t)
        ret = true
      end
    end
  end
  return ret
end

---@param type RouteItemType
---@param modifier integer
---@return boolean
function Voice:supports(type, modifier)
  local phraseIndices = self.mode:convert(type, modifier, {}, {}, false)
  if phraseIndices then
    for _, v in ipairs(phraseIndices) do
      local t = self.entries[v]
      if t then
        return true
      end
    end
  end
  return false
end

---@param dt number`
function Voice:update(dt, volume)
  if avGroup then
    AppState.connection.speechPeak = avGroup:getDSPMetering(0, 'input')
    ac.debug('peak', AppState.connection.speechPeak)
  end
   
  if #self.samplesDelayedQueue > 0 and not uis.ctrlDown then
    for _, v in ipairs(self.samplesDelayedQueue) do self.samplesQueue[#self.samplesQueue + 1] = v end
    table.clear(self.samplesDelayedQueue)
  end
  if self.fadingEvent then
    self.fadingEvent.volume = math.applyLag(self.fadingEvent.volume, 0, 0.8, dt / self.fade)
    if self.fadingEvent.volume < 0.1 then
      self.fadingEvent:stop()
      table.insert(self.fadingEventPool, self.fadingEvent)
      self.fadingEvent = nil
      self.fadingEventSource = nil
    end
  end
  if self.curEvent > 0 then
    self.mainEvent.volume = math.applyLag(self.mainEvent.volume, volume, 0.8, dt / math.max(0.0001, self.fade))
    self.curEvent = self.curEvent - dt
    if self.curEvent <= 0 then
      if self.fade <= 0 then
        self.mainEvent:stop()
        table.insert(self.mainEventPool, self.mainEvent)
      else
        if self.fadingEvent then
          self.fadingEvent:stop()
          table.insert(self.fadingEventPool, self.fadingEvent)
          ac.error('fadingEvent is still active')
        end
        self.fadingEvent, self.fadingEventPool, self.fadingEventSource = self.mainEvent, self.mainEventPool, self.mainEventSource
      end
      self.mainEvent, self.mainEventSource = nil, nil
    end
  elseif #self.samplesQueue > 0 then 
    local ev = table.remove(self.samplesQueue, 1) ---@type VoiceEntry
    if not ev.debug then
      if #self.lastPlayed > 6 then
        table.remove(self.lastPlayed, #self.lastPlayed)
      end
      table.insert(self.lastPlayed, 1, ev)
    end
    ensureSamplesAreReady(self, ev.file)
    if ev.to - ev.from < self.minLength - 0.005 then
      ac.warn('Phrase is too short')
    else
      if self.mainEvent ~= nil then
        self.mainEvent:stop()
        table.insert(self.mainEventPool, self.mainEvent)
        ac.error('self.mainEvent is still active')
      end
      self.mainEventPool = self.evs[ev.file]
      if self.mainEventPool then
        self.mainEvent = table.remove(self.mainEventPool, #self.mainEventPool)
        self.mainEvent.volume = 0
        self.mainEvent:start()
        self.mainEvent:seek(ev.from)
        self.curEvent = ev.to - ev.from
        self.mainEventSource = ev
      end
    end
  end
end

function Voice:dispose()
  if not self.evs then return end
  for _, v in pairs(self.evs) do
    for _, e in ipairs(v) do
      e:dispose()
    end
  end
  table.clear(self.evs)
  if self.watcher then
    self.watcher()
    self.watcher = nil
  end
end

return class.emmy(Voice, Voice.allocate)