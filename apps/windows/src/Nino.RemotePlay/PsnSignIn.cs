// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text;

namespace Nino.RemotePlay;

/// <summary>
/// PSN girişinin adresleri ve yönlendirme okuma (ikinci hesabın kimliği için). İstemci bilgileri chiaki-ng'nin
/// herkese açık PSN girişiyle aynıdır.
/// </summary>
public static class PsnSignIn
{
    public const string ClientId = "ba495a24-818c-472b-b12d-ff231c1b5745";
    public const string ClientSecret = "mvaiZkRsAsI1IBkY";
    public const string AuthorizeUrl = "https://auth.api.sonyentertainmentnetwork.com/2.0/oauth/authorize";
    public const string TokenUrl = "https://auth.api.sonyentertainmentnetwork.com/2.0/oauth/token";
    const string RemotePlayHost = "https://remoteplay.dl.playstation.net";
    public const string RedirectPrefix = RemotePlayHost + "/remoteplay/redirect";
    public const string Scope =
        "psn:clientapp referenceDataService:countryConfig.read pushNotification:webSocket.desktop.connect sessionManager:remotePlaySession.system.update";

    /// <summary>Sony alanları (sayfa metni iletisinin geldiği yer denetlenirken).</summary>
    public static readonly string[] SonyDomains = ["sony.com", "sonyentertainmentnetwork.com", "playstation.com", "playstation.net"];

    /// <summary>Giriş sayfasının adresi (sorgu sırası sabit).</summary>
    public static string SignInUrl()
    {
        // Ad, değer çiftleri; sıra Sony'nin beklediği gibi.
        string[] pairs =
        [
            "service_entity", "urn:service-entity:psn", "response_type", "code", "client_id", ClientId,
            "redirect_uri", RedirectPrefix, "scope", Scope, "request_locale", "en_US", "ui", "pr",
            "service_logo", "ps", "layout_type", "popup", "smcid", "remoteplay", "prompt", "always",
            "PlatformPrivacyWs1", "minimal",
        ];
        var sb = new StringBuilder(AuthorizeUrl).Append('?');
        for (int i = 0; i < pairs.Length; i += 2)
            sb.Append(i == 0 ? "" : "&").Append(Encode(pairs[i])).Append('=').Append(Encode(pairs[i + 1]));
        return sb.ToString();
    }

    /// <summary>Jeton isteğinin gövdesi.</summary>
    public static string TokenRequestBody(string code) =>
        $"grant_type=authorization_code&code={Encode(code)}&scope={Encode(Scope)}&redirect_uri={Encode(RedirectPrefix)}";

    /// <summary>
    /// Sorgu kodlaması: UTF-8 baytları; ASCII harf/rakam ve <c>-._~:/?@!$'()*,;</c> olduğu gibi, gerisi %XX (büyük harf).
    /// </summary>
    public static string Encode(string text)
    {
        const string keep = "-._~:/?@!$'()*,;";
        var sb = new StringBuilder(text.Length);
        foreach (byte b in Encoding.UTF8.GetBytes(text))
        {
            char c = (char)b;
            if (b < 0x80 && (char.IsAsciiLetterOrDigit(c) || keep.Contains(c)))
                sb.Append(c);
            else
                sb.Append('%').Append(b.ToString("X2"));
        }
        return sb.ToString();
    }

    /// <summary>Adres mutlak ve (büyük/küçük harfe duyarlı) yönlendirme önekiyle başlıyor mu.</summary>
    public static bool IsRedirect(string? url) =>
        url is not null && Uri.TryCreate(url, UriKind.Absolute, out _) && url.StartsWith(RedirectPrefix, StringComparison.Ordinal);

    /// <summary>Yönlendirmedeki <c>code</c> değeri; yönlendirme değilse ya da kod yoksa null.</summary>
    public static string? Code(string? url)
    {
        if (!IsRedirect(url))
            return null;
        return Query(url!).TryGetValue("code", out string? code) && code.Length > 0 ? code : null;
    }

    /// <summary>Yönlendirmedeki Sony hatası ("error: açıklama (kod)") ya da null.</summary>
    public static string? SonyError(string? url)
    {
        if (!IsRedirect(url))
            return null;
        var q = Query(url!);
        q.TryGetValue("error", out string? error);
        q.TryGetValue("error_description", out string? description);
        q.TryGetValue("error_code", out string? code);
        return FormatSonyError(error, description, code);
    }

