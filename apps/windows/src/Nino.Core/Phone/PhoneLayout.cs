// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;
using Nino.Core.Reading;

namespace Nino.Core.Phone;

/// <summary>
/// Telefonun yanındaki yerleşim: sohbet paneli (zemin + balonlar) ve uygulama balonları. Bütün kutular kareye göre.
/// Windows'ta balon açısı TV'ye gönderilmez (öğelerde açı yok).
/// </summary>
public static class PhoneLayout
{
    /// <summary>Panel sütununun genişliği.</summary>
    public const double PanelWidth = 0.27;

    /// <summary>Sütun hesabının varsayılan genişliği (yalnız testte).</summary>
    public const double DefaultColumnWidth = 0.30;

    static readonly Rgb DefaultEdge = new(233, 233, 236);
    static readonly Rgb DefaultFloor = new(226, 228, 233);
    static readonly Rgb NoColorFill = new(58, 58, 60);

    const string DarkInk = "#2c2c2e";
    const string LightInk = "#f5f5f7";

    /// <summary>Bir mesajın oyundaki balon rengi ve çevirisi ("kaplama").</summary>
    public sealed record Overlay(string Source, string Text, Box MessageBox, Box Box, double LineHeight, Rgb Fill, string Ink);

    /// <summary>
    /// Sarma ölçüsü: satır başı harf <c>max(12, ⌊genişlik / max(0,004, boy × 0,5 × 9/16)⌋)</c>; sözcük sözcük.
    /// Döner: (satır sayısı, en uzun satırın uzunluğu).
    /// </summary>
    public static (int Lines, int Longest) Wrap(string text, double width, double lineHeight)
    {
        var perLine = Math.Max(12, (int)Math.Floor(width / Math.Max(0.004, lineHeight * 0.5 * 9 / 16)));
        var lines = new List<string>();
        var current = "";
        foreach (var word in PhoneText.Words(text))
        {
            if (current.Length > 0 && current.Length + 1 + word.Length > perLine)
            {
                lines.Add(current);
                current = word;
            }
            else current = current.Length == 0 ? word : current + " " + word;
        }
        if (current.Length > 0) lines.Add(current);
        if (lines.Count == 0) return (1, text.Length);
        return (lines.Count, lines.Max(l => l.Length));
    }

    /// <summary>Telefonun yanındaki sütun: telefon sağ yarıdaysa solunda, değilse sağında.</summary>
    public static (double Left, double Right) Column(Box phone, double width = DefaultColumnWidth)
    {
        if (phone.CenterX > 0.5)
        {
            var right = phone.Left - 0.035;
            return (Math.Max(0.02, right - width), right);
        }
        var left = phone.Right + 0.035;
        return (left, Math.Min(0.98, left + width));
    }

    /// <summary>Mesajların balon renkleri; çevirisi boş ya da değmeyen mesajlar atılır.</summary>
    public static List<Overlay> Overlays(IReadOnlyList<PhoneMessage> messages, IReadOnlyList<string> translations,
        IColorSampler sampler)
    {
        var list = new List<Overlay>();
        for (var i = 0; i < Math.Min(messages.Count, translations.Count); i++)
        {
            var m = messages[i];
            var text = (translations[i] ?? "").Trim();
            if (text.Length == 0 || !PhoneText.WorthShowing(m.Text, text)) continue;
            var b = m.Box;
            Rgb? edge = null;
            foreach (var ratio in new[] { 0.15, 0.35, 0.5, 0.65, 0.85 })
                foreach (var pad in new[] { 0.0045, 0.0045 * 0.6 })
                    if (sampler.At(b.Left - pad, b.Top + b.Height * ratio) is { } c
                        && (edge is null || c.Luma1000 > edge.Value.Luma1000)) edge = c;
            var edgeColor = edge ?? DefaultEdge;
            var inner = new List<Rgb>();
            for (var yi = 0; yi < 8; yi++)
                for (var xi = 0; xi < 9; xi++)
                    if (sampler.At(b.Left + b.Width * (0.1 + 0.1 * xi), b.Top + b.Height * (0.15 + 0.1 * yi)) is { } c)
                        inner.Add(c);
            var sorted = inner.OrderBy(c => c.Luma1000).ToArray();
            Rgb fill;
            if (sorted.Length >= 10)
            {
                var k = sorted.Length * 4 / 10;
                var floor = sorted[^k..];
                var middle = floor[floor.Length / 2];
                fill = middle.Luma1000 * 4 < edgeColor.Luma1000 * 3 ? edgeColor : middle;
            }
            else fill = edgeColor;
            var ink = fill.Luma > 140 ? DarkInk : LightInk;
            var box = new Box(b.Left - 0.0035, b.Top - 0.004, b.Right + 0.0035, b.Bottom + 0.004);
            list.Add(new Overlay(m.Text, text, b, box, m.LineHeight, fill, ink));
        }
        return list;
    }

