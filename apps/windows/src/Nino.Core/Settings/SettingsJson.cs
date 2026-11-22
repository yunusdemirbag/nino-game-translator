// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text.Json;

namespace Nino.Core.Settings;

/// <summary>
/// <c>settings.json</c> okuma/yazma. Eski Windows dosyasıyla aynı kurallar: alan adları büyük/küçük harf duyarlı,
/// girintisiz tek satır, ASCII dışı ve <c>" &lt; &gt; &amp; + '</c> kaçışla yazılır. Herhangi bir hata (bozuk metin,
/// yanlış tip, tanınmayan enum adı, <c>AreaPreset: null</c>) dosyanın tamamını geçersiz kılar.
/// </summary>
public static class SettingsJson
{
    static readonly JsonSerializerOptions Options = new()
    {
        // Varsayılanlar: harf duyarlı alan adları, adlandırma kuralı yok, varsayılan kaçış kodlayıcı, girintisiz.
        WriteIndented = false,
    };

    /// <summary>Tek satır JSON.</summary>
    public static string Serialize(AppSettings settings) => JsonSerializer.Serialize(settings, Options);

    /// <summary>Okur ve düzeltir; geçersizse <see cref="JsonException"/> fırlatır.</summary>
    public static AppSettings Deserialize(string json)
    {
        bool hasPreset;
        using (var doc = JsonDocument.Parse(json))
        {
            if (doc.RootElement.ValueKind != JsonValueKind.Object)
                throw new JsonException("Ayar dosyası bir JSON nesnesi değil.");
            hasPreset = doc.RootElement.TryGetProperty(nameof(AppSettings.AreaPreset), out var preset);
            if (hasPreset && preset.ValueKind == JsonValueKind.Null)
                throw new JsonException("AreaPreset boş olamaz.");
        }

        var settings = JsonSerializer.Deserialize<AppSettings>(json, Options)
                       ?? throw new JsonException("Ayar dosyası boş.");
        Repair(settings);
        if (!hasPreset) settings.AreaPreset = RegionPresets.Detect(settings.Region);
        return settings;
    }

    /// <summary>
    /// Okunan değerlerdeki boşlukları ve tanımsız sayıları varsayılana çevirir (eski uygulama tanımsız sayıyı olduğu
    /// gibi bırakırdı; tarif varsayılana çevirmeyi önerir).
    /// </summary>
    static void Repair(AppSettings s)
    {
        var d = new AppSettings();
        s.Region ??= new Region();
        s.Style ??= new SubtitleStyle();
        s.SourceLanguage ??= d.SourceLanguage;
        s.TargetLanguage ??= d.TargetLanguage;
        s.GeminiModel ??= d.GeminiModel;
        s.OpenAiModel ??= d.OpenAiModel;
        s.ClaudeModel ??= d.ClaudeModel;
        s.LocalAiBaseUrl ??= d.LocalAiBaseUrl;
        s.LocalAiModel ??= d.LocalAiModel;
        s.Hotkeys ??= [];
        s.Hotkeys.RemoveAll(h => h is null || !Enum.IsDefined(h.Action) || h.Slot is not (0 or 1));

        s.AreaPreset = Defined(s.AreaPreset, d.AreaPreset);
        s.ExtraTarget1 = Defined(s.ExtraTarget1, d.ExtraTarget1);
        s.ExtraTarget2 = Defined(s.ExtraTarget2, d.ExtraTarget2);
        s.ExtraTarget3 = Defined(s.ExtraTarget3, d.ExtraTarget3);
        s.FreeAreaTarget = Defined(s.FreeAreaTarget, d.FreeAreaTarget);
        s.TranslationDevice = Defined(s.TranslationDevice, d.TranslationDevice);
        s.OnlineEngine = Defined(s.OnlineEngine, d.OnlineEngine);
        s.Output = Defined(s.Output, d.Output);
        s.VideoSource = Defined(s.VideoSource, d.VideoSource);
        s.GameConsole = Defined(s.GameConsole, d.GameConsole);
        s.Appearance = Defined(s.Appearance, d.Appearance);
        s.HomeStyle = Defined(s.HomeStyle, d.HomeStyle);
        s.FrameSource = Defined(s.FrameSource, d.FrameSource);
        s.RemotePlayApp = Defined(s.RemotePlayApp, d.RemotePlayApp);
        s.XboxStreamQuality = Defined(s.XboxStreamQuality, d.XboxStreamQuality);

        var st = s.Style;
        var ds = new SubtitleStyle();
        st.Placement = Defined(st.Placement, ds.Placement);
        st.TextColor = Defined(st.TextColor, ds.TextColor);
        st.DisplayMode = Defined(st.DisplayMode, ds.DisplayMode);
        st.BackgroundShape = Defined(st.BackgroundShape, ds.BackgroundShape);
        st.Font = Defined(st.Font, ds.Font);
    }

    static T Defined<T>(T value, T fallback) where T : struct, Enum => Enum.IsDefined(value) ? value : fallback;
}
