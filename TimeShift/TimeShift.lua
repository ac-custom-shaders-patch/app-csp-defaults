local MAX_STATES = const(5000)
local RECORD_FREQUENCY = const(5)
local REWIND_SPEED = const(5)

local states = {}
local rewindAmount = 0
local lastRewind = 0

local sim = ac.getSim()
local rewindButton = ac.ControlButton('__APP_TIMESHIFT_REWIND')

setInterval(function ()
  if sim.isReplayActive or sim.isPaused or rewindAmount > 0 then
    return
  end
  ac.saveCarStateAsync(function (err, data)
    if not data or rewindAmount > 0 then return end
    if #states >= MAX_STATES then table.remove(states, 1) end
    states[#states + 1] = data
  end)
end, 1 / RECORD_FREQUENCY)

ac.onCarJumped(0, function ()
  if os.preciseClock() > lastRewind + 1 then
    table.clear(states)
  end
end)

function script.update(dt)
  if rewindButton:down() and not sim.isReplayActive and not sim.isPaused then
    rewindAmount = rewindAmount + REWIND_SPEED * RECORD_FREQUENCY * dt
    lastRewind = os.preciseClock()
    local timePoint = math.max(1, #states - rewindAmount)
    local state0 = states[math.floor(timePoint)]
    local state1 = states[math.min(math.floor(timePoint) + 1, #states)]
    ac.loadCarState(state0, state1, timePoint - math.floor(timePoint), 30)
  elseif rewindAmount > 0 then
    states = table.slice(states, 1, math.max(1, math.floor(#states - rewindAmount)))
    rewindAmount = 0
  end
end

function script.windowMain(dt)
  if not ac.isCarResetAllowed() then
    ui.text('Not available in this race:')
    ui.alignTextToFramePadding()
    ui.text('Try a single-car offline practice session.')
  elseif rewindAmount > 0 then
    ui.text('Rewinding:')
    ui.progressBar(rewindAmount / #states, vec2(-0.1, 0), '%.1f s' % (rewindAmount / RECORD_FREQUENCY))
  else
    ui.text('Recorded: %s/%s (%.1f KB)' % {#states, MAX_STATES, table.reduce(states, 0, function (d, i) return d + #i end) / 1024})
    ui.alignTextToFramePadding()
    ui.text('Rewind key:')
    ui.sameLine(100)
    rewindButton:control(vec2(-0.1, 0))
  end
end
