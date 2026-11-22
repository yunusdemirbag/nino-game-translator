// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Runtime.CompilerServices;
using System.Text.Json;

namespace Nino.Core.Tests.Library;

/// <summary>Ortak test verisi (Fixtures klasörü çıktıya kopyalanmaz; kaynak yoluyla bulunur).</summary>
internal static class LibraryTestFiles
{
    static string Here([CallerFilePath] string path = "") => path;

    public static string FixturePath(string name) =>
        Path.Combine(Path.GetDirectoryName(Path.GetDirectoryName(Here()))!, "Fixtures", name);

    public static byte[] Bytes(string name) => File.ReadAllBytes(FixturePath(name));

    public static JsonDocument Json(string name) => JsonDocument.Parse(File.ReadAllBytes(FixturePath(name)));

    /// <summary>Test başına geçici klasör.</summary>
    public static string TempFolder()
    {
        var dir = Path.Combine(Path.GetTempPath(), "nino-lib-tests", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        return dir;
    }
}

/// <summary>Elle ilerletilen saat.</summary>
internal sealed class ManualClock(DateTimeOffset start) : TimeProvider
{
    DateTimeOffset _now = start;

    public ManualClock(double unixSeconds) : this(DateTimeOffset.FromUnixTimeMilliseconds((long)(unixSeconds * 1000))) { }

    public override DateTimeOffset GetUtcNow() => _now;

    public void Advance(TimeSpan by) => _now += by;

    public void AdvanceSeconds(double seconds) => _now += TimeSpan.FromSeconds(seconds);
}
