// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;
using Nino.Core.Reading;
using Nino.Core.Settings;

namespace Nino.Core.Link;

/// <summary>Konuşan adının <c>show.speaker</c> olarak ayrılması (Mac ile aynı kural).</summary>
public static class TvSpeaker
{
    /// <summary>Adın en uzun boyu (uzunu kırpılır).</summary>
    public const int MaxLength = 60;

    static readonly string[] Separators = [":", "："];

    /// <summary>
    /// Gösterilecek çeviriden konuşan adını ayırır. Yalnız ayar açıkken, kaynakta tek bir baştaki etiket (<c>AD: …</c>)
    /// varsa ve çeviri o adla (<c>AD:</c> ya da <c>AD：</c>) başlıyorsa; adın ardında harf yoksa bölünmez. Çok konuşanlı
    /// satırda adlar metinde kalır. Dönen <c>Text</c> adsız çeviridir.
    /// </summary>
    public static (string Text, string? Speaker) Split(string text, string? source, bool showSpeakerNames)
    {
        if (!showSpeakerNames) return (text, null);
        var lines = (source ?? "").Replace("\r\n", "\n").Split('\n').Select(l => l.Trim()).Where(l => l.Length > 0).ToList();
        if (lines.Count == 0 || SpeakerName.Split(lines[0]).Name is not { } name) return (text, null);
        if (lines.Count(l => SpeakerName.Split(l).HasName) != 1) return (text, null);
        return Strip(text, name) is { } body ? (body, name) : (text, null);
    }

    /// <summary>Metin <paramref name="name"/> etiketiyle başlıyorsa adsız gövde (harf içermiyorsa null).</summary>
    public static string? Strip(string text, string name)
    {
        foreach (var sep in Separators)
        {
            if (!text.StartsWith(name + sep, StringComparison.Ordinal)) continue;
            var body = text[(name.Length + sep.Length)..].Trim();
            return body.Any(char.IsLetter) ? body : null;
        }
        return null;
    }

    /// <summary>JSON'a yazılacak ad: kırpılmış, en çok 60 karakter; boşsa null.</summary>
    public static string? Clean(string? speaker)
    {
        var t = (speaker ?? "").Trim();
        return t.Length == 0 ? null : t.Length > MaxLength ? t[..MaxLength] : t;
    }
}

/// <summary><c>show.position</c>: altyazının TV'de üstte mi altta mı durduğu.</summary>
public static class TvPosition
{
    public const string Bottom = "bottom";
    public const string Top = "top";

    /// <summary>Hazır alan "üst" ya da okuma bölgesinin altı karenin yarısından yukarıdaysa <c>top</c>, değilse <c>bottom</c>.</summary>
    public static string For(AreaPreset preset, Region region) =>
        preset == AreaPreset.Top || region.Bottom < 0.5 ? Top : Bottom;
}

/// <summary><see cref="TvShowBuilder"/>'ın o anki ayarları okuduğu yerler (ayar değişince yeniden kurmak gerekmesin).</summary>
public sealed record TvShowOptions
{
    /// <summary>"Konuşanın adı" ayarı.</summary>
    public Func<bool> ShowSpeakerNames { get; init; } = () => true;

    /// <summary><see cref="TvPosition"/> değeri.</summary>
    public Func<string> Position { get; init; } = () => TvPosition.Bottom;

    /// <summary>Son kare (buzlu zemin için); yoksa null.</summary>
    public Func<BgraFrame?> LastFrame { get; init; } = () => null;

    /// <summary>Kareyi JPEG'e çeviren (kalite verilir); yoksa ya da null dönerse <c>cover</c> gönderilmez (ör. Linux).</summary>
    public Func<BgraFrame, int, byte[]?>? EncodeJpeg { get; init; }
}

/// <summary>
/// Okuma hattının altyazısından TV olayı: konuşan adı (<c>speaker</c>), konum, kaynak metin ve buzlu zemin (<c>cover</c>)
/// burada eklenir. Platformdan bağımsızdır; JPEG kodlayıcı dışarıdan verilir.
/// </summary>
public sealed class TvShowBuilder(TvShowOptions options)
{
    /// <summary>Altyazıdan TV olayı.</summary>
    public SubtitleShown Build(SubtitleShow show)
    {
        var (_, speaker) = TvSpeaker.Split(show.Text, show.Source, SafeGet(options.ShowSpeakerNames, true));
        return new SubtitleShown(show.Text, show.DurationMs, show.Box, show.Paragraphs, show.Replace, show.Source)
        {
            Speaker = speaker,
            Position = SafeGet(options.Position, TvPosition.Bottom),
            Cover = CoverFor(show.Box),
        };
    }

    string? CoverFor(Box? box)
    {
        if (box is not { } b || options.EncodeJpeg is not { } encode) return null;
        var frame = SafeGet<BgraFrame?>(options.LastFrame, null);
        if (frame is null) return null;
        try { return FrostCover.Make(frame, b, encode); }
        catch (Exception) { return null; }
    }

    static T SafeGet<T>(Func<T> get, T fallback)
    {
        try { return get(); }
        catch (Exception) { return fallback; }
    }
}
