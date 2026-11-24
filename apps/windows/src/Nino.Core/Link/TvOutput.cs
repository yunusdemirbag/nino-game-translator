// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Net.Sockets;

namespace Nino.Core.Link;

/// <summary><see cref="TvOutput"/> ayarları.</summary>
public sealed record TvOutputOptions
{
    /// <summary>Gönderici kimliği (<c>/nino/info</c>, <c>hello</c>).</summary>
    public SenderIdentity Identity { get; init; } = new();

    public int LegacyPort { get; init; } = LegacySubtitleServer.DefaultPort;
    public int IngressPort { get; init; } = LinkIngress.DefaultPort;

    /// <summary>Port dolu olunca deneme sayısı ve aralığı (eski süreç portu birkaç saniye bırakmayabilir).</summary>
    public int PortAttempts { get; init; } = 6;
    public TimeSpan PortRetryDelay { get; init; } = TimeSpan.FromSeconds(1);

    /// <summary>Altyazı günlüğüne (altyazi.log) satır. TV bağlanma/kopmaları da buraya yazılır (adresle).</summary>
    public Action<string>? Log { get; init; }

    public TimeProvider? Clock { get; init; }
    public LinkTimings? Timings { get; init; }

    /// <summary>Android TV'yi bulan (yoksa mDNS + /24 taraması).</summary>
    public ILinkTvLocator? Locator { get; init; }

    /// <summary>Giden bağlantının beklemeleri (testler kısaltır).</summary>
    public IReadOnlyList<TimeSpan>? ConnectorBackoff { get; init; }
}

/// <summary>
/// "TV çıkışı": uygulama her olayı buraya yollar, o da üç çıkışa aynı anda iletir (biri hata verirse ötekiler yine
/// alır): eski 8787 sunucusu (eski TV'ler ve OBS), 47800 gönderici girişi (LG/Samsung web TV'leri bağlanır) ve
/// giden bağlantı (yeni Android TV dinler). Yeni bağlanan TV'ye son durumu verir; bağlı TV sayısını toplar;
/// bilgisayar penceresine (yerel dinleyici) özet olayları çağıranın iş parçacığında verir.
/// </summary>
public sealed class TvOutput : IAsyncDisposable
{
    readonly TvOutputOptions options;
    readonly TimeProvider clock;
    readonly LegacySubtitleServer legacy;
    readonly LinkIngress ingress;
    readonly SemaphoreSlim legacyStart = new(1, 1);
    readonly SemaphoreSlim ingressStart = new(1, 1);
    readonly object gate = new();
    LinkConnector? connector;
    StyleChanged? lastStyle;
    bool running;
    DateTimeOffset? startedAt;
    bool senderActive;
    long showCounter;
    long? lastShowId;
    (SubtitleShown Show, long Id, DateTimeOffset At)? lastShow;
    (ScreenShown Screen, DateTimeOffset At)? lastOverlay;
    bool subtitlesOnTv = true;
    int lastCount;
    readonly HashSet<TvLinkKind> handshakeStreak = [];

    public TvOutput(TvOutputOptions? options = null)
    {
        this.options = options ?? new TvOutputOptions();
        clock = this.options.Clock ?? TimeProvider.System;
        legacy = new LegacySubtitleServer(clock);
        legacy.TvCountChanged += _ => NotifyCount(force: true);
        legacy.ModelReported += model => ReportInfo(new TvLinkInfo("", model, null, ""));
        legacy.TvConnected += c => RaiseConnected(new TvLinkConnected(c.Id, TvLinkKind.Legacy, LegacyPort == 0 ? this.options.LegacyPort : LegacyPort,
            c.Address, c.Model, null, TimeSpan.Zero));
        legacy.TvDropped += (c, reason) => RaiseDropped(new TvLinkDropped(c.Id, TvLinkKind.Legacy,
            LegacyPort == 0 ? this.options.LegacyPort : LegacyPort, c.Address, reason, true, clock.GetUtcNow() - c.ConnectedAt,
            c.Model, null));
        ingress = new LinkIngress(this.options.Identity, this.options.Timings, clock) { OnReady = IngressReady };
        ingress.PeerConnected += p => PeerConnected(TvLinkKind.WebTv, IngressPortNow, p);
        ingress.PeerEnded += (p, end) => PeerEnded(TvLinkKind.WebTv, IngressPortNow, p, end);
        ingress.DisplaysChanged += list =>
        {
            foreach (var info in list) ReportInfo(info);
            NotifyCount(force: false);
        };
    }

