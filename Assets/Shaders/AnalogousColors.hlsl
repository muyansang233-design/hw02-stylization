#ifndef ANALOGOUS_COLORS_INCLUDED
#define ANALOGOUS_COLORS_INCLUDED

// Shader Graph Custom Function: File mode, Name = AnalogousColors,
// Supports Single and Half precision. Inputs: BaseColor (Vector3), Angle (Float, degrees).
// Outputs: ColorLeft (Vector3), ColorRight (Vector3).
// Uses HSV in the supplied RGB space; preserves saturation and value,
// not perceptual lightness. BaseColor must have nonnegative RGB channels.
void AnalogousColors_float(float3 BaseColor, float Angle,
                          out float3 ColorLeft, out float3 ColorRight)
{
    // RGB -> HSV. The epsilon keeps black and gray inputs well-defined.
    float4 k = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    float4 p = lerp(float4(BaseColor.bg, k.wz),
                    float4(BaseColor.gb, k.xy), step(BaseColor.b, BaseColor.g));
    float4 q = lerp(float4(p.xyw, BaseColor.r),
                    float4(BaseColor.r, p.yzx), step(p.x, BaseColor.r));
    float d = q.x - min(q.w, q.y);
    float h = abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10));
    float s = d / (q.x + 1e-10);
    float v = q.x;

    float offset = clamp(Angle, 0.0, 360.0) / 360.0;
    float3 shifts = float3(0.0, 2.0 / 3.0, 1.0 / 3.0);

    // HSV -> RGB with hue shifted to either side and wrapped around the wheel.
    float3 leftRamp = saturate(abs(frac((h - offset).xxx + shifts) * 6.0 - 3.0) - 1.0);
    float3 rightRamp = saturate(abs(frac((h + offset).xxx + shifts) * 6.0 - 3.0) - 1.0);
    ColorLeft = v * lerp(float3(1.0, 1.0, 1.0), leftRamp, s);
    ColorRight = v * lerp(float3(1.0, 1.0, 1.0), rightRamp, s);
}

// Sub Graph previews may request half precision even when the parent uses float.
// Keep the HSV calculation in float so its epsilon remains representable.
void AnalogousColors_half(half3 BaseColor, half Angle,
                         out half3 ColorLeft, out half3 ColorRight)
{
    float3 left;
    float3 right;
    AnalogousColors_float((float3)BaseColor, (float)Angle, left, right);
    ColorLeft = (half3)left;
    ColorRight = (half3)right;
}

#endif
