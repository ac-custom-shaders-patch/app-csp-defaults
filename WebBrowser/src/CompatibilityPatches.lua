--[[
  This module updates WebBrowser library, adding some methods from 0.2.7 and 0.2.8 so that app could work with older CSP builds. Feel free to
  copy it to your code if you want to target older CSPs. 
]]

local webBrowser = require('shared/web/browser')
local webUI = require('shared/web/ui')

if not webBrowser.VERSION then
  webBrowser.VERSION = 1
end

if not webUI.DefaultHandlers.onPermissionRequest then
  webUI.DefaultHandlers.onPermissionRequest = function (browser, data, callback) callback(false) end
end

if not webUI.getPermissionsSubject then
  webUI.getPermissionsSubject = function () return nil end
end

if not WebBrowser.onPermissionRequest then
  function WebBrowser:onPermissionRequest() return self end
end

if not WebBrowser.setGeolocation then
  function WebBrowser:setGeolocation() return self end
end

if not WebBrowser.adsFilter then
  function WebBrowser.adsFilter()
    return "^https://(?:(?:(?:www\\.)?(?:datadoghq-browser-agent\\.com|google(?:-analytics|tagmanager|tagservices)\\.com|fastly-insights\\.com|syndicatedsearch\\.goog|tranquilveranda\\.com)|(?:[\\w\\d-]+\\.)(?:1rx\\.io|3lift\\.com|activemetering\\.com|ad(?:nxs\\.com|safeprotected\\.com|trafficquality\\.google|s\\.linkedin\\.com|srvr\\.org)|afcdn\\.net|analytics\\.yahoo\\.com|anonymised\\.io|ay\\.delivery|bfmio\\.com|blueconic\\.net|buysellads\\.com|carbonads\\.com|casalemedia\\.com|chartbeat\\.com|clean\\.gg|cloud(?:flareinsights\\.com|front\\.net)|connatix\\.com|criteo\\.com|crwdcntrl\\.net|cxense\\.com|demdex\\.net|dmgmediaprivacy\\.co\\.uk|dns-finder\\.com|dotmetrics\\.net|double(?:click\\.net|verify\\.com)|ebxcdn\\.com|emxdgt\\.com|eyeota\\.net|fastclick\\.net|fwmrm\\.net|g\\.doubleclick\\.net|geoedge\\.be|getclicky\\.com|go-mpulse\\.net|googlesyndication\\.com|gumgum\\.com|hadronid\\.net|hotjar\\.com|indexww\\.com|imrworldwide\\.com|keywee\\.co|liadm\\.com|localiq\\.com|marketo\\.net|mopinion\\.com|nitro(?:pay\\.com|cnct\\.com)|npttech\\.com|nr-data\\.net|nxt-psh\\.com|omnitagjs\\.com|onedollarstats\\.com|onthe\\.io|openx\\.net|orbsrv\\.com|outbrain\\.com|p-n\\.io|p7cloud\\.net|parsely\\.com|pbxai\\.com|piano\\.io|privacymanager\\.io|pubmatic\\.com|quant(?:cast|count|serve)\\.com|rambler\\.ru|rfihub\\.com|rlcdn\\.com|rlets\\.com|rubiconproject\\.com|s-onetag\\.com|sail-horizon\\.com|scorecardresearch\\.com|script\\.ac|seedtag\\.com|segment\\.(?:com|io)|servenobid\\.com|sitescout\\.com|skcrtxr\\.com|skimresources\\.com|smartocto\\.com|stickyadstv\\.com|tapad\\.com|tinypass\\.com|ujscdn\\.com|userreport\\.com|viafoura\\.co|vntsm\\.com|yieldmo\\.com|wp\\.com)|(?:[\\w\\d-]+\\.)*(?:12ezo5v60\\.com|ad(?:-delivery\\.net|\\.gt|sco\\.re|blockrelief\\.com|skeeper.com|form\\.net)|amazon-adsystem\\.com|amplitude\\.com|antiadblocksystems\\.com|broadstreetads\\.com|bt(?:loader\\.com|message\\.com)|chimpstatic\\.com|fvcwqkkqmuv\\.com|googleadservices\\.com|fwmrm\\.net|hexagon-analytics\\.com|[\\w-]*id5-sync\\.com|isolatedovercomepasted\\.com|kueezrtb\\.com|media\\.net|merequartz\\.com|mmcdn\\.com|nervoussummer\\.com|ofcamerupta\\.com|omtrdc\\.net|permutive\\.(?:app|com)|pncloudfl\\.com|rackcdn\\.com|ragofkanc\\.com|rtmark\\.net|sharethis\\.com|smartadserver\\.com|sonobi\\.com|steadfastsystem\\.com|taboola\\.com|the-ozone-project\\.com|victoriousrequest\\.com|webcontentassessor\\.com|wisepops\\.com|ybs2ffs7v\\.com)|(?:imasdk|ogads-pa)\\.googleapis\\.com|bat\\.bing\\.com|cloudmetrics\\.xenforo\\.com|connect\\.facebook\\.net|ct\\.pinterest\\.com|mc\\.yandex\\.ru|iad\\.anm\\.co\\.uk|insitez\\.blob\\.core\\.windows\\.net|p\\.typekit\\.net|pixel\\.servebom\\.com|pulsar\\.ebay\\.com|strike\\.fox\\.com|webc2s\\.pubgw\\.yahoo\\.com)[:/]|www\\.google\\.com/adsense\\b|w\\w\\w\\.facebook\\.com/plugins/like\\.php|yandex\\.ru/ads|yastatic\\.net/pcode/adfox|wsknow\\.net/jssdk)"
  end
end

if not webBrowser.interactive then
  function webBrowser:interactive() return not self._loadError and not self:blank() and not self:crash() end
end

if not webBrowser.handlesLoadErrors then
  function webBrowser.handlesLoadErrors()
    return false
  end
end

if not webBrowser.devToolsTabSupported then
  function webBrowser.devToolsTabSupported()
    return true
  end
end