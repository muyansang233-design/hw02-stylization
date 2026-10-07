#ifndef PAINT_RING_STAMPS_INCLUDED
#define PAINT_RING_STAMPS_INCLUDED

#include "PaintPoissonDisk.hlsl"
#include "Includes/LightingHelp.hlsl"

// Match the graph's signed main-light value and additional-light lift.
// Thresholds/ramps are shared with its ComputeAdditionalLighting node.
float PaintRingLightingValue(float3 positionWS, float3 normalWS,
    float2 thresholds, float3 ramps)
{
    float3 color, direction, additionalColor;
    float distanceAtten, shadowAtten, additionalDiffuse;
    GetMainLight_float(positionWS, color, direction, distanceAtten, shadowAtten);
    ComputeAdditionalLighting_float(positionWS, normalWS, thresholds, ramps,
        additionalColor, additionalDiffuse);
    float mainValue = lerp(-1.0, dot(normalWS, direction), saturate(distanceAtten * shadowAtten));
    return min(mainValue + 2.0 * dot(additionalColor, float3(0.2126, 0.7152, 0.0722)), 1.0);
}

// Fragment-only. All shadow rings use the same total-light boundary test:
// a dark-side center with at least one brighter neighbor across Boundary.
// Width controls the spatial probe radius. Position/normal are local surface
// approximations, not a mesh raycast or a global color bake.
void PaintRingStampsColors_float(float2 UV, float3 WorldPosition, float3 WorldNormal,
    float Boundary, float Width, float Density, float BrushSize, float ShadowStrength,
    float2 AdditionalThresholds, float3 AdditionalRamps,
    Texture2D Brush, SamplerState BrushSampler,
    out float Mask, out float ColorMix)
{
    Mask = 0.0;
    ColorMix = 0.0;
    // Evaluate derivatives before runtime branches and loops.
    float2 ux = ddx(UV), uy = ddy(UV);
    float3 px = ddx(WorldPosition), py = ddy(WorldPosition);
    float3 nx = ddx(WorldNormal), ny = ddy(WorldNormal);
    float determinant = ux.x * uy.y - ux.y * uy.x;
    float determinantScale = sqrt(dot(ux, ux) * dot(uy, uy));
    if (Width <= 0.0 || Density <= 0.0 || BrushSize <= 0.0 || ShadowStrength <= 0.0 ||
        abs(determinant) <= max(1e-20, determinantScale * 1e-4))
        return;

    float3 dPdu = (px * uy.y - py * ux.y) / determinant;
    float3 dPdv = (py * ux.x - px * uy.x) / determinant;
    float3 dNdu = (nx * uy.y - ny * ux.y) / determinant;
    float3 dNdv = (ny * ux.x - nx * uy.x) / determinant;
    float size = clamp(BrushSize, 0.0001, 2.0);
    float radius = Width * size / Density;
    float3 offsetU = dPdu * radius, offsetV = dPdv * radius;
    float3 normalU = dNdu * radius, normalV = dNdv * radius;
    float footprint = max(length(dPdu), length(dPdv)) * size / Density;
#ifdef SHADERGRAPH_PREVIEW
    float3 lightDirection = normalize(float3(0.5, 0.5, 0));
#else
    float3 lightDirection = SafeNormalize(_MainLightPosition.xyz);
#endif
    float3 projectionBias = lightDirection * footprint * 0.25;
    const float seed = 2.0;
    float2 shift = float2(PaintPoissonHash(seed + 17.0), PaintPoissonHash(seed + 53.0)) * 4.0;
    float2 position = frac((UV * Density + shift) / 4.0) * 4.0;
    float2 dx = ux * Density / size, dy = uy * Density / size;

    [loop]
    for (int i = 0; i < PAINT_POISSON_SET0_SIZE; ++i)
    {
        float2 delta = position - PaintPoissonPoints0[i];
        delta -= floor(delta / 4.0 + 0.5) * 4.0;
        float angle = (PaintPoissonHash((float)i + seed * 101.0 + 7.0) * 2.0 - 1.0) * 0.5235987756;
        float sn, cs;
        sincos(angle, sn, cs);
        float2 brushUV = float2(cs * delta.x - sn * delta.y, sn * delta.x + cs * delta.y) / size + 0.5;
        if (any(brushUV < 0.0) || any(brushUV > 1.0))
            continue;
        float2 brushDx = float2(cs * dx.x - sn * dx.y, sn * dx.x + cs * dx.y);
        float2 brushDy = float2(cs * dy.x - sn * dy.y, sn * dy.x + cs * dy.y);
        float stamp = saturate(1.0 - SAMPLE_TEXTURE2D_GRAD(Brush, BrushSampler, brushUV, brushDx, brushDy).r);
        if (stamp <= 0.0)
            continue;

        float2 centerOffset = delta / Density;
        float3 centerWS = WorldPosition - dPdu * centerOffset.x - dPdv * centerOffset.y + projectionBias;
        float3 centerNormal = WorldNormal - dNdu * centerOffset.x - dNdv * centerOffset.y;
        float centerValue = PaintRingLightingValue(centerWS, SafeNormalize(centerNormal),
            AdditionalThresholds, AdditionalRamps);
        if (centerValue > Boundary)
            continue;

        // Surface shading, attenuation and additional lights all participate
        // in this one test. There is no separate shadowmap-edge branch.
        float brightestValue = PaintRingLightingValue(centerWS + offsetU, SafeNormalize(centerNormal + normalU),
            AdditionalThresholds, AdditionalRamps);
        brightestValue = max(brightestValue, PaintRingLightingValue(centerWS - offsetU, SafeNormalize(centerNormal - normalU),
            AdditionalThresholds, AdditionalRamps));
        brightestValue = max(brightestValue, PaintRingLightingValue(centerWS + offsetV, SafeNormalize(centerNormal + normalV),
            AdditionalThresholds, AdditionalRamps));
        brightestValue = max(brightestValue, PaintRingLightingValue(centerWS - offsetV, SafeNormalize(centerNormal - normalV),
            AdditionalThresholds, AdditionalRamps));
        if (brightestValue <= Boundary)
            continue;

        // Keep the whole stamp and a stable analogous-color choice per center.
        float choice = step(0.5, PaintPoissonHash((float)i + seed * 101.0 + 83.0));
        ColorMix = ColorMix * (1.0 - stamp) + choice * stamp;
        Mask = 1.0 - (1.0 - Mask) * (1.0 - stamp);
    }
    ColorMix = Mask > 0.000001 ? saturate(ColorMix / Mask) : 0.0;
    // Strength fades every ring uniformly without changing the chosen colors.
    Mask *= saturate(ShadowStrength);
}

void PaintRingStampsColors_float(float2 UV, float3 WorldPosition, float3 WorldNormal,
    float Boundary, float Width, float Density, float BrushSize, float ShadowStrength,
    float2 AdditionalThresholds, float3 AdditionalRamps,
    UnityTexture2D Brush, UnitySamplerState BrushSampler,
    out float Mask, out float ColorMix)
{
    PaintRingStampsColors_float(UV, WorldPosition, WorldNormal, Boundary, Width, Density,
        BrushSize, ShadowStrength, AdditionalThresholds, AdditionalRamps,
        Brush.tex, BrushSampler.samplerstate, Mask, ColorMix);
}

#endif
