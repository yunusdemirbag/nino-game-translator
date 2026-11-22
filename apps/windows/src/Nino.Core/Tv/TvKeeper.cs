// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.Core.Tv;

/// <summary>Bir TV'ye (adresiyle ve anahtarıyla) uzaktan kumanda bağlantısı açan işlev.</summary>
public delegate Task<ITvRemote> TvConnect(string host, string key, CancellationToken ct);

/// <summary>Bir markadaki TV'leri arayan işlev.</summary>
public delegate Task<IReadOnlyList<FoundTv>> TvFind(TvBrand brand, CancellationToken ct);

/// <summary>Gerçek bağlantı ve arama işlevleri.</summary>
public static class TvRemoteFactory
{
    /// <summary>Markaya göre LG SSAP ya da Samsung bağlantısı (Samsung istemci adı verilir).</summary>
    public static TvConnect For(TvBrand brand, string samsungClientName = SamsungRemote.ClientName) => brand switch
    {
        TvBrand.Lg => async (host, key, ct) => await LgRemote.ConnectAsync(host, key, ct).ConfigureAwait(false),
        TvBrand.Samsung => async (host, key, ct) =>
            await SamsungRemote.ConnectAsync(host, samsungClientName, key, ct).ConfigureAwait(false),
        _ => (_, _, _) => throw new NotSupportedException("Android TV uzaktan denetlenmez"),
    };

    public static TvFind Finder(TvDiscovery? discovery = null)
    {
        var d = discovery ?? new TvDiscovery();
        return (brand, ct) => d.FindAsync(brand, ct);
    }
}

/// <summary>Eşleşme sonucu: saklanacak anahtar ve TV uygulamasının açılıp açılamadığı.</summary>
public sealed record PairResult(string Key, bool Launched);

/// <summary>"Bağlan": TV ile eşleşir ve TV uygulamasını açmayı dener.</summary>
public static class TvPairing
{
    /// <summary>
    /// LG: bağlan (client-key), uygulamayı aç; açılamazsa yine başarılı ama <c>Launched=false</c>. Samsung: bağlan
    /// (jeton), aç (hata yutulur), hep açıldı sayılır. Android TV: hiçbir şey yapılmaz.
    /// </summary>
    public static async Task<PairResult> PairAsync(TvRecord tv, string? savedKey, string launchParameters,
        TvConnect? connect = null, CancellationToken ct = default)
    {
        if (tv.Brand == TvBrand.AndroidTv) return new PairResult("", true);
        connect ??= TvRemoteFactory.For(tv.Brand);
        await using var remote = await connect(tv.Host, savedKey ?? "", ct).ConfigureAwait(false);
        var launched = true;
        try
        {
            await remote.LaunchAsync(launchParameters, ct).ConfigureAwait(false);
        }
        catch (Exception) when (!ct.IsCancellationRequested)
        {
            launched = tv.Brand != TvBrand.Lg;
        }
        return new PairResult(TvRecord.KeyToStore(savedKey, remote.Key), launched);
    }
}

/// <summary>
/// Konum izleyici: kayıtlı adrese bağlanılamazsa (son aramadan bu yana 30 sn geçtiyse) aynı markadaki TV'leri arar;
/// kayıtlı adres listede yoksa aynı adlı tek TV'ye, o da yoksa bulunan tek TV'ye geçer. Tahmin edemezse ilk hata döner.
/// </summary>
public sealed class TvRelocator(TvRecord tv, TvConnect connect, TvFind find, TimeProvider? clock = null)
{
    readonly TimeProvider clock = clock ?? TimeProvider.System;
    DateTimeOffset? lastSearch;

    /// <summary>Arama aralığı.</summary>
    public TimeSpan SearchEvery { get; init; } = TimeSpan.FromSeconds(30);

    /// <summary>Güncel TV kaydı.</summary>
    public TvRecord Tv { get; private set; } = tv;

    /// <summary>TV yeni adreste bulundu (uygulama kaydı güncellesin).</summary>
    public event Action<TvRecord>? Moved;

