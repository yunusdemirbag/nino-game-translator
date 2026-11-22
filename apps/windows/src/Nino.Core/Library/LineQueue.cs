// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Globalization;
using System.Text;
using System.Text.Json;
using Nino.Core.Data;

namespace Nino.Core.Library;

/// <summary>Satır gönderme kuyruğunun ayarları.</summary>
/// <param name="Folder"><c>%LOCALAPPDATA%\Nino\pool</c>.</param>
/// <param name="Endpoint">Sunucu (null: adres yok, satırlar bekler).</param>
/// <param name="AppVersion">Nino'nun sürümü.</param>
/// <param name="Http">HTTP istemcisi.</param>
/// <param name="Enabled">Açılışta etkin mi (yanlışsa "etkisiz" kip: alır, göndermez, silmez).</param>
/// <param name="LegacyQueueFile">Eski <c>pool.json</c> (varsa bir kez içe aktarılır).</param>
/// <param name="Clock">Saat.</param>
/// <param name="Random">0–1 arası rastgele (bekleme oynaması).</param>
/// <param name="NewId">Yeni kimlik üretici (küçük harf, tireli).</param>
/// <param name="ChunkLines">Parça başına en çok farklı satır.</param>
public sealed record LineQueueOptions(string Folder, Uri? Endpoint, string AppVersion, HttpClient Http,
    bool Enabled = true, string? LegacyQueueFile = null, TimeProvider? Clock = null, Func<double>? Random = null,
    Func<string>? NewId = null, int ChunkLines = 200);

/// <summary>Kuyruğun durum özeti (ayarlar için).</summary>
public sealed record LineQueueStatus(int Pending, int Outbox, int Parked, long Dropped, bool HasEndpoint, string InstallId);

/// <summary>
/// Pakette olmayan İngilizce satırları sunucuya kayıpsız gönderen kuyruk (havuz/paket tarifi §7): her görülme
/// <c>pending.jsonl</c>'a eklenir, dondurulunca <c>outbox\</c> parçalarına dönüşür, <c>/v1/batches</c>'e gider.
/// </summary>
public sealed class LineQueue
{
    /// <summary>Açılıştan ilk denemeye kadar.</summary>
    public static readonly TimeSpan FirstAttemptDelay = TimeSpan.FromSeconds(5);

    /// <summary>Denemeler arası.</summary>
    public static readonly TimeSpan AttemptInterval = TimeSpan.FromMinutes(1);

    /// <summary>Zamanlayıcının n. denemesinden (0'dan) önceki bekleme.</summary>
    public static TimeSpan DelayBeforeAttempt(int attempt) => attempt == 0 ? FirstAttemptDelay : AttemptInterval;

    const long MaxPendingBytes = 64L * 1024 * 1024;
    const long MaxRejectedBytes = 1024 * 1024;
    const int FreezeLines = 200;
    static readonly TimeSpan FreezeAge = TimeSpan.FromSeconds(120);
    const int MaxOutbox = 2000;

    readonly LineQueueOptions _o;
    readonly TimeProvider _clock;
    readonly Func<double> _random;
    readonly Func<string> _newId;
    readonly object _gate = new();
    readonly SemaphoreSlim _sending = new(1, 1);
    readonly List<Seen> _pending = [];
    State _state = new();
    Uri? _endpoint;
    bool _enabled;
    bool _closed;
    long _nextSeq = 1;

    sealed record Seen(long Seq, string Text, string? Game, string? Session, double At);

    sealed class State
    {
        public string Install = "";
        public long FrozenThrough;
        public int Failures;
        public double NextAttempt;
        public double ServerRetryAt;
        public string App = "";
        public long Dropped;
    }

    string Dir(string name) => Path.Combine(_o.Folder, name);
    string PendingPath => Dir("pending.jsonl");
    string StatePath => Dir("state.json");
    string Outbox => Dir("outbox");
    string Parked => Dir("parked");

    /// <summary>Kuyruğu açar (§7.2).</summary>
    public LineQueue(LineQueueOptions options)
    {
        _o = options;
        _clock = options.Clock ?? TimeProvider.System;
        _random = options.Random ?? System.Random.Shared.NextDouble;
        _newId = options.NewId ?? (() => Guid.NewGuid().ToString("D"));
        _endpoint = options.Endpoint;
        _enabled = options.Enabled;
        Open();
    }

    double Now => PoolHttp.Unix(_clock.GetUtcNow());

