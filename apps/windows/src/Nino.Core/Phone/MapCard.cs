// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text.RegularExpressions;
using Nino.Core.Imaging;
using Nino.Core.Reading;

namespace Nino.Core.Phone;

/// <summary>Harita ekranındaki seçili görevin kartı.</summary>
/// <param name="Title">Başlık (yoksa boş).</param>
/// <param name="Sentences">Açıklamanın cümleleri.</param>
/// <param name="Box">Kartın yazılarının kutusu (kareye göre).</param>
/// <param name="LineHeight">Kart satırlarının boyu (ortanca).</param>
public sealed record MapCardText(string Title, IReadOnlyList<string> Sentences, Box Box, double LineHeight)
{
    /// <summary>Başlık ve cümleler boşlukla (başlık boşsa başta bir boşluk kalır).</summary>
    public string All => string.Join(" ", new[] { Title }.Concat(Sentences));
}

/// <summary>Harita görev kartını okumadan bulma ve çerçevesini görüntüden çıkarma.</summary>
public static partial class MapCard
{
    [GeneratedRegex(@"\s?\b\d+(?:[.,]\d+)? ?(?:km|mi|ft|m)\b\s?", RegexOptions.CultureInvariant)]
    private static partial Regex DistancePattern();

    [GeneratedRegex(@"^(?:[^A-Za-z\s]+\s+)+(?=[A-Za-z])", RegexOptions.CultureInvariant)]
    private static partial Regex LeadingSymbols();

    [GeneratedRegex(@"^(?:(?:[iI•●◆△▲]|\S*\d\S*|ml)\s+)+(?=[A-Z])", RegexOptions.CultureInvariant)]
    private static partial Regex LeadingCrumbs();

    [GeneratedRegex(@"(?:\s[^A-Za-z\s]{1,3})+$", RegexOptions.CultureInvariant)]
    private static partial Regex TrailingCrumbs();

    sealed record Candidate(string Text, Box Box);

    static bool IsSentenceLine(string text) =>
        PhoneText.Words(text).Length >= 3 && text.Count(char.IsLower) >= 6;

    static bool EndsSentence(string text) => PhoneText.EndsWithAny(text, ".!?");

    static bool Overlaps(Box a, Box b) => a.Left < b.Right && b.Left < a.Right;

    /// <summary>
    /// Okumadan (kareye göre kutular) kartı bulur; yoksa null. Önce sağ taraf (x &gt; 0,30) aranır; yoksa kart ekranın
    /// solunda da olabilir (duraklatma menüsünün MAP sekmesinde sol üstteki aktivite kartı, ör. BREAKFAST RUN). Solda
    /// yalnız yapısıyla tanınır: büyük harfli başlık hemen üstte, cümleler nokta/ünlem/soruyla biter, en az 6 sözcük;
    /// soldaki menü listesinin satırları bu yapıda değildir.
    /// </summary>
    public static MapCardText? Find(OcrReading reading)
    {
        if (Find(reading, 0.30) is { } right) return right;
        if (Find(reading, 0) is not { } left || left.Title.Length == 0) return null;
        if (PhoneText.Words(string.Join(" ", left.Sentences)).Length < 6 || !left.Sentences.All(EndsSentence)) return null;
        return left;
    }

