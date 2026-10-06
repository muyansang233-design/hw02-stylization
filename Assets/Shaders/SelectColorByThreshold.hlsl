#ifndef SELECT_COLOR_BY_THRESHOLD_INCLUDED
#define SELECT_COLOR_BY_THRESHOLD_INCLUDED

// Shader Graph Custom Function (File): SelectColorByThreshold
// Inputs: Color1/Color2 (Vector4), Threshold/Value (Float).
// Output: Out (Vector4). Equality selects Color2; alpha is preserved.
void SelectColorByThreshold_float(float4 Color1, float4 Color2,
                                 float Threshold, float Value, out float4 Out)
{
    Out = Value > Threshold ? Color1 : Color2;
}

void SelectColorByThreshold_half(half4 Color1, half4 Color2,
                                half Threshold, half Value, out half4 Out)
{
    Out = Value > Threshold ? Color1 : Color2;
}

#endif
