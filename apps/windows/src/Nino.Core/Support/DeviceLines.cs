// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text.RegularExpressions;
using Nino.Core.Data;
using Nino.Core.Settings;
using Nino.Core.Tv;

namespace Nino.Core.Support;

/// <summary>Altyazının okunduğu yol (cihaz bilgisinin <c>console</c> satırı için).</summary>
public enum ConsoleRoute
{
    /// <summary>Nino PS5'e Remote Play ile kendisi bağlanıyor.</summary>
    Ps5RemotePlay,

    /// <summary>Nino Xbox'a uzaktan oynatma ile bağlanıyor.</summary>
    XboxStream,

    /// <summary>Yerel bilgisayardaki oyun penceresi.</summary>
    GameWindow,

    /// <summary>Remote Play uygulamasının penceresi.</summary>
    RemotePlayWindow,

    /// <summary>Kullanıcının seçtiği pencere.</summary>
    ChosenWindow,

    /// <summary>HDMI yakalama kartı.</summary>
    CaptureCard,
}

/// <summary>
/// Cihaz bilgisinin <c>tv</c>, <c>console</c> ve <c>status</c> satırları. Değerler çevrilmez (ekip okur); kişiyi tanıtan
/// hiçbir şey (TV'nin ya da PS5'in adı, adres, pencere başlığı, kart adı) girmez. Diğer satırlar ve özet
/// <see cref="DeviceInfo"/>'dadır.
/// </summary>
public static partial class DeviceLines
{
    [GeneratedRegex(@"^[0-9][A-Za-z0-9.+\-]{0,30}$")]
    private static partial Regex VersionLike();

    [GeneratedRegex(@"^Xbox[A-Za-z0-9]{0,20}$")]
    private static partial Regex XboxModelLike();

    [GeneratedRegex(@"(?<=[a-z0-9])(?=[A-Z])")]
    private static partial Regex CamelBreak();

    [GeneratedRegex(@"^0x[0-9a-fA-F]{1,8}$")]
    private static partial Regex HexCode();

    [GeneratedRegex(@"^[A-Za-z]{1,40}$")]
    private static partial Regex ReasonName();

    /// <summary>
    /// TV satırı: marka, TV uygulamasının bildirdiği model, sürüm gibi görünüyorsa <c>uygulama &lt;sürüm&gt;</c>,
    /// <c>bağlantı var</c>/<c>bağlantı yok</c>; " · " ile. TV yoksa null.
    /// </summary>
    /// <param name="brand">Eşleşen TV'nin markası; yoksa null.</param>
    /// <param name="model">TV uygulamasının bildirdiği model.</param>
    /// <param name="statusVersion">TV uygulaması durumundaki sürüm.</param>
    /// <param name="installedVersion">Kayıtlı kurulan sürüm (durumda sürüm yoksa).</param>
    /// <param name="connected">TV uygulaması şu an bağlı mı.</param>
    public static string? Tv(TvBrand? brand, string? model, string? statusVersion, string? installedVersion,
        bool connected)
    {
        if (brand is not { } b) return null;
        var parts = new List<string>
        {
            b switch { TvBrand.Samsung => "Samsung Tizen", TvBrand.AndroidTv => "Android TV", _ => "LG webOS" },
        };
        var cleanModel = DeviceInfo.CleanValue(model);
        if (cleanModel.Length > 0) parts.Add(cleanModel);
        var version = (string.IsNullOrWhiteSpace(statusVersion) ? installedVersion : statusVersion)?.Trim() ?? "";
        if (VersionLike().IsMatch(version)) parts.Add("uygulama " + version);
        parts.Add(connected ? "bağlantı var" : "bağlantı yok");
        return string.Join(" · ", parts);
    }

    /// <summary>
    /// Xbox modeli: <c>XboxSeriesX</c> → <c>Xbox Series X</c>, <c>XboxOne</c> → <c>Xbox One</c>; başka her şey <c>Xbox</c>.
    /// </summary>
    public static string XboxModel(string? value)
    {
        var text = (value ?? "").Trim();
        return XboxModelLike().IsMatch(text) ? CamelBreak().Replace(text, " ") : "Xbox";
    }

