// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;

namespace Nino.Core.Phone;

/// <summary>
/// Karede bulunan telefon ekranı (paralelkenar): çevreleyen kutu, üst kenardaki sol x, eğim (bir kare yüksekliği
/// aşağı inince sol kenarın kare genişliğine oranla kayması) ve ekran genişliği.
/// </summary>
public sealed record PhoneShape(Box Box, double TopLeft, double Slant, double Width)
{
    /// <summary>Dik telefon (eğim 0, sol = kutunun solu, genişlik = kutunun genişliği).</summary>
    public static PhoneShape Upright(Box box) => new(box, box.Left, 0, box.Width);

    /// <summary><paramref name="y"/> yüksekliğinde ekranın sol kenarı.</summary>
    public double LeftAt(double y) => TopLeft + Slant * (y - Box.Top);

    /// <summary><paramref name="y"/> yüksekliğinde ekranın ortası.</summary>
    public double CenterAt(double y) => LeftAt(y) + Width / 2;

    /// <summary>Dönme açısı (derece, saat yönü artı): <c>atan(−eğim × 16 / 9)</c>.</summary>
    public double AngleDegrees => Math.Atan(-Slant * 16 / 9) * 180 / Math.PI;
}

/// <summary>
/// Telefonu karede bulma: kare 240 × 135'e küçültülür; açık ekran, kararmış ekran ve koyu temalı uygulama için
/// sırayla şekil araması yapılır.
/// </summary>
public static class PhoneFinder
{
    /// <summary>Arama ızgarasının genişliği.</summary>
    public const int GridWidth = 240;

    /// <summary>Arama ızgarasının yüksekliği.</summary>
    public const int GridHeight = 135;

    /// <summary>Sınanan en çok aday.</summary>
    public const int MaxCandidates = 32;

    /// <summary>Karede telefonu arar; yoksa null.</summary>
    public static PhoneShape? Find(BgraFrame frame)
    {
        if (RgbGrid.Downscale(frame, GridWidth, GridHeight) is not { } g) return null;
        return Find(g);
    }

    /// <summary>Küçültülmüş ızgarada telefonu arar.</summary>
    public static PhoneShape? Find(RgbGrid g)
    {
        int W = g.Width, H = g.Height;
        var low = new int[W * H];
        var spread = new int[W * H];
        var max = new int[W * H];
        for (var y = 0; y < H; y++)
            for (var x = 0; x < W; x++)
            {
                var c = g.At(x, y);
                var i = y * W + x;
                low[i] = c.Min;
                max[i] = c.Max;
                spread[i] = c.Max - c.Min;
            }

        // 1. Açık ekran.
        var found = Search(W, H, (x, y) => low[y * W + x] >= 118 && spread[y * W + x] <= 45, (x, y) => low[y * W + x] < 90);
        if (found is not null) return found;

        // 2. Kararmış ekran: ortadaki noktaların %95'lik düşük değeri 40–117 ise kazançla aydınlatılır.
        var samples = new List<int>();
        for (var y = H / 10; y < H * 9 / 10; y += 2)
            for (var x = W * 15 / 100; x < W * 85 / 100; x += 2)
                samples.Add(low[y * W + x]);
        if (samples.Count > 0)
        {
            samples.Sort();
            var slice = samples[samples.Count * 95 / 100];
            if (slice is >= 40 and < 118)
            {
                var gain = 225.0 / slice;
                found = Search(W, H,
                    (x, y) => (int)(low[y * W + x] * gain) >= 118 && (int)(spread[y * W + x] * gain) <= 45,
                    (x, y) => (int)(low[y * W + x] * gain) < 90);
                if (found is not null) return found;
            }
        }

        // 3. Koyu temalı uygulama.
        found = Search(W, H, (x, y) => max[y * W + x] <= 75 && spread[y * W + x] <= 40, (x, y) => max[y * W + x] >= 85);
        if (found is null || found.Box.Bottom > 0.96) return null;
        return HasDarkThemeText(found, W, H, max) ? found : null;
    }

