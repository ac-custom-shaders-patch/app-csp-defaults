--[[
  Some tests for building a simple adblock.
]]

local log = {}
local webFilter = [[
+hosts:https://adaway.org/hosts.txt
+youtube:^[\w\d_-]+\.googlevideo\.com/videoplayback?;&rn=1&;
+css:youtube\.com;#masthead-ad,#mealbar-promo-renderer,#player-ads,#shorts-inner-container>.ytd-shorts:has(>.ytd-reel-video-renderer>ytd-ad-slot-renderer),.YtdShortsSuggestedActionStaticHostContainer,.ytd-merch-shelf-renderer,.ytp-featured-product,.ytp-suggested-action>button.ytp-suggested-action-badge,ytd-ad-slot-renderer,ytd-rich-item-renderer:has(>#content>ytd-ad-slot-renderer),ytd-search-pyv-renderer
+css:m.youtube\.com;lazy-list>ad-slot-renderer,ytm-companion-slot[data-content-type]>ytm-companion-ad-renderer,ytm-rich-item-renderer>ad-slot-renderer
+subdomain:^(
  (
      datadoghq-browser-agent\.com
    | google( -analytics | tagmanager | tagservices )\.com
    | fastly-insights\.com
    | fundingchoicesmessages\.google\.com
    | ogads-pa\.googleapis\.com
    | syndicatedsearch\.google
    | tranquilveranda\.com
    )
  | [\w\d_-]+\.(
      1rx\.io
    | 3lift\.com
    | activemetering\.com
    | ad( nxs\.com | safeprotected\.com | trafficquality\.google | s\.linkedin\.com | srvr\.org )
    | afcdn\.net
    | analytics\.yahoo\.com
    | anonymised\.io
    | ay\.delivery
    | bfmio\.com
    | blueconic\.net
    | buysellads\.com
    | carbonads\.com
    | casalemedia\.com
    | chartbeat\.com
    | clean\.gg
    | cloud( flareinsights\.com | front\.net )
    | connatix\.com
    | criteo\.com
    | crwdcntrl\.net
    | cxense\.com
    | demdex\.net
    | dmgmediaprivacy\.co\.uk
    | dns-finder\.com
    | dotmetrics\.net
    | double( click\.net | verify\.com )
    | ebxcdn\.com
    | emxdgt\.com
    | eyeota\.net
    | fastclick\.net
    | fwmrm\.net
    | g\.doubleclick\.net
    | geoedge\.be
    | getclicky\.com
    | go-mpulse\.net
    | googlesyndication\.com
    | gumgum\.com
    | hadronid\.net
    | hotjar\.com
    | indexww\.com
    | imrworldwide\.com
    | keywee\.co
    | liadm\.com
    | localiq\.com
    | marketo\.net
    | mopinion\.com
    | nitro( pay\.com | cnct\.com )
    | npttech\.com
    | nr-data\.net
    | nxt-psh\.com
    | omnitagjs\.com
    | onedollarstats\.com
    | onthe\.io
    | openx\.net
    | orbsrv\.com
    | outbrain\.com
    | p-n\.io
    | p7cloud\.net
    | parsely\.com
    | pbxai\.com
    | piano\.io
    | privacymanager\.io
    | pubmatic\.com
    | quant( cast | count | serve )\.com
    | rambler\.ru
    | rfihub\.com
    | rlcdn\.com
    | rlets\.com
    | rubiconproject\.com
    | s-onetag\.com
    | sail-horizon\.com
    | scorecardresearch\.com
    | script\.ac
    | seedtag\.com
    | segment\.( com | io )
    | servenobid\.com
    | sitescout\.com
    | skcrtxr\.com
    | skimresources\.com
    | smartocto\.com
    | stickyadstv\.com
    | tapad\.com
    | tinypass\.com
    | ujscdn\.com
    | userreport\.com
    | viafoura\.co
    | vntsm\.com
    | yieldmo\.com
    | wp\.com
    )
  )$
+domain:^(
    12ezo5v60\.com
  | ad( -delivery\.net | \.gt | sco\.re | blockrelief\.com | skeeper.com | form\.net )
  | amazon-adsystem\.com
  | amplitude\.com
  | antiadblocksystems\.com
  | broadstreetads\.com
  | bt( loader\.com | message\.com )
  | chimpstatic\.com
  | fvcwqkkqmuv\.com
  | googleadservices\.com
  | fwmrm\.net
  | hexagon-analytics\.com
  | [\w-]*id5-sync\.com
  | isolatedovercomepasted\.com
  | kueezrtb\.com
  | media\.net
  | merequartz\.com
  | mmcdn\.com
  | nervoussummer\.com
  | ofcamerupta\.com
  | omtrdc\.net
  | permutive\.(?:app|com)
  | pncloudfl\.com
  | rackcdn\.com
  | ragofkanc\.com
  | rtmark\.net
  | sharethis\.com
  | smartadserver\.com
  | sonobi\.com
  | steadfastsystem\.com
  | taboola\.com
  | the-ozone-project\.com
  | tm-awx\.com
  | victoriousrequest\.com
  | webcontentassessor\.com
  | wisepops\.com
  | ybs2ffs7v\.com 
  )$
+protocoless:^(
    google\.com/adsense
  | w\w\w\.facebook\.com/plugins/like\.php
  | play\.google\.com/log
  | wsknow\.net/jssdk 
  | yandex\.ru/ads
  | yastatic\.net/pcode/adfox
  | youtube\.com/( api/stats/qoe | get_video_info | youtubei/v1/log_event )
  | ( youtube | google )\.\w+/( pagead | ptracking )
  )\b
]]

print(stringify(webFilter))

local allowed = {
  'ssl.p.jwpcdn.com',
  'entitlements.jwplayer.com',
  'polyfill.io',
  'geolocation.onetrust.com',
  'assets.adobedtm.com',
  'cdn.cookielaw.org',
  'fonts.googleapis.com',
  'fonts.gstatic.com',
  'ajax.googleapis.com',
}

return function (created)
  created:blockURLs(webFilter)
  created:collectURLs(function (browser, url, blocked) -- TODO
    if not blocked then
      local d = WebBrowser.getDomainName(browser:url())
      local u = WebBrowser.getDomainName(url)
      if d:startsWith('www.') then d = d:sub(5) end
      if not table.contains(allowed, u) and not table.contains(log, url) 
          -- and not string.find(u, d) 
          then
        table.insert(log, url) 
        io.save('D:/log.txt', table.concat(log, '\n'))
      end
      print(url)
    else
      ac.warn(url)
    end
  end)
end
