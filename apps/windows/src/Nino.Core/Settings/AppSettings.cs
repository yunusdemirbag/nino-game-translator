// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text.Json.Serialization;

namespace Nino.Core.Settings;

/// <summary>
/// <c>settings.json</c>'un içeriği. Özellik adları ve sırası dosyadakiyle birebir (PascalCase); sıra değiştirilmemeli.
/// Dosyada olmayan hesaplanan değerler <see cref="SettingsRules"/>'tadır.
/// </summary>
public sealed class AppSettings
{
    internal const bool On = true;

    public Region Region { get; set; } = new();
    public AreaPreset AreaPreset { get; set; } = AreaPreset.Bottom;
    public Region? ExtraRegion1 { get; set; }
    public Region? ExtraRegion2 { get; set; }
    public Region? ExtraRegion3 { get; set; }
    public ResultTarget ExtraTarget1 { get; set; }
    public ResultTarget ExtraTarget2 { get; set; }
    public ResultTarget ExtraTarget3 { get; set; }
    public bool ExtraLive1 { get; set; }
    public bool ExtraLive2 { get; set; }
    public bool ExtraLive3 { get; set; }
    public ResultTarget FreeAreaTarget { get; set; }
    public SubtitleStyle Style { get; set; } = new();
    public int MisreadWaitMs { get; set; } = 800;
    public int PartialWaitMs { get; set; } = 300;
    public string SourceLanguage { get; set; } = "en";
    public string TargetLanguage { get; set; } = SettingsRules.FallbackTargetLanguage;
    public TranslationDevice TranslationDevice { get; set; } = TranslationDevice.Cpu;
    public int CpuTranslationThreads { get; set; } = 2;
    public bool FastSubtitleDetection { get; set; }
    public bool OnlineTranslation { get; set; }
    public OnlineEngine OnlineEngine { get; set; } = OnlineEngine.DeepL;
    public string GeminiModel { get; set; } = AiModelLists.Default.Gemini[0];
    public string OpenAiModel { get; set; } = AiModelLists.Default.OpenAi[0];
    public string ClaudeModel { get; set; } = AiModelLists.Default.Claude[0];
    public string LocalAiBaseUrl { get; set; } = SettingsRules.OllamaBaseUrl;
    public string LocalAiModel { get; set; } = SettingsRules.DefaultLocalModel;
    public SubtitleOutput Output { get; set; } = SubtitleOutput.Tv;
    public bool OverlayClickThrough { get; set; }
    public VideoSource VideoSource { get; set; } = VideoSource.Ps5;
    public GameConsole GameConsole { get; set; } = GameConsole.Ps5;
    public OverlayPlacement? Overlay { get; set; }
    public bool GamePacks { get; set; } = true;
    public bool SharePool { get; set; } = true;
    public bool AutoReport { get; set; } = true;
    public Appearance Appearance { get; set; } = Appearance.System;
    public HomeStyle HomeStyle { get; set; } = HomeStyle.LivingRoom;
    public bool AskGame { get; set; } = true;
    public bool ShowSpeakerNames { get; set; } = On;
    public FrameSource FrameSource { get; set; } = FrameSource.Ps5;
    public bool XboxLegacyFrameRate { get; set; }
    public CaptureWindowChoice? CaptureWindow { get; set; }
    public RemotePlayApp RemotePlayApp { get; set; } = RemotePlayApp.Automatic;
    public List<HotkeyBinding>? Hotkeys { get; set; } = [];

    /// <summary>
    /// Xbox doğrudan yayınının çözünürlüğü (dosyada sayı: 0 kendiliğinden, 1 = 720p). Yeni alan: varsayılanken dosyaya
    /// hiç yazılmaz (eski dosyalarla bayt bayt aynı kalsın); eski dosyada yoksa varsayılan.
    /// </summary>
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingDefault)]
    public XboxStreamQuality XboxStreamQuality { get; set; } = XboxStreamQuality.Auto;

    /// <summary>Ana ekranda TV'nin üstündeki oyun odası tabelası açık mı. Yeni alan; varsayılanken dosyaya yazılmaz.</summary>
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingDefault)]
    public bool GameRoomSign { get; set; }

    /// <summary>Tabeladaki oda adı (en çok 16 harf). Yeni alan; boşken dosyaya yazılmaz.</summary>
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingDefault)]
    public string? GameRoomName { get; set; }

    /// <summary>
    /// Oda adı soruldu mu (kaydedildi ya da atlandı). Eski dosyada yok; bu yüzden tabelayı getiren sürüme geçince bir kez
    /// sorulur. Varsayılanken dosyaya yazılmaz.
    /// </summary>
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingDefault)]
    public bool GameRoomAsked { get; set; }

    /// <summary>Derin kopya.</summary>
    public AppSettings Clone() => SettingsJson.Deserialize(SettingsJson.Serialize(this));

    /// <summary>Dosyaya yazılacak hali aynı mı.</summary>
    public bool SameAs(AppSettings other) =>
        string.Equals(SettingsJson.Serialize(this), SettingsJson.Serialize(other), StringComparison.Ordinal);
}