    /// <summary>Bağlı TV sayısı değişti (8787 TV'leri + gelen web TV'ler + giden Android TV; OBS sayılmaz).</summary>
    public event Action<int>? TvCountChanged;

    /// <summary>TV modelini/sürümünü söyledi (8787 <c>model</c> sorgusu ya da <c>welcome</c>).</summary>
    public event Action<TvLinkInfo>? TvInfoReported;

    /// <summary>Bir TV bağlandı (8787 TV'si, 47800 web TV'si ya da Android TV; OBS izleyicisi hariç). Herhangi bir iş parçacığında.</summary>
    public event Action<TvLinkConnected>? TvConnected;

    /// <summary>
    /// Bir TV bağlantısı bitti ya da el sıkışma olmadı (<see cref="TvLinkEndReason.Handshake"/>). Neden
    /// <see cref="TvLinkEndReason.Stopped"/> ise Nino kapatmıştır, kopma değildir. Herhangi bir iş parçacığında.
    /// </summary>
    public event Action<TvLinkDropped>? TvDropped;

    /// <summary>Masaüstü penceresine giden olay (ağdan bağımsız; çağıranın iş parçacığında).</summary>
    public event Action<LocalSubtitleEvent>? LocalEvent;

    /// <summary>Giden bağlantı aramayla yeni bir Android TV adresi buldu.</summary>
    public event Action<string>? AndroidTvHostFound;

    /// <summary>Giden bağlantının durumu değişti.</summary>
    public event Action<LinkConnectorState>? AndroidTvStateChanged;

    /// <summary>8787 sunucusu (OBS sayfası ve eski TV'ler).</summary>
    public LegacySubtitleServer Legacy => legacy;

    /// <summary>47800 gönderici girişi.</summary>
    public LinkIngress Ingress => ingress;

    /// <summary>8787 sunucusunun gerçekten dinlediği port (açılmadıysa 0).</summary>
    public int LegacyPort => legacy.Port;

    /// <summary>
    /// Yeni bağlanan TV'ye <c>started</c> yalnız çeviri bu kadar önce başladıysa yeniden yollanır (TV her
    /// <c>started</c>'da "çeviri başladı" balonu gösterir; sürdüğünü <c>state</c> söyler).
    /// </summary>
    public static readonly TimeSpan StartedReplayWindow = TimeSpan.FromSeconds(20);

    /// <summary>Gönderici etkin mi: çeviri sürüyor (started..stopped) ve altyazı TV'ye gidiyor.</summary>
    public bool SenderActive
    {
        get { lock (gate) return senderActive; }
    }

    /// <summary>Bağlı TV sayısı.</summary>
    public int TvCount
    {
        get
        {
            var android = connector?.Connected is not null ? 1 : 0;
            return legacy.TvCount + ingress.TvCount + android;
        }
    }

    /// <summary>
    /// Altyazı TV'ye gitsin mi. Kapalıyken altyazı olayları (show/clear/screen*/region*/style) yalnız OBS'e gider;
    /// started/stopped/ping herkese. Kapatınca yeni TV'ler temizlenir, açınca son stil ve altyazı yollanır.
    /// </summary>
    public bool SubtitlesOnTv
    {
        get { lock (gate) return subtitlesOnTv; }
        set
        {
            bool changed;
            lock (gate)
            {
                changed = subtitlesOnTv != value;
                subtitlesOnTv = value;
            }
            legacy.SubtitlesOnTv = value;
            if (!changed) return;
            if (value)
            {
                foreach (var m in Snapshot(includeStarted: false)) BroadcastLink(m);
            }
            else
            {
                BroadcastLink(TvWire.LinkMessage(new SubtitleCleared()));
                BroadcastLink(TvWire.LinkMessage(new ScreenCleared()));
                BroadcastLink(TvWire.LinkMessage(new RegionsCleared()));
            }
            SyncActive();
        }
    }

