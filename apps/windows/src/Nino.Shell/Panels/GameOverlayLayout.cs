// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Globalization;
using Nino.Core.Imaging;
using Nino.Core.Link;
using Nino.Core.Settings;

namespace Nino.Shell.Panels;

/// <summary>Bilgisayardaki altyazı penceresinin yeri: dikdörtgen (WPF birimi) ve satırların üste mi yaslandığı.</summary>
/// <param name="Rect">Pencerenin yeri.</param>
/// <param name="TopAligned">Satırlar pencerenin üstüne yaslı (İngilizcenin altına oturunca); değilse alta.</param>
/// <param name="UserPlaced">Kullanıcının kaydettiği yer kullanıldı.</param>
public readonly record struct OverlaySeat(ScreenRect Rect, bool TopAligned, bool UserPlaced);

/// <summary>
/// HDMI kartıyla oynarken altyazı penceresinin yeri (kullanıcı hatası: çeviri hep altta sabitti, oyunun kendi altyazısını
/// örtüyordu). Kural:
/// <list type="number">
/// <item>Kullanıcı pencereyi bir yere taşıdıysa (ayarlardaki <c>Overlay</c>) o yer kullanılır (tarif §5.3 kuralıyla).</item>
/// <item>Değilse pencere oyunun üstüne oturur; okunan İngilizce satırın yeri biliniyorsa yazı onun <b>üstüne</b>
/// (yerleşim "altında" ise altına) konur, sığmazsa öbür yana; ikisi de sığmazsa ya da yerleşim "sabit" ise eski
/// oturuş (oyunun altı).</item>
/// <item>Pencere zaten İngilizceyle çakışmayan bir yerdeyse yerinde kalır (her satırda kıpırdamasın).</item>
/// </list>
/// </summary>
public static class CardOverlaySeat
{
    /// <summary>İngilizce satırla çeviri arasındaki boşluk (oyun yüksekliğine oran).</summary>
    public const double Gap = 0.015;

    /// <summary>
    /// Yazının kapladığı tahmini yükseklik (WPF birimi): iki satırlık şimdiki satır kutusu (boy × 1,3) ile iç boşluk ve
    /// aralıklar.
    /// </summary>
    public static double TextBlockHeight(int fontSize, double scale) =>
        OverlayLayout.FontSize(fontSize) * scale * 1.3 * 2 + 42 * scale;

    /// <summary>Yeri hesaplar.</summary>
    /// <param name="game">Oyunun ekrandaki alanı (ekran pikseli).</param>
    /// <param name="dpi">Sistem DPI'ı (piksel → WPF birimi: / (dpi/96)).</param>
    /// <param name="height">Pencere yüksekliği (WPF birimi).</param>
    /// <param name="textHeight">Yazının tahmini yüksekliği (<see cref="TextBlockHeight"/>).</param>
    /// <param name="english">Okunan İngilizce satırın karedeki yeri (oran) ya da bilinmiyor.</param>
    /// <param name="placement">Altyazı yerleşimi ayarı.</param>
    /// <param name="saved">Kullanıcının kaydettiği yer ya da yok.</param>
    /// <param name="screens">Bütün ekranlar.</param>
    /// <param name="workArea">Birincil çalışma alanı.</param>
    /// <param name="scale">Ölçek.</param>
    /// <param name="current">Pencerenin şimdiki yeri (kıpırdamasın diye) ya da yok.</param>
    public static OverlaySeat Place(PixelRect game, double dpi, double height, double textHeight, Box? english,
        SubtitlePlacement placement, OverlayPlacement? saved, IReadOnlyList<ScreenRect> screens, ScreenRect? workArea,
        double scale, OverlaySeat? current = null)
    {
        if (saved is not null)
            return new OverlaySeat(OverlayLayout.Place(saved, height, screens, workArea, scale), false, true);
        var fixedSeat = new OverlaySeat(OverlayDrawing.OnGame(game, dpi, height), false, false);
        if (english is not { } box || placement == SubtitlePlacement.Fixed) return fixedSeat;

        var f = dpi > 0 && double.IsFinite(dpi) ? dpi / 96.0 : 1;
        var gy = game.Y / f;
        var gh = game.Height / f;
        if (gh <= 0) return fixedSeat;
        var gap = gh * Gap;
        var boxTop = gy + Math.Clamp(box.Top, 0, 1) * gh;
        var boxBottom = gy + Math.Clamp(box.Bottom, 0, 1) * gh;

        if (current is { UserPlaced: false } now && Math.Abs(now.Rect.Width - fixedSeat.Rect.Width) < 0.5
            && Math.Abs(now.Rect.Height - height) < 0.5 && Math.Abs(now.Rect.X - fixedSeat.Rect.X) < 0.5)
        {
            var (zoneTop, zoneBottom) = Zone(now, textHeight);
            var inside = zoneTop >= gy - 0.5 && zoneBottom <= gy + gh + 0.5;
            var clear = zoneBottom <= boxTop - gap / 2 || zoneTop >= boxBottom + gap / 2;
            if (inside && clear) return now;
        }

        var aboveFits = boxTop - gap - textHeight >= gy;
        var belowFits = boxBottom + gap + textHeight <= gy + gh;
        var preferBelow = placement == SubtitlePlacement.Below;
        var x = fixedSeat.Rect.X;
        var w = fixedSeat.Rect.Width;
        OverlaySeat Above() => new(new ScreenRect(x, boxTop - gap - height, w, height), false, false);
        OverlaySeat Below() => new(new ScreenRect(x, boxBottom + gap, w, height), true, false);
        if (preferBelow ? belowFits : aboveFits) return preferBelow ? Below() : Above();
        if (preferBelow ? aboveFits : belowFits) return preferBelow ? Above() : Below();
        return fixedSeat;
    }

