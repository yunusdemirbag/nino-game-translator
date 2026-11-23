// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.Core.Settings;

/// <summary>Ayarlarla ilgili saf kurallar: açılış düzeltmeleri, yazma kuralları, iş parçacığı, dil.</summary>
public static class SettingsRules
{
    /// <summary>Ollama'nın yerel adresi (varsayılan yerel sunucu).</summary>
    public const string OllamaBaseUrl = "http://localhost:11434/v1";

    /// <summary>LM Studio'nun yerel adresi.</summary>
    public const string LmStudioBaseUrl = "http://localhost:1234/v1";

    /// <summary>Yerel modelin varsayılanı.</summary>
    public const string DefaultLocalModel = "translategemma:4b";

    /// <summary>Çeviri dili seçilemediğinde (ve bozuk ayar dosyasında) Türkçe.</summary>
    public const string FallbackTargetLanguage = "tr";

    /// <summary>Çeviri dilleri (Türkçe ilk).</summary>
    public static IReadOnlyList<string> TargetLanguages { get; } =
        ["tr", "ar", "hi", "id", "th", "vi", "ur", "bn", "ms", "tl", "nl"];

    /// <summary>Bekleme sürelerinin kullanılırken sıkıştırıldığı üst sınır (ms).</summary>
    public const int MaxWaitMs = 2000;

    /// <summary>
    /// İlk açılışta (dosya yokken) çeviri dili: arayüz dilinin iki harfi (Filipince <c>fil…</c> → <c>tl</c>)
    /// desteklenen dillerdense o, değilse <c>tr</c>.
    /// </summary>
    public static string FirstRunTargetLanguage(string? uiLanguage)
    {
        var code = (uiLanguage ?? "").Trim().ToLowerInvariant();
        if (code.StartsWith("fil", StringComparison.Ordinal)) return "tl";
        if (code.Length >= 2) code = code[..2];
        return TargetLanguages.Contains(code) ? code : FallbackTargetLanguage;
    }

    /// <summary>Bekleme süresi 0–2000 ms arasına sıkıştırılır.</summary>
    public static int ClampWait(int ms) => Math.Clamp(ms, 0, MaxWaitMs);

    /// <summary>Kaydırıcıdaki saniye → dosyadaki ms (yuvarlanır).</summary>
    public static int SecondsToWaitMs(double seconds) => (int)Math.Round(seconds * 1000, MidpointRounding.AwayFromZero);

    // ---- İşlemci iş parçacığı ----

    /// <summary>Sunulan iş parçacığı seçenekleri: 2, 4, 8, 12'den işlemci sayısını aşmayanlar; 2'den azsa yalnız 1.</summary>
    public static IReadOnlyList<int> CpuThreadOptions(int logicalProcessors)
    {
        if (logicalProcessors < 2) return [1];
        return new[] { 2, 4, 8, 12 }.Where(n => n <= logicalProcessors).ToArray();
    }

    /// <summary>İstenen değere eşit ya da küçük seçeneklerin en büyüğü; yoksa ilk seçenek.</summary>
    public static int NormalizeCpuThreads(int requested, int logicalProcessors)
    {
        var options = CpuThreadOptions(logicalProcessors);
        var fitting = options.Where(n => n <= requested).ToArray();
        return fitting.Length > 0 ? fitting.Max() : options[0];
    }

    /// <summary>"Kapasiteye yakın" uyarısı: seçilen × 4 ≥ işlemci × 3.</summary>
    public static bool CpuThreadsNearCapacity(int selected, int logicalProcessors) =>
        selected * 4 >= logicalProcessors * 3;

    // ---- Hesaplanan değerler ----

    /// <summary>Seçili motor: çevrimiçi açık ve motor ücretsiz değilse o, yoksa ücretsiz motor.</summary>
    public static OnlineEngine SelectedEngine(AppSettings s) =>
        s.OnlineTranslation && s.OnlineEngine != OnlineEngine.Free ? s.OnlineEngine : OnlineEngine.Free;

    /// <summary>Yerel model sunucusunun adresi geçerli mi (mutlak http/https adresi).</summary>
    public static Uri? LocalServer(AppSettings s) =>
        Uri.TryCreate(s.LocalAiBaseUrl?.Trim(), UriKind.Absolute, out var uri)
        && (uri.Scheme == Uri.UriSchemeHttp || uri.Scheme == Uri.UriSchemeHttps)
            ? uri
            : null;

    // ---- Açılış düzeltmeleri (ayarlar-modeli §3) ----

    /// <summary>
    /// Okuduktan hemen sonraki düzeltmeler: model listeleri, iş parçacığı, eski "ikisi de". Değer değiştiyse true
    /// döner (o zaman dosya hemen yeniden yazılmalı).
    /// </summary>
    public static bool ApplyStartupFixes(AppSettings s, int logicalProcessors, AiModelLists? models = null)
    {
        models ??= AiModelLists.Default;
        var before = SettingsJson.Serialize(s);

        if (models.Gemini.Count > 0 && !models.Gemini.Contains(s.GeminiModel)) s.GeminiModel = models.Gemini[0];
        if (models.OpenAi.Count > 0 && !models.OpenAi.Contains(s.OpenAiModel)) s.OpenAiModel = models.OpenAi[0];
        if (models.Claude.Count > 0 && !models.Claude.Contains(s.ClaudeModel)) s.ClaudeModel = models.Claude[0];
        var local = (s.LocalAiModel ?? "").Trim();
        s.LocalAiModel = local.Length == 0 ? DefaultLocalModel : local;

        s.CpuTranslationThreads = NormalizeCpuThreads(s.CpuTranslationThreads, logicalProcessors);

        if (s.Output == SubtitleOutput.Both && s.VideoSource != VideoSource.Card) s.Output = SubtitleOutput.Tv;

        return !string.Equals(before, SettingsJson.Serialize(s), StringComparison.Ordinal);
    }

