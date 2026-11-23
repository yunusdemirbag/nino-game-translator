// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Design;
using Nino.Core.Library;
using Nino.Core.Settings;
using Nino.Core.Translation;
using Nino.Core.Tv;
using Nino.Translation.Online;

namespace Nino.Shell.Panels;

// Ayarlar penceresinin Mac'le aynı yapısı (Mac Ayarlar: liste görünümü → bölüm sayfası). Windows ve Linux paneli aynı
// listeyi, sırayı, metin anahtarlarını ve kuralları buradan okur; çizim platformundur.

/// <summary>Ayarlar'ın bölümleri. Sıra listedeki sıra değildir; liste <see cref="SettingsPages.Groups"/>'tan kurulur.</summary>
public enum SettingsPage
{
    Connection,
    Passcode,
    Appearance,
    Translation,
    Shortcuts,
    Obs,
    Health,
    Updates,
    AskNino,
    Report,
    About,
    Reset,
    Interface,
    Language,
    Packs,
    Area,

    /// <summary>Ana ekran: oyun odası tabelası (anahtar + oda adı).</summary>
    Home,
}

/// <summary>Listedeki satıra basınca ne olur.</summary>
public enum SettingsPageOpens
{
    /// <summary>Bölüm sayfası Ayarlar'ın içinde açılır (sağdan kayarak).</summary>
    Page,

    /// <summary>Başka bir pencere açılır (sağlık ve sorun bildirme pencereleri); Ayarlar açık kalır.</summary>
    Window,

    /// <summary>Ayarlar kapanır, <see cref="SettingsPages.AskNinoDelayMs"/> sonra Nino'ya Sor açılır.</summary>
    CloseThenAskNino,
}

/// <summary>Bölüm listesi, gruplar, simge renkleri ve sayfa genişlikleri (Mac'teki değerler).</summary>
public static class SettingsPages
{
    /// <summary>Nino'ya Sor'un Ayarlar kapandıktan sonra açılma gecikmesi.</summary>
    public const int AskNinoDelayMs = 350;

    /// <summary>Bölüm sayfasının içerik genişliği (Görünüş bölümü dışında).</summary>
    public const double ContentWidth = 640;

    /// <summary>Hakkında bölümünün içerik genişliği (Mac'te 560).</summary>
    public const double AboutContentWidth = 560;

    /// <summary>Görünüş sayfasının içerik genişliği (önizleme + kart yan yana).</summary>
    public const double WideContentWidth = 900;

    /// <summary>
    /// Listenin grupları, gizliler dahil. Mac'le aynı sıra; Windows'a özgü Kısayollar ikinci grupta Çeviri'nin ardından
    /// (Mac'te karşılığı yok).
    /// </summary>
    public static IReadOnlyList<IReadOnlyList<SettingsPage>> Groups { get; } =
    [
        [SettingsPage.Connection, SettingsPage.Passcode],
        [SettingsPage.Appearance, SettingsPage.Home, SettingsPage.Translation, SettingsPage.Shortcuts, SettingsPage.Interface,
            SettingsPage.Language, SettingsPage.Packs, SettingsPage.Area],
        [SettingsPage.Obs],
        [SettingsPage.Health, SettingsPage.Updates, SettingsPage.AskNino, SettingsPage.Report, SettingsPage.About],
        [SettingsPage.Reset],
    ];

    /// <summary>Listede görünmeyen ama sayfası hazır bölümler (Mac'te de gizli): Arayüz, Dil, Paketler, Altyazı bölgesi.</summary>
    public static bool IsTuckedAway(SettingsPage page) =>
        page is SettingsPage.Interface or SettingsPage.Language or SettingsPage.Packs or SettingsPage.Area;

    /// <summary>Görünen gruplar (gizliler süzülür, boş kalan grup atılır).</summary>
    public static IReadOnlyList<IReadOnlyList<SettingsPage>> VisibleGroups { get; } =
        Groups.Select(g => (IReadOnlyList<SettingsPage>)g.Where(p => !IsTuckedAway(p)).ToList())
            .Where(g => g.Count > 0)
            .ToList();

