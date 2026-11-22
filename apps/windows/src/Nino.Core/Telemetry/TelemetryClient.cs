// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Globalization;
using System.IO.Compression;
using System.Text.Json.Nodes;
using Nino.Core.Data;

namespace Nino.Core.Telemetry;

/// <summary>Ölçüm istemcisinin kurulum bilgileri.</summary>
/// <param name="Folder">Disk kuyruğunun ve çalışma işaretinin klasörü (<c>&lt;veri klasörü&gt;\telemetry</c>).</param>
/// <param name="Install">Kurulum kimliği (havuzdakiyle aynı UUID).</param>
/// <param name="Context">Her gönderimde o anki <c>ctx</c>.</param>
/// <param name="Sender">HTTP gönderici (testte sahte).</param>
public sealed record TelemetryOptions(string Folder, string Install, Func<TelemetryContext> Context,
    ITelemetrySender Sender)
{
    /// <summary>Saat (testte sahte).</summary>
    public TimeProvider Clock { get; init; } = TimeProvider.System;

    /// <summary>Ağ var mı; yoksa hiçbir şey denenmez. Verilmezse hep var.</summary>
    public Func<bool>? IsOnline { get; init; }
}

/// <summary>Bir gönderim denemesinin sonucu.</summary>
public enum FlushOutcome
{
    /// <summary>Gönderilecek bir şey yoktu.</summary>
    Nothing,
    /// <summary>Hepsi gönderildi (ya da sunucu reddettiği için silindi).</summary>
    Sent,
    /// <summary>Ölçüm kapalı, ağ yok ya da bekleme süresi dolmadı: denenmedi.</summary>
    Skipped,
    /// <summary>Sunucu hazır değil ya da hız sınırı: saklandı, sonra yeniden denenecek.</summary>
    Deferred,
}

/// <summary>
/// Ölçüm istemcisi: olayları diskteki kuyrukta tutar, toplu ve gzip'li gönderir, cevaba göre siler/böler/bekler.
/// Kullanıcı ayarıyla kapatılamaz; yalnız sunucunun <c>telemetry.enabled = false</c> ayarı durdurur (kuyruk silinir).
/// </summary>
public sealed class TelemetryClient
{
    /// <summary>Diskteki kuyruğun en çok olayı.</summary>
    public const int MaxQueue = 2000;

    /// <summary>Bir gönderim parçasındaki en çok olay.</summary>
    public const int MaxBatchEvents = 300;

    /// <summary>Kuyrukta bu kadar olay birikince gönderim istenir.</summary>
    public const int FlushThreshold = 100;

    /// <summary>Sıkıştırılmış gövde sınırı.</summary>
    public const int MaxCompressedBytes = 64 * 1024;

    /// <summary>Açılmış gövde sınırı.</summary>
    public const int MaxRawBytes = 512 * 1024;

    const string QueueFile = "queue.json";

    readonly TelemetryOptions _options;
    readonly string _queuePath;
    readonly object _gate = new();
    readonly SemaphoreSlim _sending = new(1, 1);
    readonly SemaphoreSlim _wake = new(0, int.MaxValue);
    readonly List<TelemetryEvent> _queue = [];
    readonly List<Batch> _batches = [];
    TelemetryConfig _config = TelemetryConfig.Default;
    string _day = "";
    int _dayCount;
    int _failures;
    long _nextAttempt;
    bool _dirty;
    DateTimeOffset _lastSave = DateTimeOffset.MinValue;

    sealed record Batch(string Id, List<TelemetryEvent> Events);

    /// <param name="options">Kurulum bilgileri.</param>
    public TelemetryClient(TelemetryOptions options)
    {
        _options = options;
        _queuePath = Path.Combine(options.Folder, QueueFile);
        Marker = new CrashMarker(Path.Combine(options.Folder, CrashMarker.FileName), options.Clock);
        LoadQueue();
    }

    /// <summary>Çalışma işareti.</summary>
    public CrashMarker Marker { get; }

    /// <summary>Geçerli uzak ayar.</summary>
    public TelemetryConfig Config
    {
        get { lock (_gate) return _config; }
    }

    /// <summary>Kuyruktaki (henüz parçaya girmemiş) olay sayısı.</summary>
    public int QueuedCount
    {
        get { lock (_gate) return _queue.Count; }
    }

    /// <summary>Parçaya girmiş, gönderilmeyi bekleyen olay sayısı.</summary>
    public int PendingCount
    {
        get { lock (_gate) return _queue.Count + _batches.Sum(b => b.Events.Count); }
    }

