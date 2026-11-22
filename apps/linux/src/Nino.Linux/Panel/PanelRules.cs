// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Linux.Ports;

namespace Nino.Linux.Panel;

/// <summary>Panelden gelen girdilerin denetimi.</summary>
public static class PanelRules
{
    public const double ShortestRegion = 0.05;
    public const double NarrowestRegion = 0.1;

    /// <summary>Bölge karenin içinde ve okunabilecek kadar büyük mü.</summary>
    public static bool IsUsable(PanelRegion region) =>
        region.Top >= 0 && region.Left >= 0 && region.Bottom <= 1 && region.Right <= 1
        && region.Bottom - region.Top >= ShortestRegion
        && region.Right - region.Left >= NarrowestRegion;

    /// <summary>
    /// Kullanıcı Sony'nin yönlendirme adresini tam, yalnız sorgu kısmıyla ("code=…") ya da yalnız kodla
    /// yapıştırabilir; üçü de aynı adrese çevrilir. Adres kurulamazsa null.
    /// </summary>
    public static Uri? RedirectFrom(string pasted, string prefix)
    {
        var text = (pasted ?? "").Trim();
        if (text.Length == 0) return null;
        if (!text.Contains("://", StringComparison.Ordinal))
        {
            var query = text.Contains('=') ? text.TrimStart('?') : "code=" + text;
            text = prefix + "?" + query;
        }
        return Uri.TryCreate(text, UriKind.Absolute, out var address) ? address : null;
    }

    /// <summary>Çevrimiçi anahtarın türü: Anthropic anahtarları bu önekle başlar, gerisi DeepL sayılır.</summary>
    public const string ClaudeKeyPrefix = "sk-ant-";

    public static string EngineForKey(string key) =>
        key.Trim().StartsWith(ClaudeKeyPrefix, StringComparison.Ordinal) ? "Claude" : "DeepL";
}
