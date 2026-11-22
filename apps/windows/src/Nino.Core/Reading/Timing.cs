// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;

namespace Nino.Core.Reading;

/// <summary>Milisaniye saati (tekdüze). Hattın, sabitleyicinin ve ek alan izleyicisinin saati dışarıdan verilir.</summary>
public interface IMsClock
{
    /// <summary>Şimdiki an (ms).</summary>
    long NowMs { get; }
}

/// <summary>Sistemin açılıştan beri geçen milisaniyesi.</summary>
public sealed class SystemMsClock : IMsClock
{
    /// <summary>Ortak örnek.</summary>
    public static SystemMsClock Instance { get; } = new();

    /// <inheritdoc />
    public long NowMs => Environment.TickCount64;
}

/// <summary>Elle ilerleyen saat (testler). İş parçacığı güvenlidir.</summary>
public sealed class ManualMsClock(long start = 1_000_000) : IMsClock
{
    long _now = start;

    /// <inheritdoc />
    public long NowMs
    {
        get => Interlocked.Read(ref _now);
        set => Interlocked.Exchange(ref _now, value);
    }

    /// <summary>Saati ilerletir.</summary>
    public void Advance(long ms) => Interlocked.Add(ref _now, ms);
}

/// <summary>Tek kare kapısına giriş denemesinin sonucu.</summary>
public enum GateOutcome
{
    /// <summary>İçeri girildi; çıkışta numara verilmeli.</summary>
    Entered,

    /// <summary>Önceki kare işleniyor; bu kare atlanır.</summary>
    Busy,

    /// <summary>Önceki okuma çok uzun sürdü (arıza); kapı sıfırlandı, çağıran hattı yeniden kurmalı.</summary>
    Stuck,
}

/// <summary>Kapıya giriş denemesi: sonuç, giriş numarası ve (takıldıysa) geçen süre.</summary>
public readonly record struct GateEntry(GateOutcome Outcome, long Ticket, long ElapsedMs);

/// <summary>
/// Tek kare kapısı: okuma hattına aynı anda yalnız bir kare girer; önceki kare işleniyorsa yeni kare atlanır
/// (kareler birikmez). Sıfırlamadan sonra eski girişin geç çıkışı hiçbir şey değiştirmez.
/// </summary>
public sealed class FrameGate(long stuckAfterMs = FrameGate.WindowsStuckMs)
{
    /// <summary>Windows'ta takılma süresi (Mac'te 45 000).</summary>
    public const long WindowsStuckMs = 15_000;

    readonly object _lock = new();
    long _next;
    long? _inside;
    long _enteredAt;

    /// <summary>İçeride kare var mı.</summary>
    public bool IsBusy
    {
        get { lock (_lock) return _inside is not null; }
    }

    /// <summary>Girmeyi dener.</summary>
    public GateEntry TryEnter(long nowMs)
    {
        lock (_lock)
        {
            if (_inside is not null)
            {
                var elapsed = nowMs - _enteredAt;
                if (elapsed < stuckAfterMs) return new(GateOutcome.Busy, 0, elapsed);
                _inside = null;
                return new(GateOutcome.Stuck, 0, elapsed);
            }
            _next = unchecked(_next + 1);
            _inside = _next;
            _enteredAt = nowMs;
            return new(GateOutcome.Entered, _next, 0);
        }
    }

    /// <summary>Çıkar; yalnız o numara hâlâ içerideyse kapı açılır.</summary>
    public void Exit(long ticket)
    {
        lock (_lock)
            if (_inside == ticket) _inside = null;
    }

    /// <summary>İçerideki girişi unutur.</summary>
    public void Reset()
    {
        lock (_lock) _inside = null;
    }
}

/// <summary>Okuma planının bir kare için kararı.</summary>
public readonly record struct PlanDecision(bool Reuse, bool Deep, string? LastText);

/// <summary>
/// Okuma planı: altyazı bölgesi çoğu zaman ya boştur ya aynı kalır; iz değişmedikçe son okuma yeniden kullanılır.
/// Derin okuma yalnız "boş okuma sayacı" <c>deepEvery</c>'ye tam bölünüyorsa istenir. Kilitsizdir (hat kilitler).
/// </summary>
public sealed class ReadPlan(int threshold, int reuseLimit, int deepEvery)
{
    byte[]? _previous;
    string? _lastText;
    int _reused;
    int _emptyCount;

    /// <summary>Uygulamanın planı: eşik 16, yeniden kullanım 20 (hızlı algılamada 2), derin her 3'te bir.</summary>
    public static ReadPlan ForApp(bool fastDetection) => new(RegionSignature.DefaultThreshold, fastDetection ? 2 : 20, 3);

    /// <summary>"Her zaman" planı (hattın varsayılanı, testler): her kare okunur, her boş karede derin.</summary>
    public static ReadPlan Always() => new(-1, 0, 1);

    /// <summary>Bu kare için karar; iz saklanır.</summary>
    public PlanDecision Next(byte[] signature)
    {
        var previous = _previous;
        _previous = signature;
        if (previous is not null && _reused < reuseLimit && !RegionSignature.Changed(previous, signature, threshold))
        {
            _reused++;
            return new(true, false, _lastText);
        }
        _reused = 0;
        return new(false, deepEvery <= 1 || _emptyCount % deepEvery == 0, _lastText);
    }

    /// <summary>Gerçek bir okumadan sonra metni kaydeder (boşsa boş sayacı artar, değilse 1 olur).</summary>
    public void Record(string? text)
    {
        _lastText = text ?? "";
        _emptyCount = string.IsNullOrWhiteSpace(text) ? _emptyCount + 1 : 1;
    }

    /// <summary>Önceki iz, son metin ve sayaçlar silinir.</summary>
    public void Reset()
    {
        _previous = null;
        _lastText = null;
        _reused = 0;
        _emptyCount = 0;
    }
}
