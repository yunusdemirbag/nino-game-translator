// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace Nino.Core.Telemetry;

/// <summary>
/// Tek ölçüm olayı (<c>{"k": tür, "t": unix saniye, …}</c>). Yalnız kodlar ve sayılar taşır; altyazı metni, ad, adres,
/// yol ya da istisna iletisi asla konmaz. Kurucular alanları sunucunun kurallarına göre süzer.
/// </summary>
public sealed partial class TelemetryEvent
{
    TelemetryEvent(JsonObject body) => Body = body;

    /// <summary>Olayın JSON'u (gövdeye olduğu gibi girer).</summary>
    public JsonObject Body { get; }

    /// <summary>Tür (<c>launch</c>, <c>error</c>…).</summary>
    public string Kind => Body["k"]!.GetValue<string>();

    /// <summary>Çökme olayları günlük sınıra ve kuyruk atmaya takılmaz.</summary>
    public bool IsCrash => Kind == "crash";

    /// <summary>Diskten okunan olay.</summary>
    internal static TelemetryEvent? FromJson(JsonNode? node) =>
        node is JsonObject o && o["k"] is JsonValue k && k.TryGetValue<string>(out _) && o["t"] is JsonValue
            ? new TelemetryEvent((JsonObject)o.DeepClone())
            : null;

    static TelemetryEvent Make(string kind, DateTimeOffset at) =>
        new(new JsonObject { ["k"] = kind, ["t"] = at.ToUnixTimeSeconds() });

    TelemetryEvent With(string name, JsonNode? value)
    {
        if (value is not null) Body[name] = value;
        return this;
    }

    /// <summary>Uygulama açıldı (<c>ms</c>: soğuk açılış süresi).</summary>
    public static TelemetryEvent Launch(DateTimeOffset at, long? ms = null) =>
        Make("launch", at).With("ms", ms is { } v ? Math.Max(0, v) : null);

    /// <summary>Çeviri oturumu bitti.</summary>
    public static TelemetryEvent Session(DateTimeOffset at, long durationSeconds, string? game, SessionSource source,
        long lines, SessionTimings? timings) =>
        Make("session", at)
            .With("dur", Math.Max(0, durationSeconds))
            .With("game", TelemetryText.Game(game))
            .With("src", source switch
            {
                SessionSource.Capture => "capture",
                SessionSource.Xbox => "xbox",
                SessionSource.Screen => "screen",
                _ => "remoteplay",
            })
            .With("lines", Math.Max(0, lines))
            .With("h", timings?.ToJson());

    /// <summary>Önceki çalışma çöktü (<c>ver</c>: çöken sürüm, <c>up</c>: çalışma süresi sn).</summary>
    public static TelemetryEvent Crash(DateTimeOffset at, string? code, string? where, string version, long? uptimeSeconds) =>
        Make("crash", at)
            .With("code", TelemetryText.Code(code) ?? "unclean_exit")
            .With("where", TelemetryText.Where(where))
            .With("ver", TelemetryText.AppVersion(version))
            .With("up", uptimeSeconds is { } u ? Math.Max(0, u) : null);

    /// <summary>Yakalanan hata (yalnız kod; <c>http</c> durum kodu, <c>n</c> tekrar).</summary>
    public static TelemetryEvent Error(DateTimeOffset at, string code, int? http = null, int? count = null) =>
        Make("error", at)
            .With("code", TelemetryText.Code(code) ?? TelemetryCodes.Invalid)
            .With("http", http)
            .With("n", count is > 1 ? count : null);

    /// <summary>PS5 bağlantı denemesi bitti (<c>r</c>: <c>ok</c> ya da hata kodu).</summary>
    public static TelemetryEvent Ps5Connect(DateTimeOffset at, string result, long ms, Ps5Route via) =>
        Make("ps5_connect", at)
            .With("r", Result(result))
            .With("ms", Math.Max(0, ms))
            .With("via", via switch { Ps5Route.Remote => "remote", Ps5Route.Xbox => "xbox", _ => "lan" });

    /// <summary>Bağlıyken PS5 koptu.</summary>
    public static TelemetryEvent Ps5Drop(DateTimeOffset at, string reason, long afterSeconds) =>
        Make("ps5_drop", at).With("code", TelemetryText.Code(reason) ?? "other").With("after", Math.Max(0, afterSeconds));

    /// <summary>TV bağlantı denemesi bitti.</summary>
    public static TelemetryEvent TvConnect(DateTimeOffset at, string result, long ms, TvBrand brand, TvProtocol proto) =>
        Make("tv_connect", at)
            .With("r", Result(result))
            .With("ms", Math.Max(0, ms))
            .With("brand", TelemetryText.Brand(brand))
            .With("proto", proto == TvProtocol.Legacy ? "legacy" : "nino");

