#ifndef PAINT_RING_STAMPS_INCLUDED
#define PAINT_RING_STAMPS_INCLUDED
#include "PaintPoissonDisk.hlsl"

// Fragment-only. UV derivatives approximate the signed lighting field at each
// candidate center. This is exact for a locally affine field, not a global UV bake.
// Accept centers inside the ring, then accumulate whole stamps WITHOUT masking
// their pixels by the ring. Stamps are allowed to extend outside the center band.
void PaintRingStampsColors_float(float2 UV, float Value, float Boundary, float Width,
    float Density, float BrushSize, Texture2D Brush, SamplerState BrushSampler,
    out float Mask, out float ColorMix)
{
    float2 ux = ddx(UV), uy = ddy(UV);
    float vx = ddx(Value), vy = ddy(Value);
    float determinant = ux.x * uy.y - ux.y * uy.x;
    Mask = 0.0;
    ColorMix = 0.0;
    if (Width <= 0.0 || Density <= 0.0 || BrushSize <= 0.0 || abs(determinant) < 1e-20)
        return;
    float2 gradient = float2(vx * uy.y - vy * ux.y, ux.x * vy - uy.x * vx) / determinant;
    const float seed = 2.0;
    float2 shift = float2(PaintPoissonHash(seed + 17.0), PaintPoissonHash(seed + 53.0)) * 4.0;
    float2 position = frac((UV * Density + shift) / 4.0) * 4.0;
    // A rotated square of width <= 2 fits inside half the period, so each
    // point's nearest periodic image includes every stamp that can cover UV.
    float size = clamp(BrushSize, 0.0001, 2.0);
    float2 dx = ux * Density / size, dy = uy * Density / size;
    [loop]
    for (int i = 0; i < PAINT_POISSON_SET0_SIZE; ++i)
    {
        float2 delta = position - PaintPoissonPoints0[i];
        delta -= floor(delta / 4.0 + 0.5) * 4.0;
        float centerValue = Value - dot(gradient, delta / Density);
        if (abs(centerValue - Boundary) >= Width)
            continue;
        float angle = (PaintPoissonHash((float)i + seed * 101.0 + 7.0) * 2.0 - 1.0) * 0.5235987756;
        float sn, cs;
        sincos(angle, sn, cs);
        float2 brushUV = float2(cs * delta.x - sn * delta.y, sn * delta.x + cs * delta.y) / size + 0.5;
        if (any(brushUV < 0.0) || any(brushUV > 1.0))
            continue;
        float2 brushDx = float2(cs * dx.x - sn * dx.y, sn * dx.x + cs * dx.y);
        float2 brushDy = float2(cs * dy.x - sn * dy.y, sn * dy.x + cs * dy.y);
        float stamp = saturate(1.0 - SAMPLE_TEXTURE2D_GRAD(Brush, BrushSampler, brushUV, brushDx, brushDy).r);
        // Stable binary choice per brush center. Accumulate its contribution
        // with the same alpha-over order as the mask, keeping color math in nodes.
        float choice = step(0.5, PaintPoissonHash((float)i + seed * 101.0 + 83.0));
        ColorMix = ColorMix * (1.0 - stamp) + choice * stamp;
        Mask = 1.0 - (1.0 - Mask) * (1.0 - stamp);
    }
    ColorMix = Mask > 0.000001 ? saturate(ColorMix / Mask) : 0.0;
}

// Both signatures are supported: older open graph windows may still emit bare
// Texture2D/SamplerState calls even after the serialized node has been upgraded.
void PaintRingStampsColors_float(float2 UV, float Value, float Boundary, float Width,
    float Density, float BrushSize, UnityTexture2D Brush, UnitySamplerState BrushSampler,
    out float Mask, out float ColorMix)
{
    PaintRingStampsColors_float(UV, Value, Boundary, Width, Density, BrushSize,
        Brush.tex, BrushSampler.samplerstate, Mask, ColorMix);
}

void PaintRingStampsColors_half(half2 UV, half Value, half Boundary, half Width,
    half Density, half BrushSize, Texture2D Brush, SamplerState BrushSampler,
    out half Mask, out half ColorMix)
{
    float mask, colorMix;
    PaintRingStampsColors_float((float2)UV, Value, Boundary, Width, Density, BrushSize, Brush, BrushSampler, mask, colorMix);
    Mask = (half)mask;
    ColorMix = (half)colorMix;
}

void PaintRingStampsColors_half(half2 UV, half Value, half Boundary, half Width,
    half Density, half BrushSize, UnityTexture2D Brush, UnitySamplerState BrushSampler,
    out half Mask, out half ColorMix)
{
    float mask, colorMix;
    PaintRingStampsColors_float((float2)UV, Value, Boundary, Width, Density, BrushSize, Brush, BrushSampler, mask, colorMix);
    Mask = (half)mask;
    ColorMix = (half)colorMix;
}

// Compatibility with one-output graph previews.
void PaintRingStamps_float(float2 UV, float Value, float Boundary, float Width,
    float Density, float BrushSize, Texture2D Brush, SamplerState BrushSampler, out float Mask)
{
    float colorMix;
    PaintRingStampsColors_float(UV, Value, Boundary, Width, Density, BrushSize, Brush, BrushSampler, Mask, colorMix);
}

void PaintRingStamps_float(float2 UV, float Value, float Boundary, float Width,
    float Density, float BrushSize, UnityTexture2D Brush, UnitySamplerState BrushSampler, out float Mask)
{
    float colorMix;
    PaintRingStampsColors_float(UV, Value, Boundary, Width, Density, BrushSize, Brush, BrushSampler, Mask, colorMix);
}

void PaintRingStamps_half(half2 UV, half Value, half Boundary, half Width,
    half Density, half BrushSize, Texture2D Brush, SamplerState BrushSampler, out half Mask)
{
    half colorMix;
    PaintRingStampsColors_half(UV, Value, Boundary, Width, Density, BrushSize, Brush, BrushSampler, Mask, colorMix);
}

void PaintRingStamps_half(half2 UV, half Value, half Boundary, half Width,
    half Density, half BrushSize, UnityTexture2D Brush, UnitySamplerState BrushSampler, out half Mask)
{
    half colorMix;
    PaintRingStampsColors_half(UV, Value, Boundary, Width, Density, BrushSize, Brush, BrushSampler, Mask, colorMix);
}
#endif
