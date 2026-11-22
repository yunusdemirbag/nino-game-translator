// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Net;
using System.Net.WebSockets;
using System.Text.Json;
using Nino.Core.Tv;

namespace Nino.Core.Link;

/// <summary>Dinleyen (Android TV) Nino TV'lerini bulur.</summary>
public interface ILinkTvLocator
{
    /// <summary>Bulunan TV adresleri (en iyi aday önce).</summary>
    Task<IReadOnlyList<string>> FindAsync(CancellationToken ct);
}

/// <summary>
/// Önce mDNS (<c>_nino._tcp</c>, 3 sn); cevap yoksa yerel /24'te <c>GET /nino/info</c> taraması (aynı anda 24, 1.2 sn).
/// <c>role:"sender"</c> taşıyan cevaplar (başka bir bilgisayar) TV sayılmaz.
/// </summary>
public sealed class LinkTvLocator(HttpClient? http = null, int port = LinkIngress.DefaultPort) : ILinkTvLocator
{
    readonly HttpClient http = http ?? new HttpClient();

    public TimeSpan MdnsWait { get; init; } = TimeSpan.FromSeconds(3);
    public TimeSpan ProbeTimeout { get; init; } = TimeSpan.FromMilliseconds(1200);
    public int Parallel { get; init; } = 24;

    /// <summary>Yerel adresler (test için değiştirilebilir).</summary>
    public Func<IReadOnlyList<string>> LocalAddresses { get; init; } = () => LocalNetwork.PrivateAddresses();

    public async Task<IReadOnlyList<string>> FindAsync(CancellationToken ct)
    {
        var locals = LocalAddresses();
        try
        {
            var services = await MdnsBrowser.BrowseAsync(locals.Select(IPAddress.Parse), MdnsWait, ct: ct).ConfigureAwait(false);
            var hosts = services.Select(s => s.Address).Distinct().ToList();
            if (hosts.Count > 0) return hosts;
        }
        catch (Exception) when (!ct.IsCancellationRequested) { }
        return await ScanAsync(LocalNetwork.ScanTargets(locals), ct).ConfigureAwait(false);
    }

    /// <summary>Hedeflerden Nino TV'si (gönderici değil) olanlar, son bayta göre sıralı.</summary>
    public async Task<IReadOnlyList<string>> ScanAsync(IEnumerable<string> targets, CancellationToken ct)
    {
        var found = new List<string>();
        await System.Threading.Tasks.Parallel.ForEachAsync(targets,
            new ParallelOptions { MaxDegreeOfParallelism = Parallel, CancellationToken = ct }, async (host, token) =>
            {
                if (await IsNinoTvAsync(host, token).ConfigureAwait(false))
                    lock (found) found.Add(host);
            }).ConfigureAwait(false);
        return found.OrderBy(h => IPAddress.TryParse(h, out var ip) ? ip.GetAddressBytes()[^1] : 0).ToList();
    }

    /// <summary><c>/nino/info</c> cevabı Nino TV'si mi (app nino, role sender değil).</summary>
    public async Task<bool> IsNinoTvAsync(string host, CancellationToken ct)
    {
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        cts.CancelAfter(ProbeTimeout);
        try
        {
            var text = await http.GetStringAsync($"http://{host}:{port}/nino/info", cts.Token).ConfigureAwait(false);
            return IsTvInfo(text);
        }
        catch (Exception) when (!ct.IsCancellationRequested)
        {
            return false;
        }
    }

    /// <summary><c>{"app":"nino",…}</c> ve <c>role</c> "sender" değil.</summary>
    public static bool IsTvInfo(string json)
    {
        try
        {
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;
            if (root.ValueKind != JsonValueKind.Object) return false;
            if (!root.TryGetProperty("app", out var app) || app.ValueKind != JsonValueKind.String || app.GetString() != "nino")
                return false;
            return !(root.TryGetProperty("role", out var role) && role.ValueKind == JsonValueKind.String
                && role.GetString() == "sender");
        }
        catch (JsonException)
        {
            return false;
        }
    }
}