    /// <summary>
    /// Sohbet paneli: telefonun yanında zemin (yarı saydam) ve üst üste binmeyen balonlar; giden mesajlar sağa,
    /// gelenler sola. Öğe sırası: zemin, sonra balonlar.
    /// </summary>
    public static List<ScreenItem> ChatPanel(IReadOnlyList<PhoneMessage> messages, IReadOnlyList<string> translations,
        PhoneShape phone, IColorSampler sampler, string? title)
    {
        var overlays = Overlays(messages, translations, sampler);
        if (overlays.Count == 0) return [];
        var (colLeft, colRight) = Column(phone.Box, PanelWidth);
        var innerLeft = colLeft + 0.012;
        var innerRight = colRight - 0.012;
        var maxWidth = (innerRight - innerLeft) * 0.82;
        const double pad = 0.012;

        // Her kaplama, kaynağı aynı metin olan ilk mesaja eşlenir.
        PhoneMessage MessageOf(Overlay o) => messages.First(m => m.Text == o.Source);

        var sizes = new List<(double Size, int Lines, int Longest, double Top)>();
        foreach (var o in overlays)
        {
            var m = MessageOf(o);
            var size = Math.Min(Math.Max(m.LineHeight, 0.018), 0.028) * 0.97;
            var (lines, longest) = Wrap(o.Text, maxWidth - pad, size);
            sizes.Add((size, lines, longest, m.Box.Top));
        }

        var tops = new double[overlays.Count];
        var heights = new double[overlays.Count];
        var floorY = 0.0;
        for (var i = 0; i < overlays.Count; i++)
        {
            var (size, lines, _, top) = sizes[i];
            var height = size * Math.Max(1, lines) * 1.3;
            var t = Math.Min(Math.Max(top, floorY), Math.Max(0, 0.98 - height));
            tops[i] = t;
            heights[i] = height;
            floorY = t + height + size * 0.6;
        }
        var limit = phone.Box.Bottom - 0.012 - 0.03;
        var lastBottom = tops[^1] + heights[^1];
        if (lastBottom > limit)
        {
            var shift = lastBottom - limit;
            for (var i = 0; i < tops.Length; i++) tops[i] -= shift;
        }

        // Giden mesajlar.
        var screenWidth = phone.Width;
        int Blue(Rgb c) => c.B - (c.R + c.G) / 2;
        var blues = overlays.Select(o => Blue(o.Fill)).ToArray();
        var minBlue = blues.Min();
        var indents = overlays.Select(o => o.MessageBox.Left - phone.LeftAt(o.MessageBox.CenterY)).ToArray();
        var rightIndents = overlays.Select(o => o.MessageBox.Right - phone.LeftAt(o.MessageBox.CenterY)).ToArray();
        var minIndent = indents.Min();
        var maxRightIndent = rightIndents.Max();
        var outgoing = new bool[overlays.Count];
        for (var i = 0; i < overlays.Count; i++)
            outgoing[i] = indents[i] > screenWidth * 0.2
                || (indents[i] - minIndent > screenWidth * 0.1 && maxRightIndent - rightIndents[i] < screenWidth * 0.08)
                || blues[i] - minBlue >= 14;

        // Zemin.
        var floorColors = new List<Rgb>();
        for (var i = 0; i < overlays.Count; i++)
        {
            if (indents[i] > screenWidth * 0.2) continue;
            var y = overlays[i].MessageBox.CenterY;
            if (sampler.At(phone.LeftAt(y) + screenWidth - 0.012, y) is { } c) floorColors.Add(c);
        }
        var byTotal = floorColors.OrderBy(c => c.R + c.G + c.B).ToArray();
        var floor = byTotal.Length > 0 ? byTotal[byTotal.Length / 2] : DefaultFloor;
        var light = floor.Luma > 150;
        if (light)
        {
            static int Toward(int v, double k) => (int)(v + (255 - v) * k);
            floor = new Rgb(Toward(floor.R, 0.6), Toward(floor.G, 0.6), Toward(floor.B, 0.6));
        }
        var items = new List<ScreenItem>();
        var hasTitle = !string.IsNullOrEmpty(title);
        var floorLine = hasTitle ? Math.Min(Math.Max(messages.Max(m => m.LineHeight), 0.02), 0.028) : 0.02;
        items.Add(new ScreenItem("", hasTitle ? title! : "", new Box(colLeft, phone.Box.Top, colRight, phone.Box.Bottom), floorLine)
        {
            Fill = floor.Hex,
            Alpha = 0.6,
            Backdrop = true,
        });

        for (var i = 0; i < overlays.Count; i++)
        {
            var o = overlays[i];
            var (size, _, longest, _) = sizes[i];
            var width = Math.Min(maxWidth, longest * size * 0.5 * 9 / 16 + pad + pad);
            var (left, right) = outgoing[i] ? (innerRight - width, innerRight) : (innerLeft, innerLeft + width);
            var fill = o.Fill;
            if (light)
                fill = outgoing[i]
                    ? new Rgb((int)(fill.R * 0.86), (int)(fill.G * 0.93), Math.Min(255, (int)(fill.B * 1.04)))
                    : new Rgb((int)(fill.R + (255 - fill.R) * 0.7), (int)(fill.G + (255 - fill.G) * 0.7),
                        (int)(fill.B + (255 - fill.B) * 0.7));
            items.Add(new ScreenItem(o.Source, o.Text, new Box(left, tops[i], right, tops[i] + heights[i] + size * 0.3), size)
            {
                Fill = fill.Hex,
                Ink = o.Ink,
                Alpha = 0.95,
                Side = true,
            });
        }
        return items;
    }

