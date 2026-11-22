// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;
using Nino.Core.Reading;

namespace Nino.Core.Phone;

/// <summary>Altyazı hattının telefon sınamaları: açık zeminde koyu yazı ve telefon uygulaması yazısı.</summary>
public static class PhoneLineRules
{
    static readonly string[] AppRoots =
    [
        "trip detail", "change destinat", "destinatio", "messages encrypt", "map pin expir", "checking accoun",
        "family saving", "workout window", "strength workout", "cardio workout", "calorie balanc", "maintain weight",
        "gain weight", "lose weight",
    ];

    static readonly HashSet<string> AppWords = new(StringComparer.Ordinal) { "ryde", "rydeme", "buckme" };

    /// <summary>
    /// Açık zeminde koyu yazı mı (telefon ekranı; beyaz altyazı değil): kutunun içindeki parlaklıkların %5, %50 ve %95
    /// dilimlerine bakılır.
    /// </summary>
    public static bool IsDarkTextOnLight(IColorSampler sampler, Box box)
    {
        var step = Math.Max(box.Height / 6, 0.001);
        var rows = (int)Math.Floor(box.Height / step + 1e-9);
        var lumas = new List<int>();
        for (var yi = 0; yi <= rows; yi++)
        {
            var y = box.Top + step * yi;
            for (var xi = 0; xi < 33; xi++)
                if (sampler.At(box.Left + box.Width * (0.02 + 0.03 * xi), y) is { } c) lumas.Add(c.Luma);
        }
        if (lumas.Count < 20) return false;
        lumas.Sort();
        var n = lumas.Count;
        var dark = lumas[n / 20];
        var mid = lumas[n / 2];
        var bright = lumas[n * 19 / 20];
        return mid - dark >= 25 && mid - dark > (bright - mid) * 2;
    }

    /// <summary>Telefon uygulamasına özgü yazı mı (araç çağırma, banka, spor uygulaması…).</summary>
    public static bool IsPhoneAppText(string? text)
    {
        var t = text ?? "";
        var key = PhoneText.Key(t);
        if (key.Length == 0) return false;
        var spaced = " " + key;
        if (AppRoots.Any(r => spaced.Contains(" " + r, StringComparison.Ordinal))) return true;
        if (PhoneText.Words(key).Any(AppWords.Contains)) return true;
        var open = t.IndexOf('(');
        var close = t.LastIndexOf(')');
        var bare = open >= 0 && close > open ? t[..open] + t[(close + 1)..] : t;
        if (PhoneGlossary.ContainsKey(PhoneText.Key(bare))) return true;
        return PhoneText.Words(t).Length >= 2 && PhoneGlossary.Lookup(t) is not null;
    }
}

/// <summary>
/// Okuma hattının telefon/harita kancaları: telefonu hattın kendi takipçisiyle arar, telefonun yazılarını okumadan
/// atar, harita açıkken altyazıyı susturur.
/// </summary>
public sealed class PhoneLineHooks : IPhoneLineHooks
{
    readonly Func<bool> _searchPhone;
    readonly Func<bool> _mapOpen;
    readonly Func<IReadOnlyList<string>> _recentMessages;
    readonly Action<BgraFrame, IReadOnlyList<Box>>? _phoneTextSeen;
    BgraFrame? _frame;

    /// <summary>Kancalar.</summary>
    /// <param name="clock">Saat (hattın takipçisi için).</param>
    /// <param name="searchPhone">Telefon aransın mı (telefon oyunu).</param>
    /// <param name="mapOpen">Harita açık mı.</param>
    /// <param name="recentMessages">Telefon okuyucusunun son mesajları (okuyucu yoksa boş).</param>
    /// <param name="phoneTextSeen">Telefon yazısı görüldü (kare, kareye göre kutular): telefon okuyucusunun takipçisi benimser.</param>
    /// <param name="finder">Telefon bulucu (testler için).</param>
    public PhoneLineHooks(IMsClock clock, Func<bool> searchPhone, Func<bool> mapOpen,
        Func<IReadOnlyList<string>> recentMessages, Action<BgraFrame, IReadOnlyList<Box>>? phoneTextSeen = null,
        Func<BgraFrame, PhoneShape?>? finder = null)
    {
        _searchPhone = searchPhone;
        _mapOpen = mapOpen;
        _recentMessages = recentMessages;
        _phoneTextSeen = phoneTextSeen;
        Tracker = new PhoneTracker(clock, finder);
    }

    /// <summary>Hattın kendi telefon takipçisi.</summary>
    public PhoneTracker Tracker { get; }

    /// <inheritdoc />
    public bool SearchPhone => _searchPhone();

    /// <inheritdoc />
    public bool MapOpen => _mapOpen();

    /// <inheritdoc />
    public Box? LocatePhone(BgraFrame frame)
    {
        Volatile.Write(ref _frame, frame);
        return Tracker.Locate(frame)?.Box;
    }

    /// <inheritdoc />
    public OcrReading FilterLines(PhoneLineContext context)
    {
        var area = context.Area;
        var reading = context.Reading;
        bool Boxed(OcrLine l, out Box inArea, out Box inFrame)
        {
            inArea = l.Box ?? default;
            inFrame = l.Box is { } b ? b.PlaceIn(area) : default;
            return l.Box is not null;
        }

        if (context.MaskBox is { } mask)
        {
            var wide = mask.Inflate(0.02);
            reading = reading.Where(l => !Boxed(l, out _, out var f) || !wide.Contains(f.CenterX, f.CenterY));
        }

        var search = SearchPhone;
        if (search && context.RegionImage.Width > 0 && context.RegionImage.Height > 0)
        {
            var sampler = new FrameSampler(context.RegionImage);
            reading = reading.Where(l => !Boxed(l, out var a, out _) || !PhoneLineRules.IsDarkTextOnLight(sampler, a));
        }

        if (search)
        {
            var app = reading.Lines.Where(l => l.Box is not null && PhoneLineRules.IsPhoneAppText(l.Text)).ToArray();
            if (app.Length > 0)
            {
                var boxes = app.Select(l => l.Box!.Value.PlaceIn(area)).ToArray();
                if (Volatile.Read(ref _frame) is { } frame)
                {
                    if (!context.PhoneFound) Tracker.Adopt(frame, boxes);
                    _phoneTextSeen?.Invoke(frame, boxes);
                }
                var drop = app.ToHashSet();
                reading = reading.Where(l => !drop.Contains(l));
            }
        }

        var recent = _recentMessages().Select(PhoneText.Key).Where(k => k.Length > 0).ToArray();
        if (context.MaskBox is not null || recent.Length > 0)
            reading = reading.Where(l => !Boxed(l, out _, out var f) || f.CenterY >= 0.8);
        if (recent.Length > 0)
            reading = reading.Where(l =>
            {
                var key = PhoneText.Key(l.Text);
                return PhoneText.Words(key).Length < 3 || !recent.Any(m => m.Contains(key, StringComparison.Ordinal));
            });
        return reading;
    }
}
