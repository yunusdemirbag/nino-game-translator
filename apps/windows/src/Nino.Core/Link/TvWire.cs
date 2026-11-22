// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text;
using Nino.Core.Imaging;

namespace Nino.Core.Link;

/// <summary>
/// Olaydan TV metnine çeviren tek yer. Eski 8787 çerçevesi (<c>event: ad\ndata: JSON\n\n</c>) ile yeni protokol
/// mesajı (<c>{"app":"nino","type":…}</c>) aynı gövde parçalarından üretilir; yuvarlama bir kez yapılır.
/// </summary>
public static class TvWire
{
    /// <summary>Yeni protokolün sürümü.</summary>
    public const int ProtocolVersion = 1;

    /// <summary><c>cover</c> taşımayan mesajların üst sınırı.</summary>
    public const int CompactMessageBytes = 16 * 1024;

    /// <summary>Eski olay adı (8787).</summary>
    public static string LegacyName(TvEvent e) => e switch
    {
        SubtitleShown => "subtitle",
        SubtitleCleared => "clear",
        TranslationStarted => "started",
        TranslationStopped => "stopped",
        ScreenShown => "screen",
        ScreenCleared => "screen-clear",
        RegionShown => "region",
        RegionsCleared => "region-clear",
        StyleChanged => "style",
        _ => throw new ArgumentOutOfRangeException(nameof(e)),
    };

    /// <summary>Yeni protokoldeki tür.</summary>
    public static string LinkType(TvEvent e) => e switch
    {
        SubtitleShown => "show",
        _ => LegacyName(e),
    };

    /// <summary>"TV'ye gönderme" kapısı kapalıyken TV'ye gitmeyen (altyazı) olaylar.</summary>
    public static bool IsSubtitleEvent(TvEvent e) => e is not (TranslationStarted or TranslationStopped);

    /// <summary>Eski 8787 gövdesi.</summary>
    public static WireObject LegacyBody(TvEvent e, long atUnixMs)
    {
        switch (e)
        {
            case SubtitleShown s:
            {
                var o = SubtitleCommon(s);
                o["at"] = atUnixMs;
                o["duration"] = s.DurationMs;
                return o;
            }
            case ScreenShown sc:
            {
                var o = ScreenCommon(sc);
                o["duration"] = sc.DurationMs;
                return o;
            }
            case RegionShown r: return RegionBody(r);
            case StyleChanged st: return StyleBody(st.Style);
            default: return new WireObject();
        }
    }

    /// <summary>Eski 8787 SSE çerçevesi.</summary>
    public static string LegacyFrame(TvEvent e, long atUnixMs) =>
        $"event: {LegacyName(e)}\ndata: {LegacyBody(e, atUnixMs).ToLegacyString()}\n\n";

    /// <summary>
    /// Yeni protokol mesajı. <paramref name="showId"/>: <c>show</c> için kimlik; <c>clear</c> için silinecek son
    /// <c>show</c>'un kimliği (yoksa kimliksiz). <paramref name="durationOverrideMs"/>: hazırlıkta kalan süre.
    /// </summary>
    public static string LinkMessage(TvEvent e, long? showId = null, int? durationOverrideMs = null)
    {
        WireObject o;
        switch (e)
        {
            case SubtitleShown s:
                o = SubtitleCommon(s);
                o["id"] = showId ?? 0L;
                o["durationMs"] = durationOverrideMs ?? s.DurationMs;
                o["position"] = "bottom";
                if (!string.IsNullOrEmpty(s.Source)) o["source"] = s.Source!;
                break;
            case SubtitleCleared:
                o = new WireObject();
                if (showId is { } id) o["id"] = id;
                break;
            case ScreenShown sc:
                o = ScreenCommon(sc);
                o["durationMs"] = durationOverrideMs ?? sc.DurationMs;
                break;
            case RegionShown r: o = RegionBody(r); break;
            case StyleChanged st: o = StyleBody(st.Style); break;
            default: o = new WireObject(); break;
        }
        return Envelope(LinkType(e), o);
    }

    /// <summary>Gövdeye <c>app</c> ve <c>type</c> eklenmiş mesaj (önce bu ikisi).</summary>
    public static string Envelope(string type, WireObject? body = null)
    {
        var o = body?.Clone() ?? new WireObject();
        o["app"] = "nino";
        o["type"] = type;
        return o.ToString("app", "type");
    }

    /// <summary>Mesajın UTF-8 bayt boyu.</summary>
    public static int ByteCount(string message) => Encoding.UTF8.GetByteCount(message);