    /// <summary>
    /// Uygulama balonları (sohbet olmayan ekran): uygulamanın rengiyle, telefonun yanındaki sütunda satır satır;
    /// zemin paneli yok.
    /// </summary>
    public static List<ScreenItem> AppBubbles(IReadOnlyList<PhoneMessage> lines, IReadOnlyList<string> translations,
        PhoneShape phone, IColorSampler sampler)
    {
        var kept = new List<(PhoneMessage Line, string Text)>();
        for (var i = 0; i < Math.Min(lines.Count, translations.Count); i++)
        {
            var text = (translations[i] ?? "").Trim();
            if (PhoneText.WorthShowing(lines[i].Text, text)) kept.Add((lines[i], text));
        }
        if (kept.Count == 0) return [];

        var (fill, ink) = AppColors(kept.Select(k => k.Line).ToList(), phone, sampler);

        var heights = kept.Select(k => k.Line.LineHeight / 0.85).OrderBy(v => v).ToArray();
        var size = Math.Min(Math.Max(heights[heights.Length / 2], 0.018), 0.028) * 0.95;
        var (colLeft, colRight) = Column(phone.Box, PanelWidth);
        var colWidth = colRight - colLeft;
        var alignRight = colRight <= phone.Box.Left;
        var charWidth = size * 0.5 * 9 / 16;
        var perLine = Math.Max(8, (int)Math.Floor((colWidth - 0.03) / (charWidth * 0.85)));

        var items = new List<ScreenItem>();
        var floorY = 0.0;
        foreach (var (line, text) in kept)
        {
            var rows = Math.Max(1, (int)Math.Ceiling((double)text.Length / perLine));
            double width, height, top;
            if (rows > 1)
            {
                width = colWidth;
                height = size * (1.22 * rows + 0.45);
                top = line.Box.Top;
            }
            else
            {
                width = Math.Min(colWidth, text.Length * charWidth + 0.03);
                height = size * 1.55;
                top = line.Box.CenterY - height / 2;
            }
            top = Math.Min(Math.Max(top, floorY), Math.Max(0, 0.98 - height));
            floorY = top + height + size * 0.4;
            var box = alignRight ? new Box(colRight - width, top, colRight, top + height)
                : new Box(colLeft, top, colLeft + width, top + height);
            items.Add(new ScreenItem(line.Text, text, box, size)
            {
                Fill = fill.Hex,
                Ink = ink,
                Alpha = 0.95,
                Side = true,
            });
        }
        return items;
    }