    /// <summary>Bölümün kimliği (metin anahtarı ve ekran dökümü dosya adı için).</summary>
    public static string Id(SettingsPage page) => page switch
    {
        SettingsPage.Connection => "connection",
        SettingsPage.Passcode => "passcode",
        SettingsPage.Appearance => "appearance",
        SettingsPage.Translation => "translation",
        SettingsPage.Shortcuts => "shortcuts",
        SettingsPage.Obs => "obs",
        SettingsPage.Health => "health",
        SettingsPage.Updates => "updates",
        SettingsPage.AskNino => "askNino",
        SettingsPage.Report => "report",
        SettingsPage.About => "about",
        SettingsPage.Reset => "reset",
        SettingsPage.Interface => "interface",
        SettingsPage.Language => "language",
        SettingsPage.Packs => "packs",
        SettingsPage.Home => "home",
        _ => "area",
    };

    /// <summary>Bölüm adının anahtarı: <c>settings.section.&lt;kimlik&gt;</c>.</summary>
    public static string TitleKey(SettingsPage page) => "settings.section." + Id(page);

    /// <summary>Satıra basınca ne olur.</summary>
    public static SettingsPageOpens Opens(SettingsPage page) => page switch
    {
        SettingsPage.Health or SettingsPage.Report => SettingsPageOpens.Window,
        SettingsPage.AskNino => SettingsPageOpens.CloseThenAskNino,
        _ => SettingsPageOpens.Page,
    };

    /// <summary>Sayfanın içerik genişliği.</summary>
    public static double Width(SettingsPage page) => page switch
    {
        SettingsPage.Appearance => WideContentWidth,
        SettingsPage.About => AboutContentWidth,
        _ => ContentWidth,
    };

    /// <summary>Sayfa ortak başlığı çizmez mi (Paketler başlığa hap ekler; Hakkında kendi logolu başını çizer).</summary>
    public static bool DrawsOwnHeader(SettingsPage page) => page is SettingsPage.Packs or SettingsPage.About;

    /// <summary>Bölüm renginin RGB değeri (0–255). Mac'teki 0–1 değerlerinin 255 katı, yuvarlanmış.</summary>
    public static (byte R, byte G, byte B) Color(SettingsPage page) => page switch
    {
        SettingsPage.Connection => Rgb(0.10, 0.45, 0.95),
        SettingsPage.Passcode => Rgb(0.30, 0.35, 0.45),
        SettingsPage.Appearance => Rgb(0.00, 0.44, 0.82),
        SettingsPage.Translation => Rgb(0.00, 0.62, 0.75),
        SettingsPage.Shortcuts => Rgb(0.55, 0.36, 0.90),
        SettingsPage.Obs => Rgb(0.92, 0.26, 0.30),
        SettingsPage.Health => Rgb(0.95, 0.30, 0.45),
        SettingsPage.Updates => Rgb(0.12, 0.62, 0.36),
        SettingsPage.AskNino => Rgb(0.00, 0.44, 0.82),
        SettingsPage.Report => Rgb(0.96, 0.62, 0.12),
        SettingsPage.About => Rgb(0.45, 0.50, 0.60),
        SettingsPage.Reset => Rgb(0.90, 0.30, 0.28),
        SettingsPage.Interface => Rgb(0.36, 0.30, 0.95),
        SettingsPage.Language => Rgb(0.20, 0.70, 0.40),
        SettingsPage.Packs => Rgb(0.98, 0.55, 0.10),
        SettingsPage.Home => Rgb(0.78, 0.36, 0.95),
        _ => Rgb(0.35, 0.40, 0.95),
    };

    static (byte, byte, byte) Rgb(double r, double g, double b) =>
        ((byte)Math.Round(r * 255), (byte)Math.Round(g * 255), (byte)Math.Round(b * 255));

    /// <summary>Ekran dökümü kimliğinden bölüm (bilinmiyorsa null).</summary>
    public static SettingsPage? FromId(string? id) =>
        Enum.GetValues<SettingsPage>().Cast<SettingsPage?>().FirstOrDefault(p => Id(p!.Value) == id);
}

/// <summary>Çeviri › "Nino Game Translator Kütüphanesi Aktif" kartının oyun listesi.</summary>
public static class SettingsLibrary
{
    /// <summary>Her zaman ilk sırada duran (havuz öncelikli) oyun.</summary>
    public const string AlwaysFirst = "GTA 6";

    /// <summary>Kartta en çok bu kadar ad görünür; kalanı "+n oyun daha".</summary>
    public const int ShownLimit = 8;