/// <summary>Giden bağlantının durumu.</summary>
public enum LinkConnectorState { Idle, Searching, Connecting, Connected, Waiting, Replaced, UpdateRequired }

/// <summary>
/// Giden bağlantı (TV dinler, Windows bağlanır): yeni Android TV uygulamasına <c>ws://&lt;TV&gt;:47800/nino/ws</c>.
/// Kopunca 1, 2, 4, 8, 8… sn bekleyip yeniden bağlanır. Başka bir gönderici TV'yi alırsa (<c>replaced</c>)
/// kendiliğinden yeniden bağlanmaz; yalnız <see cref="Start"/> yeniden çağrılınca (çeviri yeniden başladı ya da TV
/// yeniden seçildi).
/// </summary>
public sealed class LinkConnector : IAsyncDisposable
{
    readonly SenderIdentity identity;
    readonly ILinkTvLocator locator;
    readonly LinkTimings timings;
    readonly TimeProvider clock;
    readonly object gate = new();
    CancellationTokenSource? run;
    Task? loop;
    LinkPeer? current;

    public LinkConnector(SenderIdentity identity, ILinkTvLocator? locator = null, LinkTimings? timings = null,
        TimeProvider? clock = null, int port = LinkIngress.DefaultPort)
    {
        this.identity = identity;
        this.locator = locator ?? new LinkTvLocator(port: port);
        this.timings = timings ?? LinkTimings.Default;
        this.clock = clock ?? TimeProvider.System;
        Port = port;
    }

    public int Port { get; }

    /// <summary>Yeniden bağlanma beklemeleri (son değer tekrarlanır).</summary>
    public IReadOnlyList<TimeSpan> Backoff { get; init; } =
        [TimeSpan.FromSeconds(1), TimeSpan.FromSeconds(2), TimeSpan.FromSeconds(4), TimeSpan.FromSeconds(8)];

    /// <summary>Bağlanma zaman aşımı.</summary>
    public TimeSpan ConnectTimeout { get; init; } = TimeSpan.FromSeconds(5);

    public LinkConnectorState State { get; private set; } = LinkConnectorState.Idle;

    /// <summary>Hazır bağlantının TV bilgisi.</summary>
    public TvLinkInfo? Connected => current is { IsReady: true } p ? p.Info : null;

    /// <summary>Şu an kullanılan TV adresi.</summary>
    public string? Host { get; private set; }

    public event Action<LinkConnectorState>? StateChanged;

    /// <summary>Kayıtlı adres yerine aramayla yeni bir adres bulundu (TV kaydı güncellenebilir).</summary>
    public event Action<string>? HostFound;

    /// <summary>TV hazır oldu; hazırlık mesajları buradan verilir.</summary>
    public Action<LinkPeer>? OnReady { get; set; }

    /// <summary>TV hazır oldu (hazırlık mesajlarından sonra; herhangi bir iş parçacığında).</summary>
    public event Action<LinkPeer>? PeerConnected;

    /// <summary>WebSocket'i açılmış bir bağlantı bitti (hazır olmamış olabilir).</summary>
    public event Action<LinkPeer, LinkEnd>? PeerEnded;

    /// <summary>Bağlantıyı başlatır (zaten çalışıyorsa önce durdurur). <paramref name="savedHost"/> önce denenir.</summary>
    public void Start(string? savedHost)
    {
        Stop();
        lock (gate)
        {
            Host = string.IsNullOrWhiteSpace(savedHost) ? null : savedHost.Trim();
            run = new CancellationTokenSource();
            loop = LoopAsync(run.Token);
        }
    }

    public void Stop()
    {
        lock (gate)
        {
            run?.Cancel();
            run = null;
            current?.Stop();
        }
        SetState(LinkConnectorState.Idle);
    }

    /// <summary>Hazırsa mesajı yollar; değilse atılır (hazırlıkta son durum zaten gider).</summary>
    public void Send(string message)
    {
        if (current is { IsReady: true } p) p.Send(message);
    }

