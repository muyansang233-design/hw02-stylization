// Seed selects one of two sets and translates it; it does not generate a new set.
#ifndef PAINT_POISSON_DISK_INCLUDED
#define PAINT_POISSON_DISK_INCLUDED
#include "PaintPoissonPoints.hlsl"

float PaintPoissonHash(float value)
{
    return frac(sin(value * 127.1 + 311.7) * 43758.5453);
}

void PaintPoissonDisk_float(float2 UV, float Density, float Seed,
    float BrushSize, float RotationDegrees,
    out float2 BrushUV, out float RandomValue, out float ColorChoice, out float Coverage)
{
    float seed = floor(Seed);
    float2 shift = float2(PaintPoissonHash(seed + 17.0), PaintPoissonHash(seed + 53.0)) * 4.0;
    float2 position = frac((UV * max(Density, 0.0001) + shift) / 4.0) * 4.0;
    float bestDistance = 1e10;
    float2 closestDelta = 0.0;
    float pointIndex = 0.0;
    // Minimum-image wrapping searches neighboring tiles without a 3x3 tile loop.
    if (fmod(abs(seed), 2.0) < 0.5)
    {
        [unroll]
        for (int i = 0; i < PAINT_POISSON_SET0_SIZE; ++i)
        {
            float2 delta = position - PaintPoissonPoints0[i];
            delta -= floor(delta / 4.0 + 0.5) * 4.0;
            float d = dot(delta, delta);
            if (d < bestDistance) { bestDistance = d; closestDelta = delta; pointIndex = (float)i; }
        }
    }
    else
    {
        [unroll]
        for (int i = 0; i < PAINT_POISSON_SET1_SIZE; ++i)
        {
            float2 delta = position - PaintPoissonPoints1[i];
            delta -= floor(delta / 4.0 + 0.5) * 4.0;
            float d = dot(delta, delta);
            if (d < bestDistance) { bestDistance = d; closestDelta = delta; pointIndex = (float)i; }
        }
    }
    RandomValue = PaintPoissonHash(pointIndex + seed * 101.0 + 7.0);
    ColorChoice = step(0.5, PaintPoissonHash(pointIndex + seed * 101.0 + 83.0));
    float angle = (RandomValue * 2.0 - 1.0) * RotationDegrees * 0.017453292519943;
    float sn, cs;
    sincos(angle, sn, cs);
    float2 rotated = float2(cs * closestDelta.x - sn * closestDelta.y,
                           sn * closestDelta.x + cs * closestDelta.y);
    BrushUV = rotated / max(BrushSize, 0.0001) + 0.5;
    // Suppress clamp-edge streaks outside the rotated brush square.
    float2 inside = step(0.0, BrushUV) * step(BrushUV, 1.0);
    Coverage = inside.x * inside.y * step(0.0001, Density);
}

void PaintPoissonDisk_half(half2 UV, half Density, half Seed,
    half BrushSize, half RotationDegrees,
    out half2 BrushUV, out half RandomValue, out half ColorChoice, out half Coverage)
{
    float2 uv; float randomValue, colorChoice, coverage;
    PaintPoissonDisk_float((float2)UV, (float)Density, (float)Seed,
        (float)BrushSize, (float)RotationDegrees, uv, randomValue, colorChoice, coverage);
    BrushUV = (half2)uv;
    RandomValue = (half)randomValue;
    ColorChoice = (half)colorChoice;
    Coverage = (half)coverage;
}
#endif