    /// <summary>
    /// GTA 6 her zaman, ardından yüklü paketlerin oyunları; aynı oyun bir kez (asıl kimliğe ya da ad anahtarına göre).
    /// Genel paket oyun değildir, listede yok. Tablodaki oyunlar okunur adıyla ("GTA 5").
    /// </summary>
    public static IReadOnlyList<string> GameNames(IEnumerable<PackInfo> packs)
    {
        var names = new List<string> { AlwaysFirst };
        var ids = new HashSet<string>(StringComparer.Ordinal) { GameIds.FromName(AlwaysFirst)! };
        foreach (var pack in packs)
        {
            if (pack.Id == PackLibrary.GeneralPackId || string.IsNullOrWhiteSpace(pack.Title)) continue;
            var id = GameIds.ForPack(pack.Id, pack.Title);
            if (id is not null && !ids.Add(id)) continue;
            var name = id is not null && GameIds.Names.TryGetValue(id, out var known) ? known : pack.Title.Trim();
            if (names.Any(n => GameIds.Same(n, name))) continue;
            names.Add(name);
        }
        return names;
    }

    /// <summary>Görünen adlar ve gizlenen sayısı.</summary>
    public static (IReadOnlyList<string> Shown, int More) Shown(IReadOnlyList<string> names, int limit = ShownLimit)
    {
        var shown = names.Take(limit).ToList();
        return (shown, names.Count - shown.Count);
    }
}

/// <summary>Çeviri › API anahtarları satırının durumu.</summary>
public enum ApiProviderState
{
    /// <summary>Çeviri bununla yapılıyor.</summary>
    InUse,

    /// <summary>Anahtarı var, kullanılmıyor.</summary>
    Saved,

    /// <summary>Anahtar yok.</summary>
    None,

    /// <summary>Yerel model kullanılmıyor (anahtarı yoktur).</summary>
    Off,
}

/// <summary>Satırın altındaki düğme.</summary>
public enum ApiProviderAction
{
    /// <summary>Düğme yok.</summary>
    None,

    /// <summary>"Bununla Çevir": sağlayıcıyı devreye alır.</summary>
    Use,

    /// <summary>"Kullanmayı Bırak" (yalnız yerel model): ücretsiz çeviriye döner.</summary>
    Stop,
}

/// <summary>
/// Çeviri › API anahtarları akordiyonu (Mac'le aynı): her sağlayıcı tek satır, aynı anda bir tanesi açık; anahtar yokken
/// çeviri kütüphane, havuz ve cihaz içi modelle sürer (seçim gerekmez, "Ücretsiz" ayrı bir satır değildir).
/// </summary>
public static class ApiProviders
{
    /// <summary>Satırların sırası.</summary>
    public static IReadOnlyList<OnlineEngine> Order { get; } =
        [OnlineEngine.Gemini, OnlineEngine.DeepL, OnlineEngine.OpenAi, OnlineEngine.Claude, OnlineEngine.Local];

    /// <summary>Marka adı (çevrilmez). Yerel modelin satır adı metin kataloğundan gelir; bu ad hata metinlerindedir.</summary>
    public static string Brand(OnlineEngine engine) => engine switch
    {
        OnlineEngine.DeepL => "DeepL",
        OnlineEngine.Gemini => "Gemini",
        OnlineEngine.OpenAi => "OpenAI",
        OnlineEngine.Claude => "Claude",
        _ => "Ollama",
    };

    /// <summary>
    /// Satırın durumu. Seçili motor yalnız anahtarı varsa (yerel modelde her zaman) "kullanılıyor" sayılır; anahtarsız
    /// seçili bulut motoru (ör. "ücretsiz anahtar al"dan sonra) anahtar gelene dek ücretsiz çeviriyle sürer.
    /// </summary>
    public static ApiProviderState State(OnlineEngine engine, OnlineEngine selected, bool hasKey)
    {
        if (engine == selected && (hasKey || engine == OnlineEngine.Local)) return ApiProviderState.InUse;
        if (engine == OnlineEngine.Local) return ApiProviderState.Off;
        return hasKey ? ApiProviderState.Saved : ApiProviderState.None;
    }

    /// <summary>Durum noktası: kullanılıyor ya da kayıtlıysa yeşil, değilse boşta.</summary>
    public static StatusTone Tone(ApiProviderState state) =>
        state is ApiProviderState.InUse or ApiProviderState.Saved ? StatusTone.Good : StatusTone.Idle;

