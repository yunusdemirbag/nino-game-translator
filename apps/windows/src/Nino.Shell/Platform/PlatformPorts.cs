// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;
using Nino.Core.Logging;
using Nino.Core.Reading;
using Nino.Core.Settings;

namespace Nino.Shell.Platform;

// Denetleyicinin platformdan istediği küçük işler. Windows'ta Nino.App, Linux'ta Linux sunucusu, testlerde sahteler
// doldurur. Varsayılan gövdesi olan üyeler doldurulmayabilir; o zaman özellik o derlemede kapalı sayılır.
// İŞ PARÇACIĞI: bu arayüzlerin olayları ve geri çağrıları herhangi bir iş parçacığından gelebilir; denetleyici
// hepsini kendi "arayüze aktar" işleviyle arayüz iş parçacığına geçirir (bkz. NinoController dosya başı).

/// <summary>Uyku bekçisi: çeviri sürerken bilgisayar boşta uykuya geçmesin.</summary>
public interface ISleepGuard
{
    /// <summary>Uykuyu engeller; çeviri sürerken bayrak değiştirmek için yeniden çağrılabilir.</summary>
    /// <param name="keepDisplayOn">Ekran da açık kalsın mı.</param>
    void Begin(bool keepDisplayOn);

    /// <summary>Engeli kaldırır.</summary>
    void End();
}

/// <summary>Hiçbir şey yapmayan uyku bekçisi (Linux).</summary>
public sealed class NoSleepGuard : ISleepGuard
{
    /// <inheritdoc />
    public void Begin(bool keepDisplayOn) { }

    /// <inheritdoc />
    public void End() { }
}

/// <summary>
/// Saat ve zamanlayıcılar. Tikler herhangi bir iş parçacığından gelebilir (denetleyici arayüze aktarır). Testlerde
/// elle ilerletilen sahte kullanılır.
/// </summary>
public interface IShellTimers
{
    /// <summary>Şimdi.</summary>
    DateTimeOffset Now { get; }

    /// <summary>Her <paramref name="period"/>'da bir çağırır (ilk çağrı bir aralık sonra). Bırakınca durur.</summary>
    IDisposable Every(TimeSpan period, Action tick);

    /// <summary><paramref name="due"/> sonra bir kez çağırır. Bırakınca iptal.</summary>
    IDisposable After(TimeSpan due, Action tick);
}

/// <summary>Gerçek saat ve <see cref="System.Threading.Timer"/> zamanlayıcıları.</summary>
public sealed class SystemShellTimers(TimeProvider? clock = null) : IShellTimers
{
    readonly TimeProvider _clock = clock ?? TimeProvider.System;

    /// <inheritdoc />
    public DateTimeOffset Now => _clock.GetUtcNow();

    /// <inheritdoc />
    public IDisposable Every(TimeSpan period, Action tick) => _clock.CreateTimer(_ => Safe(tick), null, period, period);

    /// <inheritdoc />
    public IDisposable After(TimeSpan due, Action tick) =>
        _clock.CreateTimer(_ => Safe(tick), null, due < TimeSpan.Zero ? TimeSpan.Zero : due, Timeout.InfiniteTimeSpan);

    static void Safe(Action a)
    {
        try { a(); } catch (Exception) { }
    }
}

/// <summary>Denetleyicinin yazdığı günlükler.</summary>
public interface IShellLogs
{
    /// <summary><c>remoteplay.log</c>'un tam yolu (hata iletisindeki "şu dosyayı gönderin" ipucu); yoksa null.</summary>
    string? RemotePlayLogPath { get; }

    /// <summary><c>remoteplay.log</c>'a <c>[nino] </c> önekli satır.</summary>
    void RemotePlay(string line);

    /// <summary><c>altyazi.log</c>'a satır.</summary>
    void Subtitle(string line);

    /// <summary><c>hata.log</c>'a satır.</summary>
    void Error(string message, Exception? error = null);
}

/// <summary>Hiçbir yere yazmayan günlük (testler satırları ayrıca toplayabilir).</summary>
public class SilentShellLogs : IShellLogs
{
    /// <inheritdoc />
    public virtual string? RemotePlayLogPath => null;

    /// <inheritdoc />
    public virtual void RemotePlay(string line) { }

    /// <inheritdoc />
    public virtual void Subtitle(string line) { }

    /// <inheritdoc />
    public virtual void Error(string message, Exception? error = null) { }
}

/// <summary>
/// Günlük dosyalarına yazan günlük. Remote Play günlüğü <see cref="Nino.RemotePlay.RemotePlayLog"/>'dur: aynı nesne
/// <c>CoreShellServicesOptions.RemotePlayLog</c>'a da verilmeli (dosyanın tek yazanı).
/// </summary>
public sealed class FileShellLogs(Nino.RemotePlay.RemotePlayLog? remotePlay, SubtitleLog? subtitle, ErrorLog? error) : IShellLogs
{
    /// <inheritdoc />
    public string? RemotePlayLogPath => remotePlay?.FilePath;

    /// <inheritdoc />
    public void RemotePlay(string line) => remotePlay?.Nino(line);

    /// <inheritdoc />
    public void Subtitle(string line) => subtitle?.Write(line);

    /// <inheritdoc />
    public void Error(string message, Exception? e = null) => error?.Write(message, e);
}

