// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;
using Nino.Core.Library;
using Nino.Core.Reading;

namespace Nino.Core.Phone;

/// <summary>
/// Telefon ve harita okuyucularını bir arada tutar: her karede ikisine kare verir, örtülerini tek listede (önce
/// telefon, sonra harita) TV'ye <c>screen</c> olarak gönderir, liste boşalınca kaldırır ve uzun açık kalan örtüyü
/// 60 sn'de bir yeniden gönderir. Okuyucuların kurulmasını (arayüz iş parçacığında, bir kez) denetleyici yapar.
/// </summary>
public sealed class PhoneOverlay
{
    /// <summary>TV'ye gönderilen örtünün süresi.</summary>
    public const int DurationMs = 120_000;

    /// <summary>Örtü gösterilirken yeniden gönderme aralığı.</summary>
    public const long RefreshMs = 60_000;

    readonly ISubtitleOutput _output;
    readonly IMsClock _clock;
    readonly object _lock = new();
    PhoneReader? _phone;
    MapReader? _map;
    bool _showing;
    long _sentAt;
    IReadOnlyList<ScreenItem> _sent = [];

    /// <summary>Örtü yöneticisi.</summary>
    public PhoneOverlay(ISubtitleOutput output, IMsClock? clock = null)
    {
        _output = output;
        _clock = clock ?? SystemMsClock.Instance;
    }

    /// <summary>Telefon okuyucusu (kurulmadıysa null).</summary>
    public PhoneReader? Phone
    {
        get { lock (_lock) return _phone; }
    }

    /// <summary>Harita okuyucusu (kurulmadıysa null).</summary>
    public MapReader? Map
    {
        get { lock (_lock) return _map; }
    }

    /// <summary>Okuyucular kurulu mu.</summary>
    public bool Installed
    {
        get { lock (_lock) return _phone is not null && _map is not null; }
    }

    /// <summary>Örtü TV'de gösteriliyor mu.</summary>
    public bool Showing
    {
        get { lock (_lock) return _showing; }
    }

    /// <summary>
    /// İki okuyucuyu kurar (her biri kendi tanıyıcısıyla). <paramref name="services"/> ortak bağlantılardır; örtü
    /// bildirimi ve telefonun haritadan sonraki duraklaması burada bağlanır.
    /// </summary>
    public void Install(OverlayServices services, ITextReader phoneOcr, ITextReader mapOcr,
        Func<BgraFrame, PhoneShape?>? finder = null)
    {
        Remove();
        var mapReader = new MapReader(services with { Ocr = mapOcr, Changed = Publish, Paused = null });
        var phone = new PhoneReader(services with
        {
            Ocr = phoneOcr,
            Changed = Publish,
            Paused = () => mapReader.RecentlyOpen(MapReader.PhonePauseMs),
        }, finder);
        lock (_lock)
        {
            _phone = phone;
            _map = mapReader;
        }
    }

    /// <summary>Okuyucuları sıfırlayıp bırakır ve TV'deki örtüleri kaldırır.</summary>
    public void Remove()
    {
        PhoneReader? phone;
        MapReader? map;
        lock (_lock)
        {
            phone = _phone;
            map = _map;
            _phone = null;
            _map = null;
        }
        phone?.Reset();
        map?.Reset();
        Publish();
    }

    /// <summary>İki okuyucuyu sıfırlar (PS5'le bağlantı kesildi); okuyucular kalır.</summary>
    public void ResetReaders()
    {
        Phone?.Reset();
        Map?.Reset();
        Publish();
    }

    /// <summary>Bilinen çeviri ve sözlük ayarını yeniden verir.</summary>
    public void Update(Func<string, string?>? ready, bool glossary)
    {
        if (Phone is { } p)
        {
            p.Ready = ready;
            p.Glossary = glossary;
        }
        if (Map is { } m) m.Ready = ready;
    }

    /// <summary>Her karede (telefon oyunu açıkken): haritaya, sonra telefona kare verir; gerekiyorsa örtüyü yeniler.</summary>
    public void OnFrame(BgraFrame frame)
    {
        Map?.OfferFrame(frame);
        Phone?.OfferFrame(frame);
        IReadOnlyList<ScreenItem>? resend = null;
        lock (_lock)
        {
            if (_showing && _clock.NowMs - _sentAt >= RefreshMs)
            {
                resend = _sent;
                _sentAt = _clock.NowMs;
            }
            if (resend is not null) _output.ShowScreen(resend, DurationMs, true);
        }
    }

