// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Globalization;

namespace Nino.Core.Reading;

/// <summary>Yığındaki satırın rolü.</summary>
public enum StackRole
{
    /// <summary>İki önceki satır (en üstte).</summary>
    SecondPrevious,

    /// <summary>Önceki satır.</summary>
    Previous,

    /// <summary>Şimdiki satır.</summary>
    Current,
}

/// <summary>Yığının görünen bir satırı.</summary>
public sealed record StackLine(long Id, string Text, StackRole Role, bool Fading, bool Paragraphs);

/// <summary>
/// Bilgisayardaki altyazı penceresinin yığını (TV uygulamasıyla aynı kurallar): yeni satır kısa süre içinde gelirse
/// önceki üstte kalır, sonra solar. Zaman saniye cinsinden dışarıdan verilir. Kilitsizdir.
/// </summary>
public sealed class SubtitleStack
{
    /// <summary>Önceki satır, yeni satır bu süre içinde gelirse üstte kalır.</summary>
    public const double StackWindow = 1.5;

    /// <summary>Üste çıkan satırın solmadan önce durduğu süre.</summary>
    public const double HoldBeforeFade = 1.5;

    /// <summary>Solma süresi.</summary>
    public const double Fade = 0.4;

    /// <summary>En kısa görünme.</summary>
    public const double MinVisible = 1.2;

    /// <summary>"Temizle"nin bekleyeceği en uzun okuma süresi.</summary>
    public const double MaxClearWait = 5;

    /// <summary>Opaklıklar: şimdiki, önceki, iki önceki.</summary>
    public const double CurrentOpacity = 1, PreviousOpacity = 0.6, SecondPreviousOpacity = 0.45;

    sealed class Current
    {
        public long Id;
        public string Text = "";
        public bool Paragraphs;
        public double Shown;
        public double RemoveAt;
        public double EarliestClear;
    }

    sealed record Upper(long Id, string Text, double Shown)
    {
        public double FadeAt => Shown + HoldBeforeFade;
        public double GoneAt => FadeAt + Fade;
    }

    Current? _current;
    Upper? _previous;
    Upper? _second;
    long _nextId;

    /// <summary>"Önceki satırı üste çıkar" (<c>StackPrevious</c>).</summary>
    public bool StackPrevious { get; set; } = true; // ayarın varsayılanı

    void DropExpired(double now)
    {
        if (_current is not null && now >= _current.RemoveAt)
        {
            _current = null;
            _previous = null;
            _second = null;
            return;
        }
        if (_previous is not null && now >= _previous.GoneAt) _previous = null;
        if (_second is not null && now >= _second.GoneAt) _second = null;
    }

    /// <summary>Satır gösterir.</summary>
    public void Show(string text, int durationMs, bool paragraphs, double now, bool replace = false)
    {
        DropExpired(now);
        // Yerine konan düzeltmede (satır satır değilse) üsttekiler olduğu gibi kalır.
        var keepUpper = replace && _current is not null && !paragraphs;
        if (keepUpper) { }
        else if (StackPrevious && _current is { } cur && now - cur.Shown < StackWindow && !cur.Paragraphs && !paragraphs
                 && !SameLine(cur.Text, text))
        {
            _second = _previous is { } prev && now < prev.FadeAt && !SameLine(prev.Text, cur.Text) ? prev with { Shown = now } : null;
            _previous = new Upper(cur.Id, cur.Text, now);
        }
        else
        {
            _previous = null;
            _second = null;
        }
        var reading = 2 + text.Length * 0.06;
        double visible = Math.Min(8, reading);
        if (durationMs > 0) visible = Math.Max(MinVisible, durationMs / 1000.0);
        _current = new Current
        {
            Id = ++_nextId,
            Text = text,
            Paragraphs = paragraphs,
            Shown = now,
            RemoveAt = now + visible,
            EarliestClear = now + Math.Min(MaxClearWait, reading),
        };
    }

    /// <summary>"Temizle": en erken temizlenme geçtiyse hepsi kalkar, değilse satır o anda kalkar.</summary>
    public void Clear(double now)
    {
        DropExpired(now);
        if (_current is null) return;
        if (now >= _current.EarliestClear)
        {
            Hide();
            return;
        }
        _current.RemoveAt = _current.EarliestClear;
    }

    /// <summary>Hepsi hemen kalkar (çeviri durdu).</summary>
    public void Hide()
    {
        _current = null;
        _previous = null;
        _second = null;
    }

    /// <summary>Görünen satırlar (üstten alta).</summary>
    public IReadOnlyList<StackLine> Lines(double now)
    {
        if (_current is null || now >= _current.RemoveAt) return [];
        var list = new List<StackLine>();
        if (_second is { } s && now < s.GoneAt) list.Add(new(s.Id, s.Text, StackRole.SecondPrevious, now >= s.FadeAt, false));
        if (_previous is { } p && now < p.GoneAt) list.Add(new(p.Id, p.Text, StackRole.Previous, now >= p.FadeAt, false));
        list.Add(new(_current.Id, _current.Text, StackRole.Current, false, _current.Paragraphs));
        return list;
    }