/// <summary>Yazı okuyucu fabrikası (Windows OCR, Linux Tesseract).</summary>
public interface ITextReaderFactory
{
    /// <summary>Oyun dili için okuyucu; hiç OCR dili kurulu değilse null.</summary>
    ITextReader? Create(string language);

    /// <summary>Tek geçişte okuyan okuyucu (telefon ekranı, harita kartı).</summary>
    ITextReader? CreateSinglePass(string language) => Create(language);

    /// <summary>Oyun dilinin kendi OCR paketi kurulu mu (değilse sistem diliyle okunur, uyarı gösterilir).</summary>
    bool HasLanguagePack(string language) => true;

    /// <summary>Oyunu ekrandan tanımak için küçük JPEG (en çok genişlik, kalite); yapılamıyorsa null.</summary>
    byte[]? SmallJpeg(BgraFrame frame, int maxWidth, int quality) => null;

    /// <summary>
    /// Okuma kalitesi ölçüleri (Windows'ta yalnız İngilizce oyunlarda, yazım denetleyicisi çalışıyorsa); yoksa null.
    /// Varsa hat kurulurken dört ayar birlikte açılır (okuma-hatti §3.5): ek "bozuk okuma" ölçüsü, okuma puanı ve
    /// paketsiz bekletme (okuyucunun sözlük puanını fabrika kendisi verir).
    /// </summary>
    ReadingQuality? QualityFor(string language) => null;
}

/// <summary>Okuma kalitesi ölçüleri (yazım denetimi).</summary>
/// <param name="IsMisread">Okuma bozuk mu.</param>
/// <param name="Score">Okuma puanı.</param>
public sealed record ReadingQuality(Func<string, bool> IsMisread, Func<string, int> Score);

/// <summary>Windows Güvenlik Duvarı (yalnız Windows).</summary>
public interface IFirewall
{
    /// <summary>Bu exe için Özel ağda gelen kural var mı (yönetici gerekmez). Okuma hatası "yok" sayılır.</summary>
    Task<bool> HasPrivateRuleAsync(CancellationToken cancellationToken = default);

    /// <summary>Yönetici izniyle kuralı ekler; izin verilmezse ya da kural yine yoksa false.</summary>
    Task<bool> AddRuleAsync(CancellationToken cancellationToken = default);

    /// <summary>Bağlı ağlardan biri "Ortak" mı.</summary>
    Task<bool> IsOnPublicNetworkAsync(CancellationToken cancellationToken = default) => Task.FromResult(false);
}

/// <summary>Uygulama güncelleyicisi (Windows'ta Velopack).</summary>
public interface IAppUpdater
{
    /// <summary>Kendini güncelleyebilir mi (kurulum dosyasıyla kuruldu mu).</summary>
    bool CanSelfUpdate { get; }

    /// <summary>İndirme sayfasının adresi.</summary>
    string DownloadPage { get; }

    /// <summary>Daha yeni sürümün numarası; yoksa null. Ağ hataları fırlatılabilir (denetleyici sessiz geçer).</summary>
    Task<string?> FindNewerAsync(CancellationToken cancellationToken = default);

    /// <summary>
    /// İndirir, kurar, yeniden başlatır. <paramref name="beforeInstall"/> kurulumdan hemen önce çağrılır; hata fırlatırsa
    /// kurulum başlamaz.
    /// </summary>
    Task DownloadAndInstallAsync(IProgress<double> progress, Action beforeInstall,
        CancellationToken cancellationToken = default);
}

/// <summary>Varsayılan tarayıcıda adres açan iş.</summary>
public interface IBrowser
{
    /// <summary>Adresi açar (hata yutulur).</summary>
    void Open(string url);
}

/// <summary>Hiçbir şey açmayan tarayıcı (testler).</summary>
public sealed class NoBrowser : IBrowser
{
    /// <inheritdoc />
    public void Open(string url) { }
}

/// <summary>
/// Genel kısayolları tutan platform (Windows'ta RegisterHotKey). Denetleyici yalnız çeviri sürerken ve Ayarlar yeni
/// tuş beklemiyorken tutturur; tuşa basılınca platform <c>NinoController.RunHotkey</c>'i çağırır.
/// </summary>
public interface IHotkeyHost
{
    /// <summary>Çözülmüş tabloyu tutar (kimlik: 0x4353 + Index) (tutuluyorsa bırakıp yeniden alır).</summary>
    void Hold(IReadOnlyList<ResolvedHotkey> hotkeys);

    /// <summary>Bütün kısayolları bırakır.</summary>
    void Release();
}

/// <summary>PSN giriş penceresinin sonucu.</summary>
/// <param name="RedirectUrl">Sony'nin yönlendirme adresi (kod içerir); pencere yönlendirme olmadan kapandıysa null.</param>
/// <param name="Problem">Pencerenin gördüğü sorun (sayfa açılamadı, "429" …); yoksa null.</param>
public sealed record PsnWindowOutcome(string? RedirectUrl, string? Problem = null);

/// <summary>Uygulama içi PSN giriş penceresi (Windows'ta WebView2). Linux'ta yok: kullanıcı adresi yapıştırır.</summary>
public interface IPsnSignInWindow
{
    /// <summary>Giriş sayfasını açar, yönlendirmeyi bekler.</summary>
    Task<PsnWindowOutcome> SignInAsync(string signInUrl, CancellationToken cancellationToken = default);
}
