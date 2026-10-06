using System;
using System.Collections.Generic;
using System.IO;
using UnityEditor;
using UnityEngine;

// Runs once after installation, or manually via Tools/Paint/Reimport and Validate.
// Does not save scenes, materials, or open Shader Graph windows.
[InitializeOnLoad]
internal static class PaintShaderDiagnostics
{
    private const string SessionKey = "PaintShaderDiagnostics.RingAnalogousColors.v2";
    private const string ReportPath = "Temp/PaintShaderValidation.json";

    static PaintShaderDiagnostics()
    {
        if (!SessionState.GetBool(SessionKey, false))
            EditorApplication.update += RunWhenReady;
    }

    private static void RunWhenReady()
    {
        if (EditorApplication.isCompiling || EditorApplication.isUpdating || EditorApplication.isPlayingOrWillChangePlaymode)
            return;
        EditorApplication.update -= RunWhenReady;
        SessionState.SetBool(SessionKey, true);
        Validate();
    }

    [Serializable]
    private class Report
    {
        public string utc;
        public string shader;
        public int passCount;
        public bool hasErrors;
        public string exception;
        public List<string> messages = new List<string>();
    }

    [MenuItem("Tools/Paint/Reimport and Validate")]
    private static void Validate()
    {
        var report = new Report { utc = DateTime.UtcNow.ToString("o") };
        bool oldAsync = ShaderUtil.allowAsyncCompilation;
        Material temporary = null;
        try
        {
            string[] paths = {
                "Assets/Shaders/AnalogousColors.hlsl",
                "Assets/Shaders/SelectColorByThreshold.hlsl",
                "Assets/Shaders/PaintPoissonPoints.hlsl",
                "Assets/Shaders/PaintPoissonDisk.hlsl",
                "Assets/Shaders/PaintRingStamps.hlsl",
                "Assets/Shaders/SG_Paint_PoissonDisk.shadersubgraph",
                "Assets/Shaders/SG_Paint_BrushDistribution.shadersubgraph",
                "Assets/Shaders/SG_Paint_LayerColors.shadersubgraph",
                "Assets/Shaders/MAT_Paint.shadergraph"
            };
            ShaderUtil.allowAsyncCompilation = false;
            foreach (string path in paths)
                AssetDatabase.ImportAsset(path, ImportAssetOptions.ForceUpdate | ImportAssetOptions.ForceSynchronousImport);
            Shader shader = AssetDatabase.LoadAssetAtPath<Shader>(paths[paths.Length - 1]);
            if (shader == null)
                throw new InvalidOperationException("MAT_Paint shader asset did not import.");
            report.shader = shader.name;
            var source = AssetDatabase.LoadAssetAtPath<Material>("Assets/Materials/MAT_Paint.mat");
            temporary = source != null ? new Material(source) : new Material(shader);
            temporary.shader = shader;
            report.passCount = temporary.passCount;
            for (int pass = 0; pass < temporary.passCount; pass++)
                ShaderUtil.CompilePass(temporary, pass);
            foreach (var message in ShaderUtil.GetShaderMessages(shader))
            {
                report.messages.Add(message.severity + ": " + message.message + " (line " + message.line + ")");
                if (message.severity.ToString() == "Error")
                    report.hasErrors = true;
            }
        }
        catch (Exception exception)
        {
            report.hasErrors = true;
            report.exception = exception.ToString();
        }
        finally
        {
            ShaderUtil.allowAsyncCompilation = oldAsync;
            if (temporary != null)
                UnityEngine.Object.DestroyImmediate(temporary);
            Directory.CreateDirectory("Temp");
            File.WriteAllText(ReportPath, JsonUtility.ToJson(report, true));
            Debug.Log("Paint shader validation: " + (report.hasErrors ? "FAILED" : "PASSED") + ". Report: " + ReportPath);
        }
    }
}
