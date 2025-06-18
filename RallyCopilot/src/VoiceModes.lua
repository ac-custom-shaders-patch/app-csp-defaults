local VoiceMode = require('src/VoiceMode')
local RouteItemType = require('src/RouteItemType')
local RouteItemHint = require('src/RouteItemHint')

local VoiceModes = {}

do
  local numHelpers = 2
  local numTurns = numHelpers + 12
  local numStraights = numTurns + 10
  local numHints = numStraights + 9
  local numMiscs = numHints + 5
  local numOn = numMiscs + 4

  VoiceModes.merged = VoiceMode({
    'Helper/And',
    'Helper/On',

    'Left/Hairpin',
    'Left/Two',
    'Left/Three',
    'Left/Four',
    'Left/Five',
    'Left/Six',
    'Right/Hairpin',
    'Right/Two',
    'Right/Three',
    'Right/Four',
    'Right/Five',
    'Right/Six',

    'Straight/20 m',
    'Straight/30 m',
    'Straight/40 m',
    'Straight/50 m',
    'Straight/70 m',
    'Straight/100 m',
    'Straight/200 m',
    'Straight/300 m',
    'Straight/400 m',
    'Straight/500 m',

    'Hints/Cut',
    'Hints/Do not cut',
    'Hints/Long',
    'Hints/Very long',
    'Hints/Tightens',
    'Hints/Open',
    'Hints/Caution',
    'Hints/Keep left',
    'Hints/Keep right',

    'Miscellaneous/Big jump',
    'Miscellaneous/Jump',
    'Miscellaneous/Overcrest',
    'Miscellaneous/Narrows',
    'Miscellaneous/Over bridge',

    'On/Tarmac',
    'On/Gravel',
    'On/Sand',
    'On/Asphalt',

    'Extras/Finish',
    'Extras/Start/Get ready…',
    'Extras/Start/3…',
    'Extras/Start/2…',
    'Extras/Start/1…',
    'Extras/Start/Go!',
  }, function (type, modifier, hints, tags, continuation)
    if type == RouteItemType.Extra then
      return {numOn + modifier}
    end
    local ret = nil
    if type == RouteItemType.TurnLeft then
      ret = {numHelpers + modifier}
    elseif type == RouteItemType.TurnRight then
      ret = {numHelpers + 6 + modifier}
    elseif type == RouteItemType.KeepLeft then
      ret = {numStraights + 8}
    elseif type == RouteItemType.KeepRight then
      ret = {numStraights + 9}
    elseif type == RouteItemType.Straight then
      ret = {numTurns + modifier}
      continuation = false
    elseif type == RouteItemType.Jump then
      if modifier == 1 then
        ret = {numHints + 1}
        continuation = false
      elseif modifier == 2 then
        ret = {numHints + 2}
        continuation = false
      else
        ret = {numHints + 3}
        continuation = false
      end
    elseif type == RouteItemType.Narrows then
      ret = {numHints + 4}
      continuation = false
    elseif type == RouteItemType.OverBridge then
      ret = {numHints + 5}
      continuation = false
    elseif type == RouteItemType.SurfaceType then
      if modifier == -1 then return nil end
      ret = {numMiscs + modifier}
      continuation = false
    else
      return nil
    end
    if continuation then
      table.insert(ret, 1, 1)
    end
    if #hints > 0 then
      for _, v in ipairs(hints) do
        if v == RouteItemHint.Cut then table.insert(ret, numStraights + 1) end
        if v == RouteItemHint.DoNotCut then table.insert(ret, numStraights + 2) end
        if v == RouteItemHint.Long then table.insert(ret, numStraights + 3) end
        if v == RouteItemHint.VeryLong then table.insert(ret, numStraights + 4) end
        if v == RouteItemHint.Tightens then table.insert(ret, numStraights + 5) end
        if v == RouteItemHint.Open then table.insert(ret, numStraights + 6) end
        if v == RouteItemHint.Caution then table.insert(ret, numStraights + 7) end
        if v == RouteItemHint.KeepLeft then table.insert(ret, numStraights + 8) end
        if v == RouteItemHint.KeepRight then table.insert(ret, numStraights + 9) end
      end
    end
    return ret
  end, function (phraseIndex)
    if phraseIndex <= numHelpers then
      return ui.Icons.Link
    end
    if phraseIndex <= numHelpers + 6 then
      return RouteItemType.icon(RouteItemType.TurnLeft, phraseIndex - numHelpers, nil, true)
    end
    if phraseIndex <= numTurns then
      return RouteItemType.icon(RouteItemType.TurnLeft, phraseIndex - (numHelpers + 6), nil, true)
    end
    if phraseIndex == numStraights + 8 then
      return RouteItemType.icon(RouteItemType.KeepLeft, nil, nil, true)
    end
    if phraseIndex == numStraights + 9 then
      return RouteItemType.icon(RouteItemType.KeepRight, nil, nil, true)
    end
    if phraseIndex <= numStraights then
      return RouteItemType.icon(RouteItemType.Straight, phraseIndex - 14, nil, true)
    end
    if phraseIndex <= numHints then
      return ui.Icons.Info
    end
    if phraseIndex == numHints + 1 then
      return RouteItemType.icon(RouteItemType.Jump, 1, nil, true)
    end
    if phraseIndex == numHints + 2 then
      return RouteItemType.icon(RouteItemType.Jump, 2, nil, true)
    end
    if phraseIndex == numHints + 3 then
      return RouteItemType.icon(RouteItemType.Jump, 3, nil, true)
    end
    if phraseIndex == numHints + 4 then
      return RouteItemType.icon(RouteItemType.Narrows, nil, nil, true)
    end
    if phraseIndex == numHints + 5 then
      return RouteItemType.icon(RouteItemType.OverBridge, nil, nil, true)
    end
    if phraseIndex > numOn then
      return ui.Icons.Info
    end
    if phraseIndex > numMiscs - 1 then
      return RouteItemType.icon(RouteItemType.SurfaceType, phraseIndex - (numMiscs - 1), nil, true)
    end
    return ui.Icons.Road
  end, function (phraseIndex)
    return phraseIndex <= numOn
  end)
