#ifndef PAINT_RING_STAMPS_INCLUDED
#define PAINT_RING_STAMPS_INCLUDED

#include "PaintPoissonDisk.hlsl"
#include "Includes/LightingHelp.hlsl"

// Match the graph's signed main-light value and additional-light lift.
// Thresholds/ramps are shared with its ComputeAdditionalLighting node.
float PaintRingLightingValue(float3 positionWS, float3 normalWS,
    float2 thresholds, float3 ramps, out float occlusion)
{
    float3 color, direction, additionalColor;
    float distanceAtten, shadowAtten, additionalDiffuse;
    GetMainLight_float(positionWS, color, direction, distanceAtten, shadowAtten);
    ComputeAdditionalLighting_float(positionWS, normalWS, thresholds, ramps,
        additionalColor, additionalDiffuse);
    occlusion = saturate(1.0 - shadowAtten);
    float mainValue = lerp(-1.0, dot(normalWS, direction), saturate(distanceAtten * shadowAtten));
    return min(mainValue + 2.0 * dot(additionalColor, float3(0.2126, 0.7152, 0.0722)), 1.0);
}

// Fragment-only. Both rings share projected centers, four neighbors, spatial
// Width and full brush stamps. Position and normal are local approximations,
// not a mesh raycast or a global color bake.
void PaintRingStampsColors_float(float2 UV, float3 WorldPosition, float3 WorldNormal,
    float Boundary, float Width, float Density, float BrushSize, float ShadowStrength,
    float2 AdditionalThresholds, float3 AdditionalRamps,
    Texture2D Brush, SamplerState BrushSampler,
    out float Mask, out float ColorMix, out float ShadowRingMask, out float ShadowColorMix)
{
    Mask = 0.0;
    ColorMix = 0.0;
    ShadowRingMask = 0.0;
    ShadowColorMix = 0.0;
    // Evaluate derivatives before runtime branches and loops.
    float2 ux = ddx(UV), uy = ddy(UV);
    float3 px = ddx(WorldPosition), py = ddy(WorldPosition);
    float3 nx = ddx(WorldNormal), ny = ddy(WorldNormal);
    float determinant = ux.x * uy.y - ux.y * uy.x;
    float determinantScale = sqrt(dot(ux, ux) * dot(uy, uy));
    if (Width <= 0.0 || Density <= 0.0 || BrushSize <= 0.0 ||
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
        float centerOcclusion;
        float centerValue = PaintRingLightingValue(centerWS, SafeNormalize(centerNormal),
            AdditionalThresholds, AdditionalRamps, centerOcclusion);
        bool colorCandidate = centerValue <= Boundary;
        bool shadowCandidate = false;
#if !defined(SHADERGRAPH_PREVIEW) && defined(MAIN_LIGHT_CALCULATE_SHADOWS) && !defined(_MAIN_LIGHT_SHADOWS_SCREEN)
        shadowCandidate = ShadowStrength > 0.0 && centerOcclusion > 0.0;
#endif
        if (!colorCandidate && !shadowCandidate)
            continue;

        // Each light/shadow lookup serves both boundary tests.
        float neighborOcclusion;
        float brightestValue = PaintRingLightingValue(centerWS + offsetU, SafeNormalize(centerNormal + normalU),
            AdditionalThresholds, AdditionalRamps, neighborOcclusion);
        float leastOcclusion = neighborOcclusion;
        brightestValue = max(brightestValue, PaintRingLightingValue(centerWS - offsetU, SafeNormalize(centerNormal - normalU),
            AdditionalThresholds, AdditionalRamps, neighborOcclusion));
        leastOcclusion = min(leastOcclusion, neighborOcclusion);
        brightestValue = max(brightestValue, PaintRingLightingValue(centerWS + offsetV, SafeNormalize(centerNormal + normalV),
            AdditionalThresholds, AdditionalRamps, neighborOcclusion));
        leastOcclusion = min(leastOcclusion, neighborOcclusion);
        brightestValue = max(brightestValue, PaintRingLightingValue(centerWS - offsetV, SafeNormalize(centerNormal - normalV),
            AdditionalThresholds, AdditionalRamps, neighborOcclusion));
        leastOcclusion = min(leastOcclusion, neighborOcclusion);

        // A fixed choice per Poisson center keeps both kinds of brush stable.
        float choice = step(0.5, PaintPoissonHash((float)i + seed * 101.0 + 83.0));
        if (colorCandidate && brightestValue > Boundary)
        {
            ColorMix = ColorMix * (1.0 - stamp) + choice * stamp;
            Mask = 1.0 - (1.0 - Mask) * (1.0 - stamp);
        }
        if (shadowCandidate && leastOcclusion < centerOcclusion)
        {
            float shadowStamp = stamp * centerOcclusion;
            ShadowColorMix = ShadowColorMix * (1.0 - shadowStamp) + choice * shadowStamp;
            ShadowRingMask = 1.0 - (1.0 - ShadowRingMask) * (1.0 - shadowStamp);
        }
    }
    ColorMix = Mask > 0.000001 ? saturate(ColorMix / Mask) : 0.0;
    // Normalize before Strength: fading the overlay must not change its colors.
    ShadowColorMix = ShadowRingMask > 0.000001 ? saturate(ShadowColorMix / ShadowRingMask) : 0.0;
    ShadowRingMask *= saturate(ShadowStrength);
}

void PaintRingStampsColors_float(float2 UV, float3 WorldPosition, float3 WorldNormal,
    float Boundary, float Width, float Density, float BrushSize, float ShadowStrength,
    float2 AdditionalThresholds, float3 AdditionalRamps,
    UnityTexture2D Brush, UnitySamplerState BrushSampler,
    out float Mask, out float ColorMix, out float ShadowRingMask, out float ShadowColorMix)
{
    PaintRingStampsColors_float(UV, WorldPosition, WorldNormal, Boundary, Width, Density,
        BrushSize, ShadowStrength, AdditionalThresholds, AdditionalRamps,
        Brush.tex, BrushSampler.samplerstate, Mask, ColorMix, ShadowRingMask, ShadowColorMix);
}

#endif
