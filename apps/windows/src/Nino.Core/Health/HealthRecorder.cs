// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.Core.Health;

/// <summary>Oturum sayılarının anlık görüntüsü (değişmez).</summary>
public sealed record HealthSnapshot
{
    /// <summary>Görüntünün alındığı an.</summary>
    public DateTimeOffset Now { get; init; }

    /// <summary>Oturum sürüyor mu.</summary>
    public bool Active { get; init; }

    /// <summary>Oturumun başladığı an; hiç oturum olmadıysa yok.</summary>
    public DateTimeOffset? StartedAt { get; init; }

    /// <summary>Şu an PS5 görüntüsü geliyor mu.</summary>
    public bool Streaming { get; init; }

    /// <summary>Görüntünün geldiği toplam saniye (sürüyorsa şu ana kadar).</summary>
    public double StreamedSeconds { get; init; }

    public int ConnectAttempts { get; init; }
    public int Connects { get; init; }

    /// <summary>Görüntü gelirken nedenli kopma sayısı.</summary>
    public int Drops { get; init; }

    /// <summary>Son kopma nedeninin adı (ör. <c>NotFound</c>).</summary>
    public string? LastReason { get; init; }

    /// <summary>Kopukluğun başladığı an; görüntü geri gelince yok.</summary>
    public DateTimeOffset? DisconnectedSince { get; init; }

    public int NetworkLosses { get; init; }
    public int TvDrops { get; init; }
    public int Resends { get; init; }
    public int Overflows { get; init; }
    public int Stalls { get; init; }
    public int CorruptFrames { get; init; }
    public int Lines { get; init; }
    public int Translations { get; init; }

    /// <summary>Son 200 çeviri süresinin ortancası (ms); yoksa yok.</summary>
    public long? MedianTranslationMs { get; init; }

    /// <summary>En uzun çeviri süresi (ms).</summary>
    public long LongestTranslationMs { get; init; }

    /// <summary>Hiç ölçüm yok (hiç oturum başlamadı).</summary>
    public bool HasData => StartedAt is not null;

    /// <summary>Oturum sürüyor, görüntü gelmiyor ve kopukluk sürüyor.</summary>
    public bool IsDisconnected => Active && !Streaming && DisconnectedSince is not null;

    /// <summary>Kopukluğun süresi (saniye); kopuk değilse 0.</summary>
    public double DisconnectedSeconds =>
        IsDisconnected ? Math.Max(0, (Now - DisconnectedSince!.Value).TotalSeconds) : 0;

    /// <summary>Akış dakikası.</summary>
    public double StreamedMinutes => StreamedSeconds / 60.0;

    /// <summary>Oranların hesaplandığı en kısa akış (dakika).</summary>
    public const double MinMinutesForRates = 0.5;

    /// <summary>Dakikada kayıp paket (yeniden gönderim + taşma); 0,5 dk'dan kısa akışta yok.</summary>
    public double? LossPerMinute =>
        StreamedMinutes >= MinMinutesForRates ? (Resends + Overflows) / StreamedMinutes : null;

    /// <summary>Dakikada görüntü durması; 0,5 dk'dan kısa akışta yok.</summary>
    public double? StallsPerMinute => StreamedMinutes >= MinMinutesForRates ? Stalls / StreamedMinutes : null;
}

/// <summary>
/// Uygulama boyunca tek, paylaşılan sağlık kaydedici: PS5 oturumunun bağlantı, görüntü ve çeviri sayıları.
/// Kilitle korunur, her iş parçacığından çağrılabilir. Saat dışarıdan verilebilir.
/// </summary>
public sealed class HealthRecorder(TimeProvider? clock = null)
{
    /// <summary>Ortancası alınan son çeviri süresi sayısı.</summary>
    public const int DurationWindow = 200;

    readonly TimeProvider _clock = clock ?? TimeProvider.System;
    readonly object _gate = new();
    readonly Queue<long> _durations = new();

    bool _active;
    DateTimeOffset? _startedAt;
    bool _streaming;
    double _streamedSeconds;
    DateTimeOffset? _streamSince;
    int _attempts, _connects, _drops, _networkLosses, _tvDrops;
    int _resends, _overflows, _stalls, _corrupt, _lines, _translations;
    bool _inStall;
    string? _lastReason;
    DateTimeOffset? _disconnectedSince;
    long _longest;

    /// <summary>Oturum başladı: her şey sıfırlanır.</summary>
    public void SessionStarted()
    {
        lock (_gate)
        {
            _durations.Clear();
            _streaming = false;
            _streamedSeconds = 0;
            _streamSince = null;
            _attempts = _connects = _drops = _networkLosses = _tvDrops = 0;
            _resends = _overflows = _stalls = _corrupt = _lines = _translations = 0;
            _inStall = false;
            _lastReason = null;
            _disconnectedSince = null;
            _longest = 0;
            _active = true;
            _startedAt = _clock.GetUtcNow();
        }
    }