    /// <summary>Yerin yazı bölgesi (üst, alt).</summary>
    public static (double Top, double Bottom) Zone(OverlaySeat seat, double textHeight) => seat.TopAligned
        ? (seat.Rect.Y, seat.Rect.Y + textHeight)
        : (seat.Rect.Bottom - textHeight, seat.Rect.Bottom);
}

/// <summary>Panelin bir yazı parçası: metin ve vurgulu mu (<c>⟦…⟧</c>).</summary>
public readonly record struct PanelRun(string Text, bool Highlight);

/// <summary>Bir rengin RGB'si.</summary>
public readonly record struct PanelColor(byte R, byte G, byte B)
{
    /// <summary><c>#rrggbb</c> okur; bozuksa null.</summary>
    public static PanelColor? Parse(string? hex)
    {
        if (string.IsNullOrWhiteSpace(hex)) return null;
        var h = hex.Trim().TrimStart('#');
        if (h.Length != 6 || !int.TryParse(h, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var v)) return null;
        return new PanelColor((byte)(v >> 16), (byte)(v >> 8), (byte)v);
    }

    /// <summary>Parlaklık (0–255, 0.299/0.587/0.114).</summary>
    public double Luma => 0.299 * R + 0.587 * G + 0.114 * B;
}

/// <summary>Panelin çizim türü.</summary>
public enum PanelKind
{
    /// <summary>Oyunun satırını tam örten kutu (görev şeridi gibi).</summary>
    Cover,

    /// <summary>Kutusuz, gölgeli sade yazı.</summary>
    Plain,

    /// <summary>Telefonun yanındaki balon (yuvarlak, gölgeli).</summary>
    Side,

    /// <summary>Yazısız zemin paneli (varsa üstte başlık).</summary>
    Backdrop,

    /// <summary>Harita görev kartı (opak koyu zemin, üstte vurgu çizgisi, ilk satır başlık).</summary>
    Card,
}

/// <summary>Bir örtü öğesinin çizimi (WPF birimi; alanın sol üstüne göre).</summary>
public sealed record PanelVisual(
    PanelKind Kind,
    ScreenRect Rect,
    double FontSize,
    double CornerRadius,
    PanelColor? Fill,
    double FillAlpha,
    PanelColor Ink,
    bool Shadow,
    bool Italic,
    bool BoldFirstLine,
    bool AccentBar,
    bool VerticalCenter,
    double Angle,
    double Padding,
    IReadOnlyList<PanelRun> Runs);

/// <summary>
/// Sürekli örtülerin (telefon/harita) bilgisayardaki çizim hesabı: öğe kutusu oyunun alanına oranla gelir. Bayrak
/// anlamları TV'deki gibidir (tv-baglanti.md §4.6, protokol: <c>card</c> kutuya tam oturur ve opak çizilir,
/// <c>side</c> yuvarlak ve gölgeli, <c>backdrop</c> yazısız zemin, <c>plain</c> kutusuz; <c>⟦…⟧</c> vurgu rengiyle).
/// </summary>
public static class ScreenPanelLayout
{
    /// <summary>Vurgu rengi (TV'deki pembe).</summary>
    public static readonly PanelColor Accent = new(0xFF, 0x5F, 0xB2);

    /// <summary>Kartın zemini.</summary>
    public static readonly PanelColor CardFill = new(0x1C, 0x1C, 0x1E);

    /// <summary>Açık zeminde yazı rengi.</summary>
    public static readonly PanelColor DarkInk = new(0x2C, 0x2C, 0x2E);

    /// <summary>Koyu zeminde yazı rengi.</summary>
    public static readonly PanelColor LightInk = new(0xFF, 0xFF, 0xFF);

    /// <summary>Öğe türü.</summary>
    public static PanelKind KindOf(ScreenItem item) =>
        item.Card ? PanelKind.Card
        : item.Backdrop ? PanelKind.Backdrop
        : item.Side ? PanelKind.Side
        : item.Plain ? PanelKind.Plain
        : PanelKind.Cover;