    // ---- Yazma kuralları (ayarlar-modeli §4) ----

    /// <summary>
    /// Yeni ayarı kaydetmeden önceki düzeltmeler: iş parçacığı; iki görüntü kaynağı tek seçim gibi; PS5 yoluna
    /// dönüşte çıktı TV. <paramref name="next"/> yerinde değişir. Kaydedilecek bir fark varsa true.
    /// </summary>
    public static bool ApplyWriteRules(AppSettings previous, AppSettings next, int logicalProcessors)
    {
        next.CpuTranslationThreads = NormalizeCpuThreads(next.CpuTranslationThreads, logicalProcessors);
        next.GameRoomName = Design.GameRoomSign.CleanName(next.GameRoomName);

        var frameChanged = next.FrameSource != previous.FrameSource;
        var videoChanged = next.VideoSource != previous.VideoSource;
        if (frameChanged && next.FrameSource != FrameSource.Ps5 && next.VideoSource != VideoSource.Ps5)
            next.VideoSource = VideoSource.Ps5;
        else if (videoChanged && next.VideoSource != VideoSource.Ps5 && next.FrameSource != FrameSource.Ps5)
            next.FrameSource = FrameSource.Ps5;

        if (previous.VideoSource != VideoSource.Ps5 && next.VideoSource == VideoSource.Ps5
            && next.FrameSource == FrameSource.Ps5 && next.Output != SubtitleOutput.Tv)
            next.Output = SubtitleOutput.Tv;

        return !previous.SameAs(next);
    }
}

/// <summary>Bölge hazır seçimleri ve kaydırıcı hesapları.</summary>
public static class RegionPresets
{
    public static Region Bottom { get; } = new(0.62, 0.97, 0.14, 0.86);
    public static Region Top { get; } = new(0.03, 0.38, 0.14, 0.86);
    public static Region Full { get; } = new(0, 1, 0, 1);

    /// <summary>Ek bölge önerileri: görev paneli.</summary>
    public static Region ExtraQuest { get; } = new(0.03, 0.30, 0.66, 0.98);

    /// <summary>Ek bölge önerileri: bildirim.</summary>
    public static Region ExtraNotification { get; } = new(0.58, 0.88, 0.02, 0.30);

    /// <summary>Ek bölge önerileri: telefon.</summary>
    public static Region ExtraPhone { get; } = new(0.50, 0.95, 0.72, 0.98);

    const double Tolerance = 0.001;

    /// <summary>Hazır seçimin bölgesi; <see cref="AreaPreset.Custom"/>'da null (kayıtlı bölge kalır).</summary>
    public static Region? RegionOf(AreaPreset preset) => preset switch
    {
        AreaPreset.Bottom => Bottom,
        AreaPreset.Top => Top,
        AreaPreset.Full => Full,
        _ => null,
    };

    /// <summary>Bölge bir hazır seçimle her kenarda 0.001 payla aynıysa o, değilse Custom.</summary>
    public static AreaPreset Detect(Region region)
    {
        foreach (var preset in new[] { AreaPreset.Bottom, AreaPreset.Top, AreaPreset.Full })
        {
            var r = RegionOf(preset)!;
            if (Math.Abs(r.Top - region.Top) <= Tolerance && Math.Abs(r.Bottom - region.Bottom) <= Tolerance
                && Math.Abs(r.Left - region.Left) <= Tolerance && Math.Abs(r.Right - region.Right) <= Tolerance)
                return preset;
        }
        return AreaPreset.Custom;
    }

    /// <summary>Hazır seçimi uygular (Custom'da bölge değişmez).</summary>
    public static void Apply(AppSettings s, AreaPreset preset)
    {
        s.AreaPreset = preset;
        if (RegionOf(preset) is { } r) s.Region = r;
    }

    /// <summary>Kaydırıcıdaki dikey konum (üst × 100).</summary>
    public static double Position(Region r) => r.Top * 100;

    /// <summary>Kaydırıcıdaki yükseklik ((alt − üst) × 100).</summary>
    public static double Height(Region r) => (r.Bottom - r.Top) * 100;

    /// <summary>
    /// Kaydırıcılardan yeni bölge: yükseklik %5–%100; üst 0 ile (1 − yükseklik) arasına sıkışır; sol ve sağ aynı.
    /// </summary>
    public static Region FromSliders(Region current, double positionPercent, double heightPercent)
    {
        var span = Math.Clamp(heightPercent / 100, 0.05, 1);
        var upper = Math.Clamp(positionPercent / 100, 0, 1 - span);
        return current with { Top = upper, Bottom = upper + span };
    }
}
