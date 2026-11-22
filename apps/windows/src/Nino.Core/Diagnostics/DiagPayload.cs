// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Globalization;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace Nino.Core.Diagnostics;

/// <summary>
/// <c>diag</c> olayının alan kuralları (sunucunun doğrulayıcısıyla aynı karakter kuralları ve sınırlar). Kurala uymayan
/// alan atılır; kural kodu geçersizse olay hiç kurulmaz. Ağ adresine benzeyen dizgeler de atılır.
/// </summary>
public static partial class DiagPayload
{
    /// <summary><c>state</c> en çok anahtar.</summary>
    public const int MaxStateKeys = 30;

    /// <summary><c>trail</c> en çok adım.</summary>
    public const int MaxTrail = 40;

    /// <summary><c>ver</c> en çok bileşen.</summary>
    public const int MaxVersions = 6;

    [GeneratedRegex("^[a-z0-9_.]{1,40}$")]
    private static partial Regex RuleRule();

    [GeneratedRegex("^[A-Za-z0-9_.$-]{1,64}$")]
    private static partial Regex CodeRule();

    [GeneratedRegex("^[A-Za-z0-9_.$-]{1,40}$")]
    private static partial Regex ShortRule();

    [GeneratedRegex("^[A-Za-z0-9_]{1,24}$")]
    private static partial Regex KeyRule();

    [GeneratedRegex("^[0-9A-Za-z.+-]{1,24}$")]
    private static partial Regex VersionRule();

    [GeneratedRegex("^[A-Za-z0-9][A-Za-z0-9 ,._()+-]{0,59}$")]
    private static partial Regex ModelRule();

    [GeneratedRegex("^[a-z0-9][a-z0-9._-]{0,63}$")]
    private static partial Regex GameRule();

    // Noktalı dört sayı (IPv4) ya da uzun onaltılık dizi (MAC/kimlik parçası): kod olarak geçse bile gönderilmez.
    [GeneratedRegex(@"(^|[^0-9])\d{1,3}(\.\d{1,3}){3}([^0-9]|$)|[0-9A-Fa-f]{2}([-.][0-9A-Fa-f]{2}){5}")]
    private static partial Regex AddressLike();

    static readonly HashSet<string> Brands = new(StringComparer.Ordinal) { "androidtv", "samsung", "lg" };

    /// <summary>Kural kodu geçerli mi.</summary>
    public static bool IsRule(string? rule) => rule is not null && RuleRule().IsMatch(rule);

    /// <summary>İz kodu geçerli mi (ölçümdeki hata kodu kuralı; adrese benzeyen olmaz).</summary>
    public static bool IsCode(string? code) => code is not null && CodeRule().IsMatch(code) && !AddressLike().IsMatch(code);

    /// <summary><c>state</c> ya da <c>cause</c> için kısa kod geçerli mi.</summary>
    public static bool IsShort(string? value) => value is not null && ShortRule().IsMatch(value) && !AddressLike().IsMatch(value);

    /// <summary>Gönderilebilir sayı mı (sonlu, makul büyüklük).</summary>
    public static bool IsNumber(double n) => double.IsFinite(n) && Math.Abs(n) < 1e9;

    /// <summary>Sayı düğümü: tam sayıysa tam sayı, değilse iki basamaklı ondalık.</summary>
    public static JsonNode NumberNode(double n) =>
        n == Math.Floor(n) && Math.Abs(n) < long.MaxValue ? JsonValue.Create((long)n) : JsonValue.Create(Math.Round(n, 2));

    /// <summary>
    /// Olayın gövdesi (<c>k</c> ve <c>t</c> dahil). Kural geçersizse null. Bütün alanlar süzülür.
    /// </summary>
    public static JsonObject? Build(DateTimeOffset at, string rule, string? cause, DiagSeverity severity,
        IEnumerable<KeyValuePair<string, object?>>? state, JsonArray? trail, DiagTv? tv, string? game,
        IEnumerable<KeyValuePair<string, string?>>? versions)
    {
        if (!IsRule(rule)) return null;
        var body = new JsonObject
        {
            ["k"] = "diag",
            ["t"] = at.ToUnixTimeSeconds(),
            ["rule"] = rule,
            ["cause"] = IsShort(cause) ? cause : DiagRules.Unknown,
            ["sev"] = DiagRules.Code(severity),
            ["state"] = State(state),
            ["trail"] = Trail(trail),
        };
        if (Tv(tv) is { Count: > 0 } t) body["tv"] = t;
        game = Nino.Core.Library.GameIds.Canonical(game);
        if (game is not null && GameRule().IsMatch(game)) body["game"] = game;
        if (Versions(versions) is { Count: > 0 } v) body["ver"] = v;
        return body;
    }

