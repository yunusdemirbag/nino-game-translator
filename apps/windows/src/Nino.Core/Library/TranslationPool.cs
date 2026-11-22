// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Globalization;
using System.Text.Json;
using Nino.Core.Data;
using Nino.Core.Translation;

namespace Nino.Core.Library;

/// <summary>Sunucunun çeviri ayarı (<c>/v1/config</c> → <c>translate</c>).</summary>
public sealed record PoolTranslateConfig(bool Enabled = true, int DeadlineMs = 900, int SyncSeconds = 180,
    int ContextLines = 4, int MaxLines = 12);

/// <summary>Havuz öncelikli oyunlar (<c>/v1/config</c> → <c>poolFirst</c>).</summary>
public sealed record PoolFirstConfig(IReadOnlyList<string> Games, IReadOnlyList<string> Langs, int DeadlineMs = 1500)
{
    /// <summary>Sunucuya ulaşılamazsa geçerli olanlar (GTA 6 havuz öncelikli).</summary>
    public static PoolFirstConfig Default { get; } =
        new(["grand-theft-auto-vi", "gta-vi", "gta-6", "gta6"], ["tr"]);
}

/// <summary>Çeviri havuzunun ayarları.</summary>
/// <param name="Folder"><c>%LOCALAPPDATA%\Nino\pool-translations</c>.</param>
/// <param name="Endpoint">Sunucu (null: adres yok).</param>
/// <param name="AppVersion">Nino'nun sürümü.</param>
/// <param name="Http">HTTP istemcisi.</param>
/// <param name="Clock">Saat.</param>
public sealed record TranslationPoolOptions(string Folder, Uri? Endpoint, string AppVersion, HttpClient Http,
    TimeProvider? Clock = null);

/// <summary>
/// Sunucunun çeviri havuzu (havuz/paket tarifi §8): uzak ayar, havuz önceliği, toplu indirme, anında/süreli/çok
/// satırlı soru, ping, ekrandan oyun tanıma. Dil başına bellekte anahtar → çeviri sözlüğü.
/// </summary>
public sealed class TranslationPool : IPoolFirstSource
{
    /// <summary>En çok sayfa.</summary>
    public const int MaxPages = 50;

    /// <summary>Dil başına diske yazılan en çok çeviri.</summary>
    public const int MaxStored = 400_000;

    /// <summary>Tanıma karesinin en çok boyu.</summary>
    public const int MaxImageBytes = 460_800;

    /// <summary>Çok satırlı sorunun varsayılan süresi.</summary>
    public static readonly TimeSpan MultiLineDeadline = TimeSpan.FromSeconds(10);

    static readonly TimeSpan ConfigAge = TimeSpan.FromSeconds(600);
    static readonly TimeSpan ServerGameAge = TimeSpan.FromSeconds(600);
    static readonly TimeSpan PingGap = TimeSpan.FromSeconds(55);

    readonly TranslationPoolOptions _o;
    readonly TimeProvider _clock;
    readonly object _gate = new();
    readonly Dictionary<(string Lang, ulong Key), Task<string?>> _inflight = new();
    Dictionary<ulong, string> _texts = new();
    Dictionary<string, Cursor> _cursors = new(StringComparer.Ordinal);
    bool _dirty;
    bool _share;
    string _lang;
    DateTimeOffset? _configAsked;
    DateTimeOffset? _lastPing;
    string _serverGame = "";
    DateTimeOffset _serverGameAt;
    string? _install;

    sealed class Cursor
    {
        public long Since;
        public string After = "";
        public double Checked;
    }

    /// <param name="options">Ayarlar.</param>
    /// <param name="language">Hedef dil.</param>
    /// <param name="sharePool">"Ortak havuz" ayarı.</param>
    public TranslationPool(TranslationPoolOptions options, string language, bool sharePool)
    {
        _o = options;
        _clock = options.Clock ?? TimeProvider.System;
        _lang = LangCode(language);
        _share = sharePool;
        if (_share) Load();
    }

