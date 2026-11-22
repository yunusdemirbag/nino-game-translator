// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text.RegularExpressions;

namespace Nino.Core.Reading;

/// <summary>
/// Oyunun kumanda ipuçları ("R2 Swing", "△ Pick up", "Press ✕ to jump") altyazı değildir: çevrilmez, yerleri altyazının
/// yerine katılmaz.
/// </summary>
public static partial class ButtonHints
{
    static HashSet<string> Set(string items) => new(items.Split(' '), StringComparer.Ordinal);

    static readonly HashSet<string> Buttons = Set("R1 R2 R3 L1 L2 L3 OPTIONS TOUCHPAD ✕ × ⨯ ✖ ○ ◯ ● □ ▢ ◻ ■ △ ▲ ⨂");

    static readonly HashSet<string> StrongButtons = Set("R1 R2 R3 L1 L2 L3 TOUCHPAD ✕ ○ ◯ □ △ ▲");

    static readonly HashSet<string> Actions = Set("press hold tap push use mash release");

    static readonly HashSet<string> Adverbs =
        Set("slowly quickly gently carefully rapidly repeatedly continuously briefly");

    static readonly char[] Separators = [' ', '\t', '+', '/'];
    static readonly char[] Brackets = ['(', ')', '[', ']', '{', '}', '<', '>', '「', '」'];

    // 1–3 kez "tek karakter + boşluk", sonra büyük harfli bir sözcük ve en çok iki büyük harfli sözcük daha.
    [GeneratedRegex(@"^\s*(?:\S\s+){1,3}[A-Z][A-Z']{2,}(?:\s+[A-Z][A-Z']+){0,2}\s*$", RegexOptions.CultureInvariant)]
    private static partial Regex IconPattern();

    static bool IsButton(string part) => Buttons.Contains(part.ToUpperInvariant());

    static bool IsLetterLikeButton(string part) => part is "X" or "O";

    /// <summary>Satır bir düğme ipucu mu (sırayla ilk tutan kural karar verir).</summary>
    public static bool IsHint(string? line)
    {
        var text = line ?? "";
        if (IconPattern().IsMatch(text)) return true;
        var parts = text.Split(Separators, StringSplitOptions.None)
            .Select(p => p.Trim(Brackets)).Where(p => p.Length > 0).ToArray();
        if (parts.Length == 0) return false;
        var words = parts.Count(p => !IsButton(p) && p.Any(char.IsLetter));
        var ends = TextKey.EndsSentence(text);
        if (IsButton(parts[0])) return words <= 5;
        if (IsButton(parts[^1]) && words <= 4 && !ends) return true;
        if (IsLetterLikeButton(parts[0]) && parts.Length is >= 2 and <= 4 && parts.Length > 1
            && char.IsUpper(parts[1][0]) && !ends) return true;
        if (Actions.Contains(parts[0].ToLowerInvariant()) && parts.Length is >= 2 and <= 10
            && (IsButton(parts[1]) || IsLetterLikeButton(parts[1]))) return true;
        if (Adverbs.Contains(parts[0].ToLowerInvariant()) && parts.Length is >= 3 and <= 16
            && parts.Skip(2).Any(p => p.ToLowerInvariant() == "to") && !ends) return true;
        if (parts.Length <= 16 && parts.Any(p => StrongButtons.Contains(p.ToUpperInvariant()))
            && parts.Any(p => p.ToLowerInvariant() == "to") && !ends) return true;
        return false;
    }

    /// <summary>Okumadan ipucu satırlarını atar (hiçbiri atılmadıysa aynı nesne).</summary>
    public static OcrReading Remove(OcrReading reading) => reading.Where(l => !IsHint(l.Text));
}
