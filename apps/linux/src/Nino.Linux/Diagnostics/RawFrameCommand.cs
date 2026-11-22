// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Diagnostics;
using Nino.Linux.Imaging;
using Nino.Linux.Ports;

namespace Nino.Linux.Diagnostics;

/// <summary>Tanı komutunun ihtiyaç duyduğu okuma ve çeviri (çekirdek uyarlayıcısı sağlar).</summary>
public interface IRawFrameServices
{
    bool ReaderAvailable { get; }

    /// <summary>Varsayılan altyazı bölgesini okur.</summary>
    RegionProbe Probe(BgraPicture frame, bool deep);

    bool ModelInstalled { get; }
    Task DownloadModelAsync();
    Task<string> TranslateAsync(string text);
}

/// <summary>
/// <c>nino --read-raw kare.bgra 1920 1080 [--translate]</c>: PS5 olmadan okuma ve çeviri denemesi. Kare ham BGRA
/// olmalı (<c>ffmpeg -i kare.png -pix_fmt bgra -f rawvideo kare.bgra</c>).
/// </summary>
public static class RawFrameCommand
{
    public const int Ok = 0;
    public const int Usage = 1;
    public const int TooSmall = 2;
    public const int NoReader = 3;

    public const int Rounds = 4;
    public const int DeepRounds = 2;

    /// <summary>Komut satırı bu komutu mu istiyor.</summary>
    public static bool Matches(string[] args) => args.Length > 0 && args[0] == "--read-raw";

    public static async Task<int> RunAsync(string[] args, Func<IRawFrameServices> services, TextWriter output, TextWriter errors)
    {
        if (args.Length < 4 || !int.TryParse(args[2], out var width) || !int.TryParse(args[3], out var height) || width <= 0 || height <= 0)
        {
            await errors.WriteLineAsync("Biçim: nino --read-raw <ham-bgra-dosyası> <genişlik> <yükseklik> [--translate]");
            return Usage;
        }
        var translate = args.Skip(4).Contains("--translate");
        var bytes = await File.ReadAllBytesAsync(args[1]);
        if (bytes.Length < (long)width * height * 4)
        {
            await errors.WriteLineAsync($"{width}×{height} bir kare {(long)width * height * 4} bayt ister; dosyada {bytes.Length} bayt var.");
            return TooSmall;
        }
        var tools = services();
        if (!tools.ReaderAvailable)
        {
            await errors.WriteLineAsync("Yazı tanıma açılamadı: libtesseract ile tesseract-ocr-eng paketlerini kurun.");
            return NoReader;
        }

        var frame = BgraPicture.Packed(bytes, width, height);
        RegionProbe? last = null;
        for (var round = 1; round <= Rounds; round++)
        {
            // İlk okumalar derin (boş bölgede ara sıra yapılan), sonrakiler her karede yapılan olağan okuma.
            var deep = round <= DeepRounds;
            last = tools.Probe(frame, deep);
            await output.WriteLineAsync($"#{round} {(deep ? "derin" : "olağan")}: {last.Ms} ms ({last.Width}×{last.Height} piksel)");
        }
        foreach (var line in last!.Lines) await output.WriteLineAsync($"  okunan > {line}");
        await output.WriteLineAsync($"  altyazı > {last.Subtitle}");

        if (!translate || string.IsNullOrWhiteSpace(last.Subtitle)) return Ok;
        if (!tools.ModelInstalled)
        {
            await output.WriteLineAsync("  model yok, şimdi indiriliyor (bir kez)…");
            await tools.DownloadModelAsync();
        }
        var sentence = last.Subtitle.Replace('\n', ' ');
        // İkinci çeviri ısınmış modelin süresini gösterir.
        foreach (var label in new[] { "ilk", "ısınmış" })
        {
            var clock = Stopwatch.StartNew();
            var result = await tools.TranslateAsync(sentence);
            await output.WriteLineAsync($"  çeviri ({label}) {clock.ElapsedMilliseconds} ms > {result}");
        }
        return Ok;
    }
}
