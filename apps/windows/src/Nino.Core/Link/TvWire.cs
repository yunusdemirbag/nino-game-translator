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

    /// <summary>Bir mesajın en büyük boyu (TV'ler bunu aşanı <c>too_large</c> ile kapatır); <c>cover</c> buna sığmalı.</summary>
    public const int MaxMessageBytes = 512 * 1024;

    /// <summary>Gönderici durumu mesajının türü.</summary>
    public const string StateType = "state";

    /// <summary>
    /// Gönderici durumu: <c>{"app":"nino","type":"state","active":…}</c>. Etkin: çeviri sürüyor ve altyazı TV'ye gidiyor.
    /// Yalnız 47800 girişinde (TV'nin bağlandığı yön) gönderilir.
    /// </summary>
    public static string StateMessage(bool active) => Envelope(StateType, new WireObject { ["active"] = active });

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
                var o = LegacySubtitle(s);
                o["at"] = atUnixMs;
                o["duration"] = s.DurationMs;
                return o;
            }
            case ScreenShown sc:
            {
                var o = ScreenCommon(sc, link: false);
                o["duration"] = sc.DurationMs;
                return o;
            }
            case RegionShown r: return RegionBody(r, link: false);
            case StyleChanged st: return StyleBody(st.Style, link: false);
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
                o = LinkSubtitle(s);
                o["id"] = showId ?? 0L;
                o["durationMs"] = durationOverrideMs ?? s.DurationMs;
                break;
            case SubtitleCleared:
                o = new WireObject();
                if (showId is { } id) o["id"] = id;
                break;
            case ScreenShown sc:
                o = ScreenCommon(sc, link: true);
                o["durationMs"] = Math.Max(0, durationOverrideMs ?? sc.DurationMs);
                break;
            case RegionShown r: o = RegionBody(r, link: true); break;
            case StyleChanged st: o = StyleBody(st.Style, link: true); break;
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

    /// <summary>
    /// <c>show</c>'da <c>cover</c> ile 512 KB'ı aşan mesaj: <c>cover</c> atılır (Mac gibi). Sığıyorsa olayın kendisi.
    /// </summary>
    public static SubtitleShown FitShow(SubtitleShown show, long? showId = null)
    {
        if (show.Cover is null || ByteCount(LinkMessage(show, showId)) <= MaxMessageBytes) return show;
        return show with { Cover = null };
    }

    /// <summary>Eski 8787 kutusu (4 ondalık, yarıda çifte).</summary>
    public static WireObject BoxBody(Box b) => new()
    {
        ["bottom"] = WireNumbers.Fraction(b.Bottom),
        ["left"] = WireNumbers.Fraction(b.Left),
        ["right"] = WireNumbers.Fraction(b.Right),
        ["top"] = WireNumbers.Fraction(b.Top),
    };

    /// <summary>Yeni protokol kutusu (Mac ile aynı yuvarlama: <see cref="WireNumbers.LinkUnit"/>).</summary>
    public static WireObject LinkBoxBody(Box b) => new()
    {
        ["bottom"] = WireNumbers.LinkUnit(b.Bottom),
        ["left"] = WireNumbers.LinkUnit(b.Left),
        ["right"] = WireNumbers.LinkUnit(b.Right),
        ["top"] = WireNumbers.LinkUnit(b.Top),
    };

    static WireObject BoxOf(Box b, bool link) => link ? LinkBoxBody(b) : BoxBody(b);

    /// <summary>Eski yol ve bilgisayar penceresi için metin: tam metin (adıyla), yer tutucular okunur.</summary>
    public static string ReadableText(SubtitleShown s) => IconPlaceholders.Readable(s.Text, s.Icons);

    /// <summary>
    /// Yeni protokolde gösterilecek metin ve ad: ad ayrılabiliyorsa metin adsız, ad ayrı; değilse tam metin ve ad yok.
    /// </summary>
    public static (string Text, string? Speaker) LinkText(SubtitleShown s)
    {
        if (TvSpeaker.Clean(s.Speaker) is not { } name) return (s.Text, null);
        return TvSpeaker.Strip(s.Text, s.Speaker!.Trim()) is { } body ? (body, name) : (s.Text, null);
    }

    static WireObject LegacySubtitle(SubtitleShown s)
    {
        var o = new WireObject { ["text"] = ReadableText(s) };
        if (s.Box is { } box) o["box"] = BoxBody(box);
        if (s.Paragraphs) o["paragraphs"] = true;
        if (s.Replace) o["replace"] = true;
        return o;
    }

    static WireObject LinkSubtitle(SubtitleShown s)
    {
        var (text, speaker) = LinkText(s);
        var o = new WireObject { ["text"] = text, ["position"] = s.Position == TvPosition.Top ? TvPosition.Top : TvPosition.Bottom };
        if (s.Box is { } box) o["box"] = LinkBoxBody(box);
        // Yalnız bayrak: Windows okuması satırları "\n" ile birleştirir; her iki satırlık diyalog paragraf düzenine geçmesin.
        if (s.Paragraphs) o["paragraphs"] = true;
        if (s.Replace) o["replace"] = true;
        if (!string.IsNullOrEmpty(s.Source)) o["source"] = s.Source!;
        if (s.Light is { } light) o["light"] = WireNumbers.Alpha(light);
        if (!string.IsNullOrEmpty(s.Cover)) o["cover"] = s.Cover!;
        if (speaker is not null) o["speaker"] = speaker;
        if (LinkIcon.Encode(IconPlaceholders.Used(text, s.Icons)) is { } icons) o["icons"] = icons;
        return o;
    }

    static WireObject ScreenCommon(ScreenShown sc, bool link)
    {
        var o = new WireObject { ["items"] = sc.Items.Select(i => ItemBody(i, link)).ToList() };
        if (sc.Overlay) o["overlay"] = true;
        return o;
    }

    static WireObject ItemBody(ScreenItem i, bool link)
    {
        var text = link ? i.Text : IconPlaceholders.Readable(i.Text, i.Icons);
        var o = new WireObject { ["box"] = BoxOf(i.Box, link), ["text"] = text };
        if (i.Line is { } line) o["line"] = link ? WireNumbers.LinkRound(line) : WireNumbers.Fraction(line);
        if (text.Contains('\n')) o["paragraphs"] = true;
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
        if (link && i.Frost) o["frost"] = true;
        if (link && LinkIcon.Encode(i.Icons) is { } icons) o["icons"] = icons;
        return o;
    }

    static WireObject RegionBody(RegionShown r, bool link)
    {
        var o = new WireObject { ["id"] = r.Id, ["text"] = link ? r.Text : IconPlaceholders.Readable(r.Text, r.Icons) };
        if (r.Box is { } box) o["box"] = BoxOf(box, link);
        if (r.Line is { } line) o["line"] = link ? WireNumbers.LinkRound(line) : WireNumbers.Fraction(line);
        if (link && LinkIcon.Encode(r.Icons) is { } icons) o["icons"] = icons;
        return o;
    }

    static WireObject StyleBody(TvStyle s, bool link)
    {
        var o = LegacyStyleBody(s);
        if (link) o["theme"] = s.Theme;
        return o;
    }

    static WireObject LegacyStyleBody(TvStyle s) => new()
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
        SubtitleShown s => new LocalSubtitleEvent(LocalEventKind.Subtitle, ReadableText(s), s.DurationMs, s.Paragraphs, s.Replace,
            Box: s.Box),
        SubtitleCleared => new LocalSubtitleEvent(LocalEventKind.Clear),
        // Sürekli örtüler altyazı yığınına girmez; bilgisayardaki panel katmanı öğeleri oyunun üstüne çizer.
        ScreenShown { Overlay: true } sc => new LocalSubtitleEvent(LocalEventKind.Overlay, DurationMs: sc.DurationMs,
            Items: sc.Items.Select(ReadableItem).ToList()),
        ScreenShown sc => new LocalSubtitleEvent(LocalEventKind.Screen,
            string.Join("\n", sc.Items.Select(i => IconPlaceholders.Readable(i.Text, i.Icons))), sc.DurationMs, Paragraphs: true),
        ScreenCleared => new LocalSubtitleEvent(LocalEventKind.ScreenClear),
        RegionShown r => new LocalSubtitleEvent(LocalEventKind.Region, IconPlaceholders.Readable(r.Text, r.Icons),
            RegionId: r.Id, Box: r.Box),
        RegionsCleared => new LocalSubtitleEvent(LocalEventKind.RegionClear),
        _ => null,
    };

    /// <summary>Bilgisayar penceresi simge çizmez: yer tutucular okunur metne döner (yoksa öğenin kendisi).</summary>
    static ScreenItem ReadableItem(ScreenItem i) =>
        IconPlaceholders.Contains(i.Text) ? i with { Text = IconPlaceholders.Readable(i.Text, i.Icons) } : i;
}
