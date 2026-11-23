// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows.Threading;
using Nino.Shell;

namespace Nino.App.Views;

/// <summary>
/// Fiş balonunun uygulama açık kaldıkça süren durumu (<see cref="PlugHintVisibility"/>): sahne yeniden kurulsa da kalır.
/// Görünürlük saate göre değişince <see cref="Changed"/> olur; bir sonraki değişim için tek zamanlayıcı kurulur.
/// "Fiş bir kez kullanıldı" bayrağı veri klasöründe (<see cref="PlugHintFlag"/>); klasör yoksa balon soluk başlar.
/// </summary>
internal static class PlugHintState
{
    static PlugHintVisibility? _rules;
    static string? _folder;
    static DispatcherTimer? _timer;
    static bool _visible;

    /// <summary>Görünürlük değişti.</summary>
    public static event Action? Changed;

    /// <summary>Şu an görünür mü (değilse <see cref="PlugHintVisibility.FadedOpacity"/> ile soluk).</summary>
    public static bool Visible => _visible;

    /// <summary>Kuralları bir kez kurar (bayrak bu klasörden okunur).</summary>
    public static void Attach(string? dataFolder)
    {
        if (_rules is not null) return;
        _folder = dataFolder;
        _rules = new PlugHintVisibility(PlugHintFlag.Read(dataFolder));
        _visible = _rules.IsVisible(DateTimeOffset.Now);
    }

    /// <summary>Fare prizin, fişin ya da balonun üstüne geldi/çıktı (parçaların birleşimi).</summary>
    public static void Hover(bool inside)
    {
        if (_rules is null) return;
        _rules.HoverChanged(inside, DateTimeOffset.Now);
        Recompute();
    }

    /// <summary>Fiş kullanıldı: tık, sürükleme, Enter ya da cam anahtar (yalnız kurulumu açsa da).</summary>
    public static void PlugUsed()
    {
        if (_rules is null) Attach(null);
        var wasLearned = _rules!.Learned;
        _rules.PlugUsed(DateTimeOffset.Now);
        if (!wasLearned) PlugHintFlag.Write(_folder);
        Recompute();
    }

    static void Recompute()
    {
        if (_rules is null) return;
        var now = DateTimeOffset.Now;
        var visible = _rules.IsVisible(now);
        _timer?.Stop();
        if (_rules.NextChange(now) is { } next)
        {
            _timer ??= new DispatcherTimer();
            _timer.Tick -= OnTick;
            _timer.Tick += OnTick;
            _timer.Interval = next - now + TimeSpan.FromMilliseconds(20);
            _timer.Start();
        }
        if (visible == _visible) return;
        _visible = visible;
        Changed?.Invoke();
    }

    static void OnTick(object? sender, EventArgs e)
    {
        _timer?.Stop();
        Recompute();
    }
}