    void Open()
    {
        Directory.CreateDirectory(Outbox);
        Directory.CreateDirectory(Parked);
        _state = ReadState() ?? new State();
        if (_state.Install.Length == 0) _state.Install = _newId();

        foreach (var file in SafeFiles(Outbox))
            if (ReadChunk(file) is { } chunk && chunk.UpTo > _state.FrozenThrough) _state.FrozenThrough = chunk.UpTo;

        if (_state.App != _o.AppVersion)
        {
            foreach (var file in SafeFiles(Parked))
                TryIo(() => File.Move(file, Path.Combine(Outbox, Path.GetFileName(file)), true));
            _state.App = _o.AppVersion;
        }
        _state.Failures = 0;
        _state.NextAttempt = 0;

        TrimPartialLine();
        long maxSeq = 0;
        if (File.Exists(PendingPath))
            foreach (var line in SafeLines(PendingPath))
                if (ParseSeen(line) is { } seen)
                {
                    maxSeq = Math.Max(maxSeq, seen.Seq);
                    if (seen.Seq > _state.FrozenThrough) _pending.Add(seen);
                }
        _nextSeq = Math.Max(maxSeq, _state.FrozenThrough) + 1;
        if (_enabled && _o.LegacyQueueFile is { } legacy && File.Exists(legacy)) ImportLegacy(legacy);
        WriteState();
    }

    State? ReadState()
    {
        if (!File.Exists(StatePath)) return null;
        try
        {
            using var doc = JsonDocument.Parse(File.ReadAllBytes(StatePath));
            var r = doc.RootElement;
            var s = new State
            {
                Install = r.GetProperty("install").GetString() ?? "",
                FrozenThrough = r.TryGetProperty("frozenThrough", out var f) ? f.GetInt64() : 0,
                Failures = r.TryGetProperty("failures", out var fa) ? fa.GetInt32() : 0,
                NextAttempt = r.TryGetProperty("nextAttempt", out var n) ? n.GetDouble() : 0,
                ServerRetryAt = r.TryGetProperty("serverRetryAt", out var sr) ? sr.GetDouble() : 0,
                App = r.TryGetProperty("app", out var a) ? a.GetString() ?? "" : "",
                Dropped = r.TryGetProperty("dropped", out var d) ? d.GetInt64() : 0,
            };
            if (s.Install.Length == 0) throw new JsonException("install boş");
            return s;
        }
        catch (Exception e) when (e is JsonException or InvalidOperationException or KeyNotFoundException or FormatException)
        {
            var aside = Dir($"state.broken-{(long)Now}.json");
            TryIo(() => File.Move(StatePath, aside, true));
            return null;
        }
        catch (Exception e) when (e is IOException
            or UnauthorizedAccessException)
        {
            return null;
        }
    }

    void WriteState()
    {
        var json = PoolHttp.Json(w =>
        {
            w.WriteStartObject();
            w.WriteString("install", _state.Install);
            w.WriteNumber("frozenThrough", _state.FrozenThrough);
            w.WriteNumber("failures", _state.Failures);
            w.WriteNumber("nextAttempt", _state.NextAttempt);
            w.WriteNumber("serverRetryAt", _state.ServerRetryAt);
            w.WriteString("app", _state.App);
            w.WriteNumber("dropped", _state.Dropped);
            w.WriteEndObject();
        });
        TryIo(() => FileIo.WriteAtomic(StatePath, json));
    }

    void TrimPartialLine()
    {
        try
        {
            if (!File.Exists(PendingPath)) return;
            using var fs = new FileStream(PendingPath, FileMode.Open, FileAccess.ReadWrite);
            if (fs.Length == 0) return;
            fs.Seek(-1, SeekOrigin.End);
            if (fs.ReadByte() == '\n') return;
            var bytes = new byte[fs.Length];
            fs.Seek(0, SeekOrigin.Begin);
            fs.ReadExactly(bytes);
            var last = Array.LastIndexOf(bytes, (byte)'\n');
            fs.SetLength(last + 1);
        }
        catch (Exception e) when (e is IOException
            or UnauthorizedAccessException) { }
    }

    static Seen? ParseSeen(string line)
    {
        try
        {
            using var doc = JsonDocument.Parse(line);
            var r = doc.RootElement;
            return new Seen(r.GetProperty("s").GetInt64(), r.GetProperty("t").GetString()!,
                r.TryGetProperty("g", out var g) && g.ValueKind == JsonValueKind.String ? GameIds.Canonical(g.GetString()) : null,
                r.TryGetProperty("e", out var e) && e.ValueKind == JsonValueKind.String ? e.GetString() : null,
                r.GetProperty("a").GetDouble());
        }
        catch (Exception e) when (e is JsonException or InvalidOperationException or KeyNotFoundException)
        {
            return null;
        }
    }