    /// <summary>Konsol satırı.</summary>
    /// <param name="route">Okuma yolu.</param>
    /// <param name="console">Oyunun penceresinde aranan konsol.</param>
    /// <param name="xboxModel">Xbox'ın bildirdiği tür (uzaktan oynatmada).</param>
    /// <param name="remotePlayApp">Remote Play penceresinde hangi uygulama.</param>
    public static string Console(ConsoleRoute route, GameConsole console = GameConsole.Ps5, string? xboxModel = null,
        RemotePlayApp remotePlayApp = RemotePlayApp.Automatic) => route switch
    {
        ConsoleRoute.CaptureCard => "HDMI kartı",
        ConsoleRoute.GameWindow => (console == GameConsole.Xbox ? "Xbox" : "PS5") + " · pencereden okuma",
        ConsoleRoute.XboxStream => XboxModel(xboxModel) + " · uzaktan oynatma",
        ConsoleRoute.RemotePlayWindow => "PS5 · Remote Play uygulamasından" + remotePlayApp switch
        {
            RemotePlayApp.SonyRemotePlay => " (PS Remote Play)",
            RemotePlayApp.Chiaki => " (chiaki-ng)",
            _ => "",
        },
        ConsoleRoute.ChosenWindow => "kullanıcının seçtiği pencere",
        _ => "PS5 · Remote Play",
    };

    /// <summary>
    /// Durum satırı, oyun penceresi yolunda: <c>çeviri sürüyor, pencere: Capturing</c> (durum adı
    /// <c>Stopped|LookingForWindow|Capturing</c>) + son kopma + oyun.
    /// </summary>
    public static string StatusForWindow(bool translating, string windowState, string? lastDropReason, string? game) =>
        Finish(Head(translating) + ", pencere: " + windowState, lastDropReason, game);

    /// <summary>Durum satırı, yakalama kartı yolunda (<c>Stopped|NeedsPermission|NoCard|BlackPicture|Capturing</c>).</summary>
    public static string StatusForCard(bool translating, string cardState, string? lastDropReason, string? game) =>
        Finish(Head(translating) + ", kart: " + cardState, lastDropReason, game);

    /// <summary>
    /// Durum satırı, PS5 ya da Xbox yolunda: <c>, PS5: Disconnected (NotFound)</c>; ayrıntı tam olarak <c>0x</c> + 1–8
    /// onaltılıksa <c>(Rejected 0x80108bff)</c>; adres gibi ayrıntılar alınmaz.
    /// </summary>
    /// <param name="translating">Çeviri sürüyor mu.</param>
    /// <param name="consoleLabel"><c>PS5</c> ya da <c>Xbox</c>.</param>
    /// <param name="phase"><c>Disconnected|Connecting|Streaming</c>.</param>
    /// <param name="reason">Kopuksa nedenin adı.</param>
    /// <param name="detail">Nedenin ayrıntısı.</param>
    /// <param name="lastDropReason">Sağlık kaydındaki son kopma nedeni.</param>
    /// <param name="game">Şu anki oyun; bilinmiyorsa null.</param>
    public static string StatusForStream(bool translating, string consoleLabel, string phase, string? reason,
        string? detail, string? lastDropReason, string? game)
    {
        var text = Head(translating) + $", {consoleLabel}: {phase}";
        if (phase == "Disconnected" && !string.IsNullOrWhiteSpace(reason))
        {
            var d = detail?.Trim() ?? "";
            text += HexCode().IsMatch(d) ? $" ({reason} {d})" : $" ({reason})";
        }
        return Finish(text, lastDropReason, game);
    }

    static string Head(bool translating) => translating ? "çeviri sürüyor" : "çeviri durdu";

    static string Finish(string text, string? lastDropReason, string? game)
    {
        var last = lastDropReason?.Trim() ?? "";
        if (ReasonName().IsMatch(last)) text += ", en son kopuş: " + last;
        var name = DeviceInfo.CleanValue(game);
        return text + ", oyun: " + (name.Length > 0 ? name : "bilinmiyor");
    }

    /// <summary>
    /// Altı satır (<c>app, device, system, tv, console, status</c>); boş olan (ör. TV yoksa <c>tv</c>) yazılmaz.
    /// </summary>
    public static IReadOnlyList<DeviceInfoLine> Lines(string app, string device, string system, string? tv,
        string console, string status) =>
        DeviceInfo.Lines(("app", app), ("device", device), ("system", system), ("tv", tv), ("console", console),
            ("status", status));
}
