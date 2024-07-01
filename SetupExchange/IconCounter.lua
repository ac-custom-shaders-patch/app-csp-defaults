web.get(require('Config').endpoint..'/count?carID='..string.urlEncode(ac.getCarID(0)), function (err, response)
  if not err then
    local c = JSON.parse(response.body).count
    ac.log('Available setups: %d' % c)
    local i = ui.ExtraCanvas(64)
    i:copyFrom('icon.png')
    i:update(function (dt)
      ui.beginSubtraction()
      ui.drawRectFilled(vec2(28, 26), vec2(48, 46), rgbm.colors.white)
      ui.endSubtraction()
      ui.pushDWriteFont('@System;Weight=Bold')
      ui.dwriteDrawTextClipped(math.min(c, 99), 22, vec2(15, 6), 64, ui.Alignment.Center, ui.Alignment.Center)
      ui.popDWriteFont()
    end)
    ac.setWindowIcon('main', i)
  end
  exit()
end)