    static string SeenLine(Seen s) => PoolHttp.JsonText(w =>
    {
        w.WriteStartObject();
        w.WriteNumber("s", s.Seq);
        w.WriteString("t", s.Text);
        if (s.Game is null) w.WriteNull("g");
        else w.WriteString("g", s.Game);
        if (s.Session is null) w.WriteNull("e");
        else w.WriteString("e", s.Session);
        w.WriteNumber("a", s.At);
        w.WriteEndObject();
    }) + "\n";

    void ImportLegacy(string path)
    {
        try
        {
            using var doc = JsonDocument.Parse(File.ReadAllBytes(path));
            if (doc.RootElement.TryGetProperty("queue", out var queue) && queue.ValueKind == JsonValueKind.Array)
                foreach (var item in queue.EnumerateArray())
                {
                    if (item.ValueKind != JsonValueKind.Object || !item.TryGetProperty("text", out var t)
                        || t.ValueKind != JsonValueKind.String) continue;
                    if (PoolFilter.Prepare(t.GetString()) is not { } text) continue;
                    var at = Now;
                    if (item.TryGetProperty("firstSeen", out var fs) && fs.ValueKind == JsonValueKind.String
                        && DateTimeOffset.TryParse(fs.GetString(), CultureInfo.InvariantCulture,
                            DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out var when))
                        at = PoolHttp.Unix(when);
                    Append(text, null, null, at);
                }
        }
        catch (Exception e) when (e is JsonException or IOException or UnauthorizedAccessException) { }
        var imported = path + ".imported";
        TryIo(() =>
        {
            if (File.Exists(imported)) File.Delete(imported);
            File.Move(path, imported);
        });
    }

    bool Append(string text, string? game, string? session, double at)
    {
        var seen = new Seen(_nextSeq, text, game, session, at);
        try
        {
            File.AppendAllText(PendingPath, SeenLine(seen), FileIo.Utf8);
        }
        catch (Exception e) when (e is IOException
            or UnauthorizedAccessException)
        {
            return false;
        }
        _nextSeq++;
        _pending.Add(seen);
        return true;
    }

    /// <summary>Satırı alır (§7.3); süzgeçten geçmeyen, etkisiz kipte ya da kapanmışken alınmaz.</summary>
    public bool Add(string text, string? game = null, string? session = null)
    {
        if (PoolFilter.Prepare(text) is not { } cleaned) return false;
        lock (_gate)
        {
            if (!_enabled || _closed) return false;
            try
            {
                if (File.Exists(PendingPath) && new FileInfo(PendingPath).Length >= MaxPendingBytes)
                {
                    _state.Dropped++;
                    WriteState();
                    return false;
                }
            }
            catch (Exception e) when (e is IOException
                or UnauthorizedAccessException) { }
            return Append(cleaned, GameIds.FromName(game), session, Now);
        }
    }

    /// <summary>Durum özeti.</summary>
    public LineQueueStatus Status
    {
        get
        {
            lock (_gate)
                return new LineQueueStatus(_pending.Count, SafeFiles(Outbox).Length, SafeFiles(Parked).Length,
                    _state.Dropped, _endpoint is not null, _state.Install);
        }
    }

    /// <summary>Kurulum kimliği.</summary>
    public string InstallId
    {
        get { lock (_gate) return _state.Install; }
    }

    /// <summary>Adres değişti: artan bekleme sıfırlanır.</summary>
    public void SetEndpoint(Uri? endpoint)
    {
        lock (_gate)
        {
            _endpoint = endpoint;
            _state.Failures = 0;
            _state.NextAttempt = 0;
            WriteState();
        }
    }

    /// <summary>"Ortak havuz" ayarı: kapanınca kuyruk tamamen silinir; açılınca yeniden satır alır.</summary>
    public void SetEnabled(bool enabled)
    {
        lock (_gate)
        {
            _enabled = enabled;
            if (enabled) return;
            TryIo(() => File.Delete(PendingPath));
            TryIo(() => File.Delete(Dir("rejected.jsonl")));
            foreach (var f in SafeFiles(Outbox).Concat(SafeFiles(Parked))) TryIo(() => File.Delete(f));
            _pending.Clear();
            _state.Dropped = 0;
            _state.Failures = 0;
            _state.NextAttempt = 0;
            _state.ServerRetryAt = 0;
            WriteState();
        }
    }