    /// <summary>
    /// Çok öğeli <c>screen</c> 16 KB'ı aşıyorsa listenin sonundan öğe atarak sığdırır. Atılan öğe sayısını döner.
    /// </summary>
    public static ScreenShown FitScreen(ScreenShown screen, out int dropped)
    {
        dropped = 0;
        var items = screen.Items.ToList();
        var current = screen;
        while (items.Count > 0 && ByteCount(LinkMessage(current)) > CompactMessageBytes)
        {
            items.RemoveAt(items.Count - 1);
            dropped++;
            current = screen with { Items = items.ToArray() };
        }
        return current;
    }

    public static WireObject BoxBody(Box b) => new()
    {
        ["bottom"] = WireNumbers.Fraction(b.Bottom),
        ["left"] = WireNumbers.Fraction(b.Left),
        ["right"] = WireNumbers.Fraction(b.Right),
        ["top"] = WireNumbers.Fraction(b.Top),
    };

    static WireObject SubtitleCommon(SubtitleShown s)
    {
        var o = new WireObject { ["text"] = s.Text };
        if (s.Box is { } box) o["box"] = BoxBody(box);
        if (s.Paragraphs) o["paragraphs"] = true;
        if (s.Replace) o["replace"] = true;
        return o;
    }

    static WireObject ScreenCommon(ScreenShown sc)
    {
        var o = new WireObject { ["items"] = sc.Items.Select(ItemBody).ToList() };
        if (sc.Overlay) o["overlay"] = true;
        return o;
    }

    static WireObject ItemBody(ScreenItem i)
    {
        var o = new WireObject { ["box"] = BoxBody(i.Box), ["text"] = i.Text };
        if (i.Line is { } line) o["line"] = WireNumbers.Fraction(line);
        if (i.Text.Contains('\n')) o["paragraphs"] = true;
        if (i.Plain) o["plain"] = true;
        if (i.Italic) o["italic"] = true;
        // Eski uygulama gibi: verildiyse (boş dizge de) yazılır.
        if (i.Fill is not null) o["fill"] = i.Fill;
        if (i.Ink is not null) o["ink"] = i.Ink;
        if (WireNumbers.Angle(i.Angle) is { } angle) o["angle"] = angle;
        if (i.Alpha is { } alpha) o["alpha"] = WireNumbers.Alpha(alpha);
        if (i.Side) o["side"] = true;
        if (i.Backdrop) o["backdrop"] = true;
        if (i.Card) o["card"] = true;
        return o;
    }

    static WireObject RegionBody(RegionShown r)
    {
        var o = new WireObject { ["id"] = r.Id, ["text"] = r.Text };
        if (r.Box is { } box) o["box"] = BoxBody(box);
        if (r.Line is { } line) o["line"] = WireNumbers.Fraction(line);
        return o;
    }

    static WireObject StyleBody(TvStyle s) => new()
    {
        ["autoSize"] = s.AutoSize,
        ["background"] = s.Background,
        ["backgroundShape"] = s.BackgroundShape,
        ["bold"] = s.Bold,
        ["bottomPercent"] = s.BottomPercent,
        ["displayMode"] = s.DisplayMode,
        ["font"] = s.Font,
        ["fontSize"] = s.FontSize,
        ["placement"] = s.Placement,
        ["stackPrevious"] = s.StackPrevious,
        ["textColor"] = s.TextColor,
        ["watermark"] = s.Watermark,
    };

    /// <summary>Yerel dinleyiciye gidecek özet; gitmeyecekse <c>null</c>.</summary>
    public static LocalSubtitleEvent? Local(TvEvent e) => e switch
    {
        SubtitleShown s => new LocalSubtitleEvent(LocalEventKind.Subtitle, s.Text, s.DurationMs, s.Paragraphs, s.Replace,
            Box: s.Box),
        SubtitleCleared => new LocalSubtitleEvent(LocalEventKind.Clear),
        // Sürekli örtüler altyazı yığınına girmez; bilgisayardaki panel katmanı öğeleri oyunun üstüne çizer.
        ScreenShown { Overlay: true } sc => new LocalSubtitleEvent(LocalEventKind.Overlay, DurationMs: sc.DurationMs,
            Items: sc.Items),
        ScreenShown sc => new LocalSubtitleEvent(LocalEventKind.Screen,
            string.Join("\n", sc.Items.Select(i => i.Text)), sc.DurationMs, Paragraphs: true),
        ScreenCleared => new LocalSubtitleEvent(LocalEventKind.ScreenClear),
        RegionShown r => new LocalSubtitleEvent(LocalEventKind.Region, r.Text, RegionId: r.Id, Box: r.Box),
        RegionsCleared => new LocalSubtitleEvent(LocalEventKind.RegionClear),
        _ => null,
    };
}