    public async Task<ITvRemote> ConnectAsync(string key, CancellationToken ct = default)
    {
        Exception first;
        try
        {
            return await connect(Tv.Host, key, ct).ConfigureAwait(false);
        }
        catch (Exception e) when (!ct.IsCancellationRequested)
        {
            first = e;
        }

        var now = clock.GetUtcNow();
        if (lastSearch is { } last && now - last < SearchEvery) throw first;
        lastSearch = now;

        IReadOnlyList<FoundTv> found;
        try { found = await find(Tv.Brand, ct).ConfigureAwait(false); }
        catch (Exception) when (!ct.IsCancellationRequested) { throw first; }
        var host = PickNewHost(Tv, found) ?? throw first;

        var remote = await connect(host, key, ct).ConfigureAwait(false);
        Tv = Tv with { Host = host };
        try { Moved?.Invoke(Tv); } catch (Exception) { }
        return remote;
    }

    /// <summary>Aramada yeni adres seçimi (yoksa <c>null</c>).</summary>
    public static string? PickNewHost(TvRecord tv, IReadOnlyList<FoundTv> found)
    {
        var same = found.Where(f => f.Brand == tv.Brand).ToList();
        if (same.Any(f => f.Host == tv.Host)) return null;
        var named = same.Where(f => f.Name == tv.Name).ToList();
        if (named.Count == 1) return named[0].Host;
        return same.Count == 1 ? same[0].Host : null;
    }
}

/// <summary><see cref="TvKeeper"/> ayarları.</summary>
public sealed record TvKeeperOptions
{
    public required TvRecord Tv { get; init; }

    /// <summary>Saklı anahtar/jeton.</summary>
    public string Key { get; init; } = "";

    /// <summary>Güncel açılış parametreleri (JSON metni; ör. <c>{"link":…,"server":…}</c>).</summary>
    public required Func<string> LaunchParameters { get; init; }

    /// <summary>TV uygulaması şu an bilgisayara bağlı mı (bağlı TV sayısı &gt; 0).</summary>
    public Func<bool> TvAppConnected { get; init; } = () => false;

    /// <summary>TV yeni (boş olmayan, farklı) jeton verdi; saklanmalı.</summary>
    public Action<string>? KeyChanged { get; init; }

    /// <summary>TV yeni adreste bulundu.</summary>
    public Action<TvRecord>? Moved { get; init; }

    public TvConnect? Connect { get; init; }
    public TvFind? Find { get; init; }
    public TimeProvider? Clock { get; init; }
    public TimeSpan Interval { get; init; } = TimeSpan.FromSeconds(5);

    /// <summary>Samsung'da iki açma denemesi arasındaki en kısa süre.</summary>
    public TimeSpan SamsungRetry { get; init; } = TimeSpan.FromSeconds(30);

    /// <summary>Konum izleyicinin arama aralığı.</summary>
    public TimeSpan SearchEvery { get; init; } = TimeSpan.FromSeconds(30);
}

/// <summary>
/// TV bekçisi: çeviri sürerken TV uygulamasını açık tutar. LG'de bağlantı tutulur, TV kendi girişine/yayınına
/// geçtiyse uygulama yeniden açılır. Samsung'da sürekli bağlantı tutulmaz: uygulama bağlı değilse ve son denemeden
/// 30 sn geçtiyse bağlanıp açar, hemen kapatır. Android TV'de hiçbir şey yapmaz. Turlar üst üste binmez ve hata
/// fırlatmaz.
/// </summary>
public sealed class TvKeeper : IAsyncDisposable
{
    readonly TvKeeperOptions options;
    readonly TimeProvider clock;
    readonly TvRelocator relocator;
    readonly SemaphoreSlim turn = new(1, 1);
    readonly object gate = new();
    ITvRemote? remote;
    string key;
    DateTimeOffset? lastSamsungAttempt;
    CancellationTokenSource? run;
    CancellationTokenSource? sleep;
    Task? loop;

    public TvKeeper(TvKeeperOptions options)
    {
        this.options = options;
        clock = options.Clock ?? TimeProvider.System;
        key = options.Key;
        relocator = new TvRelocator(options.Tv, options.Connect ?? TvRemoteFactory.For(options.Tv.Brand),
            options.Find ?? TvRemoteFactory.Finder(), clock) { SearchEvery = options.SearchEvery };
        relocator.Moved += tv => options.Moved?.Invoke(tv);
    }

    /// <summary>Güncel anahtar.</summary>
    public string Key => key;

    /// <summary>Güncel TV kaydı (adres değişmiş olabilir).</summary>
    public TvRecord Tv => relocator.Tv;

    public bool IsRunning => loop is { IsCompleted: false };