    /// <summary>Örtüyü gönderir (bir okuyucu "örtü değişti" dediğinde).</summary>
    public void Publish()
    {
        var items = new List<ScreenItem>();
        PhoneReader? phone;
        MapReader? map;
        lock (_lock)
        {
            phone = _phone;
            map = _map;
        }
        if (phone is not null) items.AddRange(phone.Items);
        if (map is not null) items.AddRange(map.Items);
        lock (_lock)
        {
            if (items.Count > 0)
            {
                _output.ShowScreen(items, DurationMs, true);
                _showing = true;
                _sentAt = _clock.NowMs;
                _sent = items;
            }
            else if (_showing)
            {
                _output.ClearScreen();
                _showing = false;
                _sent = [];
            }
        }
    }

    /// <summary>Okuma hattının kancaları: telefon araması, harita açık, son mesajlar, telefon yazısı benimseme.</summary>
    public PhoneLineHooks CreateLineHooks(Func<bool> phoneGame, Func<BgraFrame, PhoneShape?>? finder = null) =>
        new(_clock, phoneGame, () => Map?.IsOpen ?? false, () => Phone?.RecentMessages ?? [],
            (frame, boxes) => Phone?.AdoptPhoneText(frame, boxes), finder);
}

/// <summary>Telefon oyunu kararı ve ekrandan GTA 6 tanıma.</summary>
public static class PhoneGame
{
    /// <summary>
    /// Havuza sorulacak oyun: bilinen oyun havuz öncelikliyse o; değilse altyazı paketinin oyunu havuz öncelikliyse o;
    /// değilse paketin oyunu, o da yoksa bilinen oyun.
    /// </summary>
    public static string? PoolGame(string? known, string? pack, Func<string?, bool> isPoolFirst)
    {
        if (known is not null && isPoolFirst(known)) return known;
        if (pack is not null && isPoolFirst(pack)) return pack;
        return pack ?? known;
    }

    /// <summary>
    /// Telefon oyunu mu: çeviri duraklatılmamış ve kaynak dil İngilizce; ve (havuza sorulacak oyun havuz öncelikli ya
    /// da (oyun bilinmiyor ya da yalnız paketten tahmin edildi ve havuz önceliği çeviri diline izin veriyor)).
    /// </summary>
    /// <param name="paused">Çeviri duraklatılmış mı.</param>
    /// <param name="sourceLanguage">Kaynak dil.</param>
    /// <param name="poolGameIsPoolFirst">Havuza sorulacak oyun havuz öncelikli mi.</param>
    /// <param name="source">Bilinen oyunun kaynağı (bilinmiyorsa null).</param>
    /// <param name="poolFirstAllowsTarget">Havuz öncelikli ayarı çeviri diline izin veriyor mu.</param>
    public static bool IsPhoneGame(bool paused, string? sourceLanguage, bool poolGameIsPoolFirst, GameSource? source,
        bool poolFirstAllowsTarget)
    {
        if (paused || !string.Equals(sourceLanguage, "en", StringComparison.OrdinalIgnoreCase)) return false;
        if (poolGameIsPoolFirst) return true;
        return (source is null or GameSource.Pack) && poolFirstAllowsTarget;
    }

    /// <summary>Havuz öncelikli ayarı bu çeviri diline izin veriyor mu (<c>*</c> ya da dil listede).</summary>
    public static bool PoolFirstAllows(PoolFirstConfig config, string? targetLanguage)
    {
        var lang = TranslationPool.LangCode(targetLanguage);
        return config.Langs.Contains("*") || config.Langs.Any(l => TranslationPool.LangCode(l) == lang);
    }

    /// <summary>
    /// Ekranda GTA 6 görüldü: uygulama çalışıyorsa, bilinen oyun zaten GTA 6 değilse ve oyun PS5'ten ya da
    /// kullanıcıdan bilinmiyorsa oyun "ekranda görüldü" olarak kaydedilir, soru kapanır. Döner: kaydedildi mi
    /// (denetleyici oyunu yayınlar ve çeviri eşitlemesini başlatır).
    /// </summary>
    public static bool NoteGta6(GameSense sense, bool running, Action<string>? log = null)
    {
        if (!running) return false;
        if (sense.Current?.Name is { } name && GameIds.Same(name, Gta6Markers.Name)) return false;
        if (sense.Source is GameSource.Ps5 or GameSource.User) return false;
        log?.Invoke($"ekrandaki yazılara bakılarak oyun {Gta6Markers.Name} sayıldı");
        sense.SetScreen(Gta6Markers.Name);
        sense.MarkAsked();
        return true;
    }
}
