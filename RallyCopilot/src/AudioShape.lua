local function genMip(v1, v2)
  local n1, n2 = math.abs(v1 - 127), math.abs(v2 - 127)
  if n1 < 2 and n2 < 2 then return (v1 + v2) / 2 end
  if n1 > n2 then return v1 end
  return v2
end

local AudioShape = {}
local cache = {}

local function runProcess(filename)
  local exe = ac.getFolder(ac.FolderID.ExtCache)..'/lua_apps/RallyCopilot/RallyCopilot.AudioShape.exe'
  if not io.fileExists(exe) then
    io.createFileDir(exe)
    web.get('https://acstuff.club/u/blob/ac-rallycopilot-bin-1.zip', function (err, response)
      if not err and #response.body > 10e3 then
        ---@diagnostic disable-next-line: undefined-global
        if not __util.native('_vasi', response.body) then 
          err = 'package is damaged'
          goto error
        end
        ac.log('Package is fine 👍')
        io.extractFromZipAsync(response.body, io.getParentPath(exe), nil, function (err)
          if not err then
            runProcess(filename)
          else
            ac.warn('Failed to download extra binaries to visualize audio: %s' % {err or '?'})
          end
        end)
        return
      end
      ::error::
      ac.warn('Failed to download extra binaries to visualize audio: %s' % {err or '?'})
    end)
    return
  end 
  os.runConsoleProcess({ 
    filename = exe,
    arguments = { io.getFileName(filename), '10' },
    workingDirectory = io.getParentPath(filename),
    separateStderr = true
  }, function (err, data)
    local activeShapeFrequency = tonumber(data.stderr)
    local e = cache[filename]
    if err or #data.stdout == 0 or not activeShapeFrequency then
      e.err = err or 'Data is damaged'
    else
      local shape = data.stdout
      local l1 = table.new(#shape, 0)
      for i = 1, #shape do l1[i] = string.byte(shape, i) end

      local lM = {}
      for i = 1, 12 do
        local lB = lM[#lM] or l1
        local l2 = table.new(#lB / 2, 0)
        for j = 1, #lB / 2 - 0.5 do l2[j] = genMip(lB[j * 2], lB[j * 2 + 1]) end
        lM[i] = l2
      end

      e.l1 = l1
      e.lM = lM
    end
  end)
end

---@param filename string
---@param r1 vec2
---@param r2 vec2
---@param from number
---@param to number
function AudioShape.drawGraph(filename, r1, r2, from, to)
  if not filename then
    return
  end

  local e = cache[filename]
  if not e then
    e = {}
    cache[filename] = e
    runProcess(filename)
  end

  if e.err then
    ui.drawTextClipped(e.err, r1, r2, rgbm.colors.gray, vec2(0.5, 0.5))
  elseif e.l1 then
    local l = math.clamp(math.ceil(math.log(#e.l1 / (r2.x - r1.x), 2)), 0, #e.lM)
    local lT = l == 0 and e.l1 or e.lM[l]
    local im = #lT / (r2.x - r1.x)
    local hm = (r2.y - r1.y) / 255
    for i = from, to do
      ui.pathLineTo(vec2(r1.x + i, r1.y + (lT[math.round(im * i)] or 127) * hm))
    end
    ui.pathSmoothStroke(rgbm.colors.red, false, 1)
  else
    ui.drawIcon(ui.Icons.LoadingSpinner, (r1 + r2) / 2 - 12, (r1 + r2) / 2 + 12, rgbm.colors.gray)
  end
end

return AudioShape