    /// <summary>
    /// 8787 sunucusunu açar (açıksa bir şey yapmaz; süren açılış beklenir). Port doluysa 6 kez 1 sn arayla dener,
    /// olmazsa işletim sisteminin verdiği boş porta geçer. Gerçek portu döner.
    /// </summary>
    public async Task<int> EnsureLegacyServerAsync(CancellationToken ct = default)
    {
        await legacyStart.WaitAsync(ct).ConfigureAwait(false);
        try
        {
            if (legacy.IsRunning) return legacy.Port;
            Exception? last = null;
            for (var attempt = 1; attempt <= options.PortAttempts; attempt++)
            {
                try
                {
                    var port = legacy.Start(options.LegacyPort);
                    if (attempt > 1) options.Log?.Invoke($"altyazı sunucusu {options.LegacyPort}'de {attempt}. denemede açıldı");
                    return port;
                }
                catch (SocketException e) when (HttpWire.IsAddressInUse(e))
                {
                    last = e;
                    if (attempt < options.PortAttempts)
                        await Task.Delay(options.PortRetryDelay, clock, ct).ConfigureAwait(false);
                }
            }
            options.Log?.Invoke($"{options.LegacyPort} numaralı port kullanılamadı ({last?.Message}); sistemin verdiği başka bir port deneniyor");
            return legacy.Start(0);
        }
        finally
        {
            legacyStart.Release();
        }
    }

    /// <summary>
    /// 47800 girişini açar. Doluysa 6 kez 1 sn arayla dener; olmazsa açılmaz (web TV'ler yalnız 47800'ü tarar),
    /// günlüğe yazılır ve <c>false</c> döner. Eski 8787 yolu çalışmaya devam eder.
    /// </summary>
    public async Task<bool> EnsureIngressAsync(CancellationToken ct = default)
    {
        await ingressStart.WaitAsync(ct).ConfigureAwait(false);
        try
        {
            if (ingress.IsRunning) return true;
            Exception? last = null;
            for (var attempt = 1; attempt <= options.PortAttempts; attempt++)
            {
                try
                {
                    ingress.Start(options.IngressPort);
                    return true;
                }
                catch (SocketException e)
                {
                    last = e;
                    if (!HttpWire.IsAddressInUse(e)) break;
                    if (attempt < options.PortAttempts)
                        await Task.Delay(options.PortRetryDelay, clock, ct).ConfigureAwait(false);
                }
            }
            options.Log?.Invoke($"gönderici girişi {options.IngressPort}'de açılamadı ({last?.Message}); yalnız eski yol çalışıyor");
            return false;
        }
        finally
        {
            ingressStart.Release();
        }
    }

    /// <summary>İki sunucuyu da açar (8787 hatası çağırana gider; 47800 hatası yutulur).</summary>
    public async Task<int> EnsureStartedAsync(CancellationToken ct = default)
    {
        var port = await EnsureLegacyServerAsync(ct).ConfigureAwait(false);
        await EnsureIngressAsync(ct).ConfigureAwait(false);
        return port;
    }

    /// <summary>
    /// Yeni Android TV uygulamasına giden bağlantıyı (yeniden) başlatır. Kayıtlı adres önce denenir; yoksa ya da
    /// bağlanılamazsa aranır. <c>replaced</c> sonrası ancak bu yeniden çağrılınca bağlanılır.
    /// </summary>
    public void ConnectAndroidTv(string? savedHost)
    {
        LinkConnector c;
        lock (gate)
        {
            if (connector is null)
            {
                connector = new LinkConnector(options.Identity, options.Locator, options.Timings, clock, options.IngressPort)
                {
                    OnReady = CatchUp,
                    Backoff = options.ConnectorBackoff ?? [TimeSpan.FromSeconds(1), TimeSpan.FromSeconds(2),
                        TimeSpan.FromSeconds(4), TimeSpan.FromSeconds(8)],
                };
                connector.HostFound += h =>
                {
                    options.Log?.Invoke($"Android TV yeni adreste bulundu: {h}");
                    AndroidTvHostFound?.Invoke(h);
                };
                var port = connector.Port;
                connector.PeerConnected += p => PeerConnected(TvLinkKind.AndroidTv, port, p);
                connector.PeerEnded += (p, end) => PeerEnded(TvLinkKind.AndroidTv, port, p, end);
                connector.StateChanged += s =>
                {
                    LogAndroidState(s);
                    if (s == LinkConnectorState.Connected && connector?.Connected is { } info) ReportInfo(info);
                    try { AndroidTvStateChanged?.Invoke(s); } catch (Exception) { }
                    NotifyCount(force: false);
                };
            }
            c = connector;
        }
        c.Start(savedHost);
    }

