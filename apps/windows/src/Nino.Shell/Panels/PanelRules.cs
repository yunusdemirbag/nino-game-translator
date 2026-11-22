// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Globalization;
using System.Text;
using Nino.Core.Design;
using Nino.Core.Health;
using Nino.Core.Settings;

namespace Nino.Shell.Panels;

/// <summary>Ayarlar penceresinin küçük kuralları (ekrandan bağımsız).</summary>
public static class SettingsPanelRules
{
    static readonly char[] WordBreaks = [' ', ':', '-', '(', ')'];

    /// <summary>
    /// Paket karosunun baş harfleri: başlık boşluk, <c>:</c>, <c>-</c>, <c>(</c>, <c>)</c> ile bölünür; ilk karakteri harf
    /// ya da rakam olan ilk üç sözcüğün ilk karakteri büyük harfle ("Grand Theft Auto V" → "GTA").
    /// </summary>
    public static string PackInitials(string? title)
    {
        if (string.IsNullOrWhiteSpace(title)) return "";
        var letters = title.Split(WordBreaks, StringSplitOptions.RemoveEmptyEntries)
            .Where(w => char.IsLetterOrDigit(w[0]))
            .Take(3)
            .Select(w => char.ToUpper(w[0], CultureInfo.InvariantCulture));
        return string.Concat(letters);
    }

    /// <summary>Bekleme süresinin yazısındaki sayı: bir ondalık, geçerli kültürün ayracıyla ("0,8").</summary>
    public static string Seconds(int ms, CultureInfo culture) => (ms / 1000.0).ToString("0.0", culture);

    /// <summary>Binlik ayraçlı sayı (paket satırı, DeepL kullanımı).</summary>
    public static string Thousands(long value, CultureInfo culture) => value.ToString("#,0", culture);

    /// <summary>Alan 1–3 kapalıyken çerçevenin gösterdiği (ve "Alanı sıfırla"nın döndüğü) başlangıç bölgesi.</summary>
    public static Region ExtraStartRegion(int slot) => slot switch
    {
        1 => new Region(0.05, 0.28, 0.60, 0.97),
        2 => new Region(0.72, 0.95, 0.60, 0.97),
        _ => new Region(0.35, 0.65, 0.30, 0.70),
    };

    /// <summary>Özel bölgenin kaydırıcı değeri: yuvarlanıp aralığa kırpılmış yüzde.</summary>
    public static int SliderPercent(double value, int min, int max) =>
        Math.Clamp((int)Math.Round(value, MidpointRounding.AwayFromZero), min, max);

    /// <summary>
    /// Kayıtlı pencerenin listesi: açık pencereler; kayıtlı pencere şu an açık değilse başa "açık değil" öğesi.
    /// Seçili = süreç adı ve başlığı kayıtlıyla aynı olan (yoksa -1).
    /// </summary>
    public static (IReadOnlyList<CaptureWindowItem> Items, int Selected) CaptureWindows(IReadOnlyList<VisibleWindow> windows,
        CaptureWindowChoice? saved)
    {
        var items = windows.Select(w => new CaptureWindowItem(w.ProcessName, w.Title, false)).ToList();
        if (saved is null || saved.ProcessName.Length == 0 && saved.Title.Length == 0) return (items, -1);
        var index = items.FindIndex(i => i.ProcessName == saved.ProcessName && i.Title == saved.Title);
        if (index >= 0) return (items, index);
        items.Insert(0, new CaptureWindowItem(saved.ProcessName, saved.Title, true));
        return (items, 0);
    }

    /// <summary>Sorun bildirme penceresinin "Nino'nun gördükleri" kutusu: son 3 günün en son 6 sorunu, en yenisi üstte.</summary>
    public static IReadOnlyList<ProblemRecord> NoticedProblems(IEnumerable<ProblemRecord> records, DateTimeOffset now) =>
        records.Where(r => r.Date >= now - TimeSpan.FromDays(3)).OrderByDescending(r => r.Date).Take(6).ToList();

    /// <summary>Sağlık sayfasının son sorunlar listesi kartı: en son 8 sorun, en yenisi üstte.</summary>
    public static IReadOnlyList<ProblemRecord> RecentProblems(IEnumerable<ProblemRecord> records) =>
        records.OrderByDescending(r => r.Date).Take(8).ToList();

    /// <summary>Cihaz bilgisi satırının etiket anahtarı.</summary>
    public static string DeviceLabelKey(string id) => id switch
    {
        "app" => "device.label.app",
        "device" => "device.label.device",
        "system" => "device.label.system",
        "tv" => "",
        "console" => "settings.connection.console",
        _ => "device.label.status",
    };

    /// <summary>Günlük zip'inin adı.</summary>
    public static string LogZipName(DateTime local) =>
        "Nino-kayitlar-" + local.ToString("yyyy-MM-dd-HH-mm-ss", CultureInfo.InvariantCulture) + ".zip";
}

