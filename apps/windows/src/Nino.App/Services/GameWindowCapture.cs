// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.IO;
using System.Diagnostics;
using System.Runtime.InteropServices;
using Nino.Core.Settings;
using Nino.RemotePlay;
using Nino.Shell;
using Nino.Shell.Platform;
using Nino.Shell.WindowsRules;

namespace Nino.App.Services;

/// <summary>
/// Yerel bilgisayardaki oyun penceresini (PS Remote Play / chiaki-ng ya da Xbox penceresi) GDI ile okuyan ana okuyucu
/// (kaynaklar §2.1–2.5): ayrı arka plan iş parçacığında, monitör başına DPI farkındalığıyla, saniyede 10 kare,
/// her zaman 1920×1080. Pencere kendini vermezse (siyah) 3 sn siyah kare, sonra ekran kopyası.
/// </summary>
public sealed class GameWindowCapture : IGameWindowSource
{
    readonly GameConsole _console;
    readonly Action<string> _log;
    readonly object _gate = new();
    Thread? _thread;
    volatile bool _running;
    volatile bool _forget;
    volatile int _loopGen;
    WindowCaptureState _state = WindowCaptureState.Stopped;
    string? _name;
    PixelRect? _area;
    SourceStatus? _status;

    /// <param name="console">Hangi pencere aranır (PS5 ya da Xbox).</param>
    /// <param name="log">Altyazı günlüğü satırları.</param>
    public GameWindowCapture(GameConsole console, Action<string> log)
    {
        _console = console;
        _log = log;
    }

    /// <inheritdoc />
    public event Action<VideoFrame>? FrameArrived;

    /// <inheritdoc />
    public event Action<SourceStatus>? StatusChanged;

    /// <inheritdoc />
    public event Action<Ps5Console>? ConsoleMoved { add { } remove { } }

    /// <inheritdoc />
    public event Action<WindowCaptureState, string?>? WindowStateChanged;

    /// <inheritdoc />
    public event Action<PixelRect?>? GameAreaChanged;

    /// <inheritdoc />
    public void Start()
    {
        lock (_gate)
        {
            if (_running) return;
            _running = true;
            _status = null;
            _state = WindowCaptureState.Stopped;
            var gen = ++_loopGen;
            _thread = new Thread(() => Loop(gen)) { IsBackground = true, Name = "Nino oyun penceresi" };
            _thread.Start();
        }
    }

    /// <inheritdoc />
    public void Stop()
    {
        lock (_gate)
        {
            if (!_running) return;
            SetState(WindowCaptureState.Stopped, null);
            SetArea(null);
            _running = false;
        }
    }

    /// <inheritdoc />
    public void ReconnectNow() => _forget = true;

    /// <inheritdoc />
    public void Dispose() => Stop();

    void SetState(WindowCaptureState state, string? name)
    {
        if (!_running) return;
        if (state != _state || name != _name)
        {
            _state = state;
            _name = name;
            Safe(() => WindowStateChanged?.Invoke(state, name));
        }
        var status = state switch
        {
            WindowCaptureState.Capturing => SourceStatus.Streaming,
            WindowCaptureState.LookingForWindow => SourceStatus.Connecting,
            _ => SourceStatus.Down(DisconnectReason.Stopped),
        };
        if (status != _status)
        {
            _status = status;
            Safe(() => StatusChanged?.Invoke(status));
        }
    }

    void SetArea(PixelRect? area)
    {
        if (!_running || area == _area) return;
        _area = area;
        Safe(() => GameAreaChanged?.Invoke(area));
    }

    static void Safe(Action a)
    {
        try { a(); } catch (Exception) { }
    }

