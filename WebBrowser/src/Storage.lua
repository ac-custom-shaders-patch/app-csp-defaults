local settings = ac.storage{
  newTabStyle = 'd', ---@type 'd'|'b'|'c'|'p'
  customThemeColor = rgbm(),
  customThemeBlurring = 0.02,
  searchProviderID = 'ddg',
  lastDownloadDirectory = '',
  filtering = true,
  contentStyle = 0,
  integratedTabs = true,
  homeButton = true,
  bookmarksBar = false,
  doNotTrack = false,
  startupMode = 3,
  homePage = '',
  lastCloseTime = -1,
  askForDownloadsDestination = true,
  showDownloadsWhenReady = false,
  developerTools = false,
  developerToolsDock = 3,
  useCEFLoop = false, -- for older CEFs
  targetFPS = 60,
  skipProxyServer = true,
  safeMode = false, -- for older CEFs
  softwareRendering = false, -- for new CEFs only
  keepRunning = true,
  fmodAudio = true,
  savePasswords = true,
  interceptURLs = true,
  devToolsPosition = vec2(-1, -1),
  devToolsSize = vec2(640, 480),
  properFullscreen = true,
}

return {
  settings = settings,
}