/// <summary>Görüntünün kaynağı listesinin öğesi.</summary>
/// <param name="ProcessName">Süreç adı.</param>
/// <param name="Title">Pencere başlığı.</param>
/// <param name="NotOpen">Kayıtlı ama şu an açık değil.</param>
public sealed record CaptureWindowItem(string ProcessName, string Title, bool NotOpen);

/// <summary>Sağlık sayfası › Ayrıntılar metni (Türkçe, sabit; destek için).</summary>
public static class HealthDetailsText
{
    /// <summary>Ayrıntıların girdisi.</summary>
    public sealed record Input(
        string Version,
        string WindowsVersion,
        int Cores,
        string? OnlineEngine,
        bool Translating,
        string Ps5Phase,
        string? TvBrand,
        int ConnectedTvs,
        string TvAppKind,
        string? TvAppVersion,
        string? TvAppError,
        IReadOnlyList<string> Summary,
        IReadOnlyList<string>? SubtitleLog,
        IReadOnlyList<string>? TvInstallLog);

    /// <summary>Metin.</summary>
    public static string Build(Input i)
    {
        var sb = new StringBuilder();
        sb.Append("Nino ").Append(i.Version).Append(", Windows ").Append(i.WindowsVersion).Append(", ")
            .Append(i.Cores.ToString(CultureInfo.InvariantCulture)).Append(" çekirdek\n");
        sb.Append("motor: ").Append(i.OnlineEngine ?? "ücretsiz").Append(", çeviri: ")
            .Append(i.Translating ? "sürüyor" : "durdu").Append(", PS5: ").Append(i.Ps5Phase).Append('\n');
        sb.Append("TV: ").Append(i.TvBrand ?? "yok").Append(", bağlı TV uygulaması ")
            .Append(i.ConnectedTvs.ToString(CultureInfo.InvariantCulture)).Append(", TV uygulaması: ").Append(i.TvAppKind);
        if (!string.IsNullOrEmpty(i.TvAppVersion)) sb.Append(' ').Append(i.TvAppVersion);
        if (!string.IsNullOrEmpty(i.TvAppError)) sb.Append(" hata ").Append(i.TvAppError);
        sb.Append('\n');
        foreach (var line in i.Summary) sb.Append(line).Append('\n');
        sb.Append("\n— altyazi.log, en son satırlar —\n");
        AppendLog(sb, i.SubtitleLog);
        sb.Append("\n— tvinstall.log, en son satırlar —\n");
        AppendLog(sb, i.TvInstallLog);
        return sb.ToString().TrimEnd('\n');
    }

    static void AppendLog(StringBuilder sb, IReadOnlyList<string>? lines)
    {
        var kept = lines?.Where(l => l.Trim().Length > 0).ToList();
        if (kept is null || kept.Count == 0)
        {
            sb.Append("-\n");
            return;
        }
        foreach (var line in kept) sb.Append(line).Append('\n');
    }
}

/// <summary>HDMI yakalama kartı önizlemesinin görünüşü (yan pencereler tarifi §8.1).</summary>
/// <param name="Tone">Nokta rengi.</param>
/// <param name="PillKey">Hap yazısının anahtarı; null ise aygıt adı yazılır.</param>
/// <param name="PlaceholderVisible">Yer tutucu görünür mü.</param>
/// <param name="PlaceholderLock">Yer tutucu simgesi kilit mi (değilse kablo).</param>
/// <param name="PlaceholderKey">Yer tutucu yazısının anahtarı.</param>
/// <param name="DetailKey">Ayrıntı satırının anahtarı; yoksa satır gizli.</param>
/// <param name="DetailOk">Ayrıntı simgesi onay mı (değilse uyarı).</param>
/// <param name="ShowCameraSettings">Kamera Ayarları düğmesi görünür mü.</param>
public sealed record CardPreviewLook(StatusTone Tone, string? PillKey, bool PlaceholderVisible, bool PlaceholderLock,
    string PlaceholderKey, string? DetailKey, bool DetailOk, bool ShowCameraSettings)
{
    /// <summary>Çeviri sürmüyorken kart durumuna göre.</summary>
    public static CardPreviewLook For(CardCaptureState state) => state switch
    {
        CardCaptureState.Capturing => new(StatusTone.Good, null, false, false, "cardGuide.preview.searchingPlaceholder",
            "cardGuide.preview.workingDetail", true, false),
        CardCaptureState.BlackPicture => new(StatusTone.Warning, null, false, false, "cardGuide.preview.searchingPlaceholder",
            "cardGuide.preview.blackDetail", false, false),
        CardCaptureState.NeedsPermission => new(StatusTone.Warning, "cardGuide.preview.noPermissionPill", true, true,
            "cardGuide.preview.noPermissionPlaceholder", "cardGuide.preview.noPermissionDetail", false, true),
        CardCaptureState.NoCard => new(StatusTone.Warning, "cardGuide.preview.noCardPill", true, false,
            "cardGuide.preview.searchingPlaceholder", "cardGuide.preview.noCardDetail", false, false),
        _ => new(StatusTone.Idle, "cardGuide.preview.noCardPill", true, false, "cardGuide.preview.searchingPlaceholder",
            null, false, false),
    };
}