    /// <summary>Sistem "ağ erişilebilir" dedi: artan bekleme sıfırlanır, hemen denenir.</summary>
    public Task NetworkAvailableAsync(CancellationToken cancellationToken = default)
    {
        lock (_gate)
        {
            _state.Failures = 0;
            _state.NextAttempt = 0;
        }
        return SendAsync(false, cancellationToken);
    }

    /// <summary>Kapanış: durum yazılır, ağ beklenmez.</summary>
    public void Close()
    {
        lock (_gate)
        {
            _closed = true;
            WriteState();
        }
    }

    // ---- Gönderim ----

    sealed record ChunkLine(string Text, string? Game, string? Session, int Count, double First, double Last);

    sealed record Chunk(string Batch, List<ChunkLine> Lines, long UpTo);

    static byte[] ChunkJson(Chunk c, string install, string app) => PoolHttp.Json(w =>
    {
        w.WriteStartObject();
        w.WriteNumber("v", 1);
        w.WriteString("batch", c.Batch);
        w.WriteString("install", install);
        w.WriteString("app", app);
        w.WriteString("platform", "windows");
        w.WriteStartArray("lines");
        foreach (var l in c.Lines)
        {
            w.WriteStartObject();
            w.WriteString("text", l.Text);
            if (l.Game is null) w.WriteNull("game");
            else w.WriteString("game", l.Game);
            if (l.Session is null) w.WriteNull("session");
            else w.WriteString("session", l.Session);
            w.WriteNumber("count", l.Count);
            w.WriteNumber("first", (long)Math.Floor(l.First));
            w.WriteNumber("last", (long)Math.Floor(l.Last));
            w.WriteEndObject();
        }
        w.WriteEndArray();
        w.WriteNumber("upTo", c.UpTo);
        w.WriteEndObject();
    });

    static Chunk? ReadChunk(string path)
    {
        try
        {
            using var doc = JsonDocument.Parse(File.ReadAllBytes(path));
            var r = doc.RootElement;
            var lines = new List<ChunkLine>();
            foreach (var l in r.GetProperty("lines").EnumerateArray())
                lines.Add(new ChunkLine(l.GetProperty("text").GetString()!,
                    l.TryGetProperty("game", out var g) && g.ValueKind == JsonValueKind.String ? GameIds.Canonical(g.GetString()) : null,
                    l.TryGetProperty("session", out var s) && s.ValueKind == JsonValueKind.String ? s.GetString() : null,
                    l.GetProperty("count").GetInt32(), l.GetProperty("first").GetDouble(), l.GetProperty("last").GetDouble()));
            return new Chunk(r.GetProperty("batch").GetString()!, lines, r.GetProperty("upTo").GetInt64());
        }
        catch (Exception e) when (e is JsonException or InvalidOperationException or KeyNotFoundException
                                      or IOException or UnauthorizedAccessException)
        {
            return null;
        }
    }

    /// <summary>
    /// Bir gönderim denemesi (§7.4). Aynı anda tek gönderim; ikinci çağrı beklemeden döner. <paramref name="force"/>
    /// bekleyenleri hemen dondurur.
    /// </summary>
    public async Task SendAsync(bool force = false, CancellationToken cancellationToken = default)
    {
        if (!await _sending.WaitAsync(0, cancellationToken).ConfigureAwait(false)) return;
        try
        {
            Uri endpoint;
            lock (_gate)
            {
                if (!_enabled || _closed || _endpoint is null) return;
                endpoint = _endpoint;
                var now = Now;
                if (now < _state.NextAttempt || now < _state.ServerRetryAt) return;
                var due = force || _pending.Count >= FreezeLines
                          || (_pending.Count > 0 && now - _pending.Min(p => p.At) >= FreezeAge.TotalSeconds);
                if (due) Freeze();
            }
            await SendOutboxAsync(endpoint, cancellationToken).ConfigureAwait(false);
        }
        finally
        {
            _sending.Release();
        }
    }