    /// <summary>Koyu ekranın içinde yazı satırları var mı (koyu kıyafet/gölge de koyu dikdörtgen verir).</summary>
    internal static bool HasDarkThemeText(PhoneShape phone, int W, int H, int[] max)
    {
        var top = (int)Math.Floor(phone.Box.Top * H);
        var bottom = (int)Math.Floor(phone.Box.Bottom * H);
        var written = 0;
        for (var y = top; y < Math.Max(bottom, top + 1); y++)
        {
            var start = (int)Math.Floor(phone.LeftAt((double)y / H) * W) + 2;
            var end = start + (int)Math.Floor(phone.Width * W) - 4;
            if (end <= start) continue;
            var bright = 0;
            var row = Math.Clamp(y, 0, H - 1);
            for (var x = Math.Max(0, start); x <= Math.Min(W - 1, end); x++)
                if (max[row * W + x] >= 110) bright++;
            if (bright >= 2 && bright <= (end - start + 1) * 0.6) written++;
        }
        return written >= Math.Max(1, bottom - top) * 0.15;
    }

    readonly record struct Strip(int Start, int End);

    readonly record struct Candidate(int Votes, double Slope, int Key);

    static int RoundAway(double v) => (int)Math.Round(v, MidpointRounding.AwayFromZero);

    /// <summary>
    /// Şekil araması: beyaz şeritler, eğim oylaması, aday sınaması. <paramref name="white"/> ve
    /// <paramref name="dark"/> ızgara noktası sınamalarıdır.
    /// </summary>
    internal static PhoneShape? Search(int W, int H, Func<int, int, bool> white, Func<int, int, bool> dark)
    {
        var strips = FindStrips(W, H, white);

        var candidates = new List<Candidate>();
        foreach (var slope in Slopes())
        {
            var votes = new Dictionary<int, int>();
            for (var y = 0; y < H; y++)
                foreach (var s in strips[y])
                {
                    var intercept = RoundAway(s.Start - slope * y);
                    var key = (intercept + 400) / 2 * 1000 + (s.End - s.Start) / 2;
                    votes[key] = votes.GetValueOrDefault(key) + 1;
                }
            foreach (var kv in votes.OrderByDescending(kv => kv.Value).ThenBy(kv => kv.Key).Take(3))
                if (kv.Value >= 8) candidates.Add(new Candidate(kv.Value, slope, kv.Key));
        }
        foreach (var c in candidates.OrderByDescending(c => c.Votes).Take(MaxCandidates))
            if (Test(c, W, H, strips, white, dark) is { } phone) return phone;
        return null;
    }

    /// <summary>Eğimler (nokta/satır): 0, +0,02, −0,02, … , +0,30, −0,30.</summary>
    static IEnumerable<double> Slopes()
    {
        yield return 0;
        for (var i = 1; i <= 15; i++)
        {
            yield return i * 0.02;
            yield return -i * 0.02;
        }
    }

    static List<Strip>[] FindStrips(int W, int H, Func<int, int, bool> white)
    {
        var minLen = (int)(W * 0.12);
        var maxLen = (int)(W * 0.30);
        var rows = new List<Strip>[H];
        for (var y = 0; y < H; y++)
        {
            var list = new List<Strip>();
            var x = 0;
            while (x < W)
            {
                if (!white(x, y))
                {
                    x++;
                    continue;
                }
                var start = x;
                var end = x;
                for (var j = end + 1; j < W && j - end <= 4; j++)
                    if (white(j, y)) end = j;
                var last = end;

                // Kırıntı atma (gümüş çerçevenin 1–2 noktalık parlak çizgisi), baştan.
                while (end - start > 6)
                {
                    var c = 0;
                    while (start + c <= end && white(start + c, y)) c++;
                    if (c <= 2 && !IsWhite(start + c, y) && !IsWhite(start + c + 1, y))
                    {
                        start += c;
                        while (start <= end && !white(start, y)) start++;
                    }
                    else break;
                }
                // Sondan.
                while (end - start > 6)
                {
                    var c = 0;
                    while (end - c >= start && white(end - c, y)) c++;
                    if (c <= 2 && !IsWhite(end - c, y) && !IsWhite(end - c - 1, y))
                    {
                        end -= c;
                        while (end >= start && !white(end, y)) end--;
                    }
                    else break;
                }
                var length = end - start + 1;
                if (length >= minLen && length <= maxLen) list.Add(new Strip(start, end));
                x = last + 1;
            }
            rows[y] = list;
        }
        return rows;

        bool IsWhite(int x, int y) => x >= 0 && x < W && white(x, y);
    }