    /// <summary>Uygulamanın rengi: başlık şeridindeki ya da satır çevresindeki en canlı renk; yoksa arka plan ve yazı rengi.</summary>
    static (Rgb Fill, string Ink) AppColors(IReadOnlyList<PhoneMessage> lines, PhoneShape phone, IColorSampler sampler)
    {
        Rgb? vivid = null;
        void Consider(double x, double y)
        {
            if (sampler.At(x, y) is not { } c) return;
            if (c.Spread > 60 && c.Max >= 120 && (vivid is null || c.Spread > vivid.Value.Spread)) vivid = c;
        }
        var top = phone.Box.Top;
        for (var yi = 0; yi < 10; yi++)
        {
            var y = top - 0.04 + 0.01 * yi;
            for (var k = 1; k <= 9; k++) Consider(phone.LeftAt(y) + phone.Width * (k / 10.0), y);
        }
        if (vivid is null)
            foreach (var l in lines)
            {
                var b = l.Box;
                Consider(b.Left - 0.006, b.CenterY);
                Consider(b.Right + 0.006, b.CenterY);
                Consider(b.CenterX, b.Top - 0.006);
                Consider(b.CenterX, b.Bottom + 0.006);
            }
        if (vivid is { } v) return (v, "#ffffff");

        // Beyaz haber uygulaması gibi: en kalabalık renk kovası arka plandır.
        var buckets = new Dictionary<int, List<Rgb>>();
        for (var yi = 0; ; yi++)
        {
            var y = top + 0.02 + 0.01 * yi;
            if (!(y < phone.Box.Bottom - 0.01)) break;
            for (var k = 1; k <= 19; k++)
                if (sampler.At(phone.LeftAt(y) + phone.Width * (k * 0.05), y) is { } c)
                {
                    var key = c.R / 16 * 256 + c.G / 16 * 16 + c.B / 16;
                    if (!buckets.TryGetValue(key, out var list)) buckets[key] = list = [];
                    list.Add(c);
                }
        }
        if (buckets.Count == 0) return (NoColorFill, "#ffffff");
        var best = buckets.OrderByDescending(kv => kv.Value.Count).ThenBy(kv => kv.Key).First().Value;
        var bg = new Rgb(best.Sum(c => c.R) / best.Count, best.Sum(c => c.G) / best.Count, best.Sum(c => c.B) / best.Count);

        Rgb? ink = null;
        var inkDiff = -1;
        foreach (var l in lines)
        {
            var b = l.Box;
            var step = Math.Max(b.Height / 8, 0.002);
            var count = (int)Math.Floor(b.Height / step + 1e-9);
            for (var yi = 0; yi <= count; yi++)
            {
                var y = b.Top + step * yi;
                for (var xi = 1; xi <= 49; xi++)
                    if (sampler.At(b.Left + b.Width * (xi * 0.02), y) is { } c)
                    {
                        var d = Math.Abs(c.R - bg.R) + Math.Abs(c.G - bg.G) + Math.Abs(c.B - bg.B);
                        if (d > inkDiff)
                        {
                            inkDiff = d;
                            ink = c;
                        }
                    }
            }
        }
        var lightBg = bg.Luma1000 > 128_000;
        if (ink is { } t && inkDiff >= 90)
        {
            var color = lightBg
                ? new Rgb((int)(t.R * 0.6), (int)(t.G * 0.6), (int)(t.B * 0.6))
                : new Rgb(255 - (255 - t.R) / 2, 255 - (255 - t.G) / 2, 255 - (255 - t.B) / 2);
            return (bg, color.Hex);
        }
        return (bg, lightBg ? "#1c1c1e" : "#ffffff");
    }
}