    /// <summary>Şimdiden sonraki ilk değişim anı (yoksa null).</summary>
    public double? NextChange(double now)
    {
        if (_current is null) return null;
        var times = new List<double> { _current.RemoveAt };
        foreach (var u in new[] { _previous, _second })
            if (u is not null) times.AddRange([u.FadeAt, u.GoneAt]);
        var after = times.Where(t => t > now).ToArray();
        return after.Length == 0 ? null : after.Min();
    }

    const string LineTrim = ".,!?;:…\"'“”‘’«»()[]-–—";

    static string Normalize(string text) => string.Join(" ",
        TextKey.Words(text.ToLowerInvariant()).Select(w => w.Trim(LineTrim.ToCharArray())).Where(w => w.Length > 0));

    static bool Contains(string x, string y) =>
        x.Replace(" ", "").Contains(y.Replace(" ", ""), StringComparison.Ordinal)
        && (y.Contains(' ') || (" " + x + " ").Contains(" " + y + " ", StringComparison.Ordinal));

    /// <summary>Aynı satır mı (biri ötekinin büyümüş ya da noktalaması değişmiş okuması).</summary>
    public static bool SameLine(string first, string second)
    {
        var x = Normalize(first);
        var y = Normalize(second);
        if (x.Length * y.Length == 0) return x.Length == y.Length;
        if (x.Replace(" ", "") == y.Replace(" ", "")) return true;
        return Contains(x, y) || Contains(y, x);
    }

    /// <summary>Görünecek metin: satır satırsa aynen (ölçek 1), değilse sarılmış hali.</summary>
    public static (string Text, double Scale) Visible(string text, bool paragraphs) =>
        paragraphs ? (text, 1) : LineWrap.Wrap(text);
}

/// <summary>
/// Uzun çeviri sarma: satır başına en çok 42 karakter, en çok 3 satır, sözcük sınırından ve dengeli; 3 satıra
/// sığmayacaksa yazı küçülür (ölçek en az 0,75). Konuşan adı bölünmez, hep ilk satırdadır.
/// </summary>
public static class LineWrap
{
    /// <summary>Satır başına karakter.</summary>
    public const int LineChars = 42;

    /// <summary>En çok satır.</summary>
    public const int MaxLines = 3;

    /// <summary>En küçük ölçek.</summary>
    public const double MinScale = 0.75;

    /// <summary>Metni sarar; (satırlar <c>\n</c> ile, ölçek).</summary>
    public static (string Text, double Scale) Wrap(string text)
    {
        int length = new StringInfo(text).LengthInTextElements;
        if (length <= LineChars || text.Contains('\n')) return (text, 1);
        var words = TextKey.Words(text).ToList();
        var nameAt = words.Take(3).ToList().FindIndex(w => w.EndsWith(':') || w.EndsWith('：'));
        if (nameAt >= 0 && nameAt + 1 < words.Count)
        {
            var merged = string.Join(" ", words.Take(nameAt + 2));
            words.RemoveRange(0, nameAt + 2);
            words.Insert(0, merged);
        }
        if (words.Count < 2) return (text, 1);
        var scale = Math.Clamp(126.0 / length, MinScale, 1);
        var limit = (int)Math.Floor(LineChars / scale);
        var lines = Math.Min(MaxLines, Math.Max(2, (int)Math.Ceiling((double)length / limit)));
        lines = Math.Min(lines, words.Count);
        int Span(int start, int end) => words.Skip(start).Take(end - start).Sum(w => w.Length) + end - start - 1;
        int[]? best = null;
        (int Max, long Squares) bestScore = (int.MaxValue, long.MaxValue);
        void Consider(int[] cuts)
        {
            var bounds = new[] { 0 }.Concat(cuts).Append(words.Count).ToArray();
            var widths = Enumerable.Range(0, bounds.Length - 1).Select(k => Span(bounds[k], bounds[k + 1])).ToArray();
            var score = (widths.Max(), widths.Sum(w => (long)w * w));
            if (score.Item1 < bestScore.Max || (score.Item1 == bestScore.Max && score.Item2 < bestScore.Squares))
            {
                bestScore = score;
                best = cuts;
            }
        }
        if (lines == 2 || words.Count < 3)
            for (var c = 1; c < words.Count; c++) Consider([c]);
        else
            for (var c1 = 1; c1 < words.Count - 1; c1++)
                for (var c2 = c1 + 1; c2 < words.Count; c2++) Consider([c1, c2]);
        var b = new[] { 0 }.Concat(best!).Append(words.Count).ToArray();
        var result = string.Join("\n", Enumerable.Range(0, b.Length - 1).Select(k => string.Join(" ", words.Skip(b[k]).Take(b[k + 1] - b[k]))));
        return (result, scale);
    }
}
