// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Data;
using Nino.Core.Telemetry;
using Nino.Shell.Platform;

namespace Nino.Shell;

/// <summary>
/// Ölçümün platform bilgileri (olcum.md). Windows açılışı ve Linux kendi değerleriyle doldurur; denetleyici
/// <see cref="ShellOptions.Telemetry"/> ile alır. Kapatma ayarı yoktur: yalnız sunucunun <c>telemetry.enabled</c>'ı durdurur.
/// </summary>
public sealed record TelemetrySetup
{
    /// <summary>Veri klasörü; kuyruk ve çalışma işareti <c>&lt;veri klasörü&gt;/telemetry</c> altında.</summary>
    public required string DataFolder { get; init; }

    /// <summary><c>windows</c> ya da <c>linux</c>.</summary>
    public required string Platform { get; init; }

    /// <summary>Sistem adı ve sürümü (<c>Windows 11 26100</c>).</summary>
    public required string Os { get; init; }

    /// <summary>Cihazın üretici modeli; kullanıcının verdiği bilgisayar adı asla.</summary>
    public required string Device { get; init; }

    /// <summary>Kanal: geliştirici derlemesi ve testler <see cref="TelemetryChannel.Dev"/>.</summary>
    public TelemetryChannel Channel { get; init; } = TelemetryChannel.Release;

    /// <summary>Gönderici; null ise hizmetlerinki (<see cref="IShellServices.TelemetrySender"/>).</summary>
    public ITelemetrySender? Sender { get; init; }

    /// <summary>Kurulum kimliği; null ise havuzunki (<c>pool-translations/install</c>).</summary>
    public string? Install { get; init; }

    /// <summary>Saat (testte sahte).</summary>
    public TimeProvider? Clock { get; init; }

    /// <summary>Soğuk açılış süresi (ms), biliniyorsa.</summary>
    public long? LaunchMs { get; init; }

    /// <summary>Teşhis için bellek/işlemci ölçer; null ise süreç bilgisinden (testler sahtesini verir).</summary>
    public IResourceProbe? ResourceProbe { get; init; }

    /// <summary>Arka plan gönderim döngüsü çalışsın mı (testler kapatır, elle gönderir).</summary>
    public bool RunLoop { get; init; } = true;

    /// <summary>Kuyruk klasörü.</summary>
    public string Folder => Path.Combine(DataFolder, "telemetry");
}

/// <summary>
/// Ölçüm istemcisinin yaşam döngüsü: kurulum, açılış (<c>crash</c> + <c>launch</c>), arka plan gönderimi, düzgün
/// kapanış (işaret silinir, kısa gönderim). Denetleyici kurar; platform yalnız çökme anını
/// (<see cref="RecordCrash"/>) ve oturum kapanışı gibi ani çıkışları (<see cref="Exiting"/>) bildirir.
/// </summary>
public sealed class ShellTelemetry
{
    readonly CancellationTokenSource _loop = new();
    int _exited;

    ShellTelemetry(TelemetryClient client) => Client = client;

    /// <summary>İstemci.</summary>
    public TelemetryClient Client { get; }

    /// <summary>
    /// Kurar ve açılışı kaydeder. Gönderici yoksa (havuz adresi yok) null. Hata dışarı kaçmaz.
    /// </summary>
    /// <param name="setup">Platform bilgileri.</param>
    /// <param name="services">Hizmetler (sürüm, gönderici, havuz kimliği).</param>
    /// <param name="tv">O anki TV markası (her gönderimde okunur).</param>
    public static ShellTelemetry? Open(TelemetrySetup setup, IShellServices services, Func<TvBrand> tv)
    {
        try
        {
            if ((setup.Sender ?? services.TelemetrySender) is not { } sender) return null;
            var install = setup.Install ?? InstallOf(setup.DataFolder, services);
            var version = services.AppVersion;
            var client = new TelemetryClient(new TelemetryOptions(setup.Folder, install,
                () => new TelemetryContext(setup.Platform, version, setup.Os, setup.Device, tv(), setup.Channel), sender)
            {
                Clock = setup.Clock ?? TimeProvider.System,
            });
            var host = new ShellTelemetry(client);
            client.AppLaunched(version, setup.LaunchMs);
            if (setup.RunLoop) _ = Task.Run(() => client.RunAsync(host._loop.Token));
            return host;
        }
        catch (Exception)
        {
            return null;
        }
    }

    /// <summary>Havuzla aynı kurulum kimliği (havuz yoksa aynı dosyadan).</summary>
    static string InstallOf(string dataFolder, IShellServices services)
    {
        try
        {
            if (services.Pool?.InstallId is { Length: > 0 } id) return id;
        }
        catch (Exception) { }
        return InstallIdFile.ReadOrCreateGuid(Path.Combine(dataFolder, "pool-translations", "install"));
    }

    /// <summary>Çökme anı: istisnanın sınıfı ve uygulama içi yeri işarete yazılır (ileti asla).</summary>
    public void RecordCrash(Exception? error)
    {
        try
        {
            if (error is not null) Client.Marker.RecordCrash(error);
        }
        catch (Exception) { }
    }

    /// <summary>Uygulama düzgün çıkıyor (pencere kapanışı, oturum kapanışı, güncelleme yeniden başlatması): işaret silinir.</summary>
    public void Exiting()
    {
        if (Interlocked.Exchange(ref _exited, 1) == 1) return;
        try { _loop.Cancel(); } catch (Exception) { }
        try { Client.AppExiting(); } catch (Exception) { }
    }

    /// <summary>Çıkış iptal oldu (ör. güncelleme kurulamadı): işaret yeniden yazılır, döngü sürmez ama olaylar kaydedilir.</summary>
    public void ExitCancelled(string version)
    {
        if (Interlocked.Exchange(ref _exited, 0) == 0) return;
        try { Client.Marker.Start(version); } catch (Exception) { }
    }

    /// <summary>Kapanışta bekleyenleri kısa zaman aşımıyla gönderir (hata yutulur).</summary>
    public async Task FlushOnExitAsync(TimeSpan timeout)
    {
        using var cts = new CancellationTokenSource(timeout);
        try { await Client.FlushAsync(cts.Token, ignoreBackoff: false).ConfigureAwait(false); }
        catch (Exception) { }
    }
}
