// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Collections.Concurrent;
using System.Diagnostics;
using Nino.Core.Imaging;
using Nino.Core.Phone;
using Nino.Core.Reading;
using Nino.Core.Tests.Reading;
using Nino.Core.Translation;

namespace Nino.Core.Tests.Phone;

/// <summary>
/// Testlerde JPG çözücü: macOS'ta <c>sips</c> ile BMP'ye çevirip okur. Başka sistemde (ya da araç yoksa) yok; gerçek
/// kare sınamaları o zaman atlanır.
/// </summary>
sealed class SipsDecoder : IFrameDecoder
{
    const string Tool = "/usr/bin/sips";
    static readonly ConcurrentDictionary<string, BgraFrame?> Cache = new();

    public static SipsDecoder? Instance { get; } = OperatingSystem.IsMacOS() && File.Exists(Tool) ? new SipsDecoder() : null;

    public BgraFrame? Decode(string path) => Cache.GetOrAdd(path, p =>
    {
        var output = Path.Combine(Path.GetTempPath(), "nino-test-" + Guid.NewGuid().ToString("N") + ".bmp");
        try
        {
            var info = new ProcessStartInfo(Tool) { RedirectStandardOutput = true, RedirectStandardError = true };
            foreach (var a in new[] { "-s", "format", "bmp", p, "--out", output }) info.ArgumentList.Add(a);
            using var process = Process.Start(info)!;
            process.StandardOutput.ReadToEnd();
            process.StandardError.ReadToEnd();
            process.WaitForExit(30_000);
            return File.Exists(output) ? BmpFile.Read(File.ReadAllBytes(output)) : null;
        }
        catch { return null; }
        finally
        {
            try { File.Delete(output); } catch { }
        }
    });

    /// <summary>Fixtures klasöründeki karenin çözülmüş hâli.</summary>
    public static BgraFrame Load(string name) =>
        Instance!.Decode(Path.Combine(Fixtures.Folder, name + ".jpg")) ?? throw new InvalidOperationException(name);
}

/// <summary>Gerçek kare çözülemiyorsa atlanan test.</summary>
public sealed class RealFrameFactAttribute : FactAttribute
{
    public RealFrameFactAttribute()
    {
        if (SipsDecoder.Instance is null) Skip = "JPG çözücü yok (yalnız macOS'ta sips ile)";
    }
}

/// <summary>Gerçek kare çözülemiyorsa atlanan kuram.</summary>
public sealed class RealFrameTheoryAttribute : TheoryAttribute
{
    public RealFrameTheoryAttribute()
    {
        if (SipsDecoder.Instance is null) Skip = "JPG çözücü yok (yalnız macOS'ta sips ile)";
    }
}

/// <summary>Önek ekleyen sahte çevirmen; istekleri sayar.</summary>
sealed class PrefixTranslator(string prefix) : ITranslator
{
    public ConcurrentQueue<string> Requests { get; } = new();
    public int Calls => Requests.Count;
    public string EngineName => "prefix";
    public bool SupportsPretranslation => false;
    public bool SupportsBatch => false;

    public Task<TranslationResult> TranslateAsync(string text, CancellationToken cancellationToken = default)
    {
        Requests.Enqueue(text);
        return Task.FromResult(TranslationResult.FromEngine(prefix + text));
    }

    public Task PretranslateAsync(string text, CancellationToken cancellationToken = default) => Task.CompletedTask;

    public Task<IReadOnlyList<string>> TranslateBatchAsync(IReadOnlyList<string> texts,
        CancellationToken cancellationToken = default) => this.TranslateOneByOneAsync(texts, cancellationToken);
}

/// <summary>Sahte toplu havuz sorgusu: istekleri kaydeder, her satıra işlevin sonucunu döndürür.</summary>
sealed class FakePool(Func<string, string?> answer)
{
    public List<(string[] Lines, string[] Context)> Requests { get; } = [];

    public Task<IReadOnlyList<string?>> Ask(IReadOnlyList<string> lines, IReadOnlyList<string> context,
        CancellationToken cancellationToken)
    {
        lock (Requests) Requests.Add((lines.ToArray(), context.ToArray()));
        return Task.FromResult<IReadOnlyList<string?>>(lines.Select(answer).ToArray());
    }
}

/// <summary>Ekrana gidenleri kaydeden çıkış.</summary>
sealed class RecordingOutput : ISubtitleOutput
{
    public List<(IReadOnlyList<ScreenItem> Items, int Duration, bool Overlay)> Screens { get; } = [];
    public int Clears { get; private set; }

    public void ShowSubtitle(SubtitleShow show) { }

    public void ClearSubtitle() { }

    public void ShowScreen(IReadOnlyList<ScreenItem> items, int durationMs, bool overlay)
    {
        lock (Screens) Screens.Add((items.ToArray(), durationMs, overlay));
    }

    public void ClearScreen() => Clears++;
}

static class PhoneTestData
{
    /// <summary>Okuma satırı (kareye göre kutu).</summary>
    public static OcrLine L(string text, double l, double t, double r, double b) => new(text, new Box(l, t, r, b));

    public static OcrReading R(params OcrLine[] lines) => new(lines);

    /// <summary>Düz renkli kare.</summary>
    public static BgraFrame Solid(int w, int h, byte v) => BgraFrame.Filled(w, h, v);

    /// <summary>Bir dikdörtgeni boyar (piksel aralıkları dahil).</summary>
    public static void Paint(BgraFrame f, int x0, int y0, int x1, int y1, byte r, byte g, byte b)
    {
        for (var y = Math.Max(0, y0); y <= Math.Min(f.Height - 1, y1); y++)
            for (var x = Math.Max(0, x0); x <= Math.Min(f.Width - 1, x1); x++)
                f.SetPixel(x, y, b, g, r);
    }
}
