// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.RemotePlay;

/// <summary>
/// Tek iş parçacıklı sıralı iş kuyruğu. Bir işin hatası bildirilir, kuyruk sürer. "Gecikmeli gönder" işi bir
/// zamanlayıcıyla sonra kuyruğa koyar.
/// </summary>
public sealed class SerialQueue : IDisposable
{
    readonly object gate = new();
    readonly Queue<Action> work = new();
    readonly HashSet<ITimer> timers = [];
    readonly Thread thread;
    readonly TimeProvider time;
    readonly Action<Exception>? onError;
    bool closed;

    public SerialQueue(string name, TimeProvider? time = null, Action<Exception>? onError = null)
    {
        this.time = time ?? TimeProvider.System;
        this.onError = onError;
        thread = new Thread(Run) { Name = name, IsBackground = true };
        thread.Start();
    }

    public void Post(Action action)
    {
        lock (gate)
        {
            if (closed)
                return;
            work.Enqueue(action);
            Monitor.Pulse(gate);
        }
    }

    public void PostDelayed(TimeSpan delay, Action action)
    {
        lock (gate)
        {
            if (closed)
                return;
            ITimer? timer = null;
            timer = time.CreateTimer(_ =>
            {
                lock (gate)
                    if (timer is not null)
                        timers.Remove(timer);
                timer?.Dispose();
                Post(action);
            }, null, Timeout.InfiniteTimeSpan, Timeout.InfiniteTimeSpan);
            timers.Add(timer);
            timer.Change(delay < TimeSpan.Zero ? TimeSpan.Zero : delay, Timeout.InfiniteTimeSpan);
        }
    }

    void Run()
    {
        while (true)
        {
            Action next;
            lock (gate)
            {
                while (!closed && work.Count == 0)
                    Monitor.Wait(gate);
                if (closed)
                    return;
                next = work.Dequeue();
            }
            try
            {
                next();
            }
            catch (Exception e)
            {
                try
                {
                    onError?.Invoke(e);
                }
                catch
                {
                }
            }
        }
    }

    /// <summary>Kuyruğu kapatır; bekleyen ve gecikmeli işler atılır.</summary>
    public void Dispose()
    {
        ITimer[] pendingTimers;
        lock (gate)
        {
            closed = true;
            work.Clear();
            pendingTimers = timers.ToArray();
            timers.Clear();
            Monitor.PulseAll(gate);
        }
        foreach (var t in pendingTimers)
            t.Dispose();
    }
}
