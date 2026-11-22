// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.RemotePlay;

/// <summary>
/// Kareleri yerel iş parçacığından alıp kendi arka plan iş parçacığında ("Nino frames") dağıtır. İşleyici meşgulken
/// ya da bekleyen kare varken gelen kare kopyalanmadan atlanır; ağ iş parçacığı beklemez.
/// </summary>
public sealed class FrameDispatcher : IDisposable
{
    readonly object gate = new();
    readonly Action<VideoFrame> handler;
    readonly Action<Exception>? onError;
    readonly Thread worker;
    VideoFrame? pending;
    bool busy;
    bool closed;

    public FrameDispatcher(Action<VideoFrame> handler, Action<Exception>? onError = null)
    {
        this.handler = handler;
        this.onError = onError;
        worker = new Thread(Run) { IsBackground = true, Name = "Nino frames" };
        worker.Start();
    }

    /// <summary>Kareyi sıkı adımla (genişlik×4) kopyalayıp kuyruğa alır; atlandıysa false.</summary>
    public unsafe bool Offer(byte* bgra, int width, int height, int stride)
    {
        if (bgra == null || width <= 0 || height <= 0 || stride < width * 4)
            return false;
        return Offer(new ReadOnlySpan<byte>(bgra, checked(stride * (height - 1) + width * 4)), width, height, stride);
    }

    public bool Offer(ReadOnlySpan<byte> bgra, int width, int height, int stride)
    {
        int row = width * 4;
        if (width <= 0 || height <= 0 || stride < row || bgra.Length < stride * (height - 1) + row)
            return false;
        lock (gate)
        {
            if (closed || busy || pending is not null)
                return false;
        }
        // Kopya kilit dışında; aynı anda tek üretici (yerel iş parçacığı) vardır.
        byte[] copy = new byte[row * height];
        for (int y = 0; y < height; y++)
            bgra.Slice(y * stride, row).CopyTo(copy.AsSpan(y * row, row));
        lock (gate)
        {
            if (closed || busy || pending is not null)
                return false;
            pending = new VideoFrame(copy, width, height, row);
            Monitor.Pulse(gate);
        }
        return true;
    }

    void Run()
    {
        while (true)
        {
            VideoFrame frame;
            lock (gate)
            {
                while (!closed && pending is null)
                    Monitor.Wait(gate);
                if (closed)
                    return;
                frame = pending!;
                pending = null;
                busy = true;
            }
            try
            {
                handler(frame);
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
            lock (gate)
                busy = false;
        }
    }

    public void Dispose()
    {
        lock (gate)
        {
            closed = true;
            pending = null;
            Monitor.PulseAll(gate);
        }
    }
}
