float4 main(PS_IN pin) {
  #if MODE == 3
    float4 livery = txLivery.SampleLevel(samLinearClamp, pin.Tex * float2(-gSizeX, gSizeZ) * 0.5 + 0.5, 0);
    livery.w = 1;
    livery.rgb *= pin.NormalW.y * 0.5 + 0.5;
    return lerp(0.1, 1, livery) * float4(1, 1, 1, gAlpha);
  #elif MODE == 2
    float4 livery = txLivery.SampleLevel(samLinearClamp, pin.Tex * float2(gSizeX, gSizeZ) * 0.5 + 0.5, 5.5);
    livery.w = 1;
    livery.rgb *= pin.NormalW.y * 0.5 + 0.5;
    return lerp(0.1, 1, livery) * float4(1, 1, 1, gAlpha);
  #else
    return float4(gColor * (pin.NormalW.y * 0.25 + 0.75), 1) * float4(1, 1, 1, gAlpha);
  #endif
}