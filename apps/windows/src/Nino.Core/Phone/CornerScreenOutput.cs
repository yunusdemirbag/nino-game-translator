// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;
using Nino.Core.Reading;

namespace Nino.Core.Phone;

/// <summary>
/// Telefon/harita örtüsünün çıkışı ile köşe öğelerini birleştirir: TV <c>screen</c> listesi her gönderimde bütünü
/// değiştirdiği için örtünün son listesi (önce telefon, sonra harita) ve köşe öğeleri tek listede gider; ikisi de
/// boşsa kaldırılır. Yalnız köşe öğeleri gösterilirken liste <see cref="RefreshMs"/>'de bir yeniden gönderilir
/// (<see cref="Tick"/>). Kendi kilidi vardır; örtüye geri çağrı yapmaz.
/// </summary>
public sealed class CornerScreenOutput(ISubtitleOutput inner, IMsClock? clock = null) : ISubtitleOutput
{
    /// <summary>Yeniden gönderme aralığı (örtüyle aynı).</summary>
    public const long RefreshMs = PhoneOverlay.RefreshMs;

    readonly IMsClock _clock = clock ?? SystemMsClock.Instance;
    readonly object _lock = new();
    IReadOnlyList<ScreenItem> _base = [];
    IReadOnlyList<ScreenItem> _corners = [];
    bool _showing;
    long _sentAt;

    /// <summary>Örtü TV'de mi (örtü ya da köşe).</summary>
    public bool Showing
    {
        get { lock (_lock) return _showing; }
    }

    /// <inheritdoc />
    public void ShowSubtitle(SubtitleShow show) => inner.ShowSubtitle(show);

    /// <inheritdoc />
    public void ClearSubtitle() => inner.ClearSubtitle();

    /// <inheritdoc />
    public void ShowScreen(IReadOnlyList<ScreenItem> items, int durationMs, bool overlay)
    {
        if (!overlay)
        {
            inner.ShowScreen(items, durationMs, overlay);
            return;
        }
        lock (_lock)
        {
            _base = items.ToArray();
            SendLocked();
        }
    }

    /// <inheritdoc />
    public void ClearScreen()
    {
        lock (_lock)
        {
            _base = [];
            SendLocked();
        }
    }

    /// <summary>Köşe öğeleri değişti.</summary>
    public void SetCorners(IReadOnlyList<ScreenItem> items)
    {
        lock (_lock)
        {
            if (items.Count == 0 && _corners.Count == 0) return;
            _corners = items.ToArray();
            SendLocked();
        }
    }

    /// <summary>Her karede: yalnız köşe öğeleri gösteriliyorsa ve süresi dolduysa yeniden gönderir.</summary>
    public void Tick()
    {
        lock (_lock)
        {
            if (!_showing || _base.Count > 0 || _corners.Count == 0 || _clock.NowMs - _sentAt < RefreshMs) return;
            SendLocked();
        }
    }

    void SendLocked()
    {
        var all = _base.Concat(_corners).ToArray();
        if (all.Length > 0)
        {
            inner.ShowScreen(all, PhoneOverlay.DurationMs, true);
            _showing = true;
            _sentAt = _clock.NowMs;
        }
        else if (_showing)
        {
            inner.ClearScreen();
            _showing = false;
        }
    }

    /// <inheritdoc />
    public void ShowRegion(string id, string text, Box? box, double? lineHeight) => inner.ShowRegion(id, text, box, lineHeight);

    /// <inheritdoc />
    public void ClearRegions() => inner.ClearRegions();
}