    /// <summary>Dil kodu: küçük harf, <c>-</c>/<c>_</c> öncesi (<c>pt-BR</c> → <c>pt</c>).</summary>
    public static string LangCode(string? language)
    {
        var code = (language ?? "").Trim().ToLowerInvariant();
        var cut = code.IndexOfAny(['-', '_']);
        return cut >= 0 ? code[..cut] : code;
    }

    /// <summary>Uzak çeviri ayarı.</summary>
    public PoolTranslateConfig Translate { get; private set; } = new();

    /// <summary>Uzak havuz önceliği ayarı.</summary>
    public PoolFirstConfig PoolFirst { get; private set; } = PoolFirstConfig.Default;

    /// <summary>Sunucunun bildirdiği toplam indirme sayısı (bilinmiyorsa null).</summary>
    public long? Downloads { get; private set; }

    /// <summary>Şu anki dil.</summary>
    public string Language
    {
        get { lock (_gate) return _lang; }
    }

    /// <summary>Bellekteki çeviri sayısı.</summary>
    public int Count
    {
        get { lock (_gate) return _texts.Count; }
    }

    /// <summary>"Etkin": ortak havuz açık, sunucu çeviriyi açmış ve adres var.</summary>
    public bool Enabled => _share && Translate.Enabled && _o.Endpoint is not null;

    /// <summary>Kurulum kimliği (<c>install</c> dosyası; geçersizse yeni üretilip yazılır).</summary>
    public string InstallId
    {
        get
        {
            lock (_gate)
            {
                if (_install is not null) return _install;
                var path = Path.Combine(_o.Folder, "install");
                try
                {
                    if (File.Exists(path) && Guid.TryParse(File.ReadAllText(path).Trim(), out var g))
                        return _install = g.ToString("D");
                }
                catch (Exception e) when (e is IOException
                    or UnauthorizedAccessException) { }
                _install = Guid.NewGuid().ToString("D");
                try { FileIo.WriteAtomic(path, _install); }
                catch (Exception e) when (e is IOException
                    or UnauthorizedAccessException) { }
                return _install;
            }
        }
    }

    /// <summary>"Ortak havuz" ayarı değişti: kapanınca bellek boşalır (dosya silinmez), açılınca dosya okunur.</summary>
    public void SetSharePool(bool on)
    {
        lock (_gate)
        {
            if (on == _share) return;
            _share = on;
            if (on) Load();
            else
            {
                if (_dirty) WriteLocked();
                _texts = new();
                _cursors = new(StringComparer.Ordinal);
            }
        }
    }

    /// <summary>Hedef dil değişti: eski dil yazılır, yenisi okunur; süren indirmenin yanıtı atılır.</summary>
    public void SetLanguage(string language)
    {
        var code = LangCode(language);
        lock (_gate)
        {
            if (code == _lang) return;
            if (_dirty) WriteLocked();
            _lang = code;
            _texts = new();
            _cursors = new(StringComparer.Ordinal);
            if (_share) Load();
        }
    }

    /// <summary>İndirilmiş çevirilerde satırın tamamını arar.</summary>
    public string? Lookup(string text)
    {
        var key = LineKey.ComputeValue(PoolFilter.Clean(text));
        if (key is null) return null;
        lock (_gate) return _texts.TryGetValue(key.Value, out var t) ? t : null;
    }

    // ---- Uzak ayar ----

    /// <summary>Uzak ayarı tazeler (zorla değilse son sorudan en az 600 sn geçmiş olmalı; zaman soru başında işaretlenir).</summary>
    public async Task RefreshConfigAsync(bool force = false, CancellationToken cancellationToken = default)
    {
        if (_o.Endpoint is null) return;
        var now = _clock.GetUtcNow();
        lock (_gate)
        {
            if (!force && _configAsked is { } asked && now - asked < ConfigAge) return;
            _configAsked = now;
        }
        var response = await PoolHttp.SendAsync(_o.Http, new HttpRequestMessage(HttpMethod.Get,
            PoolEndpoint.Combine(_o.Endpoint, "v1/config")), TimeSpan.FromSeconds(30), _o.AppVersion,
            cancellationToken)
            .ConfigureAwait(false);
        if (response is null || (int)response.Status != 200) return;
        ApplyConfig(response.Body);
    }