    /// <summary>Kuyruk eşiğe ulaşınca (gönderim istenir) tetiklenir.</summary>
    public event Action? FlushRequested;

    DateTimeOffset Now => _options.Clock.GetUtcNow();

    // ---- Olay kaydı ----

    /// <summary>
    /// Açılışta: önceki çalışma işareti duruyorsa <c>crash</c> olayı, sonra <c>launch</c>; yeni işaret yazılır.
    /// </summary>
    public void AppLaunched(string version, long? launchMs = null)
    {
        if (Marker.ReadPrevious() is { } previous)
            Record(TelemetryEvent.Crash(Now, previous.Code, previous.Where,
                previous.Version.Length > 0 ? previous.Version : version, previous.UptimeSeconds));
        Record(TelemetryEvent.Launch(Now, launchMs));
        Marker.Start(version);
    }

    /// <summary>Düzgün kapanış: işaret silinir. Ardından kısa zaman aşımlı <see cref="FlushAsync"/> çağrılabilir.</summary>
    public void AppExiting()
    {
        Persist();
        Marker.Stop();
    }

    /// <summary>Yakalanan hata (yalnız kod).</summary>
    public void RecordError(string code, int? http = null) => Record(TelemetryEvent.Error(Now, code, http));

    /// <summary>Bir olayı kuyruğa ekler.</summary>
    public void Record(TelemetryEvent e)
    {
        bool wantFlush;
        lock (_gate)
        {
            if (!_config.Enabled) return;
            if (e.Kind == "session" && !_config.SamplesTimings(_options.Install)) e.Body.Remove("h");

            if (e.Kind == "error" && _queue.Count > 0 && _queue[^1].SameErrorAs(e))
            {
                _queue[^1].IncrementCount(e.Body["n"]?.GetValue<int>() ?? 1);
                SaveSoon(force: false);
                return;
            }

            var today = Now.UtcDateTime.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
            if (_day != today)
            {
                _day = today;
                _dayCount = 0;
            }
            if (!e.IsExemptFromDailyLimit)
            {
                if (_dayCount >= _config.MaxPerDay) return;
                _dayCount++;
            }

            _queue.Add(e);
            while (_queue.Count > MaxQueue)
            {
                var oldest = _queue.FindIndex(x => !x.IsCrash);
                _queue.RemoveAt(oldest >= 0 ? oldest : 0);
            }
            SaveSoon(force: e.IsCrash);
            wantFlush = _queue.Count >= FlushThreshold;
        }
        if (wantFlush)
        {
            _wake.Release();
            FlushRequested?.Invoke();
        }
    }

    // ---- Uzak ayar ----

    /// <summary>Uzak ayarı uygular; kapatılırsa kuyruk silinir.</summary>
    public void ApplyRemoteConfig(TelemetryConfig config)
    {
        lock (_gate)
        {
            _config = config;
            if (config.Enabled) return;
            _queue.Clear();
            _batches.Clear();
            _failures = 0;
            _nextAttempt = 0;
            try { File.Delete(_queuePath); }
            catch (Exception e) when (FileIo.IsIoError(e)) { }
        }
        Marker.Stop();
    }

    /// <summary>Sunucu cevabındaki <c>telemetry</c> bloğunu (varsa) uygular.</summary>
    public void ApplyRemoteConfigJson(string? json)
    {
        if (TelemetryConfig.FromResponse(json, Config) is { } config) ApplyRemoteConfig(config);
        if (json is not null) RemoteConfigReceived?.Invoke(json);
    }

    /// <summary>
    /// Uzak ayar cevabı geldi (<c>/v1/config</c> ya da <c>/v1/events</c>): ham JSON, öbür bloklar (ör. <c>telemetry.diag</c>)
    /// için. Gönderim iş parçacığından gelebilir.
    /// </summary>
    public event Action<string>? RemoteConfigReceived;

    // ---- Gönderim ----

