float4 main(PS_IN pin) {
  float2 r = (pin.PosH.xy * gSize - 1);
  float v = 1 - dot(r, r);
  return float4(0, 0, 0, (pow(saturate(max(pin.Tex.x, 1 - pin.Tex.x) * 8 - 7), 2) * 0.2) * saturate(smoothstep(0, 1, v)));
}