end

do
  local numHelpers = 2
  local numTurns = numHelpers + 2
  local numCautions = numTurns + 6
  local numHints = numCautions + 8
  local numStraights = numHints + 10
  local numMiscs = numStraights + 5
  local numSurfaceTypes = numMiscs + 4

  VoiceModes.separated = VoiceMode({
    'Helper/And',
    'Helper/On',

    'Turn/Left',
    'Turn/Right',

    'Caution/One',
    'Caution/Two',
    'Caution/Three',
    'Caution/Four',
    'Caution/Five',
    'Caution/Six',

    'Hints/Cut',
    'Hints/Do not cut',
    'Hints/Keep',
    'Hints/Long',
    'Hints/Very long',
    'Hints/Tightens',
    'Hints/Open',
    'Hints/Caution',

    'Straight/20 m',
    'Straight/30 m',
    'Straight/40 m',
    'Straight/50 m',
    'Straight/70 m',
    'Straight/100 m',
    'Straight/200 m',
    'Straight/300 m',
    'Straight/400 m',
    'Straight/500 m',

    'Miscellaneous/Big jump',
    'Miscellaneous/Jump',
    'Miscellaneous/Overcrest',
    'Miscellaneous/Narrows',
    'Miscellaneous/Over bridge',

    'Surface type/Tarmac',
    'Surface type/Gravel',
    'Surface type/Sand',
    'Surface type/Asphalt',

    'Extras/Finish',
    'Extras/Start/Get ready…',
    'Extras/Start/3…',
    'Extras/Start/2…',
    'Extras/Start/1…',
    'Extras/Start/Go!',
  }, function (type, modifier, hints, tags, continuation)
    if type == RouteItemType.Extra then
      return {numSurfaceTypes + modifier}
    end
    local ret = nil
    if type == RouteItemType.TurnLeft then
      ret = {numTurns + modifier, numHelpers + 1}
    elseif type == RouteItemType.TurnRight then
      ret = {numTurns + modifier, numHelpers + 2}
    elseif type == RouteItemType.KeepLeft then
      ret = {numCautions + 3, numHelpers + 1}
    elseif type == RouteItemType.KeepRight then
      ret = {numCautions + 3, numHelpers + 2}
    elseif type == RouteItemType.Straight then
      ret = {numHints + modifier}
      continuation = false
    elseif type == RouteItemType.Jump then
      if modifier == 1 then
        ret = {numStraights + 1}
        continuation = false
      elseif modifier == 2 then
        ret = {numStraights + 2}
        continuation = false
      else
        ret = {numStraights + 3}
        continuation = false
      end
    elseif type == RouteItemType.Narrows then
      ret = {numStraights + 4}
      continuation = false
    elseif type == RouteItemType.OverBridge then
      ret = {numStraights + 5}
      continuation = false
    elseif type == RouteItemType.SurfaceType then
      if modifier == -1 then return nil end
      ret = {2, numMiscs + modifier}
      continuation = false
    else
      return nil
    end
    if continuation then
      table.insert(ret, 1, 1)
    end
    if #hints > 0 then
      for _, v in ipairs(hints) do
        if v == RouteItemHint.Cut then table.insert(ret, numCautions + 1) end
        if v == RouteItemHint.DoNotCut then table.insert(ret, numCautions + 2) end
        if v == RouteItemHint.Long then table.insert(ret, numCautions + 4) end
        if v == RouteItemHint.VeryLong then table.insert(ret, numCautions + 5) end
        if v == RouteItemHint.Tightens then table.insert(ret, numCautions + 6) end
        if v == RouteItemHint.Open then table.insert(ret, numCautions + 7) end
        if v == RouteItemHint.Caution then table.insert(ret, numCautions + 8) end
        if v == RouteItemHint.KeepLeft or v == RouteItemHint.KeepRight then
          table.insert(ret, numCautions + 3)
          table.insert(ret, v == RouteItemHint.KeepLeft and numHelpers + 1 or numHelpers + 2)
        end
      end
    end
    return ret
  end, function (phraseIndex)
    if phraseIndex <= numHelpers then
      return ui.Icons.Link
    end
    if phraseIndex <= numTurns then
      return RouteItemType.icon(phraseIndex == numHelpers + 1 and RouteItemType.TurnLeft or RouteItemType.TurnRight, nil, nil, true)
    end
    if phraseIndex <= numCautions then
      local modifier = ((phraseIndex - (numTurns + 1)) % 6) + 1
      return RouteItemType.icon(-1, modifier, nil, true)
    end
    if phraseIndex <= numHints then
      return ui.Icons.Info
    end
    if phraseIndex <= numStraights then
      return RouteItemType.icon(RouteItemType.Straight, phraseIndex - (numHints), nil, true)
    end
    if phraseIndex == numStraights + 1 then
      return RouteItemType.icon(RouteItemType.Jump, 1, nil, true)
    end
    if phraseIndex == numStraights + 2 then
      return RouteItemType.icon(RouteItemType.Jump, 2, nil, true)
    end
    if phraseIndex == numStraights + 3 then
      return RouteItemType.icon(RouteItemType.Jump, 3, nil, true)
    end
    if phraseIndex == numStraights + 4 then
      return RouteItemType.icon(RouteItemType.Narrows, nil, nil, true)
    end
    if phraseIndex == numStraights + 5 then
      return RouteItemType.icon(RouteItemType.OverBridge, nil, nil, true)
    end
    if phraseIndex > numSurfaceTypes then
      return ui.Icons.Info
    end
    if phraseIndex > numMiscs then
      return RouteItemType.icon(RouteItemType.SurfaceType, phraseIndex - numMiscs, nil, true)
    end
    return ui.Icons.Road
  end, function (phraseIndex)
    return phraseIndex <= numSurfaceTypes
  end)
end

return VoiceModes