    /// <summary>Giden bağlantıyı bırakır.</summary>
    public void DisconnectAndroidTv() => connector?.Stop();

    /// <summary>Android TV aramasının günlükteki son kaydı (aynı durum en çok 5 dakikada bir yazılır).</summary>
    public static readonly TimeSpan AndroidSearchLogEvery = TimeSpan.FromMinutes(5);

    DateTimeOffset? androidSearchSince;
    DateTimeOffset androidSearchLogged;

    /// <summary>
    /// Android TV bağlantısının durumu altyazı günlüğüne: arama başlayınca bir kez, sürerse 5 dakikada bir; başka
    /// gönderici bağlantıyı alınca ya da TV uygulaması güncelleme isteyince. Bağlanınca arama kaydı sıfırlanır.
    /// </summary>
    void LogAndroidState(LinkConnectorState state)
    {
        var now = clock.GetUtcNow();
        switch (state)
        {
            case LinkConnectorState.Connected:
                if (androidSearchSince is { } since && now - since >= TimeSpan.FromSeconds(30))
                    options.Log?.Invoke($"Android TV {(int)(now - since).TotalSeconds} sn aradıktan sonra bulundu");
                androidSearchSince = null;
                break;
            case LinkConnectorState.Searching:
                if (androidSearchSince is null)
                {
                    androidSearchSince = now;
                    androidSearchLogged = now;
                    options.Log?.Invoke($"Android TV aranıyor: kayıtlı adres ({connector?.Host ?? "yok"}) cevap vermedi");
                }
                else if (now - androidSearchLogged >= AndroidSearchLogEvery)
                {
                    androidSearchLogged = now;
                    options.Log?.Invoke($"Android TV hâlâ bulunamadı ({(int)(now - androidSearchSince.Value).TotalMinutes} dk); TV'de Nino TV açık ve aynı ağda mı");
                }
                break;
            case LinkConnectorState.Replaced:
                options.Log?.Invoke("Android TV bağlantısını başka bir gönderici aldı (ör. telefondaki Nino); bu bilgisayar yeni oturuma kadar bağlanmaz");
                break;
            case LinkConnectorState.UpdateRequired:
                options.Log?.Invoke("Android TV uygulaması bu sürümle konuşamıyor; TV uygulaması güncellenmeli");
                break;
        }
    }

    /// <summary>Olayı bütün çıkışlara yollar.</summary>
    public void Send(TvEvent e)
    {
        var duplicateStyle = false;
        if (e is ScreenShown screen)
        {
            e = TvWire.FitScreen(screen, out var dropped);
            if (dropped > 0) options.Log?.Invoke($"ekran çevirisi 16 KB'a sığmadı; TV'ye giderken son {dropped} öğe atıldı");
        }

        if (TvWire.Local(e) is { } local)
        {
            try { LocalEvent?.Invoke(local); } catch (Exception) { }
        }

        string message;
        bool toTv;
        lock (gate)
        {
            var now = clock.GetUtcNow();
            long? id = null;
            switch (e)
            {
                case SubtitleShown s:
                    id = ++showCounter;
                    s = TvWire.FitShow(s, id);
                    e = s;
                    lastShowId = id;
                    lastShow = (s, id.Value, now);
                    break;
                case SubtitleCleared:
                    id = lastShowId;
                    lastShow = null;
                    break;
                case ScreenShown { Overlay: true } sc:
                    lastOverlay = sc.Items.Count > 0 ? (sc, now) : null;
                    break;
                case ScreenCleared:
                    lastOverlay = null;
                    break;
                case StyleChanged st:
                    // Yeni protokolde görünüm yalnız değişince gider (bağlanana zaten son görünüm verilir).
                    if (lastStyle is not null && lastStyle.Style == st.Style) duplicateStyle = true;
                    lastStyle = st;
                    break;
                case TranslationStarted:
                    running = true;
                    startedAt = now;
                    break;
                case TranslationStopped:
                    running = false;
                    startedAt = null;
                    lastShow = null;
                    lastOverlay = null;
                    break;
            }
            message = TvWire.LinkMessage(e, id);
            toTv = (subtitlesOnTv || !TvWire.IsSubtitleEvent(e)) && !duplicateStyle;
        }

        if (legacy.IsRunning)
        {
            try { legacy.Send(e); } catch (Exception) { }
        }
        if (toTv) BroadcastLink(message);
        if (e is TranslationStarted or TranslationStopped) SyncActive();
    }