    void Loop(int gen)
    {
        try { Gdi.SetThreadDpiAwarenessContext(Gdi.PerMonitorAwareV2); } catch (Exception) { }
        var grab = new WindowGrabState();
        var frameTime = TimeSpan.FromSeconds(1.0 / GameWindowCaptureRules.FramesPerSecond);
        NativeWindow? window = null;
        var lastSearch = Stopwatch.StartNew();
        var searchedOnce = false;
        var misses = 0;
        var listed = false;
        using var output = new Gdi.Surface(GameWindowCaptureRules.OutputWidth, GameWindowCaptureRules.OutputHeight);
        var black = new byte[GameWindowCaptureRules.OutputWidth * GameWindowCaptureRules.OutputHeight * 4];
        while (_running && gen == _loopGen)
        {
            var started = Stopwatch.GetTimestamp();
            try
            {
                var searchNow = !searchedOnce || lastSearch.Elapsed >= GameWindowCaptureRules.SearchEvery;
                if (_forget)
                {
                    _forget = false;
                    window = null;
                    searchNow = true;
                }
                if (window is not null && !NativeWindows.IsWindow(window.Handle))
                {
                    window = null;
                    searchNow = true;
                }
                if (searchNow)
                {
                    searchedOnce = true;
                    lastSearch.Restart();
                    var found = Find();
                    if (found is null)
                    {
                        if (window is null && ++misses == MissesBeforeListing && !listed)
                        {
                            listed = true;
                            LogCandidates();
                        }
                        window = null;
                        SetState(WindowCaptureState.LookingForWindow, null);
                        SetArea(null);
                    }
                    else if (window is null || found.Handle != window.Handle)
                    {
                        misses = 0;
                        window = found;
                        grab.Reset();
                        SetState(WindowCaptureState.Capturing,
                            GameWindowRules.DisplayName(found.ContentProcessName ?? found.ProcessName, found.Title, found.ClassName));
                        SetArea(AreaInWpfUnits(found.Handle));
                    }
                }

                if (window is not null)
                {
                    var client = NativeWindows.ClientOnScreen(window.Handle);
                    if (client is null)
                    {
                        window = null;
                    }
                    else
                    {
                        if (client.Value != window.Client)
                        {
                            window = window with { Client = client.Value };
                            SetArea(AreaInWpfUnits(window.Handle));
                        }
                        var bytes = Grab(window, grab, output, black);
                        if (bytes is not null && _running)
                        {
                            var frame = new VideoFrame(bytes, GameWindowCaptureRules.OutputWidth,
                                GameWindowCaptureRules.OutputHeight, GameWindowCaptureRules.OutputWidth * 4);
                            Safe(() => FrameArrived?.Invoke(frame));
                        }
                    }
                }
            }
            catch (Exception e)
            {
                _log($"oyun penceresi okunamadı: {e.GetType().Name}: {e.Message}");
                window = null;
            }
            var elapsed = Stopwatch.GetElapsedTime(started);
            if (elapsed < frameTime) Thread.Sleep(frameTime - elapsed);
        }
    }

    // Pencere bu kadar aramada (~15 sn) bulunamazsa adaylar bir kez günlüğe yazılır (yeni süreç/sınıf adlarını görmek için).
    const int MissesBeforeListing = 10;

    void LogCandidates()
    {
        try
        {
            var lines = NativeWindows.Visible().Where(w => !NativeWindows.IsOwn(w) && w.Client.Width >= GameWindowRules.MinWidth
                    && w.Client.Height >= GameWindowRules.MinHeight && LooksRelevant(w))
                .Take(15)
                .Select(w => $"{w.ProcessName}{(w.ContentProcessName is { } c ? "→" + c : "")} [{w.ClassName}] \"{w.Title}\" {w.Client.Width}×{w.Client.Height}");
            _log($"oyun penceresi bulunamadı ({_console}); açık pencereler: " + string.Join("; ", lines));
        }
        catch (Exception) { }
    }

    // Yalnız ilgili görünen pencereler yazılır (tarayıcı sekmesi başlıkları günlüğe düşmesin).
    static bool LooksRelevant(NativeWindow w)
    {
        var text = GameWindowRules.Fold(w.ProcessName + " " + w.ContentProcessName + " " + w.Title);
        return text.Contains("xbox") || text.Contains("gaming") || text.Contains("remote") || text.Contains("chiaki")
            || GameWindowRules.HasRemotePlayTitle(w.Title)
            || string.Equals(w.ClassName, GameWindowRules.FrameWindowClass, StringComparison.OrdinalIgnoreCase);
    }

    NativeWindow? Find()
    {
        var windows = NativeWindows.Visible().Where(w => !NativeWindows.IsOwn(w) && w.Client.Width > 0 && w.Client.Height > 0).ToList();
        var pick = GameWindowRules.Pick(windows.Select(w => w.ClientCandidate), _console);
        return pick is null ? null : windows.First(w => w.ClientCandidate == pick);
    }

    /// <summary>Altyazı penceresine giden oyun alanı: iş parçacığı bir an sistem DPI farkındalığına geçer.</summary>
    static PixelRect? AreaInWpfUnits(IntPtr handle)
    {
        IntPtr old = IntPtr.Zero;
        try
        {
            old = Gdi.SetThreadDpiAwarenessContext(Gdi.SystemAware);
            return NativeWindows.ClientOnScreen(handle) is { } c ? GameWindowCaptureRules.GameAreaOnScreen(c) : null;
        }
        catch (Exception)
        {
            return null;
        }
        finally
        {
            if (old != IntPtr.Zero)
                try { Gdi.SetThreadDpiAwarenessContext(old); } catch (Exception) { }
        }
    }

    byte[]? Grab(NativeWindow window, WindowGrabState grab, Gdi.Surface output, byte[] black)
    {
        var client = window.Client;
        var areaInClient = GameWindowRules.GameArea(client.Width, client.Height);
        if (grab.TryWindowFirst())
        {
            using var surface = new Gdi.Surface(client.Width, client.Height);
            var ok = Gdi.PrintWindow(window.Handle, surface.Dc, Gdi.PwClientOnly | Gdi.PwRenderFullContent);
            Gdi.GdiFlush();
            var picture = ok && !GameWindowCaptureRules.IsBlack(surface.Read(), surface.Width * 4, areaInClient);
            var step = grab.AfterWindow(picture, out var left);
            if (left) _log("pencere görüntüsü yine doğrudan alınabiliyor; ekrandan kopyalamaya son verildi");
            if (step == WindowGrabStep.UseWindow)
            {
                output.StretchFrom(surface.Dc, areaInClient, Gdi.SrcCopy);
                return output.Read();
            }
            if (step == WindowGrabStep.SendBlack) return black;
        }
        var screenArea = new PixelRect(client.X + areaInClient.X, client.Y + areaInClient.Y, areaInClient.Width, areaInClient.Height);
        var screen = Gdi.GetDC(IntPtr.Zero);
        try
        {
            output.StretchFrom(screen, screenArea, Gdi.SrcCopy | Gdi.CaptureBlt);
        }
        finally
        {
            Gdi.ReleaseDC(IntPtr.Zero, screen);
        }
        var bytes = output.Read();
        var screenBlack = GameWindowCaptureRules.IsBlack(bytes, output.Width * 4,
            new PixelRect(0, 0, output.Width, output.Height));
        if (grab.AfterScreen(screenBlack)) _log("pencere görüntüsü doğrudan alınamadı; ekrandan kopyalamaya geçildi");
        return bytes;
    }
}

/// <summary>GDI yardımcıları.</summary>
static class Gdi
{
    public static readonly IntPtr PerMonitorAwareV2 = new(-4);
    public static readonly IntPtr SystemAware = new(-2);
    public const uint PwClientOnly = 0x1;
    public const uint PwRenderFullContent = 0x2;
    public const int SrcCopy = 0x00CC0020;
    public const int CaptureBlt = 0x40000000;
    const int Halftone = 4;

    [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr hWnd, IntPtr dc);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr dc, uint flags);
    [DllImport("gdi32.dll")] static extern IntPtr CreateCompatibleDC(IntPtr dc);
    [DllImport("gdi32.dll")] static extern bool DeleteDC(IntPtr dc);
    [DllImport("gdi32.dll")] static extern IntPtr SelectObject(IntPtr dc, IntPtr obj);
    [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr obj);
    [DllImport("gdi32.dll")] static extern bool StretchBlt(IntPtr dst, int x, int y, int w, int h, IntPtr src, int sx, int sy, int sw, int sh, int rop);
    [DllImport("gdi32.dll")] static extern int SetStretchBltMode(IntPtr dc, int mode);
    [DllImport("gdi32.dll")] static extern bool SetBrushOrgEx(IntPtr dc, int x, int y, IntPtr old);
    [DllImport("gdi32.dll")] public static extern bool GdiFlush();
    [DllImport("gdi32.dll")] static extern IntPtr CreateDIBSection(IntPtr dc, ref BitmapInfo info, uint usage, out IntPtr bits, IntPtr section, uint offset);

    [StructLayout(LayoutKind.Sequential)]
    struct BitmapInfo
    {
        public int Size;
        public int Width;
        public int Height;
        public short Planes;
        public short BitCount;
        public int Compression;
        public int SizeImage;
        public int XPelsPerMeter;
        public int YPelsPerMeter;
        public int ClrUsed;
        public int ClrImportant;
        public int Colors;
    }

    /// <summary>Uyumlu DC + üstten alta 32 bit DIB bölümü.</summary>
    public sealed class Surface : IDisposable
    {
        readonly IntPtr _bitmap;
        readonly IntPtr _old;
        readonly IntPtr _bits;

        public Surface(int width, int height)
        {
            Width = Math.Max(1, width);
            Height = Math.Max(1, height);
            Dc = CreateCompatibleDC(IntPtr.Zero);
            var info = new BitmapInfo
            {
                Size = 40, Width = Width, Height = -Height, Planes = 1, BitCount = 32, Compression = 0,
            };
            _bitmap = CreateDIBSection(Dc, ref info, 0, out _bits, IntPtr.Zero, 0);
            if (_bitmap == IntPtr.Zero || _bits == IntPtr.Zero)
            {
                DeleteDC(Dc);
                throw new InvalidOperationException("DIB bölümü kurulamadı");
            }
            _old = SelectObject(Dc, _bitmap);
        }

        public IntPtr Dc { get; }

        public int Width { get; }

        public int Height { get; }

        public void StretchFrom(IntPtr source, PixelRect area, int rop)
        {
            SetStretchBltMode(Dc, Halftone);
            SetBrushOrgEx(Dc, 0, 0, IntPtr.Zero);
            StretchBlt(Dc, 0, 0, Width, Height, source, area.X, area.Y, area.Width, area.Height, rop);
            GdiFlush();
        }

        public byte[] Read()
        {
            var bytes = new byte[Width * Height * 4];
            Marshal.Copy(_bits, bytes, 0, bytes.Length);
            return bytes;
        }

        public void Dispose()
        {
            SelectObject(Dc, _old);
            DeleteObject(_bitmap);
            DeleteDC(Dc);
        }
    }
}
