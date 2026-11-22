// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.WindowsRuntime;
using Nino.App.Strings;
using Nino.Core.Settings;
using Nino.RemotePlay;
using Nino.Shell;
using Nino.Shell.WindowsRules;
using Windows.Graphics.Capture;
using Windows.Graphics.DirectX;
using Windows.Graphics.DirectX.Direct3D11;
using Windows.Graphics.Imaging;

namespace Nino.App.Services;

/// <summary>
/// Windows.Graphics.Capture okuyucusu (kaynaklar §2.6): eski "Remote Play penceresi" (uygulama seçimiyle) ve
/// "seçilen pencere" (süreç + tam başlık) kipleri. Kare pencerenin kendi boyunda, saniyede en çok 10, işlemci
/// belleğine kopyalanır. Pencere kapanınca yeniden aranır (çeviri durmaz).
/// </summary>
public sealed class GraphicsCaptureSource : IVideoSource
{
    readonly IReadOnlyList<string> _processes;
    readonly string? _title;
    readonly RemotePlayApp? _app;
    readonly Action<string> _log;
    readonly object _gate = new();
    int _generation;
    bool _running;
    SourceStatus? _status;
    bool _waitLogged;
    bool _borderLogged;
    CancellationTokenSource? _search;
    Capture? _capture;

    GraphicsCaptureSource(IReadOnlyList<string> processes, string? title, RemotePlayApp? app, Action<string> log)
    {
        _processes = processes;
        _title = title;
        _app = app;
        _log = log;
    }

    /// <summary>Uygulama seçimiyle (Sony, chiaki-ng ya da hangisi açıksa).</summary>
    public static GraphicsCaptureSource ForApp(RemotePlayApp app, Action<string> log) =>
        new(CaptureWindowRules.Processes(app), null, app, log);

    /// <summary>Kullanıcının seçtiği pencere: süreç adı ve başlık boş olamaz.</summary>
    public static GraphicsCaptureSource ForWindow(CaptureWindowChoice window, Action<string> log)
    {
        if (string.IsNullOrWhiteSpace(window.ProcessName) || string.IsNullOrWhiteSpace(window.Title))
            throw new ArgumentException("Pencere için süreç adı ve başlık verilmeli.", nameof(window));
        return new([window.ProcessName], window.Title, null, log);
    }

