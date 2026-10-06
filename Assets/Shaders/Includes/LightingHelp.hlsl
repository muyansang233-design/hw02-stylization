#ifndef HW02_LIGHTING_HELP_INCLUDED
#define HW02_LIGHTING_HELP_INCLUDED

#ifndef SHADERGRAPH_PREVIEW
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#endif

void GetMainLight_float(float3 WorldPos, out float3 Color, out float3 Direction, out float DistanceAtten, out float ShadowAtten)
{
#ifdef SHADERGRAPH_PREVIEW
    Direction = normalize(float3(0.5, 0.5, 0));
    Color = 1;
    DistanceAtten = 1;
    ShadowAtten = 1;
#else
#if defined(_MAIN_LIGHT_SHADOWS_SCREEN) && !defined(_SURFACE_TYPE_TRANSPARENT)
    float4 shadowCoord = ComputeScreenPos(TransformWorldToHClip(WorldPos));
#else
    float4 shadowCoord = TransformWorldToShadowCoord(WorldPos);
#endif

    // WorldPos is the fragment's world-space position, including cascade selection.
    // This overload also fades realtime shadows at the pipeline's shadow distance.
    // A white shadow mask leaves baked shadowmask lighting outside this helper's scope.
    Light mainLight = GetMainLight(shadowCoord, WorldPos, half4(1, 1, 1, 1));
    Direction = mainLight.direction;
    Color = mainLight.color;
    DistanceAtten = mainLight.distanceAttenuation;
    ShadowAtten = mainLight.shadowAttenuation;
#endif
}

void GetMainLight_half(half3 WorldPos, out half3 Color, out half3 Direction, out half DistanceAtten, out half ShadowAtten)
{
    float3 color, direction;
    float distanceAtten, shadowAtten;
    GetMainLight_float(WorldPos, color, direction, distanceAtten, shadowAtten);
    Color = color;
    Direction = direction;
    DistanceAtten = distanceAtten;
    ShadowAtten = shadowAtten;
}

void ComputeAdditionalLighting_float(float3 WorldPosition, float3 WorldNormal,
    float2 Thresholds, float3 RampedDiffuseValues,
    out float3 Color, out float Diffuse)
{
    Color = float3(0, 0, 0);
    Diffuse = 0;

#ifndef SHADERGRAPH_PREVIEW

    int pixelLightCount = GetAdditionalLightsCount();
    
    for (int i = 0; i < pixelLightCount; ++i)
    {
        Light light = GetAdditionalLight(i, WorldPosition);
        float4 tmp = unity_LightIndices[i / 4];
        uint light_i = tmp[i % 4];

        half shadowAtten = light.shadowAttenuation * AdditionalLightRealtimeShadow(light_i, WorldPosition, light.direction);
        
        half NdotL = saturate(dot(WorldNormal, light.direction));
        half distanceAtten = light.distanceAttenuation;

        half thisDiffuse = distanceAtten * shadowAtten * NdotL;
        
        half rampedDiffuse = 0;
        
        if (thisDiffuse < Thresholds.x)
        {
            rampedDiffuse = RampedDiffuseValues.x;
        }
        else if (thisDiffuse < Thresholds.y)
        {
            rampedDiffuse = RampedDiffuseValues.y;
        }
        else
        {
            rampedDiffuse = RampedDiffuseValues.z;
        }

        
        if (light.distanceAttenuation <= 0)
        {
            rampedDiffuse = 0.0;
        }

        Color += max(rampedDiffuse, 0) * light.color.rgb;
        Diffuse += rampedDiffuse;
    }
    
    if (Diffuse <= 0.3)
    {
        Color = float3(0, 0, 0);
        Diffuse = 0;
    }
    
#endif
}

void ChooseColor_float(float3 Highlight, float3 Midtone, float3 Shadow, float Diffuse, float2 Thresholds, out float3 OUT)
{
    if (Diffuse < Thresholds.x)
    {
        OUT = Shadow;
    }
    else if (Diffuse < Thresholds.y)
    {
        OUT = Midtone;
    }
    else
    {
        OUT = Highlight;
    }
}

#endif