    /// <summary>
    /// Sunucunun <c>/v1/config</c> cevabı geldi (gövde metni; herhangi bir iş parçacığından). Öbür bölümler kendi
    /// bloklarını buradan okur (ör. ölçümün <c>telemetry</c> bloğu).
    /// </summary>
    public event Action<string>? ConfigReceived;

    internal void ApplyConfig(byte[] body)
    {
        try { ConfigReceived?.Invoke(System.Text.Encoding.UTF8.GetString(body)); }
        catch (Exception) { }
        using var doc = PoolHttp.Parse(body);
        if (doc is null || doc.RootElement.ValueKind != JsonValueKind.Object) return;
        var root = doc.RootElement;
        if (root.TryGetProperty("downloads", out var d) && d.ValueKind == JsonValueKind.Number
            && d.TryGetDouble(out var dv) && dv > 0 && dv == Math.Floor(dv) && dv < long.MaxValue)
            Downloads = (long)dv;
        if (root.TryGetProperty("translate", out var t) && t.ValueKind == JsonValueKind.Object)
        {
            var def = new PoolTranslateConfig();
            Translate = new PoolTranslateConfig(
                t.TryGetProperty("enabled", out var e) && e.ValueKind is JsonValueKind.True or JsonValueKind.False
                    ? e.GetBoolean() : def.Enabled,
                Int(t, "deadlineMs") ?? def.DeadlineMs, Int(t, "syncSeconds") ?? def.SyncSeconds,
                Int(t, "contextLines") ?? def.ContextLines, Int(t, "maxLines") ?? def.MaxLines);
        }
        if (root.TryGetProperty("poolFirst", out var p) && p.ValueKind == JsonValueKind.Object)
        {
            var def = PoolFirstConfig.Default;
            PoolFirst = new PoolFirstConfig(Strings(p, "games") ?? def.Games, Strings(p, "langs") ?? def.Langs,
                Int(p, "deadlineMs") ?? def.DeadlineMs);
        }
    }

    static int? Int(JsonElement obj, string name) =>
        obj.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.Number && v.TryGetDouble(out var d)
            ? (int)Math.Clamp(d, int.MinValue, int.MaxValue)
            : null;

    static IReadOnlyList<string>? Strings(JsonElement obj, string name) =>
        obj.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.Array
            ? v.EnumerateArray().Where(x => x.ValueKind == JsonValueKind.String).Select(x => x.GetString()!).ToList()
            : null;

    // ---- Havuz önceliği ----

    /// <inheritdoc />
    public bool IsPoolFirst(string? game)
    {
        if (!Translate.Enabled || _o.Endpoint is null) return false;
        var langs = PoolFirst.Langs;
        var lang = Language;
        if (!langs.Contains("*") && !langs.Any(l => LangCode(l) == lang)) return false;
        // Sunucunun listesi ve oyun hem yazıldığı gibi hem asıl kimlikle karşılaştırılır (liste "gta-vi", oyun "gta-6"…).
        var games = PoolFirst.Games.Select(g => g.Trim().ToLowerInvariant()).Where(g => g.Length > 0)
            .SelectMany(g => new[] { g, GameIds.Canonical(g)! }).Distinct(StringComparer.Ordinal).ToList();
        bool Listed(IEnumerable<string?> ids) =>
            ids.Any(id => id is { Length: > 0 } && games.Any(g => id.Contains(g, StringComparison.Ordinal)));
        if (Listed([GameNames.Slug(game), GameIds.FromName(game)])) return true;
        lock (_gate)
        {
            if (_serverGame.Length > 0 && _clock.GetUtcNow() - _serverGameAt <= ServerGameAge
                && Listed([_serverGame, GameIds.Canonical(_serverGame)]))
                return true;
        }
        return false;
    }

    // ---- Anında soru ----

    /// <summary>Tek satır sorusu (§8.4). Gelmezse null.</summary>
    public async Task<string?> AskAsync(string line, IReadOnlyList<string> context, string? game,
        CancellationToken
            cancellationToken = default)
    {
        var results = await AskManyAsync([line], context, game, null, cancellationToken).ConfigureAwait(false);
        return results[0];
    }