    /// <summary>
    /// Bekleyenleri gönderir. 200 ve 400 parçayı siler; 413 ikiye böler (tek olaysa siler); 404 dahil öbür her
    /// sonuç ve ağ hatası parçayı aynı kimlikle saklar ve 1, 2, 4… dk (en çok 1 sa) ya da <c>retry-after</c> bekler.
    /// </summary>
    public async Task<FlushOutcome> FlushAsync(CancellationToken cancellationToken = default, bool ignoreBackoff = false)
    {
        lock (_gate)
        {
            if (!_config.Enabled) return FlushOutcome.Skipped;
            if (!ignoreBackoff && Now.ToUnixTimeSeconds() < _nextAttempt) return FlushOutcome.Skipped;
        }
        if (_options.IsOnline is { } online && !online()) return FlushOutcome.Skipped;

        await _sending.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            var sentAny = false;
            for (var guard = 0; guard < 64; guard++)
            {
                Batch? batch;
                lock (_gate)
                {
                    if (!_config.Enabled) return FlushOutcome.Skipped;
                    if (_batches.Count == 0 && _queue.Count > 0)
                    {
                        var take = Math.Min(MaxBatchEvents, _queue.Count);
                        _batches.Add(new Batch(Guid.NewGuid().ToString("D"), _queue.GetRange(0, take)));
                        _queue.RemoveRange(0, take);
                        SaveQueue();
                    }
                    batch = _batches.Count > 0 ? _batches[0] : null;
                }
                if (batch is null) return sentAny ? FlushOutcome.Sent : FlushOutcome.Nothing;

                var raw = FileIo.Utf8.GetBytes(BuildBody(batch.Id, batch.Events).ToJsonString());
                var body = Gzip(raw);
                if (raw.Length > MaxRawBytes || body.Length > MaxCompressedBytes)
                {
                    SplitOrDrop(batch);
                    continue;
                }

                TelemetryResponse response;
                try
                {
                    response = await _options.Sender.SendAsync(body, gzipped: true, cancellationToken)
                        .ConfigureAwait(false);
                }
                catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
                {
                    throw;
                }
                catch (Exception)
                {
                    Defer(null);
                    return FlushOutcome.Deferred;
                }

                switch (response.Status)
                {
                    case 200:
                        Remove(batch);
                        lock (_gate) _failures = 0;
                        ApplyRemoteConfigJson(response.Body);
                        sentAny = true;
                        break;
                    case 400:
                        Remove(batch);
                        sentAny = true;
                        break;
                    case 413:
                        SplitOrDrop(batch);
                        break;
                    case 429:
                        Defer(response.RetryAfter ?? TimeSpan.FromMinutes(1));
                        return FlushOutcome.Deferred;
                    default:
                        Defer(response.RetryAfter);
                        return FlushOutcome.Deferred;
                }
            }
            return sentAny ? FlushOutcome.Sent : FlushOutcome.Nothing;
        }
        finally
        {
            _sending.Release();
        }
    }

    /// <summary>
    /// Arka plan döngüsü: <c>flushSeconds</c>'ta bir ya da eşik dolunca gönderir; çalışma işaretini tazeler.
    /// </summary>
    public async Task RunAsync(CancellationToken cancellationToken)
    {
        try
        {
            while (true)
            {
                var wait = TimeSpan.FromSeconds(Config.FlushSeconds);
                await _wake.WaitAsync(wait, cancellationToken).ConfigureAwait(false);
                Marker.Touch();
                lock (_gate)
                    if (_dirty) SaveQueue();
                try { await FlushAsync(cancellationToken).ConfigureAwait(false); }
                catch (Exception e) when (e is not OperationCanceledException) { }
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            // kapanış
        }
    }

    /// <summary>Gönderim gövdesi (<c>{"v":1,"batch","install","ctx","events"}</c>).</summary>
    public JsonObject BuildBody(string batchId, IEnumerable<TelemetryEvent> events)
    {
        var list = new JsonArray();
        foreach (var e in events) list.Add(e.Body.DeepClone());
        return new JsonObject
        {
            ["v"] = 1,
            ["batch"] = batchId,
            ["install"] = _options.Install,
            ["ctx"] = _options.Context().ToJson(),
            ["events"] = list,
        };
    }

    static byte[] Gzip(byte[] raw)
    {
        using var output = new MemoryStream();
        using (var gzip = new GZipStream(output, CompressionLevel.Optimal, leaveOpen: true)) gzip.Write(raw);
        return output.ToArray();
    }

    void Remove(Batch batch)
    {
        lock (_gate)
        {
            _batches.Remove(batch);
            SaveQueue();
        }
    }

    void SplitOrDrop(Batch batch)
    {
        lock (_gate)
        {
            var index = _batches.IndexOf(batch);
            if (index < 0) return;
            _batches.RemoveAt(index);
            if (batch.Events.Count > 1)
            {
                var half = batch.Events.Count / 2;
                _batches.Insert(index, new Batch(Guid.NewGuid().ToString("D"), batch.Events.GetRange(half, batch.Events.Count - half)));
                _batches.Insert(index, new Batch(Guid.NewGuid().ToString("D"), batch.Events.GetRange(0, half)));
            }
            SaveQueue();
        }
    }

    void Defer(TimeSpan? retryAfter)
    {
        lock (_gate)
        {
            long wait;
            if (retryAfter is { } r) wait = Math.Max(1, (long)Math.Ceiling(r.TotalSeconds));
            else
            {
                _failures++;
                wait = (long)Math.Min(3600, 60 * Math.Pow(2, Math.Min(_failures - 1, 10)));
            }
            _nextAttempt = Now.ToUnixTimeSeconds() + wait;
            SaveQueue();
        }
    }

    /// <summary>Bir sonraki denemenin en erken zamanı (Unix sn; 0: hemen).</summary>
    public long NextAttemptUnix
    {
        get { lock (_gate) return _nextAttempt; }
    }

    // ---- Disk ----

    /// <summary>Kuyruğu hemen diske yazar (kapanırken ya da test için).</summary>
    public void Persist()
    {
        lock (_gate) SaveQueue();
    }

    // Küçük kuyruk her olayda hemen yazılır. Kuyruk büyüdüyse (2000 olaylık dosya her olayda yeniden yazılmasın) en çok
    // iki saniyede bir yazılır; arada kalan olaylar için iki saniye sonra bir kez daha yazılır. Çökme hep hemen yazılır.
    void SaveSoon(bool force)
    {
        if (force || _queue.Count < LargeQueue || Now - _lastSave >= SaveInterval)
        {
            SaveQueue();
            return;
        }
        _dirty = true;
        _trailingSave ??= _options.Clock.CreateTimer(_ =>
        {
            lock (_gate)
            {
                _trailingSave?.Dispose();
                _trailingSave = null;
                if (_dirty) SaveQueue();
            }
        }, null, SaveInterval, Timeout.InfiniteTimeSpan);
    }

    const int LargeQueue = 200;
    static readonly TimeSpan SaveInterval = TimeSpan.FromSeconds(2);
    ITimer? _trailingSave;

    void SaveQueue()
    {
        _dirty = false;
        _lastSave = Now;
        var batches = new JsonArray();
        foreach (var b in _batches)
            batches.Add(new JsonObject { ["id"] = b.Id, ["events"] = Events(b.Events) });
        var root = new JsonObject
        {
            ["events"] = Events(_queue),
            ["batches"] = batches,
            ["day"] = _day,
            ["dayCount"] = _dayCount,
            ["failures"] = _failures,
            ["nextAttempt"] = _nextAttempt,
        };
        try { FileIo.WriteAtomic(_queuePath, root.ToJsonString()); }
        catch (Exception e) when (FileIo.IsIoError(e)) { }
    }

    static JsonArray Events(IEnumerable<TelemetryEvent> events)
    {
        var a = new JsonArray();
        foreach (var e in events) a.Add(e.Body.DeepClone());
        return a;
    }

    void LoadQueue()
    {
        try
        {
            if (!File.Exists(_queuePath)) return;
            if (JsonNode.Parse(File.ReadAllText(_queuePath, FileIo.Utf8)) is not JsonObject root) return;
            if (root["events"] is JsonArray events)
                _queue.AddRange(events.Select(TelemetryEvent.FromJson).OfType<TelemetryEvent>().TakeLast(MaxQueue));
            if (root["batches"] is JsonArray batches)
                foreach (var b in batches.OfType<JsonObject>())
                {
                    var id = b["id"] is JsonValue v && v.TryGetValue<string>(out var s) && Guid.TryParse(s, out _) ? s : null;
                    var list = (b["events"] as JsonArray)?.Select(TelemetryEvent.FromJson).OfType<TelemetryEvent>().ToList();
                    if (id is not null && list is { Count: > 0 }) _batches.Add(new Batch(id, list));
                }
            _day = root["day"] is JsonValue d && d.TryGetValue<string>(out var day) ? day : "";
            _dayCount = root["dayCount"] is JsonValue c && c.TryGetValue<int>(out var count) ? count : 0;
            _failures = root["failures"] is JsonValue f && f.TryGetValue<int>(out var fails) ? fails : 0;
            _nextAttempt = root["nextAttempt"] is JsonValue n && n.TryGetValue<long>(out var next) ? next : 0;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException
                                      or System.Text.Json.JsonException or InvalidOperationException)
        {
            _queue.Clear();
            _batches.Clear();
        }
    }
}
