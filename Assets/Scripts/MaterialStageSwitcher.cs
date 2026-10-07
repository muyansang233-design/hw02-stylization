using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class MaterialStageSwitcher : MonoBehaviour
{
    public enum Stage { Unlit, Paint, PaintWithOutlinesAndPaper }

    [Serializable]
    public class MaterialPair
    {
        public Material paint;
        public Material unlit;
    }

    [SerializeField] private MaterialPair[] materialPairs = new MaterialPair[0];
    [SerializeField] private Material[] outlineMaterials = new Material[0];
    [SerializeField] private UniversalRendererData rendererData;

    public Stage CurrentStage { get; private set; }

    private class RendererState
    {
        public Renderer renderer;
        public Material[] materials;
        public bool enabled;
    }

    private readonly List<RendererState> renderers = new List<RendererState>();
    private readonly Dictionary<Material, Material> unlitMaterials = new Dictionary<Material, Material>();
    private readonly HashSet<Material> outlines = new HashSet<Material>();
    private readonly Dictionary<ScriptableRendererFeature, bool> featureStates = new Dictionary<ScriptableRendererFeature, bool>();
    private Material invisibleOutline;
    private bool initialized;

    private void OnEnable()
    {
        if (Application.isPlaying)
            ApplyStage(Stage.Unlit);
    }

    private void Update()
    {
        if (Input.GetKeyDown(KeyCode.Space))
            ApplyStage((Stage)(((int)CurrentStage + 1) % 3));
    }

    public void ApplyStage(Stage stage)
    {
        if (stage < Stage.Unlit || stage > Stage.PaintWithOutlinesAndPaper)
            throw new ArgumentOutOfRangeException(nameof(stage));
        if (!initialized && !Initialize())
            return;

        foreach (RendererState state in renderers)
        {
            if (state.renderer == null)
                continue;

            Material[] materials = (Material[])state.materials.Clone();
            for (int slot = 0; slot < materials.Length; slot++)
            {
                Material original = state.materials[slot];
                if (original == null)
                    continue;
                if (stage != Stage.PaintWithOutlinesAndPaper && outlines.Contains(original))
                    materials[slot] = invisibleOutline;
                else if (stage == Stage.Unlit && unlitMaterials.TryGetValue(original, out Material unlit))
                    materials[slot] = unlit;
            }
            // Keep every submesh/material slot in place, including extra inverted-hull slots.
            state.renderer.sharedMaterials = materials;
        }

        foreach (var entry in featureStates)
            if (entry.Key != null)
                entry.Key.SetActive(stage == Stage.PaintWithOutlinesAndPaper && entry.Value);

        CurrentStage = stage;
    }

    private bool Initialize()
    {
        Shader shader = Shader.Find("Universal Render Pipeline/Unlit");
        if (shader == null)
        {
            Debug.LogError("MaterialStageSwitcher needs the Universal Render Pipeline/Unlit shader.", this);
            return false;
        }

        invisibleOutline = new Material(shader) {
            name = "Hidden outline slot", hideFlags = HideFlags.HideAndDontSave,
            renderQueue = (int)RenderQueue.Transparent
        };
        invisibleOutline.SetColor("_BaseColor", Color.clear);
        invisibleOutline.SetFloat("_Surface", 1);
        invisibleOutline.SetFloat("_Blend", 0);
        invisibleOutline.SetFloat("_AlphaClip", 0);
        invisibleOutline.SetFloat("_SrcBlend", (float)BlendMode.SrcAlpha);
        invisibleOutline.SetFloat("_DstBlend", (float)BlendMode.OneMinusSrcAlpha);
        invisibleOutline.SetFloat("_SrcBlendAlpha", (float)BlendMode.One);
        invisibleOutline.SetFloat("_DstBlendAlpha", (float)BlendMode.OneMinusSrcAlpha);
        invisibleOutline.SetFloat("_ZWrite", 0);
        invisibleOutline.SetOverrideTag("RenderType", "Transparent");
        invisibleOutline.EnableKeyword("_SURFACE_TYPE_TRANSPARENT");
        invisibleOutline.SetShaderPassEnabled("ShadowCaster", false);
        invisibleOutline.SetShaderPassEnabled("DepthOnly", false);
        invisibleOutline.SetShaderPassEnabled("DepthNormalsOnly", false);

        foreach (MaterialPair pair in materialPairs)
            if (pair != null && pair.paint != null && pair.unlit != null)
                unlitMaterials[pair.paint] = pair.unlit;
        foreach (Material material in outlineMaterials)
            if (material != null)
                outlines.Add(material);

        foreach (Renderer renderer in FindObjectsOfType<Renderer>(true))
            if (renderer.gameObject.scene == gameObject.scene)
                renderers.Add(new RendererState {
                    renderer = renderer, materials = renderer.sharedMaterials, enabled = renderer.enabled
                });

        if (rendererData != null)
            foreach (ScriptableRendererFeature feature in rendererData.rendererFeatures)
                if (feature is NormalFeature || feature is FullScreenFeature)
                    featureStates[feature] = feature.isActive;

        initialized = true;
        return true;
    }

    private void OnDisable()
    {
        if (!initialized)
            return;

        foreach (RendererState state in renderers)
            if (state.renderer != null)
            {
                state.renderer.sharedMaterials = state.materials;
                state.renderer.enabled = state.enabled;
            }
        foreach (var entry in featureStates)
            if (entry.Key != null)
                entry.Key.SetActive(entry.Value);

        if (invisibleOutline != null)
        {
            if (Application.isPlaying) Destroy(invisibleOutline);
            else DestroyImmediate(invisibleOutline);
        }
        invisibleOutline = null;
        renderers.Clear();
        unlitMaterials.Clear();
        outlines.Clear();
        featureStates.Clear();
        initialized = false;
        CurrentStage = Stage.PaintWithOutlinesAndPaper;
    }
}