/// <summary>Karede oranla bir bölge (üst/sol kenardan, 0–1). Eksik kenar varsayılanını alır.</summary>
public sealed record Region
{
    public double Top { get; init; } = 0.62;
    public double Bottom { get; init; } = 0.97;
    public double Left { get; init; } = 0.14;
    public double Right { get; init; } = 0.86;

    public Region() { }

    public Region(double top, double bottom, double left, double right)
    {
        Top = top;
        Bottom = bottom;
        Left = left;
        Right = right;
    }
}

/// <summary>TV'deki altyazı görünümü.</summary>
public sealed class SubtitleStyle
{
    public int FontSize { get; set; } = 46;
    public int BottomPercent { get; set; } = 7;
    public SubtitlePlacement Placement { get; set; } = SubtitlePlacement.Cover;
    public int Background { get; set; } = 100;
    public bool Bold { get; set; }
    public SubtitleTextColor TextColor { get; set; } = SubtitleTextColor.White;
    public SubtitleDisplayMode DisplayMode { get; set; } = SubtitleDisplayMode.InApp;
    public bool StackPrevious { get; set; } = AppSettings.On;
    public SubtitleBackgroundShape BackgroundShape { get; set; } = SubtitleBackgroundShape.Fit;
    public SubtitleFont Font { get; set; } = SubtitleFont.Condensed;
    public bool Watermark { get; set; } = true;
    public bool? AutoSize { get; set; }

    /// <summary>"Oyun boyuna uy" sonucu: <see cref="AutoSize"/> boşsa (eski kayıt) yazı boyu 46 ise açık.</summary>
    [JsonIgnore]
    public bool EffectiveAutoSize => AutoSize ?? FontSize == 46;
}

/// <summary>Bilgisayardaki altyazı penceresinin son yeri ve genişliği (WPF birimi).</summary>
public sealed record OverlayPlacement
{
    public double Left { get; init; }
    public double Top { get; init; }
    public double Width { get; init; }
}

/// <summary>Açıkça seçilen pencere (süreç adı ve başlık ikisi de eşleşmeli).</summary>
public sealed record CaptureWindowChoice
{
    public string ProcessName { get; init; } = "";
    public string Title { get; init; } = "";
}

/// <summary>Bir işin bir yuvasındaki kısayol. <see cref="Key"/> null ise o yuva kapalı.</summary>
public sealed record HotkeyBinding
{
    public HotkeyAction Action { get; init; }
    public int Slot { get; init; }
    public HotkeyKey? Key { get; init; }
}

/// <summary>Tuş: değiştiriciler + Win32 sanal tuş kodu.</summary>
public sealed record HotkeyKey
{
    public KeyModifiers Modifiers { get; init; }
    public int VirtualKey { get; init; }

    public HotkeyKey() { }

    public HotkeyKey(KeyModifiers modifiers, int virtualKey)
    {
        Modifiers = modifiers;
        VirtualKey = virtualKey;
    }
}

/// <summary>Gömülü yapay zekâ model listeleri (her listenin ilki varsayılan).</summary>
public sealed record AiModelLists(IReadOnlyList<string> Gemini, IReadOnlyList<string> OpenAi, IReadOnlyList<string> Claude)
{
    /// <summary><c>ai-models.json</c>'daki değerler.</summary>
    public static AiModelLists Default { get; } = new(
        ["gemini-3.5-flash-lite", "gemini-3.6-flash"],
        ["gpt-6-luna", "gpt-6.1-terra"],
        ["claude-haiku-5-5", "claude-sonnet-5-5"]);
}
