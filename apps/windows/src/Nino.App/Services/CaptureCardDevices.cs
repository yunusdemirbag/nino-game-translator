// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.App.Views;
using Nino.Shell.WindowsRules;
using Windows.Devices.Enumeration;

namespace Nino.App.Services;

/// <summary>
/// Ayarlardaki HDMI yakalama kartı aygıt listesinin kaynağı (yan pencereler tarifi §8.1): görüntü yakalama aygıtları uygulama
/// boyunca bir aygıt izleyicisiyle izlenir, son liste bellekte tutulur (<see cref="CardPreview.Devices"/> arayüz iş
/// parçacığında beklemeden okur). Takılıp çıkarmalar 700 ms birleştirilip liste yeniden okunur; yalnız aygıtlar
/// gerçekten değiştiyse <see cref="CardPreview.RaiseDevicesChanged"/> çağrılır (önizleme kendini yeniden açar).
/// </summary>
public sealed class CaptureCardDevices : IDisposable
{
    readonly Action<string> _log;
    readonly object _gate = new();
    IReadOnlyList<CardDevice> _devices = [];
    DeviceWatcher? _watcher;
    Timer? _debounce;
    int _reading;
    bool _again;
    bool _disposed;

    CaptureCardDevices(Action<string> log) => _log = log;

    /// <summary>Uygulamanın tek listesi (açılışta <see cref="Start"/>; başlamadıysa null).</summary>
    public static CaptureCardDevices? Current { get; private set; }

    /// <summary>İzlemeyi başlatır ve <see cref="CardPreview.Devices"/>'i bağlar (ikinci çağrı aynı nesneyi verir).</summary>
    public static CaptureCardDevices Start(Action<string>? log = null)
    {
        if (Current is { } running) return running;
        var list = new CaptureCardDevices(log ?? (_ => { }));
        Current = list;
        CardPreview.Devices = () => list.Snapshot;
        list.Watch();
        list.Refresh();
        return list;
    }

    /// <summary>Son okunan aygıtlar (kimlik, ad).</summary>
    public IReadOnlyList<CardDevice> Snapshot
    {
        get { lock (_gate) return _devices; }
    }

    void Watch()
    {
        try
        {
            var watcher = DeviceInformation.CreateWatcher(DeviceClass.VideoCapture);
            watcher.Added += (_, _) => Changed();
            watcher.Removed += (_, _) => Changed();
            watcher.Updated += (_, _) => Changed();
            watcher.Start();
            _watcher = watcher;
        }
        catch (Exception e)
        {
            _log("yakalama kartı aygıt izleyicisi açılamadı: " + e.Message);
        }
    }

    void Changed()
    {
        lock (_gate)
        {
            if (_disposed) return;
            _debounce?.Dispose();
            _debounce = new Timer(_ => Refresh(), null, CaptureCardRules.DeviceChangeDelay, Timeout.InfiniteTimeSpan);
        }
    }

    void Refresh()
    {
        // Tek okuma sürer; okurken gelen değişiklik bittikten sonra bir okuma daha yaptırır.
        if (Interlocked.Exchange(ref _reading, 1) == 1)
        {
            Volatile.Write(ref _again, true);
            return;
        }
        _ = Task.Run(async () =>
        {
            try
            {
                do
                {
                    Volatile.Write(ref _again, false);
                    var found = await CaptureCardCapture.FindDevicesAsync(DeviceClass.VideoCapture, _log).ConfigureAwait(false);
                    var next = found.Select(d => new CardDevice(d.Id, d.Name)).ToList();
                    bool changed;
                    lock (_gate)
                    {
                        if (_disposed) return;
                        changed = !next.SequenceEqual(_devices);
                        if (changed) _devices = next;
                    }
                    if (changed) CardPreview.RaiseDevicesChanged();
                } while (Volatile.Read(ref _again));
            }
            catch (Exception e)
            {
                _log("yakalama kartı aygıtları okunamadı: " + e.Message);
            }
            finally
            {
                Volatile.Write(ref _reading, 0);
            }
            if (Volatile.Read(ref _again) && !_disposed) Refresh();
        });
    }

    /// <inheritdoc />
    public void Dispose()
    {
        lock (_gate)
        {
            if (_disposed) return;
            _disposed = true;
            _debounce?.Dispose();
        }
        try { _watcher?.Stop(); } catch (Exception) { }
        _watcher = null;
        if (ReferenceEquals(Current, this))
        {
            Current = null;
            CardPreview.Devices = null;
        }
    }
}
