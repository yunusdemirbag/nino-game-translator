// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text.RegularExpressions;
using Nino.Core.Design;
using Nino.Core.Library;
using Nino.Core.Text;
using Nino.RemotePlay;

namespace Nino.Shell;

// Ana ekranın (salon sahnesi, cam anahtar, alt şerit, kartlar) arayüzsüz hesapları (ana-ekran.md). Windows çizer;
// Linux paneli aynı kuralları kullanabilir. Hepsi saf; testleri Nino.Shell.Tests/HomeScreenTests.cs'te.

/// <summary>Fişin prize yaylanarak gitmesi (ana-ekran §4.9): tepki 0,55 sn, sönüm 0,7, süre 0,9 sn.</summary>
public static class PlugSpring
{
    /// <summary>Tepki süresi (sn).</summary>
    public const double Response = 0.55;

    /// <summary>Sönüm oranı.</summary>
    public const double Damping = 0.7;

    /// <summary>Hareketin süresi (sn); bunda durur.</summary>
    public const double Duration = 0.9;

    static readonly double Omega = 2 * Math.PI / Response;
    static readonly double OmegaD = Omega * Math.Sqrt(1 - Damping * Damping);

    /// <summary>Başlangıç farkının t saniyede kalan payı (t = 0'da 1; süre dolunca 0).</summary>
    public static double Remaining(double seconds)
    {
        if (seconds <= 0) return 1;
        if (seconds >= Duration) return 0;
        return Math.Exp(-Damping * Omega * seconds)
            * (Math.Cos(OmegaD * seconds) + Damping * Omega / OmegaD * Math.Sin(OmegaD * seconds));
    }
}

/// <summary>Fiş bırakılınca ne olacağı (ana-ekran §4.10).</summary>
public enum PlugRelease
{
    /// <summary>Aç/kapat.</summary>
    Toggle,

    /// <summary>Fiş yerine döner.</summary>
    SnapBack,
}

/// <summary>Fişi bırakma kuralı.</summary>
public static class PlugDrop
{
    /// <summary>Bundan kısa sürükleme tıklamadır.</summary>
    public const double ClickDistance = 6;

    /// <summary>Prize bundan yakın bırakılan fiş "takılı" sayılır.</summary>
    public const double SocketReach = 140;

    /// <summary>Sürükleme farkıyla bırakılan fişin sonucu.</summary>
    /// <param name="scene">Sahne düzeni.</param>
    /// <param name="plugged">Fiş şu an takılı mı.</param>
    /// <param name="offset">Sürükleme farkı (sahne pikseli).</param>
    public static PlugRelease Decide(LivingRoomScene scene, bool plugged, ScenePoint offset)
    {
        if (Math.Sqrt(offset.X * offset.X + offset.Y * offset.Y) < ClickDistance) return PlugRelease.Toggle;
        var from = plugged ? scene.Socket : scene.PlugRest;
        var end = new ScenePoint(from.X + offset.X, from.Y + offset.Y);
        var dx = end.X - scene.Socket.X;
        var dy = end.Y - scene.Socket.Y;
        var near = Math.Sqrt(dx * dx + dy * dy) < SocketReach;
        return near != plugged ? PlugRelease.Toggle : PlugRelease.SnapBack;
    }
}

/// <summary>Salondaki TV'nin içinde hangi ekran (ana-ekran §5.1).</summary>
public enum TvScreenKind
{
    /// <summary>"Fişi prize sürükleyin" bekleme ekranı.</summary>
    Idle,

    /// <summary>Nino açılışı.</summary>
    Splash,

    /// <summary>Canlı ekran.</summary>
    Live,
}

/// <summary>TV ekranı seçimi.</summary>
public static class TvScreenRule
{
    /// <summary>Fiş takılı değilse bekleme; takılı ve açılış bitmediyse açılış; değilse canlı.</summary>
    public static TvScreenKind Choose(bool plugged, bool splashFinished) =>
        !plugged ? TvScreenKind.Idle : !splashFinished ? TvScreenKind.Splash : TvScreenKind.Live;

    /// <summary>
    /// İndirme göstergesi görünür mü (§5.4): açılış beklemesinde gizli; fiş takılı değilken ya da TV açılışı
    /// bittikten sonra görünür; açılış sırasında gizli.
    /// </summary>
    public static bool DownloadsVisible(bool introWaiting, TvScreenKind screen) =>
        !introWaiting && screen != TvScreenKind.Splash;
}

/// <summary>Canlı ekranın satırı.</summary>
/// <param name="Text">Gösterilecek metin.</param>
/// <param name="IsSubtitle">Altyazı mı (yarı kalın beyaz, koyu kutu) yoksa durum metni mi (soluk, saydam kutu).</param>
public readonly record struct LiveLine(string Text, bool IsSubtitle);

