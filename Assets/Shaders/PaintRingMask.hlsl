#ifndef PAINT_RING_MASK_INCLUDED
#define PAINT_RING_MASK_INCLUDED

// Width is the half-width in the signed lighting-value domain, not world units.
void PaintRingMask_float(float Value, float Boundary, float Width,
                         float BrushMask, float Coverage, out float Mask)
{
    float distanceToBoundary = abs(Value - Boundary);
    float ring = 1.0 - smoothstep(0.0, max(Width, 0.0001), distanceToBoundary);
    Mask = Width > 0.0 ? ring * saturate(BrushMask) * saturate(Coverage) : 0.0;
}

void PaintRingMask_half(half Value, half Boundary, half Width,
                        half BrushMask, half Coverage, out half Mask)
{
    float mask;
    PaintRingMask_float(Value, Boundary, Width, BrushMask, Coverage, mask);
    Mask = (half)mask;
}
#endif