    /// <summary>Etkinlik değiştiyse girişe bildirir ve bağlı web TV'lere <c>state</c> yollar (kapıdan bağımsız).</summary>
    void SyncActive()
    {
        bool now;
        lock (gate)
        {
            now = running && subtitlesOnTv;
            if (now == senderActive) return;
            senderActive = now;
        }
        ingress.Active = now;
        try { ingress.Broadcast(TvWire.StateMessage(now)); } catch (Exception) { }
    }

    /// <summary>TV'ye verilen 8787 adresi: <c>http://&lt;adres ya da 127.0.0.1&gt;:&lt;port&gt;</c>.</summary>
    public string ServerAddress(string? localIp) =>
        $"http://{(string.IsNullOrWhiteSpace(localIp) ? "127.0.0.1" : localIp)}:{(legacy.Port == 0 ? options.LegacyPort : legacy.Port)}";

    /// <summary>Web TV'lerin bağlanacağı adres: <c>ws://&lt;adres&gt;:47800/nino/ws</c>.</summary>
    public string LinkAddress(string? localIp) =>
        $"ws://{(string.IsNullOrWhiteSpace(localIp) ? "127.0.0.1" : localIp)}:{options.IngressPort}/nino/ws";

    /// <summary>
    /// LG/Samsung TV uygulamasının açılış parametreleri (JSON metni): <c>{"link":…,"server":…}</c>. Eski TV
    /// uygulaması <c>server</c>'ı, yeni web TV <c>link</c>'i kullanır. Giriş açılamadıysa yalnız <c>server</c>.
    /// </summary>
    public string LaunchParameters(string? localIp)
    {
        var o = new WireObject { ["server"] = ServerAddress(localIp) };
        if (ingress.IsRunning) o["link"] = LinkAddress(localIp);
        return o.ToString();
    }

    /// <summary>OBS adresleri: localhost ve (varsa) ağ adresiyle.</summary>
    public (string Local, string? Network) ObsAddresses(string? lanIp)
    {
        var port = legacy.Port == 0 ? options.LegacyPort : legacy.Port;
        return ($"http://localhost:{port}/obs", string.IsNullOrWhiteSpace(lanIp) ? null : $"http://{lanIp}:{port}/obs");
    }

    public async ValueTask DisposeAsync()
    {
        legacy.Stop();
        ingress.Stop();
        if (connector is { } c) await c.DisposeAsync().ConfigureAwait(false);
    }

    void BroadcastLink(string message)
    {
        try { ingress.Broadcast(message); } catch (Exception) { }
        try { connector?.Send(message); } catch (Exception) { }
    }

    /// <summary>
    /// Yeni hazır olan TV'ye sırayla: son stil, (son 20 sn içinde başladıysa) started, hâlâ ekranda olması gereken show
    /// ve örtü.
    /// </summary>
    void CatchUp(LinkPeer peer)
    {
        foreach (var m in Snapshot(includeStarted: true)) peer.Send(m);
    }

    /// <summary>Girişe bağlanan web TV: hazırlık mesajları, sonra gönderici durumu.</summary>
    void IngressReady(LinkPeer peer)
    {
        CatchUp(peer);
        bool active;
        lock (gate) active = senderActive;
        peer.Send(TvWire.StateMessage(active));
    }

    List<string> Snapshot(bool includeStarted)
    {
        var list = new List<string>();
        lock (gate)
        {
            var now = clock.GetUtcNow();
            if (subtitlesOnTv && lastStyle is not null) list.Add(TvWire.LinkMessage(lastStyle));
            if (includeStarted && running && startedAt is { } at && now - at <= StartedReplayWindow)
                list.Add(TvWire.LinkMessage(new TranslationStarted()));
            if (!subtitlesOnTv) return list;
            if (lastShow is { } show && Remaining(show.Show.DurationMs, show.At, now) is { } left)
                list.Add(TvWire.LinkMessage(show.Show, show.Id, left));
            if (lastOverlay is { } overlay && Remaining(overlay.Screen.DurationMs, overlay.At, now) is { } rest)
                list.Add(TvWire.LinkMessage(overlay.Screen, durationOverrideMs: rest));
        }
        return list;
    }

