// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Translation.Local;

namespace Nino.Translation.Tests;

// Dış kaynağa (gerçek model dosyası, python3) bağlı testler kaynak yoksa "geçti" değil "atlandı" sayılır.

/// <summary>Gerçek Türkçe CT2 modeli: <c>NINO_TEST_MODELS</c> klasöründe <c>en-tr-ct2/source.spm</c> yoksa atlanır.</summary>
public sealed class TurkishModelFactAttribute : FactAttribute
{
    public const string Variable = "NINO_TEST_MODELS";

    public static string? Folder =>
        Environment.GetEnvironmentVariable(Variable) is { Length: > 0 } root ? Path.Combine(root, "en-tr-ct2") : null;

    public TurkishModelFactAttribute()
    {
        if (Folder is not { } folder || !File.Exists(Path.Combine(folder, "source.spm")))
            Skip = $"gerçek Türkçe model yok ({Variable} verilmedi ya da en-tr-ct2 eksik)";
    }
}

/// <summary>Gerçek Arapça ONNX modeli: <c>NINO_TEST_MODELS_AR</c> kurulu model klasörü değilse atlanır.</summary>
public sealed class ArabicModelFactAttribute : FactAttribute
{
    public const string Variable = "NINO_TEST_MODELS_AR";

    public static string? Folder => Environment.GetEnvironmentVariable(Variable) is { Length: > 0 } f ? f : null;

    public ArabicModelFactAttribute()
    {
        if (Folder is not { } folder || !FreeModelStore.IsOnnxInstalled(folder))
            Skip = $"gerçek Arapça model yok ({Variable} verilmedi ya da model eksik)";
    }
}

/// <summary>
/// python3 isteyen test: Windows'ta atlanır (betik Windows'ta gömülü Python'la çalışır); macOS'ta python3 beklenir
/// (yoksa test başarısız olur); öbür sistemlerde python3 yoksa atlanır.
/// </summary>
public sealed class PythonFactAttribute : FactAttribute
{
    static readonly string[] Candidates = ["/usr/bin/python3", "/opt/homebrew/bin/python3", "/usr/local/bin/python3"];

    public static string? Python => Candidates.FirstOrDefault(File.Exists);

    public PythonFactAttribute()
    {
        if (OperatingSystem.IsWindows()) Skip = "Windows'ta sınanmaz";
        else if (!OperatingSystem.IsMacOS() && Python is null) Skip = "python3 yok";
    }
}