    /// <summary>Bağlıyken TV koptu.</summary>
    public static TelemetryEvent TvDrop(DateTimeOffset at, string reason, TvBrand brand, long afterSeconds) =>
        Make("tv_drop", at)
            .With("code", TelemetryText.Code(reason) ?? "other")
            .With("brand", TelemetryText.Brand(brand))
            .With("after", Math.Max(0, afterSeconds));

    static string Result(string result) =>
        result == "ok" ? "ok" : TelemetryText.Code(result) ?? TelemetryCodes.Invalid;

    /// <summary>Aynı kodlu hata mı (birleştirme için).</summary>
    internal bool SameErrorAs(TelemetryEvent other) =>
        Kind == "error" && other.Kind == "error"
        && Body["code"]?.GetValue<string>() == other.Body["code"]?.GetValue<string>()
        && Body["http"]?.GetValue<int>() == other.Body["http"]?.GetValue<int>();

    /// <summary>Hata tekrarını bir artırır.</summary>
    internal void IncrementCount(int by)
    {
        var n = Body["n"]?.GetValue<int>() ?? 1;
        Body["n"] = n + by;
    }
}

/// <summary>Oturumun görüntü kaynağı.</summary>
public enum SessionSource { RemotePlay, Capture, Xbox, Screen }

/// <summary>PS5 bağlantı yolu.</summary>
public enum Ps5Route { Lan, Remote, Xbox }

/// <summary>TV markası (ölçümde).</summary>
public enum TvBrand { None, AndroidTv, Samsung, Lg }

/// <summary>TV protokolü.</summary>
public enum TvProtocol { Nino, Legacy }

/// <summary>Sık kullanılan kodlar (tarifteki liste açık uçludur).</summary>
public static class TelemetryCodes
{
    /// <summary>Verilen kod kurala uymadığında yerine konan kod (iletinin kendisi asla gitmez).</summary>
    public const string Invalid = "app.code.invalid";

    /// <summary>Bilinmeyen çökme.</summary>
    public const string UncleanExit = "unclean_exit";
}

/// <summary>Alan süzgeçleri (sunucunun karakter kurallarıyla aynı).</summary>
public static partial class TelemetryText
{
    [GeneratedRegex("^[A-Za-z0-9_.$-]{1,64}$")]
    private static partial Regex CodeRule();

    [GeneratedRegex("^[A-Za-z0-9_.:$<>+-]{1,120}$")]
    private static partial Regex WhereRule();

    [GeneratedRegex("^[a-z0-9][a-z0-9._-]{0,63}$")]
    private static partial Regex GameRule();

    [GeneratedRegex("^[0-9A-Za-z.+-]{1,24}$")]
    private static partial Regex AppRule();

    [GeneratedRegex("^[a-z0-9_.]{1,32}(:[a-z0-9_-]{1,24})?$")]
    private static partial Regex MetricRule();

    /// <summary>Hata kodu kurala uyuyorsa o, değilse null.</summary>
    public static string? Code(string? code) => code is not null && CodeRule().IsMatch(code) ? code : null;

    /// <summary>Çökme yeri (yalnız sembol); kurala uymuyorsa null.</summary>
    public static string? Where(string? where) => where is not null && WhereRule().IsMatch(where) ? where : null;

    /// <summary>Oyun kimliği (asıl kimliğe çevrilmiş: <c>gta-vi</c> → <c>gta-6</c>); kurala uymuyorsa boş.</summary>
    public static string Game(string? game) =>
        Nino.Core.Library.GameIds.Canonical(game) is { } id && GameRule().IsMatch(id) ? id : "";

    /// <summary>Nino'nun sürümü; kurala uymuyorsa boş.</summary>
    public static string AppVersion(string? app) => app is not null && AppRule().IsMatch(app) ? app : "";

    /// <summary>Süre ölçümü adı geçerli mi.</summary>
    public static bool IsMetricName(string name) => MetricRule().IsMatch(name);

    /// <summary>Marka adı.</summary>
    public static string Brand(TvBrand brand) => brand switch
    {
        TvBrand.AndroidTv => "androidtv",
        TvBrand.Samsung => "samsung",
        TvBrand.Lg => "lg",
        _ => "",
    };

    /// <summary>Metni en çok <paramref name="max"/> karaktere keser.</summary>
    public static string Cut(string? text, int max)
    {
        var t = (text ?? "").Trim();
        return t.Length > max ? t[..max] : t;
    }
}
