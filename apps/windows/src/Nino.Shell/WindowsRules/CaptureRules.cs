// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Settings;

namespace Nino.Shell.WindowsRules;

// Görüntü kaynaklarının platformdan bağımsız kuralları (tarif: kaynaklar §2–§3). Windows API'leri Nino.App'te.

/// <summary>Bir yakalama aygıtı (görüntü ya da ses): kimlik, ad, kap (aynı USB kartın aygıtları aynı kaptadır).</summary>
public sealed record CaptureDevice(string Id, string Name, string? ContainerId = null);

/// <summary>Kartın sunduğu bir görüntü biçimi.</summary>
public sealed record CaptureFormat(int Width, int Height, double FrameRate, string Subtype);

/// <summary>HDMI yakalama kartı kuralları.</summary>
public static class CaptureCardRules
{
    static readonly string[] Webcams =
    [
        "webcam", "logitech", "brio", "c920", "c922", "integrated camera", "integrated webcam", "front", "rear",
        "ir camera", "hd camera", "facetime",
    ];

    static readonly string[] CardHints =
    [
        "capture", "hdmi", "elgato", "avermedia", "live gamer", "game", "cam link", "razer", "ripsaw", "ugreen",
        "usb video", "uvc", "hd60", "4k x", "4k s", "magewell", "video",
    ];

    static readonly HashSet<string> Uncompressed = new(["NV12", "YUY2", "RGB32", "ARGB32", "BGRA8", "UYVY", "I420", "IYUV"],
        StringComparer.OrdinalIgnoreCase);

    /// <summary>Bilgisayarın kendi aygıtlarının kabı.</summary>
    public const string SystemContainer = "00000000-0000-0000-ffff-ffffffffffff";

    /// <summary>Okuma hattına giden kare boyu.</summary>
    public const int OutputWidth = 1920, OutputHeight = 1080;

    /// <summary>Aygıt listesi değişince bağlanmadan önceki bekleme.</summary>
    public static readonly TimeSpan DeviceChangeDelay = TimeSpan.FromMilliseconds(700);

    /// <summary>Kamera izni yokken yeniden deneme.</summary>
    public static readonly TimeSpan PermissionRetry = TimeSpan.FromSeconds(5);

    /// <summary>Açma hatasında yeniden deneme.</summary>
    public static readonly TimeSpan OpenRetry = TimeSpan.FromSeconds(3);

    /// <summary>Oturum koptuğunda yeniden deneme.</summary>
    public static readonly TimeSpan FailedRetry = TimeSpan.FromSeconds(1);

    /// <summary>Kullanılacak görüntü aygıtı: seçili aygıt takılıysa o; yoksa web kamerası olmayanlardan kart ipucu içeren ilki, yoksa kalan ilki.</summary>
    public static CaptureDevice? PickVideo(IReadOnlyList<CaptureDevice> devices, string? preferredId)
    {
        if (!string.IsNullOrEmpty(preferredId) && devices.FirstOrDefault(d => d.Id == preferredId) is { } chosen) return chosen;
        var candidates = devices.Where(d => !Webcams.Any(w => d.Name.ToLowerInvariant().Contains(w))).ToList();
        return candidates.FirstOrDefault(d => CardHints.Any(h => d.Name.ToLowerInvariant().Contains(h)))
            ?? candidates.FirstOrDefault();
    }

    /// <summary>Kap bilgisayarın kendi kabı mı (büyük/küçük harf ve süslü parantez farkı yok sayılır).</summary>
    public static bool IsSystemContainer(string? container) =>
        string.Equals(Bare(container), SystemContainer, StringComparison.OrdinalIgnoreCase);

    static string Bare(string? container) => (container ?? "").Trim().Trim('{', '}');

    /// <summary>Kartın ses aygıtı: aynı kaptaki ilk ses aygıtı; yoksa adı kartın adını içeren ya da onda geçen; yoksa null.</summary>
    public static CaptureDevice? PickAudio(CaptureDevice card, IReadOnlyList<CaptureDevice> audio)
    {
        var container = Bare(card.ContainerId);
        if (container.Length > 0 && !IsSystemContainer(container)
            && audio.FirstOrDefault(a => string.Equals(Bare(a.ContainerId), container, StringComparison.OrdinalIgnoreCase)) is { } same)
            return same;
        var cardName = card.Name.ToLowerInvariant();
        if (cardName.Length == 0) return null;
        return audio.FirstOrDefault(a =>
        {
            var n = a.Name.ToLowerInvariant();
            return n.Length > 0 && (n.Contains(cardName) || cardName.Contains(n));
        });
    }