    void Freeze()
    {
        if (_pending.Count == 0 || SafeFiles(Outbox).Length >= MaxOutbox) return;
        var chunks = new List<Chunk>();
        var current = new List<ChunkLine>();
        var index = new Dictionary<(string?, string?, string), int>();
        long upTo = _state.FrozenThrough;
        foreach (var seen in _pending.OrderBy(p => p.Seq))
        {
            var key = (seen.Game, seen.Session, seen.Text);
            if (index.TryGetValue(key, out var at))
            {
                var l = current[at];
                current[at] = l with { Count = l.Count + 1, First = Math.Min(l.First, seen.At), Last = Math.Max(l.Last, seen.At) };
            }
            else
            {
                if (current.Count >= _o.ChunkLines)
                {
                    chunks.Add(new Chunk(_newId(), current, upTo));
                    current = [];
                    index.Clear();
                }
                index[key] = current.Count;
                current.Add(new ChunkLine(seen.Text, seen.Game, seen.Session, 1, seen.At, seen.At));
            }
            upTo = seen.Seq;
        }
        if (current.Count > 0) chunks.Add(new Chunk(_newId(), current, upTo));

        var stamp = _clock.GetUtcNow().ToUnixTimeMilliseconds().ToString("D15", CultureInfo.InvariantCulture);
        for (var i = 0; i < chunks.Count; i++)
        {
            var c = chunks[i];
            var name = $"{stamp}-{i.ToString("D4", CultureInfo.InvariantCulture)}-{c.Batch}.json";
            try { FileIo.WriteAtomic(Path.Combine(Outbox, name), ChunkJson(c, _state.Install, _o.AppVersion)); }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { break; }
            _state.FrozenThrough = c.UpTo;
        }
        WriteState();
        _pending.RemoveAll(p => p.Seq <= _state.FrozenThrough);
        var sb = new StringBuilder();
        foreach (var p in _pending) sb.Append(SeenLine(p));
        TryIo(() => FileIo.WriteAtomic(PendingPath, sb.ToString()));
    }

    async Task SendOutboxAsync(Uri endpoint, CancellationToken cancellationToken)
    {
        var tried = new HashSet<string>(StringComparer.Ordinal);
        while (true)
        {
            var next = SafeFiles(Outbox).Select(Path.GetFileName).OrderBy(n => n, StringComparer.Ordinal)
                .FirstOrDefault(n => !tried.Contains(n!));
            if (next is null) return;
            tried.Add(next);
            var path = Path.Combine(Outbox, next);
            var chunk = ReadChunk(path);
            if (chunk is null)
            {
                TryIo(() => File.Move(path, Path.Combine(Parked, next), true));
                continue;
            }
            byte[] body;
            try { body = CanonicalGames(File.ReadAllBytes(path)); }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { continue; }

            var response = await PoolHttp.SendAsync(_o.Http, PoolHttp.Post(PoolEndpoint.Combine(endpoint, "v1/batches"), body),
                TimeSpan.FromSeconds(30), _o.AppVersion, cancellationToken).ConfigureAwait(false);
            var status = response is null ? 0 : (int)response.Status;
            lock (_gate)
            {
                if (response is not null && response.Ok)
                {
                    if (!Accepted(response.Body, chunk))
                    {
                        Failed();
                        return;
                    }
                    TryIo(() => File.Delete(path));
                    _state.Failures = 0;
                    _state.NextAttempt = 0;
                    WriteState();
                    continue;
                }
                switch (status)
                {
                    case 413 when chunk.Lines.Count > 1:
                        var half = chunk.Lines.Count / 2;
                        var prefix = next.Length >= 20 ? next[..20] : next;
                        var parts = new[] { chunk.Lines.Take(half).ToList(), chunk.Lines.Skip(half).ToList() };
                        for (var i = 0; i < 2; i++)
                        {
                            var id = _newId();
                            var part = new Chunk(id, parts[i], chunk.UpTo);
                            TryIo(() => FileIo.WriteAtomic(Path.Combine(Outbox, $"{prefix}-{i}-{id}.json"),
                                ChunkJson(part, _state.Install, _o.AppVersion)));
                        }
                        TryIo(() => File.Delete(path));
                        continue;
                    case 413:
                    case 400:
                    case 422:
                        TryIo(() => File.Move(path, Path.Combine(Parked, next), true));
                        continue;
                    case 429:
                    case 503:
                        _state.ServerRetryAt = Now + RetryAfter(response!.Message).TotalSeconds;
                        WriteState();
                        return;
                    default:
                        Failed();
                        return;
                }
            }
        }
    }

