// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text;
using System.Text.RegularExpressions;

namespace Nino.Core.Translation;

/// <summary>Satırın bir parçası: çevrilecek metin ya da olduğu gibi kalan ayraç/etiket.</summary>
public readonly record struct SubtitlePiece(string Text, bool Translatable)
{
    /// <summary>Konuşmacı etiketi mi (<c>ATREUS: </c>).</summary>
    public bool IsLabel => !Translatable && Text.EndsWith(": ", StringComparison.Ordinal);

    /// <summary>Etiketin adı (sondaki <c>": "</c> atılmış); etiket değilse null.</summary>
    public string? LabelName => IsLabel ? Text[..^2] : null;
}

/// <summary>
/// Altyazı bölücüsü (çeviri tarifi §3): satırı bloklara, blokları cümlelere ayırır; konuşmacı etiketlerini ve diyalog
/// tirelerini çevrilmeyen parça yapar. Parçalar art arda birleşince satırın sadeleşmiş hâli çıkar.
/// </summary>
public static partial class SubtitleSplitter
{
    // "Ad:" gibi görünse de konuşmacı olmayan sözcükler (görev/ipucu başlıkları, ünlemler).
    static readonly HashSet<string> NotLabels = new(StringComparer.OrdinalIgnoreCase)
    {
        "and", "answer", "but", "chapter", "controls", "example", "goal", "hint", "hold", "info", "level", "listen",
        "location", "look", "mission", "new", "no", "note", "now", "objective", "objectives", "ok", "okay", "press",
        "quest", "question", "remember", "result", "results", "reward", "rewards", "so", "status", "tap", "task",
        "then", "time", "tip", "tutorial", "update", "wait", "warning", "well", "yes",
    };

    // Ardından gelen nokta cümleyi bitirmez.
    static readonly HashSet<string> Abbreviations = new(StringComparer.OrdinalIgnoreCase)
    {
        "capt", "col", "dr", "e.g", "etc", "gen", "i.e", "jr", "lt", "mr", "mrs", "ms", "mt", "prof", "sgt", "sr",
        "st", "vs",
    };

    const string Terminals = ".!?…";
    const string Closers = "\"'”’)]";

    // Ad: tümü büyük (ATREUS, SINDRI JR.) ya da baş harfi büyük (Kratos, Mimir Head); ardından ":" ve boşluk.
    [GeneratedRegex(@"^(?<name>\p{Lu}[\p{Lu}\p{Nd}'’.\-]+(?: \p{Lu}[\p{Lu}\p{Nd}'’.\-]*){0,2}|\p{Lu}\p{Ll}[\p{L}'’.\-]*(?: \p{Lu}[\p{L}'’.\-]*){0,2}):\s+",
        RegexOptions.CultureInvariant)]
    private static partial Regex LabelRegex();

    [GeneratedRegex(@"^[-–—]+")]
    private static partial Regex LeadingDashes();

    [GeneratedRegex(@"\s+")]
    private static partial Regex Whitespace();

    static readonly SubtitlePiece LineBreak = new("\n", false);
    static readonly SubtitlePiece Space = new(" ", false);

    /// <summary>Satırı parçalar.</summary>
    public static IReadOnlyList<SubtitlePiece> Split(string? text)
    {
        var output = new List<SubtitlePiece>();
        if (string.IsNullOrEmpty(text)) return output;

        var first = true;
        foreach (var block in Blocks(text))
        {
            if (!first) output.Add(LineBreak);
            first = false;
            AddBlock(output, Whitespace().Replace(block, " ").Trim());
        }
        return output;
    }

    // Satırları bloklara toplar: etiket ya da tireyle başlayan satır yeni blok açar, diğerleri öncekine eklenir.
    static List<string> Blocks(string text)
    {
        var blocks = new List<string>();
        foreach (var piece in text.Replace("\r\n", "\n").Split('\n'))
        {
            var row = piece.Trim();
            if (row.Length == 0) continue;
            var opensBlock = blocks.Count == 0 || LeadingDashes().IsMatch(row) || MatchLabel(row) is not null;
            if (opensBlock) blocks.Add(row);
            else blocks[^1] = blocks[^1] + " " + row;
        }
        return blocks;
    }

    static void AddBlock(List<SubtitlePiece> output, string block)
    {
        var dashes = LeadingDashes().Match(block);
        if (dashes.Success)
        {
            output.Add(new SubtitlePiece(dashes.Value + " ", false));
            block = block[dashes.Length..].TrimStart();
        }

        var index = 0;
        foreach (var sentence in Sentences(block))
        {
            if (index++ > 0) output.Add(Space);
            var rest = sentence;
            var label = MatchLabel(rest);
            if (label.HasValue)
            {
                output.Add(new SubtitlePiece(label.Value.Name + ": ", false));
                rest = rest[label.Value.Length..];
            }
            if (rest.Length > 0) output.Add(new SubtitlePiece(rest, rest.Any(char.IsLetter)));
        }
    }

    /// <summary>Parçaları art arda birleştirir.</summary>
    public static string Join(IEnumerable<SubtitlePiece> pieces) => string.Concat(pieces.Select(p => p.Text));

    /// <summary>Konuşmacı etiketlerinin adları (sırayla).</summary>
    public static IEnumerable<string> LabelNames(IEnumerable<SubtitlePiece> pieces)
    {
        foreach (var piece in pieces)
            if (piece.LabelName is { } name) yield return name;
    }

    /// <summary>
    /// Metin bir konuşmacı etiketiyle başlıyorsa adı ve etiketin (ardındaki boşluklar dahil) uzunluğu.
    /// </summary>
    public static (string Name, int Length)? MatchLabel(string text)
    {
        var hit = LabelRegex().Match(text);
        if (!hit.Success) return null;
        var who = hit.Groups["name"].Value;
        var singleWord = who.IndexOf(' ') < 0;
        return singleWord && NotLabels.Contains(who) ? null : (who, hit.Length);
    }

    /// <summary>Bloğu cümlelere böler (boşluklar teklenmiş olmalı).</summary>
    internal static List<string> Sentences(string block)
    {
        var found = new List<string>();
        var from = 0;
        var pos = 0;
        while (pos < block.Length)
        {
            if (Terminals.IndexOf(block[pos]) < 0)
            {
                pos++;
                continue;
            }

            var gap = Skip(block, pos, Terminals);
            gap = Skip(block, gap, Closers);
            var followed = gap + 1 < block.Length && block[gap] == ' ';
            if (followed && !SentenceGoesOn(block, from, gap))
            {
                found.Add(block[from..gap]);
                from = gap + 1;
            }
            pos = gap;
        }
        if (from < block.Length) found.Add(block[from..]);
        return found;
    }

    static int Skip(string text, int at, string set)
    {
        while (at < text.Length && set.IndexOf(text[at]) >= 0) at++;
        return at;
    }

    // Boşluktan sonra küçük harf, tek büyük harf + nokta (baş harf) ya da bilinen kısaltma: cümle sürüyor.
    static bool SentenceGoesOn(string block, int from, int gap)
    {
        if (char.IsLower(block[gap + 1])) return true;
        var segment = block.AsSpan(from, gap - from);
        if (segment.Length == 0 || segment[^1] != '.') return false;
        var head = segment[..^1];
        var lastWord = head[(head.LastIndexOf(' ') + 1)..].ToString();
        if (lastWord.Length == 1) return char.IsUpper(lastWord[0]) || Abbreviations.Contains(lastWord);
        return Abbreviations.Contains(lastWord);
    }
}