    /// <summary>Kartın biçimi: tam 1920×1080, kare hızı (60'ta kırpılıp yuvarlanmış), 1080'e yakınlık, sıkıştırılmamış.</summary>
    public static CaptureFormat? PickFormat(IEnumerable<CaptureFormat> formats) =>
        formats.Where(f => f.Width > 0 && f.Height > 0 && f.FrameRate > 0)
            .OrderBy(f => f.Width == OutputWidth && f.Height == OutputHeight ? 0 : 1)
            .ThenByDescending(f => Math.Round(Math.Min(f.FrameRate, 60)))
            .ThenBy(f => Math.Abs(OutputHeight - f.Height))
            .ThenByDescending(f => Uncompressed.Contains(f.Subtype.Trim()))
            .FirstOrDefault();

    /// <summary>Saniyede 10 kare sınırına göre okuma hattına yeni kare gönderilebilir mi.</summary>
    public static bool ReadDue(double nowSeconds, double lastSeconds) => nowSeconds - lastSeconds >= 0.1 - 0.002;

    /// <summary>
    /// Siyah kare mi: y ve x 16'dan başlayıp 32 adımla örneklenir; bir örneğin B, G ya da R'si 24'ten büyükse siyah
    /// değil. Tampon taşarsa siyah sayılır.
    /// </summary>
    public static bool IsBlack(ReadOnlySpan<byte> bgra, int width, int height, int stride)
    {
        for (var y = 16; y < height; y += 32)
            for (var x = 16; x < width; x += 32)
            {
                var i = (long)y * stride + (long)x * 4;
                if (i + 2 >= bgra.Length) return true;
                if (bgra[(int)i] > 24 || bgra[(int)i + 1] > 24 || bgra[(int)i + 2] > 24) return false;
            }
        return true;
    }

    /// <summary>Kareyi 1920×1080 sıkı BGRA'ya kopyalar: aynı boydaysa düz, değilse en yakın komşu.</summary>
    public static byte[] ToOutput(ReadOnlySpan<byte> bgra, int width, int height, int stride)
    {
        var result = new byte[OutputWidth * OutputHeight * 4];
        if (width <= 0 || height <= 0) return result;
        if (width == OutputWidth && height == OutputHeight)
        {
            for (var y = 0; y < OutputHeight; y++)
                bgra.Slice(y * stride, OutputWidth * 4).CopyTo(result.AsSpan(y * OutputWidth * 4));
            return result;
        }
        for (var y = 0; y < OutputHeight; y++)
        {
            var sy = Math.Min(height - 1, (int)((long)y * height / OutputHeight));
            var row = sy * stride;
            var dst = y * OutputWidth * 4;
            for (var x = 0; x < OutputWidth; x++)
            {
                var sx = Math.Min(width - 1, (int)((long)x * width / OutputWidth));
                var s = row + sx * 4;
                result[dst] = bgra[s];
                result[dst + 1] = bgra[s + 1];
                result[dst + 2] = bgra[s + 2];
                result[dst + 3] = 255;
                dst += 4;
            }
        }
        return result;
    }
}

/// <summary>Siyah bekçisi: siyah gelmeye başladığı an saklanır; 4 sn kesintisiz siyahsa "siyah görüntü".</summary>
public sealed class BlackPictureWatch
{
    /// <summary>Siyah sayılma süresi.</summary>
    public const double Seconds = 4;

    double? _since;

    /// <summary>Kareyi işler; siyah görüntü mü.</summary>
    public bool Feed(bool black, double nowSeconds)
    {
        if (!black)
        {
            _since = null;
            return false;
        }
        _since ??= nowSeconds;
        return nowSeconds - _since.Value >= Seconds;
    }

    /// <summary>Sıfırlar.</summary>
    public void Reset() => _since = null;
}

/// <summary>Takılma bekçisi: kart kare vermeyi keserse artan aralıklarla (3 → en çok 30 sn) yeniden açtırır.</summary>
public sealed class CardStallWatch
{
    /// <summary>Başlangıç aralığı ve sessizlik sınırı.</summary>
    public const double BaseSeconds = 3;

    /// <summary>En büyük aralık.</summary>
    public const double MaxSeconds = 30;

    double _interval = BaseSeconds;
    double _lastReopen = double.NegativeInfinity;

    /// <summary>Şu anki aralık.</summary>
    public double Interval => _interval;

    /// <summary>
    /// Saniyede bir çağrılır. Yeniden açılmalıysa sessizlik süresini (tam saniye) döner; değilse null.
    /// </summary>
    public int? Tick(double nowSeconds, double lastFrameSeconds)
    {
        var silence = nowSeconds - lastFrameSeconds;
        if (silence < BaseSeconds)
        {
            _interval = BaseSeconds;
            return null;
        }
        if (nowSeconds - _lastReopen < _interval) return null;
        _interval = Math.Min(_interval * 2, MaxSeconds);
        _lastReopen = nowSeconds;
        return (int)Math.Floor(silence);
    }