/// <summary>Canlı ekran satırının kuralı (ana-ekran §5.2).</summary>
public static class LiveLineRule
{
    /// <summary>
    /// Yayın aşamasında değilse görüntü kaynağının durum metni; yayındaysa ve son çeviri boşsa "sıradaki altyazı
    /// bekleniyor"; değilse son çeviri.
    /// </summary>
    public static LiveLine Choose(SourcePhase phase, string? lastTranslation, string consoleStatus, string waiting) =>
        phase != SourcePhase.Streaming ? new LiveLine(consoleStatus, false)
        : string.IsNullOrEmpty(lastTranslation) ? new LiveLine(waiting, false)
        : new LiveLine(lastTranslation, true);
}

/// <summary>TV'deki toplam indirme sayısının sayma gösterisi (ana-ekran §5.4).</summary>
public static class DownloadCountUp
{
    /// <summary>1, 2, 3 rakamlarının her biri.</summary>
    public const double DigitMs = 280;

    /// <summary>Saymanın başladığı an (3 × 280).</summary>
    public const double CountStartMs = 3 * DigitMs;

    /// <summary>Saymanın süresi.</summary>
    public const double CountMs = 1550;

    /// <summary>Sayma gösterisi oynar mı: hareketi azalt kapalı ve sayı 3'ten büyük.</summary>
    public static bool Plays(long total, bool reducedMotion) => !reducedMotion && total > 3;

    /// <summary>Saymanın ilerlemesi p (0–1).</summary>
    public static double Progress(double elapsedMs) => Math.Clamp((elapsedMs - CountStartMs) / CountMs, 0, 1);

    /// <summary>Gösterilen sayı: önce 1, 2, 3; sonra en büyüğü(3, yuvarla(p^2,6 × toplam)).</summary>
    public static long Shown(double elapsedMs, long total)
    {
        if (elapsedMs < DigitMs) return Math.Min(1, total);
        if (elapsedMs < 2 * DigitMs) return Math.Min(2, total);
        if (elapsedMs < CountStartMs) return Math.Min(3, total);
        var p = Progress(elapsedMs);
        return Math.Max(3, (long)Math.Round(Math.Pow(p, 2.6) * total, MidpointRounding.AwayFromZero));
    }

    /// <summary>Sayma bitti mi (p = 1).</summary>
    public static bool Finished(double elapsedMs) => elapsedMs >= CountStartMs + CountMs;

    /// <summary>Binlik ayırıcılı sayı, verilen (sistemin bölge) kültürüyle: 3439 → "3.439" ya da "3,439".</summary>
    public static string Format(long value, IFormatProvider culture) => value.ToString("N0", culture);
}

/// <summary>Cam anahtarın kapalı yazısının metin anahtarları (ana-ekran §6.5).</summary>
public static class GlassToggleText
{
    /// <summary>Başlık: açılıyorsa "Bağlanıyor…", başlatılabiliyorsa "Aç", değilse "PS5'inizi bağlayın".</summary>
    public static string TitleKey(bool starting, bool canStart) =>
        starting ? "status.common.connecting" : canStart ? "home.toggle.turnOn" : "home.toggle.connectPs5";

    /// <summary>Alt yazı: başlatılabiliyor ya da açılıyorsa altyazı dili yazısı, değilse "kuruluma başlamak için dokunun".</summary>
    public static string SubtitleKey(bool starting, bool canStart) =>
        canStart || starting ? "home.toggle.turkishSubtitles" : "home.toggle.tapToSetUp";
}

/// <summary>Ana ekrandaki aç/kapat'ın kararı (ana-ekran §4.11; açılıyorken bekleme çağıranda).</summary>
public enum HomeToggleAction
{
    /// <summary>Durdur.</summary>
    Stop,

    /// <summary>Başlat.</summary>
    Start,

    /// <summary>Kurulumun TV adımını aç.</summary>
    OpenTvStep,

    /// <summary>Kurulumun konsol adımını aç.</summary>
    OpenConsoleStep,
}

/// <summary>Aç/kapat kuralı.</summary>
public static class HomeToggleRule
{
    /// <summary>
    /// Açıksa durdur; başlatılabiliyorsa başlat; değilse kurulum: HDMI yakalama kartı ile altyazı TV'ye gidiyorsa eksik olan
    /// yalnız TV'dir (TV adımı), değilse konsol adımı.
    /// </summary>
    public static HomeToggleAction Decide(bool translating, bool canStart, bool usesCaptureCard, bool showsOnTv) =>
        translating ? HomeToggleAction.Stop
        : canStart ? HomeToggleAction.Start
        : usesCaptureCard && showsOnTv ? HomeToggleAction.OpenTvStep
        : HomeToggleAction.OpenConsoleStep;