    /// <summary>Öğeyi alan içinde (genişlik × yükseklik, WPF birimi) yerleştirir; boyu sıfırsa null.</summary>
    public static PanelVisual? Layout(ScreenItem item, double areaWidth, double areaHeight)
    {
        if (!(areaWidth > 0) || !(areaHeight > 0)) return null;
        var b = item.Box;
        var left = Math.Clamp(Math.Min(b.Left, b.Right), 0, 1);
        var right = Math.Clamp(Math.Max(b.Left, b.Right), 0, 1);
        var top = Math.Clamp(Math.Min(b.Top, b.Bottom), 0, 1);
        var bottom = Math.Clamp(Math.Max(b.Top, b.Bottom), 0, 1);
        var rect = new ScreenRect(left * areaWidth, top * areaHeight, (right - left) * areaWidth, (bottom - top) * areaHeight);
        if (rect.Width < 1 || rect.Height < 1) return null;

        var kind = KindOf(item);
        var runs = Runs(item.Text);
        var lines = Math.Max(1, string.Concat(runs.Select(r => r.Text)).Split('\n').Length);
        var line = item.Line is { } l && l > 0 ? l * areaHeight : rect.Height / lines / 1.3;
        var font = Math.Max(8, line * 0.78);

        var fill = PanelColor.Parse(item.Fill);
        var alpha = Math.Clamp(item.Alpha ?? kind switch
        {
            PanelKind.Backdrop => 0.6,
            PanelKind.Side => 0.95,
            PanelKind.Plain => 0,
            _ => 0.88,
        }, 0, 1);
        switch (kind)
        {
            case PanelKind.Card:
                fill ??= CardFill;
                alpha = 1;
                break;
            case PanelKind.Backdrop:
                fill ??= new PanelColor(0xE2, 0xE4, 0xE9);
                break;
            case PanelKind.Plain:
                fill = null;
                alpha = 0;
                break;
            default:
                fill ??= new PanelColor(0, 0, 0);
                break;
        }
        var ink = PanelColor.Parse(item.Ink) ?? (fill is { } c && alpha >= 0.5 && c.Luma > 140 ? DarkInk : LightInk);
        var corner = kind switch
        {
            PanelKind.Side => Math.Min(rect.Height / 2, font * 0.9),
            PanelKind.Card => font * 0.35,
            PanelKind.Backdrop => Math.Min(rect.Width, rect.Height) * 0.06,
            PanelKind.Plain => 0,
            _ => font * 0.25,
        };
        var angle = item.Angle is { } a && Math.Abs(a) >= 0.3 && double.IsFinite(a) ? a : 0;
        return new PanelVisual(kind, rect, font, corner, fill, alpha, ink,
            Shadow: kind is PanelKind.Side or PanelKind.Plain,
            Italic: item.Italic,
            BoldFirstLine: kind == PanelKind.Card,
            AccentBar: kind == PanelKind.Card,
            VerticalCenter: kind is PanelKind.Cover or PanelKind.Side or PanelKind.Plain,
            Angle: angle,
            Padding: kind == PanelKind.Plain ? 0 : font * 0.4,
            Runs: runs);
    }

    /// <summary>Bütün öğeler, sırasıyla (önce zemin, sonra balonlar…); çizilemeyenler atlanır.</summary>
    public static IReadOnlyList<PanelVisual> LayoutAll(IEnumerable<ScreenItem>? items, double areaWidth, double areaHeight) =>
        (items ?? []).Select(i => Layout(i, areaWidth, areaHeight)).OfType<PanelVisual>().ToList();

    /// <summary>
    /// Metni vurgulu/vurgusuz parçalara böler: <c>⟦…⟧</c> arası vurgulu; eşi olmayan işaretler atılır.
    /// </summary>
    public static IReadOnlyList<PanelRun> Runs(string? text)
    {
        var result = new List<PanelRun>();
        if (string.IsNullOrEmpty(text)) return result;
        var plain = new System.Text.StringBuilder();
        void Flush()
        {
            if (plain.Length > 0) result.Add(new PanelRun(plain.ToString(), false));
            plain.Clear();
        }
        var i = 0;
        while (i < text.Length)
        {
            var ch = text[i];
            if (ch == '⟦')
            {
                var close = text.IndexOf('⟧', i + 1);
                var nextOpen = text.IndexOf('⟦', i + 1);
                if (close >= 0 && (nextOpen < 0 || nextOpen > close))
                {
                    Flush();
                    if (close > i + 1) result.Add(new PanelRun(text[(i + 1)..close], true));
                    i = close + 1;
                    continue;
                }
                i++;
                continue;
            }
            if (ch != '⟧') plain.Append(ch);
            i++;
        }
        Flush();
        return result;
    }

    /// <summary>Örtü alanı: oyunun ekrandaki alanı (piksel) → WPF birimi (sistem DPI / 96).</summary>
    public static ScreenRect AreaOnScreen(PixelRect game, double dpi)
    {
        var f = dpi > 0 && double.IsFinite(dpi) ? dpi / 96.0 : 1;
        return new ScreenRect(game.X / f, game.Y / f, game.Width / f, game.Height / f);
    }
}