    /// <summary>
    /// Eski sürümlerin dondurduğu parçalarda oyun kimliği takma ad olabilir (<c>gta6</c>): gönderilen gövdede asıl kimliğe
    /// çevrilir (dosya değişmez). Değişecek bir şey yoksa gövde bayt bayt aynı kalır.
    /// </summary>
    internal static byte[] CanonicalGames(byte[] body)
    {
        using var doc = PoolHttp.Parse(body);
        if (doc?.RootElement.ValueKind != JsonValueKind.Object
            || !doc.RootElement.TryGetProperty("lines", out var lines) || lines.ValueKind != JsonValueKind.Array) return body;
        static bool Stale(JsonElement l) =>
            l.ValueKind == JsonValueKind.Object && l.TryGetProperty("game", out var g) && g.ValueKind == JsonValueKind.String
            && GameIds.Canonical(g.GetString()) != g.GetString();
        if (!lines.EnumerateArray().Any(Stale)) return body;
        return PoolHttp.Json(w =>
        {
            w.WriteStartObject();
            foreach (var p in doc.RootElement.EnumerateObject())
            {
                if (p.Name != "lines")
                {
                    p.WriteTo(w);
                    continue;
                }
                w.WriteStartArray("lines");
                foreach (var l in p.Value.EnumerateArray())
                {
                    if (l.ValueKind != JsonValueKind.Object)
                    {
                        l.WriteTo(w);
                        continue;
                    }
                    w.WriteStartObject();
                    foreach (var f in l.EnumerateObject())
                    {
                        if (f.Name == "game" && f.Value.ValueKind == JsonValueKind.String)
                            w.WriteString("game", GameIds.Canonical(f.Value.GetString()));
                        else f.WriteTo(w);
                    }
                    w.WriteEndObject();
                }
                w.WriteEndArray();
            }
            w.WriteEndObject();
        });
    }

    bool Accepted(byte[] body, Chunk chunk)
    {
        using var doc = PoolHttp.Parse(body);
        if (doc?.RootElement.ValueKind != JsonValueKind.Object) return false;
        var r = doc.RootElement;
        if (!r.TryGetProperty("ok", out var ok) || ok.ValueKind != JsonValueKind.True) return false;
        if (!r.TryGetProperty("batch", out var b) || b.ValueKind != JsonValueKind.String
            || !string.Equals(b.GetString(), chunk.Batch, StringComparison.OrdinalIgnoreCase)) return false;
        if (r.TryGetProperty("rejected", out var rejected) && rejected.ValueKind == JsonValueKind.Array)
            foreach (var item in rejected.EnumerateArray())
            {
                if (item.ValueKind != JsonValueKind.Object || !item.TryGetProperty("i", out var i)
                    || !i.TryGetInt32(out var index) || index < 0 || index >= chunk.Lines.Count) continue;
                var reason = item.TryGetProperty("reason", out var re) && re.ValueKind == JsonValueKind.String ? re.GetString()! : "";
                var path = Dir("rejected.jsonl");
                TryIo(() =>
                {
                    if (File.Exists(path) && new FileInfo(path).Length >= MaxRejectedBytes) return;
                    File.AppendAllText(path, PoolHttp.JsonText(w =>
                    {
                        w.WriteStartObject();
                        w.WriteString("reason", reason);
                        w.WriteString("text", chunk.Lines[index].Text);
                        w.WriteEndObject();
                    }) + "\n", FileIo.Utf8);
                });
            }
        return true;
    }

    void Failed()
    {
        _state.Failures++;
        var wait = Math.Min(30 * Math.Pow(2, Math.Min(_state.Failures - 1, 16)), 3600);
        wait *= 1 + (_random() * 0.4 - 0.2);
        _state.NextAttempt = Now + wait;
        WriteState();
    }

    TimeSpan RetryAfter(HttpResponseMessage message)
    {
        var value = TimeSpan.FromSeconds(60);
        var header = message.Headers.RetryAfter;
        if (header?.Delta is { } delta) value = delta;
        else if (header?.Date is { } date) value = date - _clock.GetUtcNow();
        if (value < TimeSpan.FromSeconds(1)) value = TimeSpan.FromSeconds(1);
        if (value > TimeSpan.FromDays(1)) value = TimeSpan.FromDays(1);
        return value;
    }

    // ---- Yardımcılar ----

    static string[] SafeFiles(string dir)
    {
        try { return Directory.Exists(dir) ? Directory.GetFiles(dir, "*.json") : []; }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { return []; }
    }

    static IEnumerable<string> SafeLines(string path)
    {
        try { return File.ReadAllLines(path, FileIo.Utf8); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { return []; }
    }

    static void TryIo(Action action)
    {
        try { action(); }
        catch (Exception e) when (e is IOException
            or UnauthorizedAccessException) { }
    }
}
