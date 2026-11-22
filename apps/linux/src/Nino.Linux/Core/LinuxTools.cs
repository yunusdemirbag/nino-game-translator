// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Diagnostics;
using Nino.Core.Data;
using Nino.Core.Imaging;
using Nino.Core.Reading;
using Nino.Core.Settings;
using Nino.Core.Translation;
using Nino.Linux.Diagnostics;
using Nino.Linux.Imaging;
using Nino.Linux.Panel;
using Nino.Linux.Ports;

namespace Nino.Linux.Core;

/// <summary>
/// Panelin ve <c>--read-raw</c>'ın tanı işleri: bir karede altyazı bölgesini bir kez okumak, bir cümleyi
/// çevirmek, modeli indirmek. Okuma hattıyla aynı okuyucuyu ve çevirmeni kullanır.
/// </summary>
public sealed class LinuxTools(LinuxPlatform platform) : IRawFrameServices
{
    private AppSettings Settings => platform.Settings.Load();

    private string Target => TargetLanguages.Code(Settings.TargetLanguage);

    public bool ReaderAvailable => platform.Readers.For(Settings.SourceLanguage) is not null;

    public RegionProbe Probe(BgraPicture frame, bool deep) => Probe(frame, Settings.Region, deep);

    /// <summary>
    /// Bölgeyi okur (süre yalnız okuma), sonra düğme ipuçlarını ve OCR gürültüsünü atıp bölgedeki altyazı
    /// bloğunu seçer.
    /// </summary>
    public RegionProbe Probe(BgraPicture frame, Region region, bool deep)
    {
        var reader = platform.Readers.For(Settings.SourceLanguage)
                     ?? throw new PanelProblem(Words.Turkish ? "Yazı tanıma (Tesseract) kurulu değil." : "Text recognition (Tesseract) isn't installed.");
        var area = Box.FromRegion(region);
        var crop = Pictures.ToFrame(frame).CropRegion(area);
        var clock = Stopwatch.StartNew();
        var reading = reader.ReadLines(crop, deep);
        var elapsed = clock.ElapsedMilliseconds;
        var block = SubtitleOf(reading, area);
        return new RegionProbe(elapsed, crop.Width, crop.Height, [.. reading.Lines.Select(line => line.Text)], block.Text);
    }

    /// <summary>
    /// Okumadan altyazı bloğu: düğme ipuçları ve OCR gürültüsü atılır, blok seçilir. Kutular kırpılmış bölgeye göredir;
    /// çekirdek onları bölgeye kendisi yerleştirir (önceden yerleştirmek bloğu kaydırır).
    /// </summary>
    public static OcrReading SubtitleOf(OcrReading cropRelative, Box area) =>
        LineLayout.SelectSubtitleBlock(OcrJunk.Clean(ButtonHints.Remove(cropRelative)), area);

    private string Source => TargetLanguages.Code(Settings.SourceLanguage);

    public bool ModelInstalled => platform.Services.FreeModel.IsInstalled(Source, Target);

    public Task DownloadModelAsync() =>
        platform.Services.FreeModel.DownloadAsync(Source, Target, new Progress<double>());

    public async Task<string> TranslateAsync(string text) =>
        (await platform.Services.Translators.CreateFree(Target).TranslateAsync(text)).Text;

    /// <summary>
    /// Panelin çeviri denemesi: çeviri hattının kullandığı zincirle (çevrimiçi açıksa önce çevrimiçi motor, olmazsa
    /// yerel model).
    /// </summary>
    public async Task<SampleTranslation> TranslateSampleAsync(string text)
    {
        if (!ModelInstalled) throw new PanelProblem(Words.Turkish ? "Çevirmen modeli bu sunucuya daha inmedi." : "The translator model has not arrived on this server.");
        var settings = Settings;
        var chain = TranslationChain.Build(settings, name => platform.Secrets.Get<string>(name), platform.Services.Translators, () => null, null);
        var clock = Stopwatch.StartNew();
        var result = await Task.Run(() => chain.Translator.TranslateAsync(text));
        var engine = chain.OnlineEnabled && result.Origin == TranslationOrigin.Engine
            ? OnlineKeys.SavedEngine(platform.Secrets, settings) ?? chain.Translator.EngineName
            : Words.Turkish ? "yerel model" : "local model";
        return new SampleTranslation(result.Text, clock.ElapsedMilliseconds, engine);
    }
}
