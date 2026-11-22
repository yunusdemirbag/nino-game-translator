// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.Core.Tests;

// Dış kaynağa (openssl, ortam değişkeni) bağlı testler koşul yoksa "geçti" değil "atlandı" sayılır.

/// <summary>openssl aracı.</summary>
public static class OpensslTool
{
    static readonly string[] Candidates = ["/usr/bin/openssl", "/opt/homebrew/bin/openssl", "/usr/local/bin/openssl"];

    /// <summary>Bulunan araçlar (sırayla).</summary>
    public static IReadOnlyList<string> Found => Candidates.Where(File.Exists).ToArray();

    /// <summary>Atlama nedeni; araç varsa null.</summary>
    public static string? SkipReason => Found.Count == 0 ? "openssl yok" : null;
}

/// <summary>openssl yoksa atlanan test.</summary>
public sealed class OpensslFactAttribute : FactAttribute
{
    public OpensslFactAttribute() => Skip = OpensslTool.SkipReason;
}

/// <summary>openssl yoksa atlanan kuram.</summary>
public sealed class OpensslTheoryAttribute : TheoryAttribute
{
    public OpensslTheoryAttribute() => Skip = OpensslTool.SkipReason;
}

/// <summary>Ortam değişkeni verilmişse (testin varsayımını bozar) atlanan test.</summary>
public sealed class FactWithoutEnvironmentAttribute : FactAttribute
{
    public FactWithoutEnvironmentAttribute(string variable)
    {
        if (Environment.GetEnvironmentVariable(variable) is { Length: > 0 }) Skip = variable + " verilmiş";
    }
}