    internal static string? FormatSonyError(string? error, string? description, string? code)
    {
        if (string.IsNullOrEmpty(error))
            return null;
        var sb = new StringBuilder(error);
        if (!string.IsNullOrEmpty(description))
            sb.Append(": ").Append(description.Replace('+', ' '));
        if (!string.IsNullOrEmpty(code))
            sb.Append(" (").Append(code).Append(')');
        return sb.ToString();
    }

    /// <summary>Sorgu parçaları (ad ve değer URL'den çözülür; <c>=</c> yoksa değer boş).</summary>
    public static Dictionary<string, string> Query(string url)
    {
        var result = new Dictionary<string, string>(StringComparer.Ordinal);
        int q = url.IndexOf('?');
        if (q < 0)
            return result;
        string query = url[(q + 1)..];
        int hash = query.IndexOf('#');
        if (hash >= 0)
            query = query[..hash];
        foreach (string part in query.Split('&', StringSplitOptions.RemoveEmptyEntries))
        {
            int eq = part.IndexOf('=');
            string name = Uri.UnescapeDataString(eq < 0 ? part : part[..eq]);
            string value = eq < 0 ? "" : Uri.UnescapeDataString(part[(eq + 1)..]);
            result[name] = value;
        }
        return result;
    }

    /// <summary>
    /// Yapıştırılan metinden yönlendirme adresi: önek (büyük/küçük harf duyarsız) aranır, ardından boşluk, tırnak, &lt; ya
    /// da &gt; görülene kadar alınır. Kod ya da Sony hatası varsa adres, değilse null.
    /// </summary>
    public static string? RedirectFromText(string? text)
    {
        if (string.IsNullOrEmpty(text))
            return null;
        int at = text.IndexOf(RedirectPrefix, StringComparison.OrdinalIgnoreCase);
        if (at < 0)
            return null;
        int start = at + RedirectPrefix.Length;
        int end = start;
        while (end < text.Length && !char.IsWhiteSpace(text[end]) && text[end] is not ('"' or '\'' or '<' or '>'))
            end++;
        string url = RedirectPrefix + text[start..end];
        if (!Uri.TryCreate(url, UriKind.Absolute, out _))
            return null;
        return Code(url) is not null || SonyError(url) is not null ? url : null;
    }

    /// <summary>Sony'nin "sunucuya bağlanılamıyor" sayfası mı (sayfa metninden).</summary>
    public static bool IsCannotConnectPage(string? pageText)
    {
        if (string.IsNullOrEmpty(pageText))
            return false;
        string[] leads = ["can not", "cannot", "can't", "can’t", "could not", "couldn't", "unable to"];
        foreach (string lead in leads)
            if (pageText.Contains(lead + " connect to the server", StringComparison.OrdinalIgnoreCase))
                return true;
        return false;
    }

    /// <summary>Ana bilgisayar Sony alanlarından biri mi.</summary>
    public static bool IsSonyHost(string? host)
    {
        if (string.IsNullOrEmpty(host))
            return false;
        host = host.ToLowerInvariant();
        return SonyDomains.Any(d => host == d || host.EndsWith("." + d, StringComparison.Ordinal));
    }

    /// <summary>"Çok fazla deneme" gibi mi.</summary>
    public static bool LooksRateLimited(string? text)
    {
        if (text is null)
            return false;
        string[] signs = ["too many", "too_many", "rate limit"];
        return signs.Any(sign => text.Contains(sign, StringComparison.OrdinalIgnoreCase));
    }
}

/// <summary>PSN hesap numarası: 8 bayt, küçük uçlu.</summary>
public static class PsnAccountId
{
    /// <summary>Sony'nin ondalık, işaretsiz 64 bit <c>user_id</c>'sinden 8 bayt; okunamazsa null.</summary>
    public static byte[]? FromUserId(string? userId)
    {
        if (string.IsNullOrEmpty(userId) || !userId.All(char.IsAsciiDigit)
            || !ulong.TryParse(userId, System.Globalization.NumberStyles.None,
                               System.Globalization.CultureInfo.InvariantCulture, out ulong value))
            return null;
        return BitConverter.IsLittleEndian
            ? BitConverter.GetBytes(value)
            : BitConverter.GetBytes(value).Reverse().ToArray();
    }

    /// <summary>Elle yazılan base64 kimlik: boşluklar atılır, tam 12 karakter ve 8 bayt olmalı; değilse null.</summary>
    public static byte[]? FromManualText(string? text)
    {
        if (text is null)
            return null;
        string compact = new(text.Where(c => !char.IsWhiteSpace(c)).ToArray());
        if (compact.Length != 12)
            return null;
        try
        {
            byte[] decoded = Convert.FromBase64String(compact);
            return decoded.Length != 8 ? null : decoded;
        }
        catch (FormatException)
        {
            return null;
        }
    }
}