    /// <inheritdoc />
    public async Task<string?> AskWithDeadlineAsync(string line, IReadOnlyList<string> context, string? game,
        CancellationToken cancellationToken)
    {
        await RefreshConfigAsync(false, cancellationToken).ConfigureAwait(false);
        var ask = AskAsync(line, context, game, CancellationToken.None);
        var deadline = TimeSpan.FromMilliseconds(Math.Clamp(PoolFirst.DeadlineMs, 100, 10_000));
        var finished = await Task.WhenAny(ask, Task.Delay(deadline, _clock, cancellationToken)).ConfigureAwait(false);
        cancellationToken
            .ThrowIfCancellationRequested();
        return finished == ask ? await ask.ConfigureAwait(false) : null;
    }

    /// <summary>
    /// Çok satırlı soru (telefon, harita): yinelenenler tek sorulur, bellektekiler hemen döner, kalanlar
    /// min(<c>maxLines</c>, 12)'lik parçalarla. <paramref name="deadline"/> verilirse en çok o kadar beklenir (istekler
    /// sürer).
    /// </summary>
    public async Task<IReadOnlyList<string?>> AskManyAsync(IReadOnlyList<string> lines, IReadOnlyList<string> context,
        string? game, TimeSpan? deadline, CancellationToken cancellationToken = default)
    {
        await RefreshConfigAsync(false, cancellationToken).ConfigureAwait(false);
        var results = new string?[lines.Count];
        var forced = IsPoolFirst(game);
        if (!((_share || forced) && Translate.Enabled && _o.Endpoint is not null)) return results;

        var waits = new List<(int Index, Task<string?> Task)>();
        var toAsk = new List<(string Text, ulong Key, TaskCompletionSource<string?> Source)>();
        string lang;
        lock (_gate)
        {
            lang = _lang;
            for (var i = 0; i < lines.Count; i++)
            {
                var cleaned = PoolFilter.Prepare(lines[i]);
                if (cleaned is null || LineKey.ComputeValue(cleaned) is not { } key) continue;
                if (_texts.TryGetValue(key, out var known))
                {
                    results[i] = known;
                    continue;
                }
                if (_inflight.TryGetValue((lang, key), out var running))
                {
                    waits.Add((i, running));
                    continue;
                }
                var source = new TaskCompletionSource<string?>(TaskCreationOptions.RunContinuationsAsynchronously);
                _inflight[(lang, key)] = source.Task;
                toAsk.Add((cleaned, key, source));
                waits.Add((i, source.Task));
            }
        }

        if (toAsk.Count > 0)
        {
            var size = Math.Max(1, Math.Min(Translate.MaxLines, 12));
            var ctx = context.Skip(Math.Max(0, context.Count - Math.Max(0, Translate.ContextLines))).ToList();
            for (var start = 0; start < toAsk.Count; start += size)
                _ = SendChunkAsync(toAsk.Skip(start).Take(size).ToList(), ctx, game, lang);
        }

        var all = Task.WhenAll(waits.Select(w => w.Task));
        if (deadline is { } limit)
            await Task.WhenAny(all, Task.Delay(limit, _clock, cancellationToken)).ConfigureAwait(false);
        else
            await all.WaitAsync(cancellationToken).ConfigureAwait(false);
        cancellationToken
            .ThrowIfCancellationRequested();
        foreach (var (index, task) in waits)
            if (task.IsCompletedSuccessfully) results[index] = task.Result;
        return results;
    }

