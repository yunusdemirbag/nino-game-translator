// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.Core.Link;

/// <summary>TV'nin hangi yoldan bağlandığı.</summary>
public enum TvLinkKind
{
    /// <summary>Eski 8787 SSE akışı (eski TV uygulamaları; OBS izleyicisi buraya girmez).</summary>
    Legacy,
    /// <summary>47800 gönderici girişine gelen LG/Samsung web TV'si.</summary>
    WebTv,
    /// <summary>Windows'un bağlandığı yeni Android TV uygulaması (47800).</summary>
    AndroidTv,
}

/// <summary>Bir TV bağlantısının neden bittiği. Kısa sabit adı <see cref="TvLinkReasons.Code"/> verir.</summary>
public enum TvLinkEndReason
{
    /// <summary><c>closed</c>: TV bağlantıyı kapattı ya da bağlantı karşıdan koptu.</summary>
    Closed,
    /// <summary><c>write_failed</c>: TV'ye yazılamadı.</summary>
    WriteFailed,
    /// <summary><c>silence</c>: TV'den 15 sn hiçbir şey gelmedi.</summary>
    Silence,
    /// <summary><c>handshake</c>: <c>welcome</c> gelmedi ya da sürüm desteklenmiyor (hiç bağlanılmadı).</summary>
    Handshake,
    /// <summary><c>replaced</c>: başka bir gönderici TV'yi aldı.</summary>
    Replaced,
    /// <summary><c>stopped</c>: Nino kendisi kapattı (çeviri durdu, yeniden başladı, uygulama kapanıyor). Kopma değildir.</summary>
    Stopped,
    /// <summary><c>error</c>: sınıflanamayan hata.</summary>
    Error,
}

/// <summary>TV bağlantısı kuruldu. Adres yalnız günlük içindir; ölçüme gitmez.</summary>
/// <param name="Id">Bu bağlantının kimliği (bitiş olayıyla eşleşir).</param>
/// <param name="Took">Bağlantının açılışından hazır olmasına kadar geçen süre (8787'de sıfır).</param>
public sealed record TvLinkConnected(
    long Id,
    TvLinkKind Kind,
    int Port,
    string Address,
    string? Model,
    string? AppVersion,
    TimeSpan Took);

/// <summary>TV bağlantısı bitti.</summary>
/// <param name="WasConnected">Bağlantı hazır olmuş muydu (<see cref="TvLinkEndReason.Handshake"/>'te hayır).</param>
/// <param name="After">Hazır olduktan sonra geçen süre; hazır olmadıysa açılıştan beri geçen süre.</param>
/// <param name="Detail">Günlük için kısa ek bilgi (ör. el sıkışmada "welcome gelmedi"); ölçüme gitmez.</param>
public sealed record TvLinkDropped(
    long Id,
    TvLinkKind Kind,
    int Port,
    string Address,
    TvLinkEndReason Reason,
    bool WasConnected,
    TimeSpan After,
    string? Model,
    string? AppVersion,
    string? Detail = null)
{
    /// <summary>Nedenin kısa sabit adı.</summary>
    public string Code => TvLinkReasons.Code(Reason);
}

/// <summary>Neden adları ve günlük satırları.</summary>
public static class TvLinkReasons
{
    static long lastId;

    /// <summary>El sıkışma ayrıntısı: <c>welcome</c> 5 sn içinde gelmedi.</summary>
    public const string NoWelcome = "welcome gelmedi";

    /// <summary>El sıkışma ayrıntısı: ortak protokol sürümü yok.</summary>
    public const string VersionUnsupported = "TV bu protokol sürümünü desteklemiyor";

    /// <summary>Yeni bağlantı kimliği (bütün yollar için tek sayaç).</summary>
    internal static long NextId() => Interlocked.Increment(ref lastId);

    /// <summary>Nedenin kısa sabit adı: closed, write_failed, silence, handshake, replaced, stopped, error.</summary>
    public static string Code(TvLinkEndReason reason) => reason switch
    {
        TvLinkEndReason.Closed => "closed",
        TvLinkEndReason.WriteFailed => "write_failed",
        TvLinkEndReason.Silence => "silence",
        TvLinkEndReason.Handshake => "handshake",
        TvLinkEndReason.Replaced => "replaced",
        TvLinkEndReason.Stopped => "stopped",
        _ => "error",
    };

    /// <summary>Günlükte yolun kısa adı: "8787", "47800 web TV", "Android TV 47800".</summary>
    public static string Route(TvLinkKind kind, int port) => kind switch
    {
        TvLinkKind.WebTv => $"{port} web TV",
        TvLinkKind.AndroidTv => $"Android TV {port}",
        _ => port.ToString(System.Globalization.CultureInfo.InvariantCulture),
    };

    /// <summary>Altyazı günlüğü satırı: <c>TV bağlandı (8787, LG OLED55, uygulama 3.2): 192.168.1.20</c>.</summary>
    public static string ConnectedLine(TvLinkConnected e)
    {
        var parts = new List<string> { Route(e.Kind, e.Port) };
        if (!string.IsNullOrWhiteSpace(e.Model)) parts.Add(e.Model!.Trim());
        if (!string.IsNullOrWhiteSpace(e.AppVersion)) parts.Add("uygulama " + e.AppVersion!.Trim());
        var line = $"TV bağlandı ({string.Join(", ", parts)})";
        return string.IsNullOrEmpty(e.Address) ? line : $"{line}: {e.Address}";
    }

    /// <summary>
    /// Altyazı günlüğü satırı: <c>TV koptu (47800 web TV): 15 sn sessizlik [silence], 42 sn bağlı kaldı: 192.168.1.20</c>.
    /// </summary>
    public static string DroppedLine(TvLinkDropped e, TimeSpan silenceLimit)
    {
        var route = Route(e.Kind, e.Port);
        var what = e.Reason switch
        {
            TvLinkEndReason.Closed => "TV bağlantıyı kapattı",
            TvLinkEndReason.WriteFailed => "TV'ye yazılamadı",
            TvLinkEndReason.Silence => $"{(int)Math.Round(silenceLimit.TotalSeconds)} sn sessizlik",
            TvLinkEndReason.Handshake => e.Detail ?? "el sıkışma olmadı",
            TvLinkEndReason.Replaced => "başka bir gönderici TV'yi aldı",
            TvLinkEndReason.Stopped => "Nino kapattı",
            _ => e.Detail is { Length: > 0 } d ? "bağlantı hatası (" + d + ")" : "bağlantı hatası",
        };
        var head = e.Reason switch
        {
            TvLinkEndReason.Handshake => $"TV ile el sıkışılamadı ({route})",
            TvLinkEndReason.Stopped => $"TV bağlantısı kapatıldı ({route})",
            _ => $"TV koptu ({route})",
        };
        var line = $"{head}: {what} [{Code(e.Reason)}]";
        if (e.WasConnected) line += $", {(long)Math.Max(0, e.After.TotalSeconds)} sn bağlı kaldı";
        return string.IsNullOrEmpty(e.Address) ? line : $"{line}: {e.Address}";
    }
}
