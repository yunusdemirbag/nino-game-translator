// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text.RegularExpressions;

namespace Nino.Core.Reading;

/// <summary>Altyazının başındaki konuşan adıyla ayrılmış hali ("ARTHUR" / "Move out now.").</summary>
public readonly record struct SpeakerSplit(string? Name, string Sentence)
{
    /// <summary>Ad var mı.</summary>
    public bool HasName => Name is not null;
}

/// <summary>
/// Konuşan adı: çeviriye gitmez; paket önce adlı satırla, sonra adsız cümleyle aranır; ekranda ad ayara göre yeniden
/// başa konur ya da hiç yazılmaz.
/// </summary>
public static partial class SpeakerName
{
    /// <summary>Adın en çok karakter sayısı.</summary>
    public const int MaxLength = 24;

    static readonly HashSet<string> NotNames = new((
        "note warning tip hint objective objectives quest goal new reward rewards location chapter mission task " +
        "tutorial update info status level controls press hold tap remember example question answer result results " +
        "time listen look wait okay ok well so yes no now then and but").Split(' '), StringComparer.Ordinal);

    [GeneratedRegex(@"^(?<name>\p{Lu}[\p{L}'’.\-]*(?: \p{Lu}[\p{L}'’.\-]*){0,2}) ?[:：]\s*(?<rest>.*)$",
        RegexOptions.Singleline | RegexOptions.CultureInvariant)]
    private static partial Regex Pattern();

    /// <summary>Metni ada ve cümleye ayırır; ad yoksa cümle kırpılmış metnin kendisidir.</summary>
    public static SpeakerSplit Split(string? text)
    {
        var t = (text ?? "").Trim();
        var m = Pattern().Match(t);
        if (!m.Success) return new(null, t);
        var name = m.Groups["name"].Value;
        var rest = m.Groups["rest"].Value.Trim();
        if (name.Length > MaxLength) return new(null, t);
        if (!name.Contains(' ') && NotNames.Contains(name.ToLowerInvariant())) return new(null, t);
        if (!rest.Any(char.IsLetter) || rest.StartsWith('/')) return new(null, t);
        return new(name, rest);
    }

    /// <summary>
    /// Çeviriyi sunar: kaynağın adı varsa ve çevirinin adı ondan farklıysa çevirinin başına "Ad: " eklenir.
    /// <paramref name="show"/> kapalıysa kaynaktaki adlarla başlayan her satırdan ad atılır.
    /// </summary>
    public static string Present(string translated, string original, bool showName)
    {
        var src = Split(original);
        var result = translated;
        if (src.Name is { } name && Split(translated).Name != name) result = name + ": " + translated;
        if (showName) return result;
        var names = new HashSet<string>(StringComparer.Ordinal);
        if (src.Name is not null) names.Add(src.Name);
        foreach (var line in original.Replace("\r\n", "\n").Split('\n'))
            if (Split(line).Name is { } n) names.Add(n);
        if (names.Count == 0) return result;
        return string.Join("\n", result.Replace("\r\n", "\n").Split('\n').Select(line =>
        {
            var s = Split(line);
            return s.Name is { } n && names.Contains(n) ? s.Sentence : line;
        }));
    }
}
