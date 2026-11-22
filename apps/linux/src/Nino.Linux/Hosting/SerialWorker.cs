// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Threading.Channels;

namespace Nino.Linux.Hosting;

/// <summary>
/// Denetleyici durumunu tek iş parçacığından değiştirir. Panel istekleri ve denetleyicinin kendi olayları bu sıraya
/// girer; sıradaki iş <c>await</c> ederse devamı da yine bu sıraya döner (iş parçacığının
/// <see cref="SynchronizationContext"/>'i bu nesnedir). Masaüstündeki arayüz iş parçacığının sunucudaki karşılığı.
/// </summary>
public sealed class SerialWorker : SynchronizationContext, IDisposable
{
    private readonly Channel<Action> inbox = Channel.CreateUnbounded<Action>(new UnboundedChannelOptions { SingleReader = true });
    private readonly Thread thread;
    private readonly Action<Exception> onFault;

    public SerialWorker(Action<Exception>? onFault = null)
    {
        this.onFault = onFault ?? (error => Journal.Shared.Write("panel", $"sırada yakalanmamış hata: {error}"));
        thread = new Thread(Loop) { IsBackground = true, Name = "nino-serial" };
        thread.Start();
    }

    /// <summary>Şu an bu sıranın iş parçacığında mıyız.</summary>
    public bool IsCurrent => Thread.CurrentThread == thread;

    private void Loop()
    {
        SetSynchronizationContext(this);
        var reader = inbox.Reader;
        while (reader.WaitToReadAsync().AsTask().GetAwaiter().GetResult())
        {
            while (reader.TryRead(out var job))
            {
                try { job(); }
                catch (Exception error) { onFault(error); }
            }
        }
    }

    public override void Post(SendOrPostCallback d, object? state) => Enqueue(() => d(state));

    public override void Send(SendOrPostCallback d, object? state)
    {
        if (IsCurrent) { d(state); return; }
        using var finished = new ManualResetEventSlim();
        Exception? failure = null;
        if (!TryEnqueue(() =>
            {
                try { d(state); }
                catch (Exception error) { failure = error; }
                finally { finished.Set(); }
            }))
            throw new ObjectDisposedException(nameof(SerialWorker));
        finished.Wait();
        if (failure is not null) throw failure;
    }

    public override SynchronizationContext CreateCopy() => this;

    /// <summary>
    /// İşi sıraya koyar. Sıra kapandıysa (sunucu kapanıyor) iş sessizce düşer: denetleyicinin geç biten işleri
    /// kapanışta hâlâ buraya dönebilir ve bunlar süreci çökertmemeli.
    /// </summary>
    public void Enqueue(Action job) => TryEnqueue(job);

    public bool TryEnqueue(Action job) => inbox.Writer.TryWrite(job);

    /// <summary>Eşzamanlı işi sırada çalıştırır, sonucunu bekletir.</summary>
    public Task<T> Invoke<T>(Func<T> job)
    {
        var done = new TaskCompletionSource<T>(TaskCreationOptions.RunContinuationsAsynchronously);
        if (!TryEnqueue(() =>
            {
                try { done.SetResult(job()); }
                catch (Exception error) { done.SetException(error); }
            }))
            done.SetException(new ObjectDisposedException(nameof(SerialWorker)));
        return done.Task;
    }

    /// <summary>Eşzamansız işi sırada başlatır; <c>await</c> sonrası da sırada sürer.</summary>
    public Task<T> Invoke<T>(Func<Task<T>> job)
    {
        var done = new TaskCompletionSource<T>(TaskCreationOptions.RunContinuationsAsynchronously);
        if (!TryEnqueue(async () =>
            {
                try { done.SetResult(await job()); }
                catch (Exception error) { done.SetException(error); }
            }))
            done.SetException(new ObjectDisposedException(nameof(SerialWorker)));
        return done.Task;
    }

    public Task Invoke(Func<Task> job) => Invoke<bool>(async () => { await job(); return true; });

    public Task Invoke(Action job) => Invoke<bool>(() => { job(); return true; });

    public void Dispose() => inbox.Writer.TryComplete();
}