    /// <summary>Kurulumda açılacak adım (yalnız <see cref="HomeToggleAction.OpenTvStep"/> ve konsol adımı için).</summary>
    public static SetupStep StepFor(HomeToggleAction action) =>
        action == HomeToggleAction.OpenTvStep ? SetupStep.Tv : SetupStep.Console;
}

/// <summary>Alt şeridin girdileri (denetleyiciden okunanlar).</summary>
public sealed record HomeFooterInput
{
    public bool UsesGameWindow { get; init; }
    public bool UsesCaptureCard { get; init; }
    public string ConsoleTitle { get; init; } = "PS5";
    public bool OnStreamPath { get; init; }
    public bool IsXbox { get; init; }
    public bool FrameSourceIsPs5 { get; init; }
    public bool IsTranslating { get; init; }
    public bool HasConsole { get; init; }
    public string? ConsoleName { get; init; }

    /// <summary>Kaynağın (PS5, pencere, kart) uzun durum metni (ipucu).</summary>
    public string ConsoleStatusText { get; init; } = "";

    /// <summary>Kaynağın (PS5, pencere, kart) kısa durum etiketi (şeritte).</summary>
    public string ConsoleShortText { get; init; } = "";
    public StatusTone ConsoleTone { get; init; }
    public bool ShowsOnTv { get; init; }
    public bool TvPaired { get; init; }

    /// <summary>Bağlı TV uygulaması sayısı.</summary>
    public int ConnectedTvs { get; init; }
    public StatusTone TvTone { get; init; }

    /// <summary>Sağdaki bağlantının değeri (<see cref="TranslationLinkRule"/>).</summary>
    public string TranslationValue { get; init; } = "";
}

/// <summary>Alt şeridin hesaplanmış hali. Şeritte yalnız kısa durum yazar; uzun açıklama ögenin ipucundadır.</summary>
/// <param name="SourceName">Görüntünün kaynağının adı (yarı kalın).</param>
/// <param name="SourceValue">Görüntünün kaynağının kısa değeri.</param>
/// <param name="SourceHelp">Görüntünün kaynağının uzun açıklaması (ipucu).</param>
/// <param name="SourceTone">Görüntünün kaynağı noktası.</param>
/// <param name="TvVisible">TV ögesi görünür mü (altyazı TV'ye gidiyorsa).</param>
/// <param name="TvValue">TV'nin kısa değeri (kurulu değilse "Bağlayın ›").</param>
/// <param name="TvHelp">TV'nin uzun açıklaması (ipucu).</param>
/// <param name="TvTone">TV noktası.</param>
/// <param name="TranslationValue">Sağdaki bağlantının değeri.</param>
public sealed record HomeFooterState(string SourceName, string SourceValue, string SourceHelp, StatusTone SourceTone,
    bool TvVisible, string TvValue, string TvHelp, StatusTone TvTone, string TranslationValue);

/// <summary>
/// Alt şerit kuralları (Mac'in alt şeridiyle aynı): solda görüntü kaynağı ve TV, ortada güncelleme, sağda çeviri bağlantısı.
/// TV ögesine tıklayınca her zaman kurulumun TV adımı açılır.
/// </summary>
public static class HomeFooter
{
    /// <summary>Alt şeridi hesaplar.</summary>
    public static HomeFooterState Compute(HomeFooterInput i, ITextSource text)
    {
        var name = i.UsesGameWindow ? text.Get("home.footer.gameWindow")
            : i.UsesCaptureCard ? text.Get("status.card.defaultName")
            : i.ConsoleTitle;
        var ready = i.OnStreamPath && !i.IsXbox && i.FrameSourceIsPs5 && !i.IsTranslating && i.HasConsole;
        var readyText = ready
            ? text.Format("home.footer.ps5Ready", string.IsNullOrEmpty(i.ConsoleName) ? "PS5" : i.ConsoleName)
            : null;
        var value = readyText ?? (i.ConsoleShortText is { Length: > 0 } shortText ? shortText : i.ConsoleStatusText);
        var help = readyText ?? i.ConsoleStatusText;

        string tvValue, tvHelp;
        StatusTone tvTone;
        if (!i.TvPaired)
        {
            tvValue = text.Get("home.short.tvSetUp") + " ›";
            tvHelp = text.Get("home.tv.connect");
            tvTone = StatusTone.Warning;
        }
        else if (i.ConnectedTvs > 0)
        {
            tvValue = text.Get("status.common.connected");
            tvHelp = tvValue;
            tvTone = i.TvTone;
        }
        else
        {
            tvValue = text.Get("home.short.tvWaiting");
            tvHelp = text.Get("status.tv.waitingForApp");
            tvTone = i.TvTone;
        }
        return new HomeFooterState(name, value, help, i.ConsoleTone, i.ShowsOnTv, tvValue, tvHelp, tvTone,
            i.TranslationValue);
    }