    /// <summary>Döngüyü başlatır (ilk tur hemen).</summary>
    public void Start()
    {
        lock (gate)
        {
            if (IsRunning) return;
            run = new CancellationTokenSource();
            loop = LoopAsync(run.Token);
        }
    }

    /// <summary>Döngüyü durdurur, bağlantıyı kapatır.</summary>
    public async Task StopAsync()
    {
        Task? l;
        lock (gate)
        {
            run?.Cancel();
            sleep?.Cancel();
            l = loop;
            loop = null;
        }
        if (l is not null)
        {
            try { await l.ConfigureAwait(false); } catch (Exception) { }
        }
        await DropAsync().ConfigureAwait(false);
    }

    /// <summary>
    /// Uykudan uyanınca ya da TV uygulaması yeni kurulunca: bağlantı kapatılır, Samsung'un son deneme anı silinir,
    /// sonraki tur hemen bağlanıp açar.
    /// </summary>
    public async Task ReconnectAsync()
    {
        await DropAsync().ConfigureAwait(false);
        lock (gate)
        {
            lastSamsungAttempt = null;
            sleep?.Cancel();
        }
    }

    public async ValueTask DisposeAsync() => await StopAsync().ConfigureAwait(false);

    async Task LoopAsync(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            await RunOnceAsync(ct).ConfigureAwait(false);
            CancellationTokenSource s;
            lock (gate) s = sleep = CancellationTokenSource.CreateLinkedTokenSource(ct);
            try { await Task.Delay(options.Interval, clock, s.Token).ConfigureAwait(false); }
            catch (OperationCanceledException) { }
            finally { s.Dispose(); }
        }
    }

    /// <summary>Tek tur (testler doğrudan çağırır). Hata fırlatmaz.</summary>
    public async Task RunOnceAsync(CancellationToken ct = default)
    {
        if (!await turn.WaitAsync(0, ct).ConfigureAwait(false)) return;
        try
        {
            switch (options.Tv.Brand)
            {
                case TvBrand.Lg: await LgTurnAsync(ct).ConfigureAwait(false); break;
                case TvBrand.Samsung: await SamsungTurnAsync(ct).ConfigureAwait(false); break;
            }
        }
        catch (Exception) { }
        finally
        {
            turn.Release();
        }
    }

    /// <summary>TV kendi girişine ya da yayınına geçmiş mi (HDMI, harici giriş, canlı TV).</summary>
    static bool IsTvOwnInput(string appId) =>
        appId == "com.webos.app.livetv"
        || new[] { "com.webos.app.hdmi", "com.webos.app.externalinput" }.Any(p => appId.StartsWith(p, StringComparison.Ordinal));

    async Task LgTurnAsync(CancellationToken ct)
    {
        try
        {
            if (remote is null)
            {
                remote = await relocator.ConnectAsync(key, ct).ConfigureAwait(false);
                RememberKey(remote.Key);
                await remote.LaunchAsync(options.LaunchParameters(), ct).ConfigureAwait(false);
                return;
            }
            var foreground = await remote.ForegroundAppAsync(ct).ConfigureAwait(false);
            if (IsTvOwnInput(foreground)) await remote.LaunchAsync(options.LaunchParameters(), ct).ConfigureAwait(false);
        }
        catch (Exception)
        {
            await DropAsync().ConfigureAwait(false);
        }
    }

    async Task SamsungTurnAsync(CancellationToken ct)
    {
        if (options.TvAppConnected()) return;
        var now = clock.GetUtcNow();
        lock (gate)
        {
            if (lastSamsungAttempt is { } last && now - last < options.SamsungRetry) return;
            lastSamsungAttempt = now;
        }
        try
        {
            await using var r = await relocator.ConnectAsync(key, ct).ConfigureAwait(false);
            RememberKey(r.Key);
            await r.LaunchAsync(options.LaunchParameters(), ct).ConfigureAwait(false);
        }
        catch (Exception) { }
    }

    void RememberKey(string incoming)
    {
        var next = TvRecord.KeyToStore(key, incoming);
        if (next == key) return;
        key = next;
        try { options.KeyChanged?.Invoke(next); } catch (Exception) { }
    }

    async Task DropAsync()
    {
        ITvRemote? r;
        lock (gate)
        {
            r = remote;
            remote = null;
        }
        if (r is not null)
        {
            try { await r.DisposeAsync().ConfigureAwait(false); } catch (Exception) { }
        }
    }
}
