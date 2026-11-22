// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;
using Nino.Core.Reading;

namespace Nino.Core.Phone;

/// <summary>
/// Telefon takipçisi: son bulunan yeri kısa süre tutar (telefon bir karede bulunamasa da ekran aynı türdeyse yer
/// döner) ve telefon uygulamasına özgü yazılardan tahmini yer benimser. İş parçacığı güvenlidir. Okuma hattında ve
/// telefon okuyucusunda ayrı birer takipçi vardır.
/// </summary>
public sealed class PhoneTracker(IMsClock clock, Func<BgraFrame, PhoneShape?>? finder = null)
{
    /// <summary>Takibin en çok süresi (ayarlanabilir üst sınır 20 sn olsa da kullanılan 3 sn).</summary>
    public const long KeepMs = 3_000;

    /// <summary>Yazılardan benimseme için son görülmenin en az yaşı.</summary>
    public const long AdoptAfterMs = 2_000;

    /// <summary>Ekran payının örnekleyici boyutu.</summary>
    const int ShareWidth = 480, ShareHeight = 270;

    readonly object _lock = new();
    readonly Func<BgraFrame, PhoneShape?> _find = finder ?? PhoneFinder.Find;
    PhoneShape? _last;
    bool _lastDark;
    long _lastSeen;

    /// <summary>Son yer (test ve tanı için).</summary>
    public PhoneShape? Last
    {
        get { lock (_lock) return _last; }
    }

    /// <summary>
    /// Bir yerdeki ekran türünün payı: 14 × 7 nokta; "koyu" = en büyük ≤ 85, "beyaz" = en küçük ≥ 118 ve
    /// yayılma ≤ 45. Nokta yoksa 0.
    /// </summary>
    public static double ScreenShare(IColorSampler sampler, PhoneShape phone, bool dark)
    {
        int seen = 0, hit = 0;
        var top = phone.Box.Top;
        var height = phone.Box.Height;
        for (var row = 1; row <= 14; row++)
        {
            var y = top + height * row / 15;
            for (var col = 1; col <= 7; col++)
            {
                var x = phone.LeftAt(y) + phone.Width * col / 8;
                if (sampler.At(x, y) is not { } c) continue;
                seen++;
                if (dark ? c.Max <= 85 : c.Min >= 118 && c.Spread <= 45) hit++;
            }
        }
        return seen == 0 ? 0 : (double)hit / seen;
    }

    static FrameSampler ShareSampler(BgraFrame frame) => new(frame, ShareWidth, ShareHeight);

    /// <summary>Karede telefonun yeri (takiple); yoksa null.</summary>
    public PhoneShape? Locate(BgraFrame frame)
    {
        var found = _find(frame);
        if (found is not null)
        {
            var dark = ScreenShare(ShareSampler(frame), found, true) >= 0.5;
            lock (_lock)
            {
                _last = found;
                _lastDark = dark;
                _lastSeen = clock.NowMs;
            }
            return found;
        }
        PhoneShape? last;
        bool lastDark;
        lock (_lock)
        {
            last = _last;
            lastDark = _lastDark;
            if (last is null || clock.NowMs - _lastSeen >= KeepMs) return null;
        }
        if (ScreenShare(ShareSampler(frame), last, lastDark) < 0.45)
        {
            lock (_lock)
                if (ReferenceEquals(_last, last)) _last = null;
            return null;
        }
        return last;
    }

    /// <summary>
    /// Telefon uygulamasına özgü yazılar görüldü ama telefon bulunamadı: yazıların karedeki kutularından tahmini yer
    /// benimsenir (son yer 2 sn'den yeniyse bir şey yapılmaz).
    /// </summary>
    public void Adopt(BgraFrame frame, IReadOnlyList<Box> textBoxes)
    {
        if (textBoxes.Count == 0) return;
        lock (_lock)
            if (_last is not null && clock.NowMs - _lastSeen < AdoptAfterMs) return;
        var guess = Estimate(textBoxes);
        var dark = ScreenShare(ShareSampler(frame), guess, true) >= 0.45;
        lock (_lock)
        {
            _last = guess;
            _lastDark = dark;
            _lastSeen = clock.NowMs;
        }
    }

    /// <summary>Yazı kutularından tahmini telefon yeri.</summary>
    public static PhoneShape Estimate(IReadOnlyList<Box> boxes)
    {
        var minLeft = boxes.Count > 0 ? boxes.Min(b => b.Left) : 0.6;
        var maxRight = boxes.Count > 0 ? boxes.Max(b => b.Right) : 0.78;
        var minTop = boxes.Count > 0 ? boxes.Min(b => b.Top) : 0.3;
        var maxBottom = boxes.Count > 0 ? boxes.Max(b => b.Bottom) : 0.8;
        var left = Math.Max(0.02, minLeft - 0.015);
        var right = Math.Min(0.98, Math.Max(maxRight + 0.015, left + 0.21));
        var top = Math.Max(0.04, Math.Min(0.2, minTop - 0.02));
        var bottom = Math.Min(0.95, Math.Max(0.82, maxBottom + 0.03));
        return new PhoneShape(new Box(left, top, right, bottom), left, 0, right - left);
    }

    /// <summary>Son yeri unutur.</summary>
    public void Reset()
    {
        lock (_lock) _last = null;
    }
}
