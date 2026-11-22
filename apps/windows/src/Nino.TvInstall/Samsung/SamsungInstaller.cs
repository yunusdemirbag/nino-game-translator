// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
// Samsung giriş/sertifika akışı, sertifika uç noktaları ve Tizen kurulum hata kodlarının anlamı MIT lisanslı
// Jellyfin2Samsung (Samsung-Jellyfin-Installer) projesinden uyarlanmıştır.

using System.Net;
using TizenSdb.SigningManager;

namespace Nino.TvInstall.Samsung;

/// <summary>Kurulum ilerleme adımlarının adları (yardımcının <c>progress.step</c> değerleri).</summary>
public static class InstallSteps
{
    public const string Reading = "reading";
    public const string SignIn = "signin";
    public const string Certificate = "certificate";
    public const string Signing = "signing";
    public const string Installing = "installing";
    public const string Uninstalling = "uninstalling";
}

/// <summary>Samsung kurulumunun girdileri.</summary>
public sealed class SamsungInstallRequest
{
    public required string Host { get; init; }

    /// <summary>TV başına sertifika klasörlerinin kökü (<c>%LOCALAPPDATA%\Nino\samsung</c>).</summary>
    public required string ProfilesRoot { get; init; }

    public required string PackagePath { get; init; }

    /// <summary>Paket sürümü; yoksa TV'deki sürüme bakılmadan kurulur.</summary>
    public string? PackageVersion { get; init; }

    public InstallLog Log { get; init; } = InstallLog.None;
    public Action<string>? OnProgress { get; init; }

    /// <summary>Samsung hesabıyla giriş (yoksa geçerli sertifika gerekiyorsa "giriş gerekiyor").</summary>
    public Func<CancellationToken, Task<SamsungAccount>>? SignInAsync { get; init; }
}

/// <summary>Samsung TV'ye geliştirici modu ve sdb ile kurulum (adım adım).</summary>
public sealed class SamsungInstaller(HttpClient http)
{
    public const int SdbPort = 26101;
    public const string DefaultToolPath = "/opt/usr/apps/tmp";

    /// <summary>sdb bağlantısı (testler sahtesini verir).</summary>
    public Func<IPAddress, ISamsungSdb> Connect { get; init; } = ip => new TizenSdbSession(ip);

    /// <summary>Bağlantı denemelerinin bekleme süreleri: hemen, 2 sn, 5 sn.</summary>
    public TimeSpan[] ConnectDelays { get; init; } = [TimeSpan.Zero, TimeSpan.FromSeconds(2), TimeSpan.FromSeconds(5)];

    public TimeSpan DuidRetryDelay { get; init; } = TimeSpan.FromMilliseconds(500);
    public Func<DateTimeOffset> Now { get; init; } = () => DateTimeOffset.UtcNow;

    /// <summary>Sertifika alma (testler kendi sunucusunu verir).</summary>
    public Func<InstallLog, SamsungCertificates>? Certificates { get; init; }

    /// <summary>İmzalama (testler sahtesini verir).</summary>
    public Func<string, SamsungCertificateFolder, Task>? Sign { get; init; }

    /// <summary>8001 bilgisi (testler sahtesini verir).</summary>
    public Func<string, CancellationToken, Task<SamsungDeviceInfo>>? DeviceInfo { get; init; }

    public async Task<TvInstallResult> InstallAsync(SamsungInstallRequest request, CancellationToken ct = default)
    {
        var log = request.Log;
        log.Write($"--- Samsung TV'ye kurulum: {request.Host}, paket {Path.GetFileName(request.PackagePath)}");
        try
        {
            var result = await RunAsync(request, ct).ConfigureAwait(false);
            log.Write(result.Installed ? "Kurulum tamam." : $"TV zaten {result.Version} sürümünde; yeniden kurmaya gerek yok.");
            return result;
        }
        catch (TvInstallException e)
        {
            log.Write($"HATA {e.Failure}: {e.Detail}");
            throw;
        }
        catch (OperationCanceledException)
        {
            log.Write("Kurulum iptal edildi.");
            throw;
        }
        catch (Exception e)
        {
            log.Write($"Beklenmeyen hata: {e}");
            throw;
        }
    }