    static int? Remaining(int durationMs, DateTimeOffset at, DateTimeOffset now)
    {
        var left = durationMs - (now - at).TotalMilliseconds;
        return left > 0 ? (int)Math.Ceiling(left) : null;
    }

    int IngressPortNow => ingress.Port == 0 ? options.IngressPort : ingress.Port;

    TimeSpan SilenceLimit => (options.Timings ?? LinkTimings.Default).SilenceLimit;

    void PeerConnected(TvLinkKind kind, int port, LinkPeer peer)
    {
        var info = peer.Info;
        var took = peer.ReadyAt is { } ready && peer.StartedAt is { } start ? ready - start : TimeSpan.Zero;
        RaiseConnected(new TvLinkConnected(peer.Id, kind, port, peer.Address, info?.Model, info?.AppVersion, took));
    }

    void PeerEnded(TvLinkKind kind, int port, LinkPeer peer, LinkEnd end)
    {
        var now = clock.GetUtcNow();
        var info = peer.Info;
        if (peer.ReadyAt is { } ready)
        {
            RaiseDropped(new TvLinkDropped(peer.Id, kind, port, peer.Address, ReasonOf(end), true, now - ready,
                info?.Model, info?.AppVersion));
            return;
        }
        // Hazır olmadan biten bağlantı yalnız el sıkışma başarısızsa bildirilir (ortak sürümle yeniden denenecekse değil).
        string? detail = end switch
        {
            LinkEnd.NoWelcome => TvLinkReasons.NoWelcome,
            LinkEnd.VersionUnsupported when peer.SuggestedVersion is null => TvLinkReasons.VersionUnsupported,
            _ => null,
        };
        if (detail is null) return;
        var started = peer.StartedAt ?? now;
        RaiseDropped(new TvLinkDropped(peer.Id, kind, port, peer.Address, TvLinkEndReason.Handshake, false, now - started,
            null, null, detail));
    }

    /// <summary>Bağlantının bitiş biçiminden neden.</summary>
    internal static TvLinkEndReason ReasonOf(LinkEnd end) => end switch
    {
        LinkEnd.Closed => TvLinkEndReason.Closed,
        LinkEnd.Silent => TvLinkEndReason.Silence,
        LinkEnd.WriteFailed => TvLinkEndReason.WriteFailed,
        LinkEnd.Replaced => TvLinkEndReason.Replaced,
        LinkEnd.Stopped => TvLinkEndReason.Stopped,
        LinkEnd.NoWelcome or LinkEnd.VersionUnsupported => TvLinkEndReason.Handshake,
        _ => TvLinkEndReason.Error,
    };

    void RaiseConnected(TvLinkConnected e)
    {
        lock (gate) handshakeStreak.Remove(e.Kind);
        options.Log?.Invoke(TvLinkReasons.ConnectedLine(e));
        try { TvConnected?.Invoke(e); } catch (Exception) { }
    }

    void RaiseDropped(TvLinkDropped e)
    {
        // Yeniden deneme döngüsünde art arda gelen el sıkışma hataları günlüğe bir kez yazılır.
        bool log;
        lock (gate) log = e.Reason != TvLinkEndReason.Handshake || handshakeStreak.Add(e.Kind);
        if (log) options.Log?.Invoke(TvLinkReasons.DroppedLine(e, SilenceLimit));
        try { TvDropped?.Invoke(e); } catch (Exception) { }
    }

    void ReportInfo(TvLinkInfo info)
    {
        try { TvInfoReported?.Invoke(info); } catch (Exception) { }
    }

    void NotifyCount(bool force)
    {
        var count = TvCount;
        bool changed;
        lock (gate)
        {
            changed = count != lastCount;
            lastCount = count;
        }
        if (!changed && !force) return;
        try { TvCountChanged?.Invoke(count); } catch (Exception) { }
    }
}