    async Task SendChunkAsync(List<(string Text, ulong Key, TaskCompletionSource<string?> Source)> chunk,
        IReadOnlyList<string> context, string? game, string lang)
    {
        string?[] answers = new string?[chunk.Count];
        try
        {
            var body = PoolHttp.Json(w =>
            {
                w.WriteStartObject();
                w.WriteNumber("v", 1);
                w.WriteString("install", InstallId);
                w.WriteString("app", _o.AppVersion);
                w.WriteString("platform", "windows");
                w.WriteString("lang", lang);
                w.WriteString("game", GameIds.FromName(game) ?? "");
                w.WriteStartArray("lines");
                foreach (var c in chunk) w.WriteStringValue(c.Text);
                w.WriteEndArray();
                w.WriteStartArray("context");
                foreach (var c in context) w.WriteStringValue(c);
                w.WriteEndArray();
                w.WriteEndObject();
            });
            var response = await PoolHttp.SendAsync(_o.Http, PoolHttp.Post(PoolEndpoint.Combine(_o.Endpoint!, "v1/translate"),
                body), TimeSpan.FromSeconds(20), _o.AppVersion, CancellationToken.None).ConfigureAwait(false);
            if (response is not null && (int)response.Status == 200)
            {
                using var doc = PoolHttp.Parse(response.Body);
                if (doc?.RootElement.ValueKind == JsonValueKind.Object)
                {
                    var root = doc.RootElement;
                    var serverGame = root.TryGetProperty("game", out var g) && g.ValueKind == JsonValueKind.String
                        ? GameIds.FromName(g.GetString()) ?? ""
                        : "";
                    lock (_gate)
                    {
                        _serverGame = serverGame;
                        _serverGameAt = _clock.GetUtcNow();
                    }
                    if (root.TryGetProperty("translations", out var list) && list.ValueKind == JsonValueKind.Array)
                    {
                        var i = 0;
                        foreach (var item in list.EnumerateArray())
                        {
                            if (i >= answers.Length) break;
                            if (item.ValueKind == JsonValueKind.Object && item.TryGetProperty("text", out var t)
                                && t.ValueKind == JsonValueKind.String && t.GetString() is { } text
                                && !string.IsNullOrWhiteSpace(text))
                                answers[i] = text;
                            i++;
                        }
                    }
                }
            }
        }
        catch
        {
            // Ağ, zaman aşımı, JSON hatası → yok.
        }
        lock (_gate)
        {
            for (var i = 0; i < chunk.Count; i++)
            {
                _inflight.Remove((lang, chunk[i].Key));
                if (answers[i] is { } a && lang == _lang)
                {
                    _texts[chunk[i].Key] = a;
                    _dirty = true;
                }
            }
        }
        for (var i = 0; i < chunk.Count; i++) chunk[i].Source.TrySetResult(answers[i]);
    }

    // ---- Toplu indirme ----

    /// <summary>Toplu indirme (§8.3); gelen öğe sayısı. <paramref name="game"/> null: bütün oyunlar.</summary>
    public async Task<int> SyncAsync(string? game, bool force, CancellationToken cancellationToken = default)
    {
        await RefreshConfigAsync(false, cancellationToken).ConfigureAwait(false);
        if (!Enabled) return 0;
        var gameId = GameIds.FromName(game) ?? "";
        var now = _clock.GetUtcNow();
        string lang;
        long since;
        string after;
        lock (_gate)
        {
            lang = _lang;
            if (!_cursors.TryGetValue(gameId, out var c)) c = new Cursor();
            if (!force && PoolHttp.Unix(now) - c.Checked < Math.Max(30, Translate.SyncSeconds)) return 0;
            c.Checked = PoolHttp.Unix(now);
            _cursors[gameId] = c;
            since = c.Since;
            after = c.After;
        }

        var received = new Dictionary<ulong, string>();
        long maxUpdated = since;
        var count = 0;
        for (var page = 0; page < MaxPages; page++)
        {
            var query = $"v1/translations?lang={Uri.EscapeDataString(lang)}&since={since.ToString(CultureInfo.InvariantCulture)}";
            if (gameId.Length > 0) query += "&game=" + Uri.EscapeDataString(gameId);
            if (after.Length > 0) query += "&after=" + Uri.EscapeDataString(after);
            var response = await PoolHttp.SendAsync(_o.Http, new HttpRequestMessage(HttpMethod.Get,
                PoolEndpoint.Combine(_o.Endpoint!, query)), TimeSpan.FromSeconds(30), _o.AppVersion,
                cancellationToken)
                .ConfigureAwait(false);
            if (response is null || (int)response.Status != 200) break;
            if (Language != lang) return 0;
            using var doc = PoolHttp.Parse(response.Body);
            if (doc is null || doc.RootElement.ValueKind != JsonValueKind.Object) break;
            var root = doc.RootElement;
            if (!root.TryGetProperty("items", out var items) || items.ValueKind != JsonValueKind.Array) break;
            foreach (var item in items.EnumerateArray())
            {
                if (item.ValueKind != JsonValueKind.Array || item.GetArrayLength() < 3) continue;
                if (item[0].ValueKind != JsonValueKind.String || item[1].ValueKind != JsonValueKind.String
                    || item[2].ValueKind != JsonValueKind.Number || !item[2].TryGetInt64(out var updated)) continue;
                if (!LineKey.TryParse(item[0].GetString()!.ToLowerInvariant(), out var key)) continue;
                received[key] = item[1].GetString()!;
                maxUpdated = Math.Max(maxUpdated, updated);
                count++;
            }
            if (root.TryGetProperty("next", out var next)
                && next.ValueKind == JsonValueKind.Object
                && next.TryGetProperty("since", out var ns) && ns.ValueKind == JsonValueKind.Number
                && ns.TryGetInt64(out var nextSince))
            {
                since = nextSince;
                after = next.TryGetProperty("after", out var na) && na.ValueKind == JsonValueKind.String
                    ? na.GetString()! : "";
                continue;
            }
            since = Math.Max(maxUpdated, since);
            after = "";
            break;
        }

        lock (_gate)
        {
            if (_lang != lang) return 0;
            var c = _cursors[gameId];
            c.Since = since;
            c.After = after;
            foreach (var (k, v) in received) _texts[k] = v;
            WriteLocked();
        }
        return count;
    }

