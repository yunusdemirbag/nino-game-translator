// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows.Threading;
using Nino.Shell.Platform;

namespace Nino.App.Services;

/// <summary>
/// Arayüz iş parçacığında tikleyen zamanlayıcılar (WPF <see cref="DispatcherTimer"/>). Dispatcher kurulurken yakalanır;
/// başka iş parçacığından istenen zamanlayıcı da o Dispatcher'da kurulur. Tik hataları yutulur.
/// </summary>
public sealed class DispatcherTimers(Dispatcher dispatcher, TimeProvider? clock = null) : IShellTimers
{
    readonly TimeProvider _clock = clock ?? TimeProvider.System;

    /// <inheritdoc />
    public DateTimeOffset Now => _clock.GetUtcNow();

    /// <inheritdoc />
    public IDisposable Every(TimeSpan period, Action tick) => new Handle(dispatcher, period, tick, repeat: true);

    /// <inheritdoc />
    public IDisposable After(TimeSpan due, Action tick) =>
        new Handle(dispatcher, due < TimeSpan.Zero ? TimeSpan.Zero : due, tick, repeat: false);

    sealed class Handle : IDisposable
    {
        readonly Dispatcher _dispatcher;
        DispatcherTimer? _timer;
        volatile bool _disposed;

        public Handle(Dispatcher dispatcher, TimeSpan interval, Action tick, bool repeat)
        {
            _dispatcher = dispatcher;
            void Create()
            {
                if (_disposed) return;
                var timer = new DispatcherTimer(DispatcherPriority.Background, _dispatcher)
                {
                    // DispatcherTimer 0 aralıkla da çalışır; en az 1 ms.
                    Interval = interval > TimeSpan.Zero ? interval : TimeSpan.FromMilliseconds(1),
                };
                timer.Tick += (_, _) =>
                {
                    if (!repeat) timer.Stop();
                    if (_disposed) return;
                    try { tick(); } catch (Exception) { }
                };
                _timer = timer;
                timer.Start();
            }
            if (dispatcher.CheckAccess()) Create();
            else dispatcher.BeginInvoke(Create);
        }

        public void Dispose()
        {
            _disposed = true;
            void StopIt() => _timer?.Stop();
            if (_dispatcher.CheckAccess()) StopIt();
            else _dispatcher.BeginInvoke(StopIt);
        }
    }
}
