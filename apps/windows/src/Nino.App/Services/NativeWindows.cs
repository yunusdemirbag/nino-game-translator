// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.IO;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using Nino.Shell;
using Nino.Shell.Platform;
using Nino.Shell.WindowsRules;

namespace Nino.App.Services;

/// <summary>
/// Üst düzey bir pencere: tutamaç, süreç, başlık, içerik alanı ve pencere dikdörtgeni (ekran pikseli), pencere sınıfı ve
/// (UWP çerçevesinde) içeriği çizen sürecin adı.
/// </summary>
public sealed record NativeWindow(IntPtr Handle, int ProcessId, string ProcessName, string Title, PixelRect Client,
    PixelRect Bounds, bool HasOwner, string ClassName = "", string? ContentProcessName = null)
{
    /// <summary>Kural sınıflarının adayı (içerik alanıyla; UWP çerçevesinde içerik süreci adıyla).</summary>
    public WindowCandidate ClientCandidate =>
        new(ContentProcessName ?? ProcessName, Title, Client.Width, Client.Height, ClassName);

    /// <summary>Kural sınıflarının adayı (pencere dikdörtgeniyle).</summary>
    public WindowCandidate BoundsCandidate => new(ProcessName, Title, Bounds.Width, Bounds.Height);
}

/// <summary>Win32 pencere listesi (görünür, simge durumunda olmayan üst düzey pencereler).</summary>
public static class NativeWindows
{
    delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    internal struct Rect
    {
        public int Left, Top, Right, Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct Point
    {
        public int X, Y;
    }

    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc proc, IntPtr lParam);
    [DllImport("user32.dll")] internal static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll")] internal static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] internal static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int max);
    [DllImport("user32.dll")] internal static extern bool GetClientRect(IntPtr hWnd, out Rect rect);
    [DllImport("user32.dll")] internal static extern bool ClientToScreen(IntPtr hWnd, ref Point point);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hWnd, out Rect rect);
    [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr hWnd, uint cmd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr hWnd, StringBuilder name, int max);
    [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr parent, EnumProc proc, IntPtr lParam);
    [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr hWnd, int attribute, out int value, int size);

    const int DwmCloaked = 14;
    const string CoreWindowClass = "Windows.UI.Core.CoreWindow";

    const uint GwOwner = 4;
    const int TitleMax = 256;

    static readonly ConcurrentDictionary<int, string> ProcessNames = new();
    static readonly int OwnProcess = Environment.ProcessId;

    /// <summary>Görünür, simge durumunda olmayan üst düzey pencereler (Nino'nunkiler hariç değil; çağıran süzer).</summary>
    public static IReadOnlyList<NativeWindow> Visible()
    {
        var list = new List<NativeWindow>();
        EnumWindows((h, _) =>
        {
            try
            {
                if (!IsWindowVisible(h) || IsIconic(h) || IsCloaked(h)) return true;
                if (Describe(h) is { } w) list.Add(w);
            }
            catch (Exception) { }
            return true;
        }, IntPtr.Zero);
        return list;
    }

    /// <summary>Pencerenin şu anki bilgisi; pencere yoksa null.</summary>
    public static NativeWindow? Describe(IntPtr h)
    {
        if (!IsWindow(h)) return null;
        GetWindowThreadProcessId(h, out var pid);
        var title = new StringBuilder(TitleMax + 1);
        GetWindowText(h, title, TitleMax + 1);
        var text = title.ToString();
        if (text.Length > TitleMax) text = text[..TitleMax];
        var client = ClientOnScreen(h) ?? default;
        var bounds = GetWindowRect(h, out var r) ? new PixelRect(r.Left, r.Top, r.Right - r.Left, r.Bottom - r.Top) : default;
        var className = ClassName(h);
        var process = ProcessName((int)pid);
        string? content = null;
        if (string.Equals(className, GameWindowRules.FrameWindowClass, StringComparison.OrdinalIgnoreCase))
            content = ContentProcess(h, (int)pid);
        return new NativeWindow(h, (int)pid, process, text, client, bounds, GetWindow(h, GwOwner) != IntPtr.Zero, className,
            content);
    }

    /// <summary>Pencere sınıfının adı (okunamazsa boş).</summary>
    static string ClassName(IntPtr h)
    {
        var name = new StringBuilder(257);
        return GetClassName(h, name, name.Capacity) > 0 ? name.ToString() : "";
    }

    /// <summary>
    /// Gizlenmiş (cloaked) pencere mi: askıya alınmış UWP çerçeveleri ve başka masaüstündeki pencereler görünür
    /// sayılsa da ekranda yoktur.
    /// </summary>
    static bool IsCloaked(IntPtr h)
    {
        try { return DwmGetWindowAttribute(h, DwmCloaked, out var cloaked, sizeof(int)) == 0 && cloaked != 0; }
        catch (Exception) { return false; }
    }

    /// <summary>
    /// UWP çerçevesinin (ApplicationFrameHost) içeriğini çizen süreç: çerçeveden başka sürece ait CoreWindow alt
    /// penceresinin süreç adı; bulunamazsa null.
    /// </summary>
    static string? ContentProcess(IntPtr frame, int framePid)
    {
        string? found = null;
        try
        {
            EnumChildWindows(frame, (child, _) =>
            {
                GetWindowThreadProcessId(child, out var childPid);
                if ((int)childPid == framePid || !string.Equals(ClassName(child), CoreWindowClass, StringComparison.Ordinal))
                    return true;
                var name = ProcessName((int)childPid);
                if (name.Length == 0) return true;
                found = name;
                return false;
            }, IntPtr.Zero);
        }
        catch (Exception) { }
        return found;
    }

    /// <summary>İçerik alanının ekrandaki yeri (başlık çubuğu ve kenarlık hariç); boşsa null.</summary>
    public static PixelRect? ClientOnScreen(IntPtr h)
    {
        if (!GetClientRect(h, out var c) || c.Right - c.Left <= 0 || c.Bottom - c.Top <= 0) return null;
        var p = new Point { X = 0, Y = 0 };
        if (!ClientToScreen(h, ref p)) return null;
        return new PixelRect(p.X, p.Y, c.Right - c.Left, c.Bottom - c.Top);
    }

    /// <summary>Süreç adı (önbellekli; okunamazsa boş).</summary>
    public static string ProcessName(int pid) => ProcessNames.GetOrAdd(pid, id =>
    {
        try
        {
            using var p = Process.GetProcessById(id);
            return p.ProcessName;
        }
        catch (Exception)
        {
            return "";
        }
    });

    /// <summary>Nino'nun kendi penceresi mi.</summary>
    public static bool IsOwn(NativeWindow w) => w.ProcessId == OwnProcess;

    /// <summary>Ayarlar'daki seçici için pencere listesi (sahipsiz, Nino hariç, başlıklı, en az 400×250).</summary>
    public static IReadOnlyList<VisibleWindow> Listing()
    {
        try
        {
            return CaptureWindowRules.Listing(Visible().Where(w => !w.HasOwner && !IsOwn(w)).Select(w => w.BoundsCandidate));
        }
        catch (Exception)
        {
            return [];
        }
    }
}