    public async ValueTask DisposeAsync()
    {
        Stop();
        if (loop is { } l)
        {
            try { await l.ConfigureAwait(false); } catch (Exception) { }
        }
    }

    async Task LoopAsync(CancellationToken ct)
    {
        var attempt = 0;
        var version = TvWire.ProtocolVersion;
        while (!ct.IsCancellationRequested)
        {
            var host = Host;
            LinkEnd? end = null;
            if (host is not null)
            {
                SetState(LinkConnectorState.Connecting);
                end = await TryOnceAsync(host, version, ct).ConfigureAwait(false);
            }
            if (end is null && !ct.IsCancellationRequested)
            {
                SetState(LinkConnectorState.Searching);
                IReadOnlyList<string> found = [];
                try { found = await locator.FindAsync(ct).ConfigureAwait(false); }
                catch (Exception) when (!ct.IsCancellationRequested) { }
                var other = found.FirstOrDefault(h => h != host);
                if (other is not null)
                {
                    Host = other;
                    try { HostFound?.Invoke(other); } catch (Exception) { }
                    SetState(LinkConnectorState.Connecting);
                    end = await TryOnceAsync(other, version, ct).ConfigureAwait(false);
                }
            }
            if (ct.IsCancellationRequested) return;

            switch (end)
            {
                case LinkEnd.Replaced:
                    SetState(LinkConnectorState.Replaced);
                    return;
                case LinkEnd.VersionUnsupported when suggested is { } v:
                    version = v;
                    continue;
                case LinkEnd.VersionUnsupported:
                    SetState(LinkConnectorState.UpdateRequired);
                    return;
            }
            if (wasReady) attempt = 0;
            SetState(LinkConnectorState.Waiting);
            var delay = Backoff[Math.Min(attempt, Backoff.Count - 1)];
            attempt++;
            try { await Task.Delay(delay, clock, ct).ConfigureAwait(false); }
            catch (OperationCanceledException) when (ct.IsCancellationRequested) { break; }
        }
    }

    bool wasReady;
    int? suggested;

    /// <summary>Bir bağlantı denemesi: bağlanamazsa <c>null</c>, bağlandıysa bitiş biçimi.</summary>
    async Task<LinkEnd?> TryOnceAsync(string host, int version, CancellationToken ct)
    {
        wasReady = false;
        var ws = new ClientWebSocket();
        ws.Options.KeepAliveInterval = TimeSpan.Zero;
        try
        {
            using var connect = CancellationTokenSource.CreateLinkedTokenSource(ct);
            connect.CancelAfter(ConnectTimeout);
            await ws.ConnectAsync(new Uri($"ws://{host}:{Port}/nino/ws"), connect.Token).ConfigureAwait(false);
        }
        catch (Exception)
        {
            ws.Dispose();
            return null;
        }

        var peer = new LinkPeer(ws, host, timings, clock);
        lock (gate) current = peer;
        var end = LinkEnd.Stopped;
        try
        {
            end = await peer.RunAsync(identity.Device, identity.Client, version, p =>
            {
                wasReady = true;
                SetState(LinkConnectorState.Connected);
                try { OnReady?.Invoke(p); } catch (Exception) { }
                try { PeerConnected?.Invoke(p); } catch (Exception) { }
            }, ct).ConfigureAwait(false);
            return end;
        }
        finally
        {
            try { PeerEnded?.Invoke(peer, end); } catch (Exception) { }
            lock (gate)
                if (ReferenceEquals(current, peer)) current = null;
            suggested = peer.SuggestedVersion;
            if (wasReady && !ct.IsCancellationRequested) SetState(LinkConnectorState.Waiting);
            await peer.DisposeAsync().ConfigureAwait(false);
        }
    }

    void SetState(LinkConnectorState state)
    {
        if (State == state) return;
        State = state;
        try { StateChanged?.Invoke(state); } catch (Exception) { }
    }
}