    /// <summary>Alt şerit girdilerini denetleyiciden okur.</summary>
    public static HomeFooterInput Read(NinoController c)
    {
        var s = c.Settings;
        return new HomeFooterInput
        {
            UsesGameWindow = c.UsesGameWindow,
            UsesCaptureCard = c.UsesCaptureCard,
            ConsoleTitle = c.ConsoleTitle,
            OnStreamPath = c.OnStreamPath,
            IsXbox = c.IsXbox,
            FrameSourceIsPs5 = s.FrameSource == Nino.Core.Settings.FrameSource.Ps5,
            IsTranslating = c.IsTranslating,
            HasConsole = c.HasConsole,
            ConsoleName = c.ConsoleName,
            ConsoleStatusText = c.ConsoleStatusText,
            ConsoleShortText = c.ConsoleShortStatusText,
            ConsoleTone = c.ConsoleTone,
            ShowsOnTv = c.ShowsOnTv,
            TvPaired = c.TvPaired,
            ConnectedTvs = c.ConnectedTvs,
            TvTone = c.TvTone,
            TranslationValue = c.TranslationLinkValue,
        };
    }
}

/// <summary>"Şu anki oyun" kartının soru hâli kuralları (ana-ekran §3.4 kart 2).</summary>
public static class GamePickerRule
{
    /// <summary>Gösterilen en çok öneri.</summary>
    public const int MaxShown = 5;

    /// <summary>Gösterilecek öneriler (ilk 5).</summary>
    public static IReadOnlyList<string> Shown(IReadOnlyList<string> suggestions) => suggestions.Take(MaxShown).ToArray();

    /// <summary>
    /// "Listede yok: … olarak kaydet" düğmesi: yazılan boş değilse ve hiçbir önerinin normalleştirilmiş adı yazılanınkiyle
    /// aynı değilse.
    /// </summary>
    public static bool OffersTyped(string? typed, IEnumerable<string> suggestions)
    {
        if (string.IsNullOrWhiteSpace(typed)) return false;
        return !suggestions.Any(s => GameIds.Same(s, typed));
    }
}

/// <summary>Cam anahtardaki ay-yıldız (ana-ekran §6.3), b kenarlı kare içinde.</summary>
public static class CrescentStar
{
    /// <summary>Ayın dolu dairesi: merkez (0,42b; b/2), yarıçap 0,42b.</summary>
    public static (ScenePoint Center, double Radius) Moon(double b) => (new(0.42 * b, b / 2), 0.42 * b);

    /// <summary>Ayın oyuğu: merkez (0,42b + 0,32r; b/2), yarıçap 0,8r.</summary>
    public static (ScenePoint Center, double Radius) Cut(double b)
    {
        var r = 0.42 * b;
        return (new(0.42 * b + 0.32 * r, b / 2), 0.8 * r);
    }

    /// <summary>Yıldızın on noktası: merkez (0,8b; b/2), dış 0,17b, iç dış × 0,382; i. açı π + i·π/5.</summary>
    public static IReadOnlyList<ScenePoint> Star(double b)
    {
        var cx = 0.8 * b;
        var cy = b / 2;
        var outer = 0.17 * b;
        var inner = outer * 0.382;
        var points = new ScenePoint[10];
        for (var i = 0; i < 10; i++)
        {
            var a = Math.PI + i * Math.PI / 5;
            var r = i % 2 == 0 ? outer : inner;
            points[i] = new ScenePoint(cx + r * Math.Cos(a), cy + r * Math.Sin(a));
        }
        return points;
    }
}

/// <summary>Yazı tanıma dil paketini kurmak için dil kodunun güvenli olup olmadığı (yönetici PowerShell'e gider).</summary>
public static partial class OcrLanguageCode
{
    [GeneratedRegex("^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$")]
    private static partial Regex Pattern();

    /// <summary>Yalnız harf, rakam ve tire içeren kısa bir dil kodu mu ("en", "en-US", "zh-Hans").</summary>
    public static bool IsSafe(string? code) => !string.IsNullOrEmpty(code) && code.Length <= 20 && Pattern().IsMatch(code);

    /// <summary>
    /// Kurulacak Windows yeteneğinin ad kalıbı: <c>Language.OCR~~~&lt;dil&gt;-*</c> (dil kodun tireden önceki kısmı,
    /// küçük harf); kod güvenli değilse null.
    /// </summary>
    public static string? CapabilityPattern(string? code) =>
        IsSafe(code) ? $"Language.OCR~~~{code!.Split('-')[0].ToLowerInvariant()}-*" : null;
}