    /// <summary>
    /// İndirme döngüsü (§8.3): hemen zorla indirme, sonra "buradayım", 60 sn bekleme, zorlamasız indirme. Durdurmak
    /// için iptal edilir; oyun ya da ayar değişince çağıran döngüyü yeniden başlatır.
    /// </summary>
    public async Task RunSyncLoopAsync(Func<string?> game, CancellationToken cancellationToken)
    {
        var force = true;
        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                await SyncAsync(game(), force, cancellationToken).ConfigureAwait(false);
                force = false;
                await PingAsync(game(), cancellationToken).ConfigureAwait(false);
                await Task.Delay(TimeSpan.FromSeconds(60), _clock, cancellationToken).ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                return;
            }
        }
    }

    // ---- Ping ve tanıma ----

    /// <summary>"Buradayım" (§8.5): 55 sn'de en çok bir; hatalar yutulur.</summary>
    public async Task PingAsync(string? game, CancellationToken cancellationToken = default)
    {
        if (!_share || _o.Endpoint is null) return;
        var now = _clock.GetUtcNow();
        lock (_gate)
        {
            if (_lastPing is { } last && now - last < PingGap) return;
            _lastPing = now;
        }
        var query = "v1/ping?install=" + Uri.EscapeDataString(InstallId) + "&platform=windows&app="
            + Uri.EscapeDataString(_o.AppVersion) + "&game=" + Uri.EscapeDataString(GameIds.FromName(game) ?? "")
            + "&lang=" + Uri.EscapeDataString(Language);
        try
        {
            await PoolHttp.SendAsync(_o.Http, new HttpRequestMessage(HttpMethod.Get, PoolEndpoint.Combine(_o.Endpoint, query)),
                TimeSpan.FromSeconds(15), _o.AppVersion, cancellationToken).ConfigureAwait(false);
        }
        catch (Exception e) when (e is not OperationCanceledException) { }
    }

    /// <summary>
    /// Oyunu ekrandan tanıma (§8.6): JPEG karesi (0 bayt ya da 450 KB'tan büyükse gönderilmez). Tanınan oyunun adı ya
    /// da null. Sunucu bir kimlik ya da tablodaki bir oyunun başka bir yazılışını verirse okunur adı döner
    /// (<c>grand-theft-auto-vi</c> → <c>GTA 6</c>); bu ad her gönderimde yine asıl kimliğe çevrilir.
    /// </summary>
    public async Task<string?> IdentifyAsync(byte[] jpeg, CancellationToken cancellationToken = default)
    {
        if (!Enabled || jpeg.Length == 0 || jpeg.Length > MaxImageBytes) return null;
        var body = PoolHttp.Json(w =>
        {
            w.WriteStartObject();
            w.WriteNumber("v", 1);
            w.WriteString("install", InstallId);
            w.WriteString("app", _o.AppVersion);
            w.WriteString("platform", "windows");
            w.WriteString("image", Convert.ToBase64String(jpeg));
            w.WriteEndObject();
        });
        var response = await PoolHttp.SendAsync(_o.Http, PoolHttp.Post(PoolEndpoint.Combine(_o.Endpoint!, "v1/identify"), body),
            TimeSpan.FromSeconds(30), _o.AppVersion, cancellationToken).ConfigureAwait(false);
        if (response is null || (int)response.Status != 200) return null;
        using var doc = PoolHttp.Parse(response.Body);
        if (doc?.RootElement.ValueKind != JsonValueKind.Object) return null;
        return doc.RootElement.TryGetProperty("game", out var g) && g.ValueKind == JsonValueKind.String
               && g.GetString()!.Trim() is { Length: > 0 } name
            ? GameIds.ReadableName(name)
            : null;
    }

    // ---- Disk ----

    string FilePath(string lang) => Path.Combine(_o.Folder, $"translations-{lang}.json");

    void Load()
    {
        _texts = new();
        _cursors = new(StringComparer.Ordinal);
        _dirty = false;
        try
        {
            var path = FilePath(_lang);
            if (!File.Exists(path)) return;
            using var doc = JsonDocument.Parse(File.ReadAllBytes(path));
            var root = doc.RootElement;
            if (root.TryGetProperty("texts", out var texts) && texts.ValueKind == JsonValueKind.Object)
                foreach (var p in texts.EnumerateObject())
                    if (p.Value.ValueKind == JsonValueKind.String && LineKey.TryParse(p.Name, out var key))
                        _texts[key] = p.Value.GetString()!;
            if (root.TryGetProperty("cursors", out var cursors) && cursors.ValueKind == JsonValueKind.Object)
                foreach (var p in cursors.EnumerateObject())
                {
                    if (p.Value.ValueKind != JsonValueKind.Object) continue;
                    var c = new Cursor();
                    if (p.Value.TryGetProperty("since", out var s) && s.TryGetInt64(out var sv)) c.Since = sv;
                    if (p.Value.TryGetProperty("after", out var a) && a.ValueKind == JsonValueKind.String) c.After = a.GetString()!;
                    if (p.Value.TryGetProperty("checked", out var ch) && ch.TryGetDouble(out var cv)) c.Checked = cv;
                    // Eski sürümler imleci takma adla yazmış olabilir ("gta6"): asıl kimliğe birleşir. İkisi de varsa
                    // daha geride olan (küçük since) kalır: bir kez fazla indirmek zararsız, atlamak değil.
                    var id = GameIds.Canonical(p.Name) ?? "";
                    if (id != p.Name) _dirty = true;
                    if (_cursors.TryGetValue(id, out var had))
                    {
                        var firstCheck = Math.Min(had.Checked, c.Checked);
                        if (c.Since > had.Since || (c.Since == had.Since && string.CompareOrdinal(c.After, had.After) > 0)) c = had;
                        c.Checked = firstCheck;
                    }
                    _cursors[id] = c;
                }
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException or InvalidOperationException) { }
    }

    /// <summary>Değişiklik varsa diske yazar (kapanışta çağrılır).</summary>
    public void Save()
    {
        lock (_gate)
            if (_dirty) WriteLocked();
    }

    void WriteLocked()
    {
        try
        {
            var lang = _lang;
            var json = PoolHttp.Json(w =>
            {
                w.WriteStartObject();
                w.WriteString("language", lang);
                w.WriteStartObject("texts");
                foreach (var (k, v) in _texts.Take(MaxStored)) w.WriteString(LineKey.Format(k), v);
                w.WriteEndObject();
                w.WriteStartObject("cursors");
                foreach (var (g, c) in _cursors)
                {
                    w.WriteStartObject(g);
                    w.WriteNumber("since", c.Since);
                    w.WriteString("after", c.After);
                    w.WriteNumber("checked", c.Checked);
                    w.WriteEndObject();
                }
                w.WriteEndObject();
                w.WriteEndObject();
            });
            FileIo.WriteAtomic(FilePath(lang), json);
            _dirty = false;
        }
        catch (Exception e) when (e is IOException
            or UnauthorizedAccessException) { }
    }
}