/// <summary>Serbest seçim penceresinin hesapları (yan pencereler tarifi §6). Birimler kare pikseli.</summary>
public static class FreeAreaMath
{
    /// <summary>Seçim karenin %1'inden dar ya da kısaysa iptal.</summary>
    public static bool TooSmall(double width, double height, int frameWidth, int frameHeight) =>
        width < frameWidth * 0.01 || height < frameHeight * 0.01;

    /// <summary>Çerçeve kalınlığı: max(2, kare yüksekliği / 360).</summary>
    public static double BorderThickness(int frameHeight) => Math.Max(2, frameHeight / 360.0);

    /// <summary>Sonuç yazısının boyu: max(16, kare yüksekliği × 0.032).</summary>
    public static double FontSize(int frameHeight) => Math.Max(16, frameHeight * 0.032);

    /// <summary>
    /// Sonuç kutusunun sol üstü: seçimin altına (boşluk = yükseklik × 0.012); taşarsa üstüne; sonra dikeyde ve
    /// yatayda kareye kırpılır; sol kenar seçimin sol kenarı.
    /// </summary>
    public static (double Left, double Top) ResultPosition(double selLeft, double selTop, double selBottom, double boxWidth,
        double boxHeight, int frameWidth, int frameHeight)
    {
        var gap = frameHeight * 0.012;
        var top = selBottom + gap;
        if (top + boxHeight > frameHeight) top = selTop - gap - boxHeight;
        top = Math.Clamp(top, 0, Math.Max(0, frameHeight - boxHeight));
        var left = Math.Clamp(selLeft, 0, Math.Max(0, frameWidth - boxWidth));
        return (left, top);
    }
}

/// <summary>Bilgisayardaki altyazı penceresinin çizim hesapları (yan pencereler tarifi §5).</summary>
public static class OverlayDrawing
{
    /// <summary>Satırın yazı boyu: max(1, boy × ölçek × (şimdiki 1, değilse 0.8) × sarma küçültmesi).</summary>
    public static double LineFontSize(int fontSize, double scale, bool current, double wrapScale) =>
        Math.Max(1, OverlayLayout.FontSize(fontSize) * scale * (current ? 1 : 0.8) * wrapScale);

    /// <summary>Satır zemininin saydamlığı: arka plan % / 100 × (şimdiki 1, değilse 0.83).</summary>
    public static double LineBackground(int backgroundPercent, bool current) =>
        Math.Clamp(backgroundPercent, 0, 100) / 100.0 * (current ? 1 : 0.83);

    /// <summary>Bölge kutusunun yazı boyu: max(12, boy × ölçek × 0.55).</summary>
    public static double RegionFontSize(int fontSize, double scale) => Math.Max(12, OverlayLayout.FontSize(fontSize) * scale * 0.55);

    /// <summary>Bölge kutusunun yatay hizası: -1 sol, 0 orta, 1 sağ (yazının yatay ortası &lt; 0.4 sol, &gt; 0.6 sağ).</summary>
    public static int RegionAlignment(double? centerX) => centerX switch
    {
        null => 0,
        < 0.4 => -1,
        > 0.6 => 1,
        _ => 0,
    };

    /// <summary>
    /// Ayar kipinde kenar tutamağıyla genişletme: orta yerinde kalır, iki yana eşit; genişlik = genişlik + 2 × kayma
    /// (en az 320, en çok bütün ekranlar). Dönen: (sol, genişlik).
    /// </summary>
    public static (double Left, double Width) ResizeFromCenter(double left, double width, double delta,
        IReadOnlyList<ScreenRect> screens)
    {
        var center = left + width / 2;
        var next = OverlayLayout.ResizeWidth(width + 2 * delta, screens);
        return (center - next / 2, next);
    }

    /// <summary>
    /// Oyunun üstüne oturma: genişlik = yuvarla(oyun genişliği × 0.9), oyuna ortalı, alt kenar = oyun altı − oyun
    /// yüksekliği × 0.03. Oyun alanı pikseldir; sistem DPI / 96'ya bölünerek WPF birimine çevrilir.
    /// </summary>
    public static ScreenRect OnGame(PixelRect game, double dpi, double height)
    {
        var f = dpi > 0 && double.IsFinite(dpi) ? dpi / 96.0 : 1;
        var x = game.X / f;
        var y = game.Y / f;
        var w = game.Width / f;
        var h = game.Height / f;
        var width = Math.Round(w * 0.9, MidpointRounding.AwayFromZero);
        var bottom = y + h - h * 0.03;
        return new ScreenRect(x + (w - width) / 2, bottom - height, width, height);
    }
}
