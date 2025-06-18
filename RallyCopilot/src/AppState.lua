AppState = {
  exchangeTrackID = ac.getTrackFullID(':'),
  exchangeEndpoint = 'https://re.acstuff.club',
  volumeKey = 'app.RallyCopilot/Rally Copilot',
  editorActive = false,
  voicesMappedActive = false,
  notesExchangeCount = nil,
  loopingSpline = ac.trackProgressToWorldCoordinate(0):closerToThan(ac.trackProgressToWorldCoordinate(1), 10),
  connection = ac.connect({
    ac.StructItem.key('app.RallyCopilot.extras'),
    distanceToNextHint = ac.StructItem.float(),
    speechPeak = ac.StructItem.float(),
    raceState = ac.StructItem.int32(), -- 0 for regular race, 1 for preparing to a start, 2 for a rally stage, 3 for a finish
    distanceToStart = ac.StructItem.float(),
    hintsCutoffFrom = ac.StructItem.float(),
    hintsCutoffTo = ac.StructItem.float(),
    countdownState = ac.StructItem.int32(),
    finalTime = ac.StructItem.int32(),
  })
}

return AppState