    async Task<TvInstallResult> RunAsync(SamsungInstallRequest req, CancellationToken ct)
    {
        var log = req.Log;
        if (!IPAddress.TryParse(req.Host, out var ip))
            throw new TvInstallException(TvInstallFailure.Unreachable, $"geçersiz TV adresi: {req.Host}");

        var self = LanScan.SourceAddressTowards(ip, SdbPort)?.ToString();
        var info = await (DeviceInfo ?? ((h, c) => SamsungDeviceInfo.FetchAsync(http, h, c)))(req.Host, ct).ConfigureAwait(false);
        var mode = info.DeveloperMode switch { true => "açık", false => "kapalı", _ => "?" };
        log.Write($"TV'ye bakan yerel adres: {self ?? "?"}; TV'deki Host PC IP: {info.DeveloperIp ?? "?"}; geliştirici modu: {mode}");
        if (SamsungDeviceInfo.IsHostPcMismatch(info.DeveloperIp, self))
            log.Write($"DİKKAT: TV'deki Host PC IP ({info.DeveloperIp}), yerel adresle ({self}) aynı değil; TV bu bağlantıyı kapatacak.");

        await using var sdb = await ConnectWithRetriesAsync(ip, req.Host, self, info.DeveloperIp, log, ct).ConfigureAwait(false);

        req.OnProgress?.Invoke(InstallSteps.Reading);
        var caps = await sdb.CapabilitiesAsync(ct).ConfigureAwait(false);
        var tizen = (caps.TryGetValue("platform_version", out var pv) ? pv : "")?.Trim() ?? "";
        var toolPath = caps.TryGetValue("sdk_toolpath", out var tp) && !string.IsNullOrWhiteSpace(tp) ? tp.Trim() : DefaultToolPath;
        log.Write($"TV yetenekleri: Tizen {(tizen.Length > 0 ? tizen : "?")}, araç klasörü {toolPath}");
        if (IsTooOld(tizen)) throw new TvInstallException(TvInstallFailure.TooOld, $"Tizen {tizen}");
        if (tizen.Length > 0 && TvVersions.IsNewerLoose("5.0", tizen)) log.Write("2017–2018 TV'si, destek deneysel.");

        var before = await ReadVersionAsync(sdb, log, ct).ConfigureAwait(false);
        if (req.PackageVersion is { Length: > 0 } pkg && before is not null && !TvVersions.IsNewerLoose(pkg, before))
            return new TvInstallResult(before, false);

        var duid = await ReadDuidAsync(sdb, ct).ConfigureAwait(false);
        var folder = SamsungCertificateFolder.ForDuid(req.ProfilesRoot, duid);
        log.Write($"Kayıtlı sertifika: {folder.Describe(duid, Now())}");
        if (!folder.IsValid(Now()) || !folder.BelongsTo(duid))
        {
            if (req.SignInAsync is null) throw new TvInstallException(TvInstallFailure.LoginFailed, "giriş gerekiyor");
            req.OnProgress?.Invoke(InstallSteps.SignIn);
            log.Write("Tarayıcıda Samsung hesabıyla oturum açılması bekleniyor.");
            var account = await req.SignInAsync(ct).ConfigureAwait(false);
            req.OnProgress?.Invoke(InstallSteps.Certificate);
            var issuer = Certificates?.Invoke(log) ?? new SamsungCertificates(http, log);
            await issuer.IssueAsync(account, duid, folder, ct).ConfigureAwait(false);
            log.Write($"Yeni sertifika: {folder.Describe(duid, Now())}");
        }

        if (NeedsDeviceProfile(tizen))
        {
            try
            {
                if (File.Exists(folder.DeviceProfilePath))
                    await sdb.PushAsync(folder.DeviceProfilePath, toolPath.TrimEnd('/') + "/device-profile.xml", ct).ConfigureAwait(false);
                else log.Write("device-profile.xml yok; gönderilmedi.");
            }
            catch (Exception e) when (e is not OperationCanceledException)
            {
                log.Write($"device-profile.xml gönderilemedi: {e.Message}");
            }
        }

        req.OnProgress?.Invoke(InstallSteps.Signing);
        CleanOldTempPackages();
        var temp = Path.Combine(Path.GetTempPath(), $"nino-{Guid.NewGuid():N}.wgt");
        try
        {
            File.Copy(req.PackagePath, temp, true);
            await (Sign ?? SignWithTizenAsync)(temp, folder).ConfigureAwait(false);

            req.OnProgress?.Invoke(InstallSteps.Installing);
            try
            {
                await InstallWithRecoveryAsync(sdb, temp, toolPath, log, req.OnProgress, ct).ConfigureAwait(false);
            }
            catch (TvInstallException e) when (e.Failure == TvInstallFailure.CertificateRejected)
            {
                folder.SetAside(Now());
                log.Write("Saklanan sertifika silindi; sonraki denemede yeni bir tane istenecek.");
                throw;
            }
        }
        finally
        {
            DeleteWithRetries(temp);
        }

        var after = await ReadVersionAsync(sdb, log, ct).ConfigureAwait(false);
        if (req.PackageVersion is { Length: > 0 } p2 && after is not null && TvVersions.IsNewerLoose(p2, after))
            throw new TvInstallException(TvInstallFailure.InstallFailed,
                $"kurulum bitti ama TV {after} sürümünde kaldı (beklenen {p2})");

        try
        {
            var r = await sdb.ShellAsync("0 was_execute " + SamsungInstallOutput.NinoAppId, ct).ConfigureAwait(false);
            log.Write($"Uygulama açıldı mı: {r.Trim()}");
        }
        catch (Exception e) when (e is not OperationCanceledException)
        {
            log.Write($"Uygulama açılamadı: {e.Message}");
        }
        return new TvInstallResult(after ?? req.PackageVersion ?? "", true);
    }

    /// <summary>"Kayıtlı geçerli sertifika var mı": bağlan, DUID oku, geçerli ve bu TV'nin mi.</summary>
    public async Task<bool> HasValidCertificateAsync(string host, string profilesRoot, CancellationToken ct = default)
    {
        if (!IPAddress.TryParse(host, out var ip)) return false;
        await using var sdb = Connect(ip);
        await sdb.ConnectAsync(ct).ConfigureAwait(false);
        var duid = await ReadDuidAsync(sdb, ct).ConfigureAwait(false);
        var folder = SamsungCertificateFolder.ForDuid(profilesRoot, duid);
        return folder.IsValid(Now()) && folder.BelongsTo(duid);
    }

    /// <summary>Tizen sürümü boş değil ve 3.0'dan eski.</summary>
    public static bool IsTooOld(string tizen) => tizen.Length > 0 && TvVersions.IsNewerLoose("3.0", tizen);

    /// <summary>Tizen 3.0–4.0 cihaz profili ister.</summary>
    public static bool NeedsDeviceProfile(string tizen) =>
        tizen.Length > 0 && !IsTooOld(tizen) && !TvVersions.IsNewerLoose(tizen, "4.0");

    async Task<ISamsungSdb> ConnectWithRetriesAsync(IPAddress ip, string host, string? self, string? tvHostPc, InstallLog log, CancellationToken ct)
    {
        Exception? last = null;
        for (var i = 0; i < ConnectDelays.Length; i++)
        {
            if (ConnectDelays[i] > TimeSpan.Zero) await Task.Delay(ConnectDelays[i], ct).ConfigureAwait(false);
            var sdb = Connect(ip);
            try
            {
                await sdb.ConnectAsync(ct).ConfigureAwait(false);
                log.Write($"sdb bağlantısı kuruldu ({host}:{SdbPort}, {i + 1}. denemede)");
                return sdb;
            }
            catch (Exception e) when (e is not OperationCanceledException || !ct.IsCancellationRequested)
            {
                last = e;
                log.Write($"sdb bağlantısı kurulamadı ({i + 1}/{ConnectDelays.Length}): {e.Message}");
                await sdb.DisposeAsync().ConfigureAwait(false);
            }
        }
        throw new TvInstallException(TvInstallFailure.Unreachable,
            $"sdb {host}:{SdbPort}: {last?.Message} (bu bilgisayar {self ?? "?"}, TV'deki Host PC IP {tvHostPc ?? "?"})", last);
    }

    static async Task<string?> ReadVersionAsync(ISamsungSdb sdb, InstallLog log, CancellationToken ct)
    {
        try
        {
            var v = SamsungInstallOutput.AppListVersion(await sdb.ShellAsync("0 vd_applist", ct).ConfigureAwait(false));
            log.Write($"TV'deki Nino sürümü: {v ?? "yok"}");
            return v;
        }
        catch (Exception e) when (e is not OperationCanceledException)
        {
            log.Write($"TV'deki sürüm okunamadı: {e.Message}");
            return null;
        }
    }

    async Task<string> ReadDuidAsync(ISamsungSdb sdb, CancellationToken ct)
    {
        var reply = "";
        for (var i = 0; i < 3; i++)
        {
            if (i > 0) await Task.Delay(DuidRetryDelay, ct).ConfigureAwait(false);
            try { reply = await sdb.ShellAsync("0 getduid", ct).ConfigureAwait(false) ?? ""; }
            catch (Exception e) when (e is not OperationCanceledException) { reply = e.Message; }
            var duid = SamsungInstallOutput.ParseDuid(reply);
            if (duid is not null) return duid;
        }
        var shown = reply.Trim();
        throw new TvInstallException(TvInstallFailure.Unreachable,
            $"TV kimliği (DUID) okunamadı; TV'den gelen: {(shown.Length > 0 ? shown : "boş")}");
    }

    /// <summary>Kurar; eski kopya sorunlarında kaldırıp bir kez daha dener.</summary>
    public static async Task InstallWithRecoveryAsync(ISamsungSdb sdb, string package, string toolPath, InstallLog log,
        Action<string>? progress, CancellationToken ct)
    {
        var output = await sdb.InstallAsync(package, toolPath, ct).ConfigureAwait(false);
        log.Write("vd_appinstall çıktısı:\n" + output);
        var problem = SamsungInstallOutput.Classify(output);
        if (problem == SamsungInstallProblem.None) return;
        if (SamsungInstallOutput.UninstallMayHelp(problem))
        {
            progress?.Invoke(InstallSteps.Uninstalling);
            var replies = new List<string>();
            foreach (var id in new[] { SamsungInstallOutput.NinoPackageId, SamsungInstallOutput.NinoAppId })
            {
                try { replies.Add((await sdb.ShellAsync("0 vd_appuninstall " + id, ct).ConfigureAwait(false)).Trim()); }
                catch (Exception e) when (e is not OperationCanceledException) { replies.Add("hata: " + e.Message); }
            }
            log.Write("Önceki kopyayı kaldırma sonucu: " + string.Join(" / ", replies));
            output = await sdb.InstallAsync(package, toolPath, ct).ConfigureAwait(false);
            log.Write("vd_appinstall çıktısı:\n" + output);
            problem = SamsungInstallOutput.Classify(output);
            if (problem == SamsungInstallProblem.None) return;
        }
        throw new TvInstallException(SamsungInstallOutput.FailureOf(problem), SamsungInstallOutput.Summary(output));
    }

    static async Task SignWithTizenAsync(string wgt, SamsungCertificateFolder folder) =>
        await TizenWgtSigner.ReSignWgtWithCertsInPlace(wgt, folder.AuthorPath, folder.DistributorPath, folder.Password, null!)
            .ConfigureAwait(false);

    static void CleanOldTempPackages()
    {
        try
        {
            foreach (var f in Directory.GetFiles(Path.GetTempPath(), "nino-*.wgt"))
            {
                try
                {
                    if (DateTime.UtcNow - File.GetLastWriteTimeUtc(f) > TimeSpan.FromMinutes(10)) File.Delete(f);
                }
                catch (IOException) { }
                catch (UnauthorizedAccessException) { }
            }
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    static void DeleteWithRetries(string path)
    {
        for (var i = 0; i < 3; i++)
        {
            try
            {
                if (File.Exists(path)) File.Delete(path);
                return;
            }
            catch (Exception ex) when (ex is UnauthorizedAccessException or IOException)
            {
                // Kitaplık dosyayı açık bırakabiliyor; bellek temizliğinden sonra yeniden dene.
                GC.Collect();
                GC.WaitForPendingFinalizers();
            }
        }
    }
}