    /// <summary>Sıfırlar.</summary>
    public void Reset()
    {
        _interval = BaseSeconds;
        _lastReopen = double.NegativeInfinity;
    }
}

/// <summary>Ana oyun penceresi okuyucusunda (GDI) karenin nereden alınacağı.</summary>
public enum WindowGrabStep
{
    /// <summary>Pencerenin verdiği kare kullanılır.</summary>
    UseWindow,

    /// <summary>Siyah kare verilir (yayın başı/yükleme).</summary>
    SendBlack,

    /// <summary>Ekranın o alanı kopyalanmalı.</summary>
    CopyScreen,
}

/// <summary>
/// Pencere içeriği / ekran kopyası kararı (kaynaklar §2.3): pencere kendini vermezse 30 siyah kareden sonra ekran
/// kopyasına geçilir; kipteyken her 20 karede bir pencere yeniden denenir.
/// </summary>
public sealed class WindowGrabState
{
    /// <summary>Kipteyken pencerenin yeniden denendiği aralık (kare).</summary>
    public const int RetryEvery = 20;

    /// <summary>Ekran kopyasına geçmeden önce verilen siyah kare sayısı.</summary>
    public const int BlackLimit = 30;

    int _sinceRetry;

    /// <summary>Ekran kopyası kipinde mi.</summary>
    public bool ScreenCopy { get; private set; }

    /// <summary>Art arda siyah sayacı.</summary>
    public int BlackCount { get; private set; }

    /// <summary>Bu karede önce pencere istenmeli mi.</summary>
    public bool TryWindowFirst()
    {
        if (!ScreenCopy) return true;
        _sinceRetry++;
        if (_sinceRetry < RetryEvery) return false;
        _sinceRetry = 0;
        return true;
    }

    /// <summary>Pencere denemesinin sonucu (başarılı ve siyah değil mi). Kipten çıkıldıysa <paramref name="leftScreenCopy"/>.</summary>
    public WindowGrabStep AfterWindow(bool gotPicture, out bool leftScreenCopy)
    {
        leftScreenCopy = false;
        if (gotPicture)
        {
            leftScreenCopy = ScreenCopy;
            ScreenCopy = false;
            BlackCount = 0;
            _sinceRetry = 0;
            return WindowGrabStep.UseWindow;
        }
        if (ScreenCopy) return WindowGrabStep.CopyScreen;
        BlackCount++;
        return BlackCount < BlackLimit ? WindowGrabStep.SendBlack : WindowGrabStep.CopyScreen;
    }

    /// <summary>Ekran kopyası alındı; kipe yeni geçildiyse true.</summary>
    public bool AfterScreen(bool screenBlack)
    {
        if (ScreenCopy) return false;
        if (screenBlack)
        {
            BlackCount = 0;
            return false;
        }
        ScreenCopy = true;
        _sinceRetry = 0;
        return true;
    }

    /// <summary>Yeni pencere seçilince.</summary>
    public void Reset()
    {
        ScreenCopy = false;
        BlackCount = 0;
        _sinceRetry = 0;
    }
}

/// <summary>Ana pencere okuyucusunun ölçüleri ve küçük kuralları.</summary>
public static class GameWindowCaptureRules
{
    /// <summary>Çıktı karesi.</summary>
    public const int OutputWidth = 1920, OutputHeight = 1080;

    /// <summary>Saniyedeki kare.</summary>
    public const int FramesPerSecond = 10;

    /// <summary>Pencere yeniden arama aralığı.</summary>
    public static readonly TimeSpan SearchEvery = TimeSpan.FromSeconds(1.5);

    /// <summary>
    /// Alan siyah mı: alanın içinde 8×8 = 64 nokta (sütun/satır k = 1..8, alan × k/9); hepsinin RGB'si 0 ise siyah.
    /// <paramref name="bgra"/> tam yüzeydir; alan yüzeyin içindedir.
    /// </summary>
    public static bool IsBlack(ReadOnlySpan<byte> bgra, int stride, PixelRect area)
    {
        if (area.Width <= 0 || area.Height <= 0) return true;
        for (var j = 1; j <= 8; j++)
            for (var k = 1; k <= 8; k++)
            {
                var x = area.X + area.Width * k / 9;
                var y = area.Y + area.Height * j / 9;
                var i = (long)y * stride + (long)x * 4;
                if (i < 0 || i + 2 >= bgra.Length) continue;
                if (bgra[(int)i] != 0 || bgra[(int)i + 1] != 0 || bgra[(int)i + 2] != 0) return false;
            }
        return true;
    }