    static MapCardText? Find(OcrReading reading, double minX)
    {
        var candidates = new List<Candidate>();
        foreach (var line in reading.Lines)
        {
            if (line.Box is not { } b || b.Right <= minX) continue;
            var text = line.Text.Trim();
            if (DistancePattern().IsMatch(text))
            {
                text = DistancePattern().Replace(text, " ").Trim();
                if (minX > 0 && b.Left < 0.5) b = b with { Left = 0.5 };
            }
            var lead = LeadingSymbols().Match(text);
            if (lead.Success && text.Length > 0)
            {
                var shift = (double)lead.Length / text.Length * b.Width;
                text = text[lead.Length..];
                b = b with { Left = b.Left + shift };
            }
            if (b.Left <= minX || PhoneText.LetterCount(text) < 3) continue;
            candidates.Add(new Candidate(text, b));
        }
        candidates = candidates.OrderBy(c => c.Box.Top).ToList();

        var startIndex = candidates.FindIndex(c => IsSentenceLine(c.Text));
        if (startIndex < 0) return null;
        var first = candidates[startIndex];
        var card = new List<Candidate> { first };
        foreach (var c in candidates.Skip(startIndex + 1))
        {
            if (!(c.Box.Top > first.Box.Top)) continue;
            var last = card[^1];
            var gap = c.Box.Top - last.Box.Bottom;
            if (IsSentenceLine(c.Text) && gap < last.Box.Height * 2.6 && Overlaps(c.Box, last.Box)
                && Math.Abs(c.Box.Left - first.Box.Left) < 0.06)
                card.Add(c);
            else if (gap < last.Box.Height * 1.2 && Math.Abs(c.Box.Left - last.Box.Left) < 0.03
                && c.Text.Any(char.IsLower) && !EndsSentence(last.Text))
                card.Add(c);
        }

        // Cümlelere ayırma.
        var edge = card.Max(c => c.Box.Right);
        var sentences = new List<List<Candidate>>();
        foreach (var c in card)
        {
            if (sentences.Count > 0)
            {
                var prev = sentences[^1];
                var prevLast = prev[^1];
                var continues = PhoneText.StartsLower(c.Text) && !EndsSentence(prevLast.Text);
                var below = Math.Abs(c.Box.Left - prev[0].Box.Left) < 0.03
                    && c.Box.Top - prevLast.Box.Bottom < prevLast.Box.Height
                    && !(prevLast.Box.Right < edge - 0.04 && PhoneText.StartsUpper(c.Text));
                if (continues || below)
                {
                    prev.Add(c);
                    continue;
                }
            }
            sentences.Add([c]);
        }

        // Başlık: ilk cümle satırının hemen üstündeki büyük harfli satır (en alttaki).
        Candidate? title = null;
        foreach (var c in candidates)
        {
            if (c.Box.Bottom <= first.Box.Top + 0.01 && first.Box.Top - c.Box.Bottom < 0.06
                && c.Box.Left < first.Box.Right && first.Box.Left < c.Box.Right + 0.05
                && c.Text == c.Text.ToUpperInvariant() && PhoneText.LetterCount(c.Text) >= 3)
                title = c;
        }

        var box = card.Select(c => c.Box).Aggregate((a, b) => a.Union(b));
        if (title is not null) box = box.Union(title.Box);
        foreach (var c in candidates)
        {
            if (c.Box.Top < box.Bottom - 0.005) continue;
            if (c.Box.Top - box.Bottom < 0.05 && c.Box.Left > box.Left - 0.03 && c.Box.Right < box.Right + 0.08)
                box = box.Union(c.Box);
        }
        var heights = card.Select(c => c.Box.Height).OrderBy(h => h).ToArray();
        var lineHeight = heights[heights.Length / 2];

        var texts = sentences.Select(s => LeadingCrumbs().Replace(
            string.Join(" ", s.Select(c => c.Text)).Replace("- ", "-"), "")).ToList();
        var titleText = title is null ? "" : TrailingCrumbs().Replace(title.Text, "");
        return new MapCardText(titleText, texts, box, lineHeight);
    }

    /// <summary>
    /// Kartın koyu çerçevesi (harita açık zeminli): yazı kutusundan dört yana kenar yürüyüşü. Bulunamazsa null.
    /// </summary>
    public static Box? FindFrame(BgraFrame frame, Box text) => FindFrame(new FrameSampler(frame, 640, 360), text);

    /// <summary>Örnekleyiciyle çerçeve.</summary>
    public static Box? FindFrame(IColorSampler sampler, Box text)
    {
        bool Dark(double x, double y) => sampler.At(x, y) is { } c && c.Luma < 130;
        var rows = new List<double>();
        for (var i = 0; ; i++)
        {
            var y = text.Top + 0.01 + 0.02 * i;
            if (!(y < text.Bottom)) break;
            rows.Add(y);
        }
        var cols = new List<double>();
        for (var i = 0; ; i++)
        {
            var x = text.Left + 0.01 + 0.03 * i;
            if (!(x < text.Right)) break;
            cols.Add(x);
        }
        if (rows.Count == 0 || cols.Count == 0) return null;
        int AtX(double x) => rows.Count(y => Dark(x, y));
        int AtY(double y) => cols.Count(x => Dark(x, y));

        var left = Walk(text.Left, -0.003, 0.04, AtX, rows.Count);
        var right = Walk(text.Right, 0.003, 0.09, AtX, rows.Count);
        var bottom = Walk(text.Bottom, 0.004, 0.08, AtY, cols.Count);
        var top = Walk(text.Top, -0.004, 0.06, AtY, cols.Count);
        if (Math.Abs(left - text.Left) >= 0.04 - 0.004) left = text.Left - 0.015;
        if (Math.Abs(right - text.Right) >= 0.09 - 0.004) right = text.Right + 0.02;
        if (Math.Abs(bottom - text.Bottom) >= 0.08 - 0.004) bottom = text.Bottom + 0.02;
        if (Math.Abs(top - text.Top) >= 0.06 - 0.004) top = text.Top - 0.02;
        if (right - left <= text.Width) return null;
        return new Box(left, top, right, bottom);
    }

    static double Walk(double start, double step, double limit, Func<double, int> counter, int total)
    {
        var pos = start;
        while (Math.Abs(pos - start) < limit)
        {
            if (counter(pos + step) * 2 >= total)
            {
                pos += step;
                continue;
            }
            var jumped = false;
            for (var k = 2; k <= 4; k++)
            {
                var next = pos + step * k;
                if (counter(next) * 2 < total) continue;
                if (Math.Abs(next - start) >= limit) return pos;
                pos = next;
                jumped = true;
                break;
            }
            if (!jumped) break;
        }
        return pos;
    }
}
