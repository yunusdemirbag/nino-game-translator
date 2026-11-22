// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text.Json.Serialization;

namespace Nino.Core.Settings;

// Dosyada YAZIYLA duran seçimler: ad olarak yazılır, okurken harf duyarsız ve sayı da kabul edilir.
// Sayı değerleri eski dosyalardaki sırayla aynıdır; sıraları değiştirilmemeli.

/// <summary>Altyazı bölgesinin hazır seçimi.</summary>
[JsonConverter(typeof(JsonStringEnumConverter<AreaPreset>))]
public enum AreaPreset
{
    Bottom,
    Top,
    Full,
    Custom,
}

/// <summary>Ücretsiz yerel çevirinin aygıtı.</summary>
[JsonConverter(typeof(JsonStringEnumConverter<TranslationDevice>))]
public enum TranslationDevice
{
    Cpu,
    Gpu,
}

/// <summary>Seçili çevrimiçi motor.</summary>
[JsonConverter(typeof(JsonStringEnumConverter<OnlineEngine>))]
public enum OnlineEngine
{
    Free,
    DeepL,
    Gemini,
    OpenAi,
    Claude,
    Local,
}

/// <summary>Altyazının gösterildiği yer.</summary>
[JsonConverter(typeof(JsonStringEnumConverter<SubtitleOutput>))]
public enum SubtitleOutput
{
    Tv,
    Computer,
    Both,
}

/// <summary>Görüntünün kaynağı: PS5'e doğrudan, bu bilgisayardaki oyun penceresi, HDMI yakalama kartı.</summary>
[JsonConverter(typeof(JsonStringEnumConverter<VideoSource>))]
public enum VideoSource
{
    Ps5,
    Window,
    Card,
}

/// <summary>Pencere yolunda aranan konsol.</summary>
[JsonConverter(typeof(JsonStringEnumConverter<GameConsole>))]
public enum GameConsole
{
    Ps5,
    Xbox,
}

/// <summary>Pencere görünümü.</summary>
[JsonConverter(typeof(JsonStringEnumConverter<Appearance>))]
public enum Appearance
{
    Dark,
    Light,
    System,
}

/// <summary>Ana ekran biçimi.</summary>
[JsonConverter(typeof(JsonStringEnumConverter<HomeStyle>))]
public enum HomeStyle
{
    LivingRoom,
    Toggle,
}

/// <summary>TV'deki altyazının yerleşimi.</summary>
[JsonConverter(typeof(JsonStringEnumConverter<SubtitlePlacement>))]
public enum SubtitlePlacement
{
    Cover,
    Above,
    Below,
    Fixed,
}

/// <summary>Altyazı yazı rengi.</summary>
[JsonConverter(typeof(JsonStringEnumConverter<SubtitleTextColor>))]
public enum SubtitleTextColor
{
    White,
    Yellow,
}

/// <summary>Android TV gösterim biçimi.</summary>
[JsonConverter(typeof(JsonStringEnumConverter<SubtitleDisplayMode>))]
public enum SubtitleDisplayMode
{
    InApp,
    Overlay,
}

/// <summary>Altyazı zemininin biçimi.</summary>
[JsonConverter(typeof(JsonStringEnumConverter<SubtitleBackgroundShape>))]
public enum SubtitleBackgroundShape
{
    Fit,
    Band,
}

/// <summary>Altyazı yazı tipi.</summary>
[JsonConverter(typeof(JsonStringEnumConverter<SubtitleFont>))]
public enum SubtitleFont
{
    Condensed,
    Modern,
    Rounded,
    System,
}

/// <summary>Kısayolla yapılan iş.</summary>
[JsonConverter(typeof(JsonStringEnumConverter<HotkeyAction>))]
public enum HotkeyAction
{
    ExtraRegion1,
    ExtraRegion2,
    ExtraRegion3,
    FreeArea,
    Snapshot,
    PauseSubtitles,
    Screen,
    ClickThrough,
}

/// <summary>Kısayol değiştiricileri; değerler Win32 ile aynı. Dosyada <c>"Alt, Control"</c> gibi yazılır.</summary>
[Flags]
[JsonConverter(typeof(JsonStringEnumConverter<KeyModifiers>))]
public enum KeyModifiers
{
    None = 0,
    Alt = 1,
    Control = 2,
    Shift = 4,
}

// Dosyada SAYIYLA duran seçimler.

/// <summary>Ek bölge ya da serbest alan çevirisinin gösterildiği yer (dosyada 0/1/2).</summary>
public enum ResultTarget
{
    Tv = 0,
    Computer = 1,
    Both = 2,
}

/// <summary>Eski görüntü kaynağı seçimi (dosyada 0/1/2).</summary>
public enum FrameSource
{
    Ps5 = 0,
    RemotePlayWindow = 1,
    ChosenWindow = 2,
}

/// <summary>Pencereden okurken hangi Remote Play uygulaması (dosyada 0/1/2).</summary>
public enum RemotePlayApp
{
    Automatic = 0,
    SonyRemotePlay = 1,
    Chiaki = 2,
}

/// <summary>Xbox doğrudan yayınında istenen görüntü (dosyada 0/1). 720p bağlantı zayıfken kopmaları azaltır.</summary>
public enum XboxStreamQuality
{
    Auto = 0,
    P720 = 1,
}