    /// <summary>
    /// Var olan bir gövdeyi sunucunun kurallarıyla yeniden süzer (testler ve gönderim öncesi son denetim). Kural
    /// geçersizse null.
    /// </summary>
    public static JsonObject? Clean(JsonObject e)
    {
        var rule = Str(e["rule"]);
        if (!IsRule(rule)) return null;
        var sev = Str(e["sev"]) switch { "info" => DiagSeverity.Info, "error" => DiagSeverity.Error, _ => DiagSeverity.Warn };
        var state = (e["state"] as JsonObject)?.Select(kv => new KeyValuePair<string, object?>(kv.Key, Scalar(kv.Value)));
        DiagTv? tv = e["tv"] is JsonObject o ? new DiagTv(Str(o["brand"]), Str(o["model"]), Str(o["app"])) : null;
        var ver = (e["ver"] as JsonObject)?.Select(kv => new KeyValuePair<string, string?>(kv.Key, Str(kv.Value)));
        var at = Number(e["t"]) is { } t && t is >= 0 and < 1e11 ? DateTimeOffset.FromUnixTimeSeconds((long)t) : DateTimeOffset.UnixEpoch;
        return Build(at, rule!, Str(e["cause"]), sev, state, e["trail"] as JsonArray, tv, Str(e["game"]), ver);
    }

    static JsonObject State(IEnumerable<KeyValuePair<string, object?>>? state)
    {
        var o = new JsonObject();
        if (state is null) return o;
        foreach (var (k, v) in state)
        {
            if (o.Count >= MaxStateKeys) break;
            if (!KeyRule().IsMatch(k) || o.ContainsKey(k)) continue;
            switch (v)
            {
                case bool b:
                    o[k] = b;
                    break;
                case string s when IsShort(s):
                    o[k] = s;
                    break;
                case int or long or double or float or decimal:
                    var d = Convert.ToDouble(v, CultureInfo.InvariantCulture);
                    if (double.IsFinite(d) && Math.Abs(d) < 1e12) o[k] = NumberNode(d);
                    break;
            }
        }
        return o;
    }

    static JsonArray Trail(JsonArray? trail)
    {
        var clean = new JsonArray();
        if (trail is null) return clean;
        foreach (var node in trail.Skip(Math.Max(0, trail.Count - MaxTrail)))
        {
            if (node is not JsonArray step || step.Count < 2) continue;
            if (Number(step[0]) is not { } ago || ago < -3600 || ago > 0) continue;
            if (Str(step[1]) is not { } code || !IsCode(code)) continue;
            var c = new JsonArray(JsonValue.Create((long)Math.Round(ago)), JsonValue.Create(code));
            if (step.Count > 2 && Number(step[2]) is { } n && IsNumber(n)) c.Add(NumberNode(n));
            clean.Add(c);
        }
        return clean;
    }

    static JsonObject Tv(DiagTv? tv)
    {
        var o = new JsonObject();
        if (tv is null) return o;
        if (tv.Brand is { } b && Brands.Contains(b)) o["brand"] = b;
        if (tv.Model is { } m && ModelRule().IsMatch(m) && !AddressLike().IsMatch(m)) o["model"] = m;
        if (tv.App is { } a && VersionRule().IsMatch(a)) o["app"] = a;
        return o;
    }

    static JsonObject Versions(IEnumerable<KeyValuePair<string, string?>>? versions)
    {
        var o = new JsonObject();
        if (versions is null) return o;
        foreach (var (k, v) in versions)
        {
            if (o.Count >= MaxVersions) break;
            if (KeyRule().IsMatch(k) && v is not null && VersionRule().IsMatch(v) && !o.ContainsKey(k)) o[k] = v;
        }
        return o;
    }

    static string? Str(JsonNode? n) => n is JsonValue v && v.TryGetValue<string>(out var s) ? s : null;

    /// <summary>Sayı düğümünü okur (bellekte kurulmuş ya da ayrıştırılmış; tam sayı ya da ondalık).</summary>
    internal static double? Number(JsonNode? n)
    {
        if (n is not JsonValue v) return null;
        if (v.TryGetValue<double>(out var d)) return d;
        if (v.TryGetValue<long>(out var l)) return l;
        if (v.TryGetValue<int>(out var i)) return i;
        if (v.TryGetValue<decimal>(out var m)) return (double)m;
        if (v.TryGetValue<float>(out var f)) return f;
        return null;
    }

    static object? Scalar(JsonNode? n) => n switch
    {
        JsonValue v when v.TryGetValue<bool>(out var b) => b,
        JsonValue v when v.TryGetValue<string>(out var s) => s,
        JsonValue v when Number(v) is { } d => d,
        _ => null,
    };
}

/// <summary>Bildirimdeki TV bilgisi: marka (<c>androidtv</c>/<c>samsung</c>/<c>lg</c>), model (ad değil), TV'deki Nino sürümü.</summary>
public sealed record DiagTv(string? Brand, string? Model, string? App);