    /// <summary>İçerik alanının ekrandaki yeri → oyun alanı (16:9, ortalı).</summary>
    public static PixelRect GameAreaOnScreen(PixelRect content)
    {
        var a = GameWindowRules.GameArea(content.Width, content.Height);
        return new PixelRect(content.X + a.X, content.Y + a.Y, a.Width, a.Height);
    }
}

/// <summary>Graphics.Capture okuyucusunun (eski "Remote Play penceresi" ve "seçilen pencere") kuralları (kaynaklar §2.6).</summary>
public static class CaptureWindowRules
{
    /// <summary>Pencere en az bu boyda olmalı.</summary>
    public const int MinWidth = 400, MinHeight = 250;

    /// <summary>Arama aralığı.</summary>
    public static readonly TimeSpan SearchEvery = TimeSpan.FromSeconds(2);

    /// <summary>Saniyede en çok kare.</summary>
    public const int MaxFramesPerSecond = 10;

    /// <summary>Art arda bu kadar siyah karede uyarı.</summary>
    public const int BlackFrameLimit = 40;

    /// <summary>Siyah örnekleme adımı (bayt).</summary>
    public const int BlackSampleStep = 4 * 997;

    /// <summary>Sony uygulamasının süreç adı.</summary>
    public const string SonyProcess = "RemotePlay";

    /// <summary>Uygulamanın süreç adları.</summary>
    public static IReadOnlyList<string> Processes(RemotePlayApp app) => app switch
    {
        RemotePlayApp.SonyRemotePlay => [SonyProcess],
        RemotePlayApp.Chiaki => ["chiaki", "chiaki-ng"],
        _ => [SonyProcess, "chiaki", "chiaki-ng"],
    };

    /// <summary>Kurulu yol adayları, sırayla (Sony önce).</summary>
    public static IReadOnlyList<string> InstallCandidates(RemotePlayApp app, string programFiles, string programFilesX86,
        string localAppData)
    {
        var sony = new[]
        {
            Path.Combine(programFilesX86, "Sony", "PS Remote Play", "RemotePlay.exe"),
            Path.Combine(programFiles, "Sony", "PS Remote Play", "RemotePlay.exe"),
        };
        var chiaki = new List<string>();
        foreach (var root in new[] { programFiles, programFilesX86, Path.Combine(localAppData, "Programs") })
        {
            chiaki.Add(Path.Combine(root, "chiaki-ng", "chiaki.exe"));
            chiaki.Add(Path.Combine(root, "chiaki-ng", "chiaki-ng.exe"));
        }
        return app switch
        {
            RemotePlayApp.SonyRemotePlay => sony,
            RemotePlayApp.Chiaki => chiaki,
            _ => [.. sony, .. chiaki],
        };
    }

    /// <summary>
    /// Yakalanacak pencere: süreç adı listede (harf duyarsız); seçilen pencerede başlık tam eşleşmeli; en az 400×250;
    /// alanı en büyük. Görünürlük ve sahiplik süzgeci çağıranda.
    /// </summary>
    public static WindowCandidate? Pick(IEnumerable<WindowCandidate> windows, IReadOnlyList<string> processes,
        string? exactTitle = null) =>
        windows.Where(w => processes.Contains(w.ProcessName, StringComparer.OrdinalIgnoreCase))
            .Where(w => exactTitle is null || string.Equals(w.Title, exactTitle, StringComparison.Ordinal))
            .Where(w => w.Width >= MinWidth && w.Height >= MinHeight)
            .OrderByDescending(w => (long)w.Width * w.Height)
            .FirstOrDefault();

    /// <summary>Ayarlar'daki pencere listesi: başlığı boş olmayan, en az 400×250, tekrarsız, süreç sonra başlık sıralı.</summary>
    public static IReadOnlyList<VisibleWindow> Listing(IEnumerable<WindowCandidate> windows) =>
        windows.Where(w => !string.IsNullOrWhiteSpace(w.Title) && w.Width >= MinWidth && w.Height >= MinHeight)
            .Select(w => new VisibleWindow(w.ProcessName, w.Title))
            .Distinct()
            .OrderBy(w => w.ProcessName, StringComparer.OrdinalIgnoreCase)
            .ThenBy(w => w.Title, StringComparer.OrdinalIgnoreCase)
            .ToList();

    /// <summary>Kare siyah mı: her 4×997 baytta bir örnek; hepsinin B, G, R'si 10'dan küçükse siyah.</summary>
    public static bool IsMostlyBlack(ReadOnlySpan<byte> bgra)
    {
        for (var i = 0; i + 2 < bgra.Length; i += BlackSampleStep)
            if (bgra[i] >= 10 || bgra[i + 1] >= 10 || bgra[i + 2] >= 10) return false;
        return true;
    }
}