    /// <summary>Durum yazısının anahtarı.</summary>
    public static string StatusKey(ApiProviderState state) => state switch
    {
        ApiProviderState.InUse => "settings.api.inUse",
        ApiProviderState.Saved => "settings.api.saved",
        ApiProviderState.Off => "settings.api.off",
        _ => "settings.api.none",
    };

    /// <summary>Açık satırın altındaki düğme.</summary>
    public static ApiProviderAction Action(OnlineEngine engine, ApiProviderState state) => state switch
    {
        ApiProviderState.Saved or ApiProviderState.Off => ApiProviderAction.Use,
        ApiProviderState.InUse when engine == OnlineEngine.Local => ApiProviderAction.Stop,
        _ => ApiProviderAction.None,
    };

    /// <summary>"Bununla Çevir" basılabilir mi (yerel modelde adres geçerli olmalı).</summary>
    public static bool CanUse(OnlineEngine engine, AppSettings settings) =>
        engine != OnlineEngine.Local || LocalServer.NormalizeAddress(settings.LocalAiBaseUrl) is not null;

    /// <summary>Sağlayıcıyı seçer (null ya da Ücretsiz: çevrimiçi çeviri kapanır, motor kaydı yerinde kalır).</summary>
    public static void Choose(AppSettings settings, OnlineEngine? engine)
    {
        if (engine is null or OnlineEngine.Free)
        {
            settings.OnlineTranslation = false;
            return;
        }
        settings.OnlineTranslation = true;
        settings.OnlineEngine = engine.Value;
    }

    /// <summary>Akordiyonda satıra basılınca açık kalacak satır (aynı satır kapanır, başkası açılır).</summary>
    public static OnlineEngine? Toggle(OnlineEngine? open, OnlineEngine pressed) => open == pressed ? null : pressed;

    /// <summary>
    /// Deneme sonucunun metin anahtarı ve biçim değerleri (Mac'in motor hata metinleri). Yerel sunucuda adres ve model
    /// adı, LM Studio / Ollama / öbür sunucu ayrımıyla.
    /// </summary>
    public static (string Key, object[] Args, bool Error) Result(OnlineEngine engine, KeyCheckStatus status, AppSettings settings,
        string? sample = null)
    {
        if (engine == OnlineEngine.DeepL)
        {
            return status switch
            {
                KeyCheckStatus.Valid => ("settings.engine.works", [], false),
                KeyCheckStatus.QuotaExhausted => ("settings.deepl.limit", [], true),
                KeyCheckStatus.InvalidKey => ("settings.deepl.badKey", [], true),
                _ => ("settings.deepl.unreachable", [], true),
            };
        }
        if (engine == OnlineEngine.Local)
        {
            var server = LocalServer.Create(settings.LocalAiBaseUrl, settings.LocalAiModel);
            var model = (settings.LocalAiModel ?? "").Trim();
            var address = server?.ShortAddress ?? (settings.LocalAiBaseUrl ?? "").Trim();
            var kind = server?.Kind ?? LocalServerKind.Other;
            return status switch
            {
                KeyCheckStatus.Valid => ("settings.engine.works", [], false),
                KeyCheckStatus.InvalidKey => ("settings.engine.local.badKey", [], true),
                KeyCheckStatus.QuotaExhausted => ("settings.engine.local.busy", [], true),
                KeyCheckStatus.ModelRejected => kind == LocalServerKind.LmStudio
                    ? ("settings.engine.local.missingLMStudio", [model], true)
                    : ("settings.engine.local.missing", [model], true),
                _ => kind switch
                {
                    LocalServerKind.Ollama => ("settings.engine.local.ollamaDown", [address, model], true),
                    LocalServerKind.LmStudio => ("settings.engine.local.lmStudioDown", [address], true),
                    _ => ("settings.engine.local.otherDown", [address], true),
                },
            };
        }
        var brand = Brand(engine);
        return status switch
        {
            KeyCheckStatus.Valid when sample is { Length: > 0 } => ("settings.key.works", [sample], false),
            KeyCheckStatus.Valid => ("settings.engine.works", [], false),
            KeyCheckStatus.InvalidKey => ("settings.engine.badKey", [brand], true),
            KeyCheckStatus.QuotaExhausted => ("settings.engine.quota", [brand], true),
            KeyCheckStatus.ModelRejected => ("settings.engine.model", [brand], true),
            _ => ("settings.engine.unreachable", [brand], true),
        };
    }
}

