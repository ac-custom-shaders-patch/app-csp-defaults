web.get(require('Config').endpoint..'/count?carID='..string.urlEncode(ac.getCarID(0)), function (err, response)
  local c = not err and response.status < 400 and tonumber(JSON.parse(response.body).count)
  if c then
    ac.setWindowIcon('main', ui.ExtraCanvas(64, 4):update(function (dt)
      ui.beginPremultipliedAlphaTexture()
      ui.drawImage('icon.png', 0, 64)
      ui.beginSubtraction()
      ui.drawRectFilled(vec2(28, 26), vec2(50, 46), rgbm.colors.white)
      ui.endSubtraction()
      ui.pushDWriteFont('@System;Weight=Bold')
      ui.dwriteDrawTextClipped(c > 99 and '99+' or c, c > 99 and 18 or 22, vec2(15, 6), 64, ui.Alignment.Center, ui.Alignment.Center)
      ui.popDWriteFont()
      ui.endPremultipliedAlphaTexture()
    end))
  end
  exit()
end)