    static PhoneShape? Test(Candidate c, int W, int H, List<Strip>[] strips, Func<int, int, bool> white,
        Func<int, int, bool> dark)
    {
        var slope = c.Slope;
        var estIntercept = c.Key / 1000 * 2 - 400;
        var estWidth = c.Key % 1000 * 2;

        var matched = new List<(int Row, Strip Strip)>();
        for (var y = 0; y < H; y++)
            foreach (var s in strips[y])
                if (Math.Abs(s.Start - (estIntercept + slope * y)) < 3.5 && Math.Abs(s.End - s.Start - estWidth) < 4)
                {
                    matched.Add((y, s));
                    break;
                }
        if (matched.Count == 0) return null;

        // Parçalar (ardışık satırlar arası en çok 10); iç parça varsa yalnız iç parçalar kalır.
        var segments = new List<List<(int Row, Strip Strip)>>();
        foreach (var m in matched)
        {
            if (segments.Count == 0 || m.Row - segments[^1][^1].Row > 10) segments.Add([]);
            segments[^1].Add(m);
        }
        if (segments.Count > 1)
        {
            var inner = segments.Where(s => s[0].Row > 1 && s[^1].Row < H - 2).ToList();
            if (inner.Count > 0) matched = inner.SelectMany(s => s).ToList();
        }
        if (matched.Count < 8) return null;

        var intercepts = matched.Select(m => m.Strip.Start - slope * m.Row).OrderBy(v => v).ToArray();
        var intercept = intercepts[intercepts.Length / 2];
        var widths = matched.Select(m => m.Strip.End - m.Strip.Start).OrderBy(v => v).ToArray();
        var sw = widths[widths.Length / 2];
        int LeftOf(int row) => RoundAway(intercept + slope * row);

        // Çerçeve: iki yanda koyu (ya da en azından beyaz olmayan) nokta.
        int framed = 0, edged = 0;
        foreach (var (row, _) in matched)
        {
            var left = LeftOf(row);
            bool leftDark = false, rightDark = false, leftNotWhite = false, rightNotWhite = false;
            for (var d = 1; d <= 4; d++)
            {
                var lx = Math.Max(0, left - d);
                var rx = Math.Min(W - 1, left + sw + d);
                if (dark(lx, row)) leftDark = true;
                if (dark(rx, row)) rightDark = true;
                if (!white(lx, row)) leftNotWhite = true;
                if (!white(rx, row)) rightNotWhite = true;
            }
            if (leftDark && rightDark) framed++;
            if (leftNotWhite && rightNotWhite) edged++;
        }
        var n = matched.Count;
        if (!(framed >= n * 0.7 || (edged >= n * 0.85 && framed >= n * 0.35))) return null;

        // Üst/alt kenar: parlak satırlarla uzatılır.
        bool Bright(int row)
        {
            var lo = Math.Max(0, LeftOf(row));
            var hi = Math.Min(W - 1, LeftOf(row) + sw);
            if (hi < lo) return false;
            var count = 0;
            for (var x = lo; x <= hi; x++)
                if (white(x, row)) count++;
            return count >= (hi - lo + 1) / 2.0;
        }
        var first = matched[0].Row;
        var last = matched[^1].Row;
        while (first - 1 >= 0 && Bright(first - 1)) first--;
        while (last + 1 < H && Bright(last + 1)) last++;

        var span = last - first + 1;
        var tall = (double)span / H;
        if (tall < 0.38 || tall > 0.86 || n < span * 0.25) return null;
        var aspect = tall * 9 / ((sw + 1) / (double)W * 16);
        if (aspect < 1.2 || aspect > 2.6) return null;

        var topLeft = intercept + slope * first;
        var bottomLeft = intercept + slope * last;
        var box = new Box(Math.Max(0, Math.Min(topLeft, bottomLeft)) / W, (double)first / H,
            Math.Min(W, Math.Max(topLeft, bottomLeft) + sw + 1) / W, (double)(last + 1) / H);
        if (box.CenterX < 0.30 || box.CenterX > 0.80 || box.Top < 0.04) return null;
        if (!(box.Bottom <= 0.96 || box.Top >= 0.2)) return null;
        return new PhoneShape(box, topLeft / W, slope * H / W, (sw + 1) / (double)W);
    }
}