/// <summary>
/// Havuz sorularına giden bağlam listesi (§8.4): son 4 satır ve zamanları; 30 sn'den eskiler düşer.
/// </summary>
public sealed class PoolContextLines(TimeProvider? clock = null)
{
    static readonly TimeSpan MaxAge = TimeSpan.FromSeconds(30);
    readonly TimeProvider _clock = clock ?? TimeProvider.System;
    readonly List<(string Text, DateTimeOffset At)> _lines = [];
    readonly object _gate = new();

    /// <summary>Satırı ekler; eklemeden önceki bağlamı döner.</summary>
    public IReadOnlyList<string> Add(string line)
    {
        lock (_gate)
        {
            var now = _clock.GetUtcNow();
            _lines.RemoveAll(l => now - l.At > MaxAge || l.Text == line);
            var context = _lines.Skip(Math.Max(0, _lines.Count - 4)).Select(l => l.Text).ToList();
            _lines.Add((line, now));
            while (_lines.Count > 4) _lines.RemoveAt(0);
            return context;
        }
    }

    /// <summary>"Satırdan öncekiler": 30 sn içindeki ve satırın kendisi olmayanların son 4'ü (eklemeden).</summary>
    public IReadOnlyList<string> Before(string line)
    {
        lock (_gate)
        {
            var now = _clock.GetUtcNow();
            var kept = _lines.Where(l => now - l.At <= MaxAge && l.Text != line).Select(l => l.Text).ToList();
            return kept.Skip(Math.Max(0, kept.Count - 4)).ToList();
        }
    }
}

