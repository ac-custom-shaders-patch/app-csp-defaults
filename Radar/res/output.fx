float4 main(PS_IN pin) {
  float2 r = pin.Tex * 2 - 1;
  r = sign(r) * max(0, abs(r) * 4 - 3);
  float v = 1 - dot(r, r);
  float4 t = txImage.Sample(samLinearSimple, pin.Tex);

  float4 n0 = txImage.Sample(samLinearSimple, pin.Tex, int2(0, 3));
  t.rgb = lerp(n0.rgb, t.rgb, saturate(t.w * 4 - 2));

  // t.rgb /= t.w;
  float o = txImage.Sample(samLinearBorder0, pin.Tex + float2(0.008, -0.006)).w;
  t.w = max(t.w, o * 0.2 * v);
  t.w = min(t.w, v) * gAlpha;
  return t;
  // return float4(pin.Tex, 0, 1) * v;
}