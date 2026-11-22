// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
// Samsung giriş/sertifika akışı, sertifika uç noktaları ve Tizen kurulum hata kodlarının anlamı MIT lisanslı
// Jellyfin2Samsung (Samsung-Jellyfin-Installer) projesinden uyarlanmıştır.

using System.Net;
using TizenSdb;
using TizenSdb.SdbClient;

namespace Nino.TvInstall.Samsung;

/// <summary>Kurucunun TV ile konuştuğu sdb oturumu (testte sahtesi verilir).</summary>
public interface ISamsungSdb : IAsyncDisposable
{
    Task ConnectAsync(CancellationToken ct);
    Task<IReadOnlyDictionary<string, string>> CapabilitiesAsync(CancellationToken ct);
    Task<string> ShellAsync(string command, CancellationToken ct);
    Task PushAsync(string localPath, string remotePath, CancellationToken ct);

    /// <summary>İmzalı paketi gönderip kurar; kurucunun yazdığı bütün çıktıyı döner (hata da çıktıya eklenir).</summary>
    Task<string> InstallAsync(string packagePath, string toolPath, CancellationToken ct);
}

/// <summary>TizenSdb.Core üstünde gerçek sdb oturumu.</summary>
public sealed class TizenSdbSession(IPAddress address, int port = SamsungInstaller.SdbPort) : ISamsungSdb
{
    static readonly SemaphoreSlim ConsoleGate = new(1, 1);
    readonly SdbTcpDevice _device = new(address, port);

    public Task ConnectAsync(CancellationToken ct) => _device.ConnectAsync(ct);

    public async Task<IReadOnlyDictionary<string, string>> CapabilitiesAsync(CancellationToken ct) =>
        await _device.CapabilityAsync(ct).ConfigureAwait(false);

    public Task<string> ShellAsync(string command, CancellationToken ct) => _device.ShellCommandAsync(command, ct);

    public async Task PushAsync(string localPath, string remotePath, CancellationToken ct)
    {
        await using var stream = File.OpenRead(localPath);
        await _device.PushAsync(stream, remotePath, null!, ct).ConfigureAwait(false);
    }

    public async Task<string> InstallAsync(string packagePath, string toolPath, CancellationToken ct)
    {
        // Kurucu sonucu konsola yazıyor: kurulum boyunca konsol çıktısı yakalanır (aynı anda tek yakalama).
        await ConsoleGate.WaitAsync(ct).ConfigureAwait(false);
        var previous = Console.Out;
        var capture = new StringWriter();
        Console.SetOut(TextWriter.Synchronized(capture));
        try
        {
            try
            {
                await new TizenInstaller(packagePath, _device, toolPath).InstallApp().WaitAsync(ct).ConfigureAwait(false);
            }
            catch (Exception e) when (e is not OperationCanceledException)
            {
                capture.WriteLine($"install failed: {e.GetType().Name}: {e.Message}");
            }
        }
        finally
        {
            Console.SetOut(previous);
            ConsoleGate.Release();
        }
        return capture.ToString();
    }

    public async ValueTask DisposeAsync()
    {
        try { await _device.DisconnectAsync().ConfigureAwait(false); }
        catch (Exception) { }
        await _device.DisposeAsync().ConfigureAwait(false);
    }
}
