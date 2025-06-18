--[[
  Very basic OpenRGB library, uses luasocket and background worker to exchange data quickly.
  Based on https://github.com/zebp/openrgb.
]]

local function connectDevice(phase, device, reset)
  local ret = ac.connect({
    ac.StructItem.key('.csp.openrgb.dev.' .. phase .. '/' .. device.index .. '/' .. #device.colors),
    frame = ac.StructItem.uint32(),
    colors = ac.StructItem.array(ac.StructItem.array(ac.StructItem.uint32(), #device.colors), 4)
  })
  if reset then
    for i = 0, 3 do
      for j = 0, #device.colors - 1 do
        ret.colors[i][j] = 0
      end
    end
  end
  return ret
end

if worker and type(worker.input) == 'table' then
  -- New idea: do both worker and its starting code in the same Lua file, because why not. This
  -- makes a lovely self-contained OpenRGB library.
  local socket = require('shared/socket')
  local binary = require('shared/utils/binary')

  local function reportStatus(status)
    ac.broadcastSharedEvent('.csp.openrgb.cb', { phase = worker.input.phase, status = status })
  end

  local function tryLaunch(linked)
    print('Trying to launch OpenRGB (linked: %s)' % linked)
    local exe
    reportStatus('Downloading OpenRGB…')
    web.loadRemoteAssets({
      url = 'https://acstuff.club/u/blob/openrgb-2.zip',
      crucial = 'OpenRGB Windows 64-bit/OpenRGB.exe',
      __verify = 'openrgb'
    },
    function(err, folder)
      if err then
        reportStatus('Failed to download OpenRGB: %s' % err)
      else
        exe = folder..'/OpenRGB Windows 64-bit/OpenRGB.exe'
      end
    end)

    while not exe do
      worker.sleep(0.1)
    end

    os.runConsoleProcess({
      filename = exe,
      arguments = { '--server', '--server-host', 'localhost', '--localconfig', not linked and '--startminimized' or nil },
      terminateWithScript = linked and 'disposable',
      assignJob = linked
    }, function(err, data)
      if err then
        reportStatus('Failed to start OpenRGB: %s' % err)
      end
      print('Process finished', err, data)
    end)
  end

  local Command = {
    RequestControllerCount = 0,
    RequestControllerData = 1,
    SetClientName = 50,
    UpdateLeds = 1050,
    UpdateZoneLeds = 1051,
    SetCustomMode = 1100,
  }

  local HEADER_SIZE = const(16)

  local function readString(r)
    local s = r:raw(r:uint16() - 1)
    r:skip(1)
    return s
  end

  local function readColor(data)
    local r, g, b, _ = data:uint8(), data:uint8(), data:uint8(), data:uint8()
    return rgb(r / 255., g / 255., b / 255.)
  end

  local function header(cmd, length, devId)
    return binary.writeData(HEADER_SIZE):append('ORGB'):uint32(devId or 0):uint32(cmd):uint32(length):stringify()
  end

  local function send(sock, command, payload, deviceIndex)
    payload = type(payload) == 'string' and payload or payload and payload:stringify() or ''
    assert(sock:send(header(command, #payload, deviceIndex or 0) .. payload))
  end

  local function read(sock, n)
    local buf, parts, left = {}, 0, n
    while left > 0 do
      local chunk, err, partial = sock:receive(left)
      local data = chunk or partial
      if not data or #data == 0 then
        error('Socket receive failed: ' .. tostring(err))
      end
      parts = parts + 1
      buf[parts] = data
      left = left - #data
    end
    return table.concat(buf)
  end

  local function response(sock)
    local h = read(sock, HEADER_SIZE)
    local r = binary.readData(h)
    r:skip(4) -- 'ORGB'
    local di = r:uint32()
    local ci = r:uint32()
    return read(sock, r:uint32()), di, ci
  end

  local Client = {}
  Client.__index = Client

  function Client.new(opts)
    local sock = assert(socket.tcp())
    sock:settimeout(opts.timeout or 5)
    assert(sock:connect(opts.host or 'localhost', opts.port or 6742))
    send(sock, Command.SetClientName, opts.name or 'Assetto Corsa')
    return setmetatable({ sock = sock }, Client)
  end

  function Client:disconnect()
    if self.sock then self.sock:close() end
    self.sock = nil
  end

  function Client:count()
    send(self.sock, Command.RequestControllerCount)
    return binary.readData(response(self.sock)):uint32()
  end

  function Client:device(id)
    send(self.sock, Command.RequestControllerData, nil, id)
    local payload = response(self.sock)
    local r = binary.readData(payload):skip(4)
    local dev = {
      index = id,
      type = r:uint32(),
      name = readString(r),
      desc = readString(r),
      version = readString(r),
      serial = readString(r),
      location = readString(r),
    }
    local modeCount = r:uint16()
    local currentMode = r:uint32()
    dev.modes = table.range(modeCount, function(index)
      return {
        active = index == currentMode + 1,
        name = readString(r),
        value = r:int32(),
        flags = r:uint32(),
        speedBounds = { min = r:uint32(), max = r:uint32() },
        colorBounds = { min = r:uint32(), max = r:uint32() },
        speed = r:uint32(),
        direction = r:uint32(),
        colorMode = r:uint32(),
        colors = table.range(r:uint16(), function() return readColor(r) end)
      }
    end)
    dev.zones = table.range(r:uint16(), function()
      return {
        name = readString(r),
        type = r:int32(),
        leds = { min = r:uint32(), max = r:uint32() },
        ledsCount = r:uint32(),
        _matrix = r:skip(r:uint16()) and nil
      }
    end)
    dev.leds = table.range(r:uint16(), function() return { name = readString(r), value = readColor(r) } end)
    dev.colors = table.range(r:uint16(), function() return readColor(r) end)
    return dev
  end

  function Client:customMode(index)
    send(self.sock, Command.SetCustomMode, nil, index)
  end

  function Client:raw(index, offset, count, raw, zone)
    if count == 0 then return end
    local size = (zone and 10 or 6) + 4 * count
    local buf = binary.writeData(size):uint32(size)
    if zone then buf:uint32(zone) end
    buf:uint16(count)
    for i = offset, offset + count - 1 do
      buf:uint32(bit.band(raw[i], 0xffffff))
    end
    send(self.sock, zone and Command.UpdateZoneLeds or Command.UpdateLeds, buf, index)
  end

  local function createState(item)
    return {
      index = item.index,
      device = item,
      colorsCount = #item.colors,
      lastFrame = item.frame,
      connect = connectDevice(worker.input.phase, item, true),
      switched = false,
      zoneFilled = table.map(item.zones, function() return 0 end),
      partialZones = #item.zones,
      filled = false
    }
  end

  local function sync(client, state)
    local f = state.connect.frame
    if f == state.lastFrame then return end
    state.lastFrame = f
    ac.memoryBarrier()
    if not state.switched then
      state.switched = true
      client:customMode(state.index)
    end
    if state.partialZones == 0 then
      -- All the zones have been fully filled, let’s just send a basic request:
      client:raw(state.index, 0, state.colorsCount, state.connect.colors[f], nil)
    else
      -- Some LEDs should keep original colors. We can’t pick individual LEDs, but at least
      -- we can try our best to leave zones untouched. First, let’s see if we can fill out
      -- things with a single request sending fewer LEDs:
      local lastNonZero = 0
      for i = 0, state.colorsCount - 1 do
        local col = state.connect.colors[f][i]
        if col ~= 0 then
          if lastNonZero == i then
            lastNonZero = i + 1
          else
            goto ZoneRoute
          end
        end
      end

      if lastNonZero == state.colorsCount then
        state.partialZones = 0
      end
      if lastNonZero > 0 then
        client:raw(state.index, 0, lastNonZero, state.connect.colors[f], nil)
      end
      do return end

      -- So, there are zeroes and then non-zeroes. Let’s submit data per-zone to try and keep
      -- zeroed LEDs untouched:
      ::ZoneRoute::
      local k = 0
      for zoneIndex = 1, #state.device.zones do
        local zone = state.device.zones[zoneIndex]
        local maxSet = state.zoneFilled[zoneIndex]
        for j = maxSet, zone.ledsCount - 1 do
          local col = state.connect.colors[f][k + j]
          if col ~= 0 then
            maxSet = j + 1
            state.zoneFilled[zoneIndex] = maxSet
            if maxSet == zone.ledsCount then
              -- Zone has been fully filled!
              state.partialZones = state.partialZones - 1
            end
          end
        end
        if maxSet > 0 then
          client:raw(state.index, k, maxSet, state.connect.colors[f], zoneIndex - 1)
        end
        k = k + zone.ledsCount
      end
    end
  end

  local update
  local cooldown = 1
  update = function()
    reportStatus('Trying to connect…')
    local connected, client = pcall(Client.new, worker.input)
    if not connected then
      if cooldown == 1 and worker.input.exe then
        tryLaunch(worker.input.exe == 'linked')
      else
        ac.warn(client)
        reportStatus('Failed to connect, trying again…')
        worker.sleep(cooldown)
      end
      cooldown = math.min(10, cooldown + 0.5)
      return
    end

    local count = 0
    for _ = 1, 10 do
      count = client:count()
      if count > 0 then
        break
      else
        reportStatus('Waiting for devices…')
        worker.sleep(1)
      end
    end

    local devices = table.range(count, function(index) return client:device(index - 1) end)
    local states = table.map(devices, createState)

    ac.broadcastSharedEvent('.csp.openrgb.cb', { phase = worker.input.phase, payload = devices })
    update = function()
      for i = 1, #states do
        sync(client, states[i])
      end
    end
  end

  while true do
    update()
    worker.sleep(0.03)
  end
  return
end

local openrgb = {}
local COLOR_BLACK = const(256 * 256 * 256)

---@param r number
---@param g number
---@param b number
local function encW(r, g, b)
  return math.floor(math.saturateN(r) * 255)
      + math.floor(math.saturateN(g) * 255) * 256
      + math.floor(math.saturateN(b) * 255) * (256 * 256)
      + 256 * 256 * 256
end

---@param c rgb
local function encR(c)
  return encW(c.r, c.g, c.b)
end

local function lerp1Encoded(v1, v2, t)
  local r = math.round(v1 + (v2 - v1) * t)
  return r == v1 and v1 ~= v2 and v1 + math.sign(v2 - v1) or r
end

local devices
local phase
local status

---@alias OpenRGB.TweakKey 'saturation'|'brightness'|'gamma'|'delay'|'smoothing'|'delay2'|'smoothing2'|'flipX'|'singleColor'|'partialCoverage'
---@alias OpenRGB.Bounds {min: integer, max: integer}
---@alias OpenRGB.Tweaks {flipX: boolean, singleColor: boolean, partialCoverage: boolean, smoothing: number, smoothing2: number?, delay: number, delay2: number?, saturation: number, brightness: number, gamma: number, backgroundColor: rgb?}

---@class OpenRGB.Device
---@field private _connect any
---@field private _changed boolean
---@field private _next integer
---@field private _ledsCount integer
---@field private _circular {values: integer[]}
---@field uuid string
---@field name string
---@field desc string
---@field serial string
---@field location string
---@field version string
---@field index integer
---@field type integer
---@field colors rgb[]
---@field leds {value: rgb, name: string}[]
---@field modes {name: string, active: boolean, flags: integer, value: integer, colors: rgb[], speed: integer, colorMode: integer, direction: integer, speedBounds: OpenRGB.Bounds, colorBounds: OpenRGB.Bounds}[]
---@field zones {name: string, leds: OpenRGB.Bounds, type: integer, ledsStart: integer, ledsCount: integer}[]
local _device = {}

function _device:set(index, color)
  local c = self._connect
  c.colors[self._next][index] = encR(color)
  self._changed = true
  return self
end

---@param c1 rgb
---@param c2 rgb
local function encL(c1, c2, t)
  local br, bg, bb = math.lerp(c1.r, c2.r, t), math.lerp(c1.g, c2.g, t), math.lerp(c1.b, c2.b, t)
  return encW(br, bg, bb)
end

---@return fun(...): any
local function createFunction(args, ...)
  return loadstring(string.format('return function(%s)%s end', table.concat(args, ','), table.concat({...}, '\n')), 'fn')()
end

local fns = {}

---@param tweaks OpenRGB.Tweaks
local function getTweaksFn(tweaks, allowAcross)
  -- Compiling functions to apply tweaks for extra performance (I worry about keyboard devices with 100+ LEDs)
  local anyAcross = allowAcross and ((tweaks.delay2 or 0) ~= (tweaks.delay or 0) or (tweaks.smoothing2 or 1) ~= (tweaks.smoothing or 1))
  local anySmoothing = ((tweaks.smoothing or 1) < 1 or anyAcross and (tweaks.smoothing2 or 1) < 1)
  local anyDelay = ((tweaks.delay or 0) > 0 or anyAcross and (tweaks.delay2 or 0) > 0)
  local key = (anySmoothing and 1 or 0)
      + ((tweaks.saturation or 1) ~= 1 and 2 or 0)
      + ((tweaks.brightness or 1) ~= 1 and 4 or 0)
      + ((tweaks.gamma or 1) ~= 1 and 8 or 0)
      + (anyDelay and 16 or 0)
      + (anyAcross and 32 or 0)
      + (tweaks.flipX and 64 or 0)
      + 256
  local ret = fns[key] 
  if not ret then
    if key == 256 then
      ret = function() end
    else
      local body = {}
      if tweaks.flipX then
        table.insert(body, 'for i=from,math.floor((from + to) / 2 - 0.01) do\nn[i],n[to+from-i]=n[to+from-i],n[i]\nend')
      end
      table.insert(body, 'for i=from,to do\nlocal c=n[i]')
      if anyAcross then
        table.insert(body, 'local mi=math.lerpInvSat(i,from,to)')
      end
      if anyDelay then
        table.insert(body, 'local fi=frameIndex%%100\
 circular[i*100+fi]=c\
 local co=circular[i*100+(fi+100-(%s)*30)%%100]\
 if co~=0 then c=co end' % (anyAcross and 'math.lerp(tweaks.delay or 0,tweaks.delay2 or tweaks.delay or 0,mi)' or 'tweaks.delay or 0'))
      end
      table.insert(body, 'local r,g,b=bit.band(c,255),bit.band(bit.rshift(c,8),255),bit.band(bit.rshift(c,16),255)')
      local round = false
      if (tweaks.saturation or 1) ~= 1 then
        table.insert(body, 'local sa,avg=tweaks.saturation or 1,(r+g+b)/3\
 r,g,b=math.clamp(avg+(r-avg)*sa,0,255),math.clamp(avg+(g-avg)*sa,0,255),math.clamp(avg+(b-avg)*sa,0,255)')
        round = true
      end
      if (tweaks.gamma or 1) ~= 1 then
        if (tweaks.brightness or 1) ~= 1 then
          table.insert(body, 'local br,ga=(tweaks.brightness or 1)/255,tweaks.gamma or 1\
 r,g,b=math.pow(math.min(r*br,1),ga)*255,math.pow(math.min(g*br,1),ga)*255,math.pow(math.min(b*br,1),ga)*255')
        else
          table.insert(body, 'local ga=tweaks.gamma or 1\nr,g,b=fns.gamma(r,ga),fns.gamma(g,ga),fns.gamma(b,ga)')
        end
        round = true
      elseif (tweaks.brightness or 1) ~= 1 then
        table.insert(body, 'local br=tweaks.brightness or 1\nr,g,b=math.min(r*br,255),math.min(g*br,255),math.min(b*br,255)')
        round = true
      end
      if round then
        table.insert(body, 'r,g,b=math.floor(r+0.5),math.floor(g+0.5),math.floor(b+0.5)')
      end
      if anySmoothing then
        table.insert(body, 'local c2=p[i]\
 local t,r2,g2,b2=(%s),bit.band(c2,255),bit.band(bit.rshift(c2,8),255),bit.band(bit.rshift(c2,16),255)\
 r,g,b=fns.lerp1Encoded(r2,r,t),fns.lerp1Encoded(g2,g,t),fns.lerp1Encoded(b2,b,t)' % (
        anyAcross and 'math.lerp(tweaks.smoothing or 1,tweaks.smoothing2 or tweaks.smoothing or 1,mi)' or 'tweaks.smoothing or 1'))
      end
      body[#body + 1] = 'n[i]=r+g*256+b*(256*256)+(256*256*256) end'
      ret = createFunction({ 'n', 'p', 'from', 'to', 'tweaks', 'fns', 'frameIndex', 'circular' }, table.unpack(body))
    end
    fns[key] = ret
  end
  return ret
end

local fnFns = {lerp1Encoded = lerp1Encoded, gamma = function (v, ga) return math.pow(v/255,ga)*255 end}

---@param tweaks OpenRGB.Tweaks?
function _device:tweaks(tweaks, from, count)
  if tweaks then
    if from == nil then
      from, count = 0, self._ledsCount
    elseif count == nil then
      from, count = self.zones[from].ledsStart, self.zones[from].ledsCount
    end
    local to = math.min(from + count - 1, self._ledsCount - 1)
    local n, p = self._connect.colors[self._next], self._connect.colors[self._connect.frame]
    getTweaksFn(tweaks, to > from)(n, p, from, to, tweaks, fnFns, self._frames, self._circular.values)
  end
  return self
end

local emptyTweaks = {}

local function fillColor(dst, from, to, color)
  for i = from, to do
    dst[i] = color
  end
end

local function fillPartial(dst, from, partial, to, color, colorBack)
  for i = from, partial do
    dst[i] = color
  end
  for i = partial + 1, to do
    dst[i] = colorBack
  end
end

local function splitPoint(from, to, progress)
  if not progress or progress > 1 then return to end
  ac.debug('r', progress)
  return math.ceil(math.lerp(from, to, progress)) - 1
end

---@return integer
local function encS(colorComplex)
  local col = colorComplex.main
  if colorComplex.alt1 and col == rgb.colors.black then col = colorComplex.alt1 end
  if colorComplex.alt2 and col == rgb.colors.black then col = colorComplex.alt2 end
  return encR(col)
end

local fillIndirect_dst
local fillIndirect_map
local fillIndirect = setmetatable({}, {
  __index = function (t, k)
    return fillIndirect_dst[fillIndirect_map[k]]
  end,
  __newindex = function (t, k, v)
    fillIndirect_dst[fillIndirect_map[k]] = v
  end
})

local fillIndirect_src
local fillIndirectPrev = setmetatable({}, {
  __index = function (t, k)
    return fillIndirect_src[fillIndirect_map[k]]
  end
})

local fillIndirect_circular
local fillIndirectCircular = setmetatable({}, {
  __index = function (t, k)
    k = fillIndirect_map[math.floor(k / 100)] + k % 100
    return fillIndirect_circular[k]
  end,
  __newindex = function (t, k, v)
    k = fillIndirect_map[math.floor(k / 100)] + k % 100
    fillIndirect_circular[k] = v
  end
})

---@param c nil|rgb|{main: rgb, alt1: rgb?, alt2: rgb?, progress: number}
---@param from nil|integer|integer[] @1-based zone index, 0-based index of starting LED or an array of 0-based LED indices.
---@param count integer? @If not set, `from` is 1-based zone index.
---@param tweaks OpenRGB.Tweaks?
---@return self
function _device:fill(c, from, count, tweaks)
  tweaks = tweaks or emptyTweaks
  local con = self._connect
  local dst
  if type(from) == 'table' then
    fillIndirect_dst = con.colors[self._next]
    fillIndirect_map = from
    dst = fillIndirect
    from, count = 1, #from
  else
    dst = con.colors[self._next]
    if from == nil then
      from, count = 0, self._ledsCount
    elseif count == nil then
      from, count = self.zones[from].ledsStart, self.zones[from].ledsCount
    end
  end
  local to = math.min(from + count - 1, self._ledsCount - 1)
  if type(c) == 'table' then
    if from == to then
      dst[from] = encS(c)
    else
      local spl = splitPoint(from, to, tweaks.partialCoverage and c.progress)
      local colBg = spl < to and tweaks.backgroundColor and encR(tweaks.backgroundColor) or COLOR_BLACK
      if tweaks.singleColor then
        fillPartial(dst, from, spl, to, encS(c), colBg)
      elseif c.alt2 and to > from + 1 then
        for i = from, spl do
          local j = (i - from) / (to - from)
          dst[i] = j > 0.5 and encL(c.main, c.alt2, (j * 2 - 1) ^ 2) or encL(c.main, c.alt1, (1 - j * 2) ^ 2)
        end
        fillColor(dst, spl + 1, to, colBg)
      elseif c.alt1 and c.main ~= c.alt1 then
        for i = from, spl do
          dst[i] = encL(c.main, c.alt1, ((i - from) / (to - from)) ^ 2)
        end
        fillColor(dst, spl + 1, to, colBg)
      else
        fillPartial(dst, from, spl, to, encR(c.main), colBg)
      end
    end
  elseif rgb.isrgb(c) then
    ---@cast c rgb
    fillColor(dst, from, to, encR(c))
  end
  if tweaks ~= emptyTweaks then
    local prev, circular
    if dst == fillIndirect then
      fillIndirect_src = con.colors[con.frame]
      fillIndirect_circular = self._circular.values
      prev, circular = fillIndirectPrev, fillIndirectCircular
    else
      prev, circular = con.colors[con.frame], self._circular.values
    end
    getTweaksFn(tweaks, to > from)(dst, prev, from, to, tweaks, fnFns, self._frames, circular)
  end
  self._changed = true
  return self
end

function _device:commit()
  if self._changed then
    self._changed = false
    local any = false
    local n, p = self._connect.colors[self._next], self._connect.colors[self._connect.frame]
    for i = 0, self._ledsCount - 1 do
      any = any or n[i] ~= p[i]
    end
    if any then
      ac.memoryBarrier()
      self._connect.frame = self._next
      self._next = (self._next + 1) % 4
    end
    self._frames = self._frames + 1
  end
  return self
end

local _device_mt = { __index = _device }

ac.onSharedEvent('.csp.openrgb.cb', function(data)
  if type(data) == 'table' and data.phase == phase then
    if data.payload then
      devices = data.payload
      for _, s in ipairs(devices) do
        s.uuid = s.name .. '/' .. s.index
        s._connect = connectDevice(phase, s)
        s._ledsCount = #s.colors
        s._circular = ac.StructItem.build({ values = ac.StructItem.array(ac.StructItem.uint32(), s._ledsCount * 100) })
        s._next = 1
        s._frames = 0
        s._changed = false
        s._zoneStart = {}
        local j = 0
        for _, v in ipairs(s.zones) do
          v.ledsStart, j = j, j + v.ledsCount
        end
        setmetatable(s, _device_mt)
      end
    elseif data.status then
      status = data.status
    end
  end
end)

---Start OpenRGB client (and, optionally, server).
---@param params {host: string?, port: integer?, name: string?, exe: nil|'linked'|'keep-alive'}
function openrgb.init(params)
  phase = math.randomKey()
  devices = nil
  status = 'Loading…'
  ac.startBackgroundWorker(package.relative('openrgb'),
    table.assign({}, params, { phase = phase }),
    function(err)
      print('worker is finished', err)
      devices = nil
      status = 'Disconnected, reconnecting in a bit…'
      setTimeout(function()
        openrgb.init(params)
      end, 1)
    end)
end

function openrgb.ready()
  return devices ~= nil
end

---@return string?
function openrgb.status()
  return status
end

---@return OpenRGB.Device[]?
function openrgb.devices()
  return devices
end

---@param index integer
---@return OpenRGB.Device?
function openrgb.device(index)
  return devices and devices[index]
end

return openrgb