    /// <summary>Oturum bitti: akış saati kapanır; sayılar silinmez (yeni oturumda sıfırlanır).</summary>
    public void SessionEnded()
    {
        lock (_gate)
        {
            CloseStreamClock();
            _active = false;
            _streaming = false;
        }
    }

    /// <summary>PS5'e bağlanılıyor.</summary>
    public void Connecting()
    {
        lock (_gate) _attempts++;
    }

    /// <summary>Görüntü geldi.</summary>
    public void PictureArrived()
    {
        lock (_gate)
        {
            _connects++;
            _streaming = true;
            _disconnectedSince = null;
            _streamSince ??= _clock.GetUtcNow();
        }
    }

    /// <summary>Bağlantı koptu. Neden yoksa kullanıcının durdurmasıdır, kopma sayılmaz.</summary>
    /// <param name="reason">Kopma nedeninin adı (ör. <c>NotFound</c>); adres ya da ayrıntı içermez.</param>
    public void Disconnected(string? reason)
    {
        lock (_gate)
        {
            if (!string.IsNullOrEmpty(reason))
            {
                if (_streaming) _drops++;
                _disconnectedSince ??= _clock.GetUtcNow();
                _lastReason = reason;
            }
            _streaming = false;
            CloseStreamClock();
        }
    }

    /// <summary>Bilgisayarın ağı gitti (yalnız oturum sürerken sayılır).</summary>
    public void NetworkLost()
    {
        lock (_gate)
            if (_active) _networkLosses++;
    }

    /// <summary>TV uygulaması koptu (yalnız oturum sürerken sayılır).</summary>
    public void TvDropped()
    {
        lock (_gate)
            if (_active) _tvDrops++;
    }

    /// <summary>Remote Play kitaplığının bir günlük satırı (sık gelir; yalnız birkaç alt dizgiye bakılır).</summary>
    public void RemotePlayLine(string line)
    {
        if (string.IsNullOrEmpty(line)) return;
        lock (_gate)
        {
            if (line.Contains("Send Buffer re-sending packet", StringComparison.Ordinal)) _resends++;
            else if (line.Contains("Send Buffer overflow", StringComparison.Ordinal)) _overflows++;
            else if (line.Contains("FEC failed", StringComparison.Ordinal)
                     || line.Contains("Video FEC failure", StringComparison.Ordinal))
            {
                if (!_inStall)
                {
                    _stalls++;
                    _inStall = true;
                }
            }
            else if (line.Contains("Received IDR frame", StringComparison.Ordinal)) _inStall = false;
            else if (line.Contains("corrupt frame", StringComparison.Ordinal)) _corrupt++;
        }
    }

    /// <summary>Ekrana bir satır gitti; çeviri süresi varsa (paketten gelen satırda yok) ölçüme girer.</summary>
    public void LineShown(TimeSpan? translationTime)
    {
        lock (_gate)
        {
            _lines++;
            if (translationTime is not { } t) return;
            var ms = (long)Math.Round(Math.Max(0, t.TotalMilliseconds));
            _durations.Enqueue(ms);
            while (_durations.Count > DurationWindow) _durations.Dequeue();
            _translations++;
            if (ms > _longest) _longest = ms;
        }
    }

    /// <summary>Anlık görüntü (akış sürüyorsa geçen süre eklenir).</summary>
    public HealthSnapshot Snapshot()
    {
        lock (_gate)
        {
            var now = _clock.GetUtcNow();
            var seconds = _streamedSeconds + (_streamSince is { } since ? Math.Max(0, (now - since).TotalSeconds) : 0);
            long? median = null;
            if (_durations.Count > 0)
            {
                var sorted = _durations.Order().ToArray();
                median = sorted[sorted.Length / 2];
            }
            return new HealthSnapshot
            {
                Now = now,
                Active = _active,
                StartedAt = _startedAt,
                Streaming = _streaming,
                StreamedSeconds = seconds,
                ConnectAttempts = _attempts,
                Connects = _connects,
                Drops = _drops,
                LastReason = _lastReason,
                DisconnectedSince = _disconnectedSince,
                NetworkLosses = _networkLosses,
                TvDrops = _tvDrops,
                Resends = _resends,
                Overflows = _overflows,
                Stalls = _stalls,
                CorruptFrames = _corrupt,
                Lines = _lines,
                Translations = _translations,
                MedianTranslationMs = median,
                LongestTranslationMs = _longest,
            };
        }
    }

    void CloseStreamClock()
    {
        if (_streamSince is not { } since) return;
        _streamedSeconds += Math.Max(0, (_clock.GetUtcNow() - since).TotalSeconds);
        _streamSince = null;
    }
}
