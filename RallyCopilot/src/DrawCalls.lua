local u0 = vec2()
local u1 = vec2()

local DrawCalls = {
  EditorIcon = {
    p1 = u0, p2 = u1,
    blendMode = render.BlendMode.BlendAccurate, 
    directValuesExchange = true,
    cacheKey = 1,
    textures = {txIcon = 'res/icons/type-turn-right.png', txOverlay = 'color::#00000000'},
    values = {gColor = rgb(1, 0.5, 0), gHovered = 0},
    shader = [[
      float4 main(PS_IN pin) {
        pin.Tex = pin.Tex * float2(1, 1) * 1.8 - 0.4;
        float2 texNrm = pin.Tex * 2 - 1;
        if (abs(texNrm.x) < 0.4 && texNrm.y > 0 && gHovered >= 0) texNrm.y -= 0.6 - abs(texNrm.x) * 1.5;
        float2 texRem = max(0, abs(texNrm) * 10 - 9);
        float texRemL = length(texRem);
        if (texRemL > 3 + 1.5 * saturate(gHovered)) discard;
        float alp = 1;
        alp *= saturate((3 + 1.5 * saturate(gHovered) - texRemL) * 2);
        float4 tx = txIcon.SampleBias(samLinearBorder0, pin.Tex, -0.5);
        float4 txOv = txOverlay.SampleBias(samLinearBorder0, pin.Tex * 0.84 + 0.08, -0.5);
        tx = lerp(tx, txOv, txOv.w);
        float4 bg = float4(gColor, 1);
        bg.rgb = lerp(bg.rgb, tx.rgb, tx.w) * 1;
        bg.w = alp;
        if (texRemL > 3) {
          float3 outline;
          if (gHovered == 1) outline = float4(0, 1, 1, alp).xyz;
          else outline = float4(1, 1, 1, alp).xyz;
          bg.rgb = lerp(bg.rgb, outline, saturate((texRemL - 3) * 2));
        }
        return bg;
      }
    ]]
  },
  HUDIcon = {
    p1 = vec2(), p2 = vec2(),
    blendMode = render.BlendMode.BlendAccurate, 
    directValuesExchange = true,
    cacheKey = 1,
    textures = {txIcon = 'res/icons/type-turn-right.png', txOverlay = 'color::#00000000'},
    values = {gColor = rgb(1, 0.5, 0), gAlpha = 1, gFadeFront = 1, gFadeAt = 0},
    shader = [[
      float4 main(PS_IN pin) {
        pin.Tex = pin.Tex * float2(1, 1) * lerp(2.2, 1.8, gFadeFront) - lerp(0.6, 0.4, gFadeFront);
        float2 texNrm = pin.Tex * 2 - 1;
        float2 texRem = max(0, abs(texNrm) * 10 - 9);
        float texRemL = max(texRem.x, texRem.y); // length(texRem);
        if (texRemL > 3) discard;
        float4 tx = txIcon.SampleBias(samLinearBorder0, pin.Tex, -0.5);
        float4 txOv = txOverlay.SampleBias(samLinearBorder0, pin.Tex * 0.84 + 0.08, -0.5);
        tx = lerp(tx, txOv, txOv.w);
        float4 bg = float4(gColor, 1);
        bg.rgb = lerp(bg.rgb, tx.rgb, tx.w) * lerp(0.8, 1, gFadeFront);
        bg.w = gAlpha;// * saturate(-(texRemL - 3) * 2);
        if (pin.PosH.x > gFadeAt) {
          bg.w *= saturate(1 - (pin.PosH.x - gFadeAt) / 10);
        }
        return bg;
      }
    ]]
  }, 
  EditorPointOnTrack = {
    pos = vec3(),
    width = 10,
    height = 20,
    up = vec3(0, 1, 0),
    directValuesExchange = true,
    cacheKey = 1,
    textures = {txIcon = '', txOverlay = 'color::#00000000'},
    values = {gColor = rgb(), gAlpha = 1, gHovered = 0, gFlipped = 0},
    shader = [[
      float4 main(PS_IN pin) {
        clip(0.5 - pin.Tex.y);
        if (!gFlipped) pin.Tex.x = 1 - pin.Tex.x;
        pin.Tex = pin.Tex * float2(1, 2) * 1.8 - 0.4;
        float2 texNrm = pin.Tex * 2 - 1;
        if (abs(texNrm.x) < 0.4 && texNrm.y > 0) texNrm.y -= 0.6 - abs(texNrm.x) * 1.5;
        float2 texRem = max(0, abs(texNrm) * 10 - 9);
        float alp = gAlpha;
        alp *= saturate((3 + 2 * saturate(gHovered) - length(texRem)) * 3);
        if (!alp) discard;
        float4 tx = txIcon.SampleBias(samLinearBorder0, pin.Tex, -0.5);
        float4 txOv = txOverlay.SampleBias(samLinearBorder0, pin.Tex * 0.84 + 0.08, -0.5);
        tx = lerp(tx, txOv, txOv.w);
        float4 bg = float4(pow(max(0, gColor), USE_LINEAR_COLOR_SPACE ? 2.2 : 1), 1);
        bg.rgb = lerp(bg.rgb, tx.rgb, tx.w) * (3 * gWhiteRefPoint);
        bg.w = alp;
        if (length(texRem) > 3) {
          float3 outline;
          if (gHovered == 1) outline = float4(0, gWhiteRefPoint * 3, gWhiteRefPoint * 3, alp).xyz;
          else outline = float4((gWhiteRefPoint).xxx * 3, alp).xyz;
          bg.rgb = lerp(bg.rgb, outline, saturate((length(texRem) - 3) * 2));
        }
        return bg;
      }
    ]]
  },
  GamePointOnTrack = {
    p1 = vec3(), p2 = vec3(), p3 = vec3(), p4 = vec3(),
    directValuesExchange = true,
    cacheKey = 1,
    textures = {txIcon = '', txOverlay = 'color::#00000000'},
    values = {gColor = rgb(), gAlpha = 1},
    shader = [[
      float4 main(PS_IN pin) {
        pin.Tex.x = 1 - pin.Tex.x;
        pin.Tex = pin.Tex * 1.8 - 0.4;
        float2 texNrm = pin.Tex * 2 - 1;
        float2 texRem = max(0, abs(texNrm) * 10 - 9);
        float texRemL = max(texRem.x, texRem.y); // length(texRem);
        if (texRemL > 3) discard;
        float4 tx = txIcon.SampleBias(samLinearBorder0, pin.Tex, -0.5);
        float4 txOv = txOverlay.SampleBias(samLinearBorder0, pin.Tex * 0.84 + 0.08, -0.5);
        if (any(abs(pin.Tex * 2 - 1) > 1)) tx = 0;
        tx = lerp(tx, txOv, txOv.w);
        float4 bg = float4(pow(max(0, gColor), USE_LINEAR_COLOR_SPACE ? 2.2 : 1), 1);
        bg.rgb = lerp(bg.rgb, tx.rgb, tx.w) * (3 * gWhiteRefPoint);
        bg.w = gAlpha * saturate((3 - texRemL) * 5);
        return pin.ApplyFog(bg);
      }
    ]]
  },
  TrackSpline = {
    mesh = ac.SimpleMesh.trackLine(0, 0.5),
    textures = {},
    values = {gColor = rgbm(), gTrackLength = ac.getSim().trackLengthM},
    -- shader = 'float4 main(PS_IN pin) {return float4(, 1); }'
    shader = [[
      float4 main(PS_IN pin) {
        float3 col = pow(max(0, gColor.rgb), USE_LINEAR_COLOR_SPACE ? 2.2 : 1);
        uint id = (uint)round(pin.Tex.y * gTrackLength / gWidth / 4);
        if (id % 4 == 0) {
          float sec = 1 - frac(pin.Tex.y * gTrackLength / gWidth / 4);
          float alp = saturate((sec * 2.5 - 1.5 - abs(pin.Tex.x * 2 - 1) * 1.2) * 100);
          if (sec < 0.2 && abs(pin.Tex.x * 2 - 1) < 0.3) alp = 1;
          col = lerp(col, 1, alp);
        }
        return float4(3 * gWhiteRefPoint * col, 1); 
      }
    ]]
  }
}

return DrawCalls