    /// <summary>Uygulamanın kurulu yolu (ilk var olan); yoksa null.</summary>
    public static string? InstalledPath(RemotePlayApp app)
    {
        var candidates = CaptureWindowRules.InstallCandidates(app,
            Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
            Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData));
        return candidates.FirstOrDefault(p => File.Exists(p));
    }

    bool Selected => _title is not null;

    /// <inheritdoc />
    public event Action<VideoFrame>? FrameArrived;

    /// <inheritdoc />
    public event Action<SourceStatus>? StatusChanged;

    /// <inheritdoc />
    public event Action<Ps5Console>? ConsoleMoved { add { } remove { } }

    /// <inheritdoc />
    public void Start()
    {
        int gen;
        lock (_gate)
        {
            if (_running) return;
            _running = true;
            gen = ++_generation;
            _waitLogged = false;
            _status = null;
        }
        Emit(SourceStatus.Connecting, gen);
        if (_app is { } app && !AnyRunning()) LaunchApp(app);
        BeginSearch(gen);
    }

    /// <inheritdoc />
    public void Stop()
    {
        lock (_gate)
        {
            if (!_running) return;
            _running = false;
            _generation++;
            _search?.Cancel();
            _search = null;
            _capture?.Dispose();
            _capture = null;
        }
        Safe(() => StatusChanged?.Invoke(SourceStatus.Down(DisconnectReason.Stopped)));
    }

    /// <inheritdoc />
    public void ReconnectNow()
    {
        int gen;
        lock (_gate)
        {
            if (!_running) return;
            gen = ++_generation;
            _search?.Cancel();
            _capture?.Dispose();
            _capture = null;
        }
        Emit(SourceStatus.Connecting, gen);
        BeginSearch(gen);
    }

    /// <inheritdoc />
    public void Dispose() => Stop();

    void Emit(SourceStatus status, int gen)
    {
        lock (_gate)
        {
            if (gen != _generation || !_running || status == _status) return;
            _status = status;
        }
        Safe(() => StatusChanged?.Invoke(status));
    }

    static void Safe(Action a)
    {
        try { a(); } catch (Exception) { }
    }

    bool AnyRunning() => _processes.Any(p =>
    {
        try
        {
            var found = Process.GetProcessesByName(p);
            foreach (var x in found) x.Dispose();
            return found.Length > 0;
        }
        catch (Exception)
        {
            return false;
        }
    });

    void LaunchApp(RemotePlayApp app)
    {
        if (InstalledPath(app) is not { } path) return;
        try
        {
            _log(Path.GetFileNameWithoutExtension(path) + " açılıyor");
            using var _ = Process.Start(new ProcessStartInfo(path) { UseShellExecute = true });
        }
        catch (Exception e)
        {
            _log("Remote Play açılamadı: " + e.Message);
        }
    }

    void BeginSearch(int gen)
    {
        var cts = new CancellationTokenSource();
        lock (_gate)
        {
            _search?.Cancel();
            _search = cts;
        }
        _ = Task.Run(async () =>
        {
            while (!cts.IsCancellationRequested)
            {
                if (TryCapture(gen)) return;
                await Task.Delay(CaptureWindowRules.SearchEvery, cts.Token).ContinueWith(_ => { }, TaskScheduler.Default)
                    .ConfigureAwait(false);
            }
        });
    }

    bool TryCapture(int gen)
    {
        NativeWindow? window;
        try
        {
            var windows = NativeWindows.Visible().Where(w => !w.HasOwner && (!Selected || !NativeWindows.IsOwn(w))).ToList();
            var pick = CaptureWindowRules.Pick(windows.Select(w => w.BoundsCandidate), _processes, _title);
            window = pick is null ? null : windows.First(w => w.BoundsCandidate == pick);
        }
        catch (Exception)
        {
            window = null;
        }
        if (window is null)
        {
            if (!_waitLogged)
            {
                _waitLogged = true;
                _log(Selected
                    ? $"Kullanıcının seçtiği pencere aranıyor: {_processes[0]} / {_title}"
                    : "Remote Play penceresi bekleniyor: PS Remote Play ya da chiaki-ng açık değil");
            }
            Emit(SourceStatus.Connecting, gen);
            return false;
        }
        try
        {
            var capture = new Capture(this, window, gen);
            lock (_gate)
            {
                if (gen != _generation || !_running)
                {
                    capture.Dispose();
                    return true;
                }
                _capture = capture;
            }
            _log($"{window.ProcessName} penceresi okunuyor: {window.Bounds.Width}×{window.Bounds.Height}");
            Emit(SourceStatus.Streaming, gen);
            capture.Begin();
            return true;
        }
        catch (Exception e)
        {
            _log("Remote Play penceresinden görüntü alınamadı: " + e.Message);
            Emit(SourceStatus.Down(DisconnectReason.Other, e.Message), gen);
            return false;
        }
    }

    void OnClosed(Capture capture)
    {
        int gen;
        lock (_gate)
        {
            if (_capture != capture || !_running) return;
            _capture = null;
            gen = _generation;
            _waitLogged = false;
        }
        capture.Dispose();
        _log("pencere kapandı");
        Emit(SourceStatus.Connecting, gen);
        BeginSearch(gen);
    }

    void OnFrame(Capture capture, VideoFrame frame, bool black)
    {
        lock (_gate)
            if (_capture != capture || !_running) return;
        if (capture.BlackStreak == CaptureWindowRules.BlackFrameLimit)
        {
            _log($"{capture.Name} penceresinden yalnız siyah kare geliyor; görüntü alma engellenmiş olabilir");
            Emit(SourceStatus.Down(DisconnectReason.Other,
                L.Get(Selected ? "source.window.selected.black" : "source.window.rpApp.black")), capture.Generation);
        }
        else if (!black) Emit(SourceStatus.Streaming, capture.Generation);
        Safe(() => FrameArrived?.Invoke(frame));
    }

    void NoteBorder(string reason)
    {
        if (_borderLogged) return;
        _borderLogged = true;
        _log("Windows'un sarı kenarlığı gizlenemedi: " + reason);
    }

    /// <summary>Tek pencerenin yakalama oturumu.</summary>
    sealed class Capture : IDisposable
    {
        readonly GraphicsCaptureSource _owner;
        readonly IDirect3DDevice _device;
        readonly GraphicsCaptureItem _item;
        readonly Stopwatch _clock = Stopwatch.StartNew();
        Direct3D11CaptureFramePool _pool;
        GraphicsCaptureSession? _session;
        Windows.Graphics.SizeInt32 _size;
        TimeSpan _last = TimeSpan.FromHours(-1);
        int _copying;
        volatile bool _disposed;

        public Capture(GraphicsCaptureSource owner, NativeWindow window, int generation)
        {
            _owner = owner;
            Generation = generation;
            Name = window.ProcessName;
            _device = Direct3D.NewDevice();
            _item = Direct3D.ItemForWindow(window.Handle);
            _size = _item.Size;
            _pool = Direct3D11CaptureFramePool.CreateFreeThreaded(_device, DirectXPixelFormat.B8G8R8A8UIntNormalized, 2, _size);
        }

        public int Generation { get; }

        public string Name { get; }

        public int BlackStreak { get; private set; }

        public void Begin()
        {
            _item.Closed += (_, _) => _owner.OnClosed(this);
            _pool.FrameArrived += OnFrameArrived;
            _session = _pool.CreateCaptureSession(_item);
            try { _session.IsCursorCaptureEnabled = false; } catch (Exception) { }
            _ = TryBorderlessAsync(_session);
            _session.StartCapture();
        }

        async Task TryBorderlessAsync(GraphicsCaptureSession session)
        {
            try
            {
                if (!OperatingSystem.IsWindowsVersionAtLeast(10, 0, 20348)
                    || !Windows.Foundation.Metadata.ApiInformation.IsPropertyPresent("Windows.Graphics.Capture.GraphicsCaptureSession", "IsBorderRequired"))
                {
                    _owner.NoteBorder("bu Windows sürümünde çerçevesiz yakalama yok");
                    return;
                }
                var access = await GraphicsCaptureAccess.RequestAccessAsync(GraphicsCaptureAccessKind.Borderless);
                if (access == Windows.Security.Authorization.AppCapabilityAccess.AppCapabilityAccessStatus.Allowed) session.IsBorderRequired = false;
                else _owner.NoteBorder("izin verilmedi (" + access + ")");
            }
            catch (Exception e)
            {
                _owner.NoteBorder(e.Message);
            }
        }

        void OnFrameArrived(Direct3D11CaptureFramePool pool, object args)
        {
            if (_disposed) return;
            Direct3D11CaptureFrame? frame = null;
            try
            {
                frame = pool.TryGetNextFrame();
                if (frame is null) return;
                if (frame.ContentSize.Width != _size.Width || frame.ContentSize.Height != _size.Height)
                {
                    _size = frame.ContentSize;
                    pool.Recreate(_device, DirectXPixelFormat.B8G8R8A8UIntNormalized, 2, _size);
                    return;
                }
                var now = _clock.Elapsed;
                if (now - _last < TimeSpan.FromSeconds(1.0 / CaptureWindowRules.MaxFramesPerSecond)) return;
                if (Interlocked.CompareExchange(ref _copying, 1, 0) != 0) return;
                _last = now;
                var captured = frame;
                frame = null; // kopya bitince bırakılır
                _ = CopyAsync(captured);
            }
            catch (Exception e)
            {
                _owner._log("Remote Play penceresi kopyalanamadı: " + e.Message);
            }
            finally
            {
                frame?.Dispose();
            }
        }

        async Task CopyAsync(Direct3D11CaptureFrame frame)
        {
            try
            {
                using var bitmap = await SoftwareBitmap.CreateCopyFromSurfaceAsync(frame.Surface, BitmapAlphaMode.Premultiplied);
                var w = bitmap.PixelWidth;
                var h = bitmap.PixelHeight;
                if (w < 2 || h < 2 || _disposed) return;
                using var bgra = bitmap.BitmapPixelFormat == BitmapPixelFormat.Bgra8
                    ? null
                    : SoftwareBitmap.Convert(bitmap, BitmapPixelFormat.Bgra8, BitmapAlphaMode.Premultiplied);
                var bytes = new byte[w * h * 4];
                (bgra ?? bitmap).CopyToBuffer(bytes.AsBuffer());
                var black = CaptureWindowRules.IsMostlyBlack(bytes);
                BlackStreak = black ? BlackStreak + 1 : 0;
                _owner.OnFrame(this, new VideoFrame(bytes, w, h, w * 4), black);
            }
            catch (Exception e)
            {
                _owner._log("Remote Play penceresi kopyalanamadı: " + e.Message);
            }
            finally
            {
                frame.Dispose();
                Interlocked.Exchange(ref _copying, 0);
            }
        }

        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;
            try { _pool.FrameArrived -= OnFrameArrived; } catch (Exception) { }
            try { _session?.Dispose(); } catch (Exception) { }
            try { _pool.Dispose(); } catch (Exception) { }
            try { _device.Dispose(); } catch (Exception) { }
        }
    }
}

/// <summary>Direct3D 11 aygıtı ve pencere yakalama öğesi (COM birlikte çalışma).</summary>
static class Direct3D
{
    const int HardwareDriver = 1;
    const uint BgraSupport = 0x20;
    const uint SdkVersion = 7;
    static readonly Guid DxgiDevice = new("54ec77fa-1377-44e6-8c32-88fd5f44c84c");
    static readonly Guid CaptureItemInterface = new("79C3F95B-31F7-4EC2-A464-632EF5D30760");

    [DllImport("d3d11.dll")]
    static extern int D3D11CreateDevice(IntPtr adapter, int driverType, IntPtr software, uint flags, IntPtr featureLevels,
        uint levels, uint sdkVersion, out IntPtr device, out int featureLevel, out IntPtr context);

    [DllImport("d3d11.dll")]
    static extern int CreateDirect3D11DeviceFromDXGIDevice(IntPtr dxgiDevice, out IntPtr graphicsDevice);

    [ComImport, Guid("3628E81B-3CAC-4C60-B7F4-23CE0E0C3356"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IGraphicsCaptureItemInterop
    {
        IntPtr CreateForWindow([In] IntPtr hwnd, [In] ref Guid riid);
    }

    /// <summary>Donanım aygıtı (BGRA desteği) → WinRT aygıtı.</summary>
    public static IDirect3DDevice NewDevice()
    {
        var hr = D3D11CreateDevice(IntPtr.Zero, HardwareDriver, IntPtr.Zero, BgraSupport, IntPtr.Zero, 0, SdkVersion,
            out var device, out _, out var context);
        Marshal.ThrowExceptionForHR(hr);
        IntPtr dxgi = IntPtr.Zero, inspectable = IntPtr.Zero;
        try
        {
            var iid = DxgiDevice;
            Marshal.ThrowExceptionForHR(Marshal.QueryInterface(device, in iid, out dxgi));
            Marshal.ThrowExceptionForHR(CreateDirect3D11DeviceFromDXGIDevice(dxgi, out inspectable));
            return WinRT.MarshalInterface<IDirect3DDevice>.FromAbi(inspectable);
        }
        finally
        {
            foreach (var p in new[] { inspectable, dxgi, context, device })
                if (p != IntPtr.Zero) Marshal.Release(p);
        }
    }

    /// <summary>Pencere için yakalama öğesi.</summary>
    public static GraphicsCaptureItem ItemForWindow(IntPtr hwnd)
    {
        var activation = WinRT.ActivationFactory.Get("Windows.Graphics.Capture.GraphicsCaptureItem");
        var itemInterop = activation.AsInterface<IGraphicsCaptureItemInterop>();
        var iid = CaptureItemInterface;
        var ptr = itemInterop.CreateForWindow(hwnd, ref iid);
        try
        {
            return GraphicsCaptureItem.FromAbi(ptr);
        }
        finally
        {
            Marshal.Release(ptr);
        }
    }
}