/// <summary>Bağlantı › Televizyon bölümü.</summary>
public static class TvSettingsRules
{
    /// <summary>"Görüntü gelmiyorsa: Katman kipi" anahtarı yalnız Android TV'de.</summary>
    public static bool ShowsOverlaySwitch(TvRecord? tv) => tv?.Brand == TvBrand.AndroidTv;

    /// <summary>Katman kipi açık mı.</summary>
    public static bool OverlayOn(SubtitleStyle style) => style.DisplayMode == SubtitleDisplayMode.Overlay;

    /// <summary>Katman kipini açar/kapatır (Android TV <c>displayMode</c>: overlay / inApp).</summary>
    public static void SetOverlay(AppSettings settings, bool on) =>
        settings.Style.DisplayMode = on ? SubtitleDisplayMode.Overlay : SubtitleDisplayMode.InApp;

    /// <summary>Eşli TV satırındaki durum yazısı.</summary>
    public static string StateKey(int connectedTvs) => connectedTvs > 0 ? "settings.tv.connected" : "settings.tv.waiting";

    /// <summary>Eşli TV satırındaki nokta.</summary>
    public static StatusTone Tone(int connectedTvs) => connectedTvs > 0 ? StatusTone.Good : StatusTone.Warning;
}

/// <summary>Görünüş bölümü kartı (Mac'teki üç seçenek: yazı boyu, arka plan, konuşanın adı).</summary>
public static class SubtitleLookRules
{
    /// <summary>Yazı boyu kaydırıcısının aralığı (1920 piksellik ekranda yazı yüksekliği).</summary>
    public const int SizeMin = 20, SizeMax = 80;

    /// <summary>Kartın başlığı: altyazı yeri yalnız TV ise "TV'de".</summary>
    public static string TitleKey(SubtitleOutput output) =>
        output == SubtitleOutput.Tv ? "settings.style.onTV" : "settings.style.title";

    /// <summary>
    /// Arka plan aralığı: İngilizce satırın yerine binerken en az %60 (yoksa İngilizce çevirinin arkasından görünür).
    /// </summary>
    public static (int Min, int Max) BackgroundRange(SubtitlePlacement placement) =>
        placement == SubtitlePlacement.Cover ? (60, 100) : (0, 100);

    /// <summary>Arka plan kaydırıcısının sol ucundaki yazı.</summary>
    public static string BackgroundMinKey(SubtitlePlacement placement) =>
        placement == SubtitlePlacement.Cover ? "settings.style.background.light" : "settings.style.background.none";

    /// <summary>Kaydırıcı değeri yazılmadan önce aralığa çekilir.</summary>
    public static int ClampSize(double value) => Math.Clamp((int)Math.Round(value), SizeMin, SizeMax);

    /// <summary>Arka plan değeri yerleşime göre aralığa çekilir.</summary>
    public static int ClampBackground(double value, SubtitlePlacement placement)
    {
        var (min, max) = BackgroundRange(placement);
        return Math.Clamp((int)Math.Round(value), min, max);
    }

    /// <summary>
    /// Önizlemedeki yazı boyu: (otomatik boyda 38, değilse seçili boy) / 1920 × önizleme genişliği × 1,6; en az 10.
    /// </summary>
    public static double PreviewFontSize(SubtitleStyle style, double width) =>
        Math.Max(10, (style.EffectiveAutoSize ? 38 : style.FontSize) / 1920.0 * width * 1.6);

    /// <summary>Önizlemenin demo satırları (çevrilmez; Mac'le aynı).</summary>
    public static IReadOnlyList<(string Source, string Translated)> DemoLines { get; } =
    [
        ("Someone has to keep an eye on this town.", "Bu kasabaya birinin göz kulak olması lazım."),
        ("Here they come. Keep your head down.", "Geliyorlar. Başını eğ, görünme."),
        ("Is anyone there?", "Orada biri mi var?"),
        ("The fog swallows every sound.", "Sis bütün sesleri yutuyor."),
        ("Up to the roof. Move!", "Çatıya çıkın. Çabuk!"),
        ("We're not done here.", "Burada işimiz bitmedi."),
    ];
}