/// <summary>Oyunun nereden bilindiği.</summary>
public enum KnownGameSource { None, Screen, Other }

/// <summary>
/// Ekrandan oyun tanıma zamanlaması (§8.6): bilinmiyorsa oturumdan 8 sn sonra, sonra 60 sn arayla en çok 6 deneme;
/// ekrandan tanındıysa doğrulama ilk 5 dk sonra, sonra 20 dk'da bir, en çok 12. Aynı anda tek istek.
/// </summary>
public sealed class GameIdentifySchedule
{
    DateTimeOffset _since;
    DateTimeOffset? _last;
    int _attempts;
    bool _busy;
    KnownGameSource _mode = KnownGameSource.None;

    /// <summary>Yeni oturum: sayaçlar sıfırlanır.</summary>
    public void StartSession(DateTimeOffset now)
    {
        _since = now;
        _last = null;
        _attempts = 0;
        _busy = false;
        _mode = KnownGameSource.None;
    }

    /// <summary>Şimdi bakılmalı mı. <paramref name="eligible"/>: çeviri sürüyor, ortak havuz açık, kaynak en, …</summary>
    public bool Due(DateTimeOffset now, KnownGameSource source, bool eligible)
    {
        if (!eligible || _busy || source == KnownGameSource.Other) return false;
        if (source != _mode)
        {
            _mode = source;
            _attempts = 0;
            _last = null;
            _since = now;
        }
        var (first, gap, max) = source == KnownGameSource.None
            ? (TimeSpan.FromSeconds(8), TimeSpan.FromSeconds(60), 6)
            : (TimeSpan.FromMinutes(5), TimeSpan.FromMinutes(20), 12);
        if (_attempts >= max) return false;
        var wait = _last is null ? first : gap;
        return now - (_last ?? _since) >= wait;
    }

    /// <summary>Deneme başladı.</summary>
    public void Begin(DateTimeOffset now)
    {
        _busy = true;
        _last = now;
        _attempts++;
    }

    /// <summary>Deneme bitti.</summary>
    public void End() => _busy = false;

    /// <summary>Kaç deneme yapıldı (bu kipte).</summary>
    public int Attempts => _attempts;
}
