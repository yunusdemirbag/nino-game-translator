// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Reflection;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text;

namespace Nino.RemotePlay.Bridge;

/// <summary>
/// nino_native'e P/Invoke (cdecl). Geri çağrılar yönetilmeyen-çağrılabilir durağan işlevlerdir; nesneye
/// sabitlenmiş tutamaçla ulaşılır ve hiçbir istisna yerel tarafa sızmaz.
/// </summary>
public sealed unsafe class NativeBridge : IRemotePlayBridge
{
    public const string LibraryName = "nino_native";

    /// <summary>Kütüphanenin tam yolu için ortam değişkeni (testler ve geliştirme).</summary>
    public const string LibraryPathVariable = "NINO_NATIVE_LIBRARY";

    static readonly object InitLock = new();
    static bool initialized;

    static NativeBridge()
    {
        try
        {
            NativeLibrary.SetDllImportResolver(typeof(NativeBridge).Assembly, Resolve);
        }
        catch (InvalidOperationException)
        {
            // Başka bir yer çözücü kurmuş; varsayılan arama sürer.
        }
    }

    public static NativeBridge Shared { get; } = new();

    static nint Resolve(string name, Assembly assembly, DllImportSearchPath? path)
    {
        if (name != LibraryName)
            return 0;
        foreach (string candidate in Candidates())
            if (NativeLibrary.TryLoad(candidate, out nint handle))
                return handle;
        return 0;
    }

    static IEnumerable<string> Candidates()
    {
        string? env = Environment.GetEnvironmentVariable(LibraryPathVariable);
        if (!string.IsNullOrWhiteSpace(env))
            yield return env;
        string file = OperatingSystem.IsWindows() ? "nino_native.dll"
            : OperatingSystem.IsMacOS() ? "nino_native.dylib" : "nino_native.so";
        string baseDir = AppContext.BaseDirectory;
        yield return Path.Combine(baseDir, file);
        yield return Path.Combine(baseDir, "native", file);
    }

    /// <summary>Kütüphanenin yüklenebildiği yol ya da null.</summary>
    public static string? FindLibrary()
    {
        foreach (string candidate in Candidates())
        {
            if (!NativeLibrary.TryLoad(candidate, out nint handle))
                continue;
            NativeLibrary.Free(handle);
            return candidate;
        }
        return null;
    }

    public bool IsAvailable() => FindLibrary() is not null;

    public void EnsureInitialized()
    {
        lock (InitLock)
        {
            if (initialized)
                return;
            int r;
            try
            {
                r = Native.Init();
            }
            catch (Exception e) when (e is DllNotFoundException or EntryPointNotFoundException or BadImageFormatException)
            {
                throw new NativeLibraryMissingException(e.Message);
            }
            if (r != 0)
                throw new RemotePlayException($"Nino's native Remote Play library failed to start ({r})");
            initialized = true;
        }
    }

    // ---------------- Arama ----------------

    public IReadOnlyList<FoundPs5> Discover(IReadOnlyList<string> targets, int timeoutMs)
    {
        EnsureInitialized();
        var found = new List<FoundPs5>();
        if (targets.Count == 0)
            return found;
        var handle = GCHandle.Alloc(found);
        nint[] strings = new nint[targets.Count];
        try
        {
            for (int i = 0; i < targets.Count; i++)
                strings[i] = Marshal.StringToCoTaskMemUTF8(targets[i]);
            fixed (nint* p = strings)
            {
                int r = Native.DiscoverEx((byte**)p, targets.Count, timeoutMs, &OnFound, GCHandle.ToIntPtr(handle));
                if (r < 0)
                    throw new RemotePlayException($"PS5 search could not be started ({r})");
            }
        }
        finally
        {
            foreach (nint s in strings)
                if (s != 0)
                    Marshal.FreeCoTaskMem(s);
            handle.Free();
        }
        lock (found)
            return found.ToArray();
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    static void OnFound(byte* host, byte* name, int awake, byte* titleId, byte* appName, nint user)
    {
        try
        {
            if (GCHandle.FromIntPtr(user).Target is not List<FoundPs5> list)
                return;
            string? h = Utf8(host);
            if (string.IsNullOrEmpty(h))
                return;
            var item = new FoundPs5(h, Utf8(name) ?? "PS5", awake != 0, Utf8(titleId), Utf8(appName));
            lock (list)
                list.Add(item);
        }
        catch
        {
            // Yerel tarafa istisna sızmaz.
        }
    }

    // ---------------- Uyandırma ----------------

    public void Wake(string host, ulong credential)
    {
        EnsureInitialized();
        byte[] text = NullTerminated(host);
        int r;
        fixed (byte* p = text)
            r = Native.Wake(p, credential);
        if (r != 0)
            throw new RemotePlayException($"Sending the wake-up signal to the PS5 failed ({r})");
    }

    // ---------------- Kayıt ----------------

    sealed class RegisterContext(Action<BridgeLogLevel, string>? log)
    {
        public readonly Action<BridgeLogLevel, string>? Log = log;
    }

    public BridgeRegistration Register(string host, byte[] accountId, uint pin, Action<BridgeLogLevel, string>? log)
    {
        ArgumentNullException.ThrowIfNull(accountId);
        if (accountId.Length != 8)
            throw new ArgumentException("The account ID must be 8 bytes.", nameof(accountId));
        EnsureInitialized();

        var context = new RegisterContext(log);
        var handle = GCHandle.Alloc(context);
        try
        {
            byte[] hostText = NullTerminated(host);
            NativeRegistration output;
            uint reason = 0;
            int r;
            fixed (byte* h = hostText)
            fixed (byte* a = accountId)
                r = Native.Register(h, a, pin, &output, &reason, &OnRegisterLog, GCHandle.ToIntPtr(handle));
            if (r != 0)
                return new BridgeRegistration(r, reason);
            string name = FixedName(new ReadOnlySpan<byte>(output.Name, 0x20));
            byte[] registKey = Copy(output.RegistKey, 0x10);
            byte[] morningKey = Copy(output.Morning, 0x10);
            return new BridgeRegistration(0, 0, name, registKey, morningKey);
        }
        finally
        {
            handle.Free();
        }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    static void OnRegisterLog(int level, byte* message, nint user)
    {
        try
        {
            if (GCHandle.FromIntPtr(user).Target is RegisterContext { Log: { } log })
                log((BridgeLogLevel)level, Utf8(message) ?? "");
        }
        catch
        {
        }
    }

    // ---------------- Oturum ----------------

    sealed class SessionHandle : IBridgeSession
    {
        readonly object gate = new();
        readonly IBridgeSessionCallbacks callbacks;
        GCHandle self;
        nint native;
        bool stopped;

        public SessionHandle(IBridgeSessionCallbacks callbacks)
        {
            this.callbacks = callbacks;
            self = GCHandle.Alloc(this);
        }

        public IBridgeSessionCallbacks Callbacks => callbacks;
        public nint User => GCHandle.ToIntPtr(self);

        public void Attach(nint session) => native = session;

        public void Release()
        {
            if (self.IsAllocated)
                self.Free();
        }

        public int SendLoginPasscode(byte[] passcode)
        {
            lock (gate)
            {
                if (stopped || native == 0)
                    return -1;
                fixed (byte* p = passcode)
                    return Native.SetLoginPin(native, p, (nuint)passcode.Length);
            }
        }

        public void Stop()
        {
            nint session;
            lock (gate)
            {
                if (stopped)
                    return;
                stopped = true;
                session = native;
                native = 0;
            }
            if (session != 0)
                Native.SessionStop(session);
            // Yerel oturum durdu, iş parçacıkları bitti: tutamaç artık bırakılabilir.
            Release();
        }
    }

    public IBridgeSession? StartSession(BridgeSessionRequest request, IBridgeSessionCallbacks callbacks)
    {
        EnsureInitialized();
        byte[] key = KeyBytes.Fit(request.RegistKey, 16);
        byte[] morning = KeyBytes.Fit(request.Morning, 16);
        byte[] account = KeyBytes.Fit(request.AccountId, 8);
        byte[] host = NullTerminated(request.Host);

        var handle = new SessionHandle(callbacks);
        nint session;
        fixed (byte* h = host)
        fixed (byte* k = key)
        fixed (byte* m = morning)
        fixed (byte* a = account)
            session = Native.SessionStart(h, k, m, a, request.MaxFps, &OnFrame, &OnEvent, &OnSessionLog, handle.User);
        if (session == 0)
        {
            handle.Release();
            return null;
        }
        handle.Attach(session);
        return handle;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    static void OnFrame(byte* bgra, int width, int height, int stride, nint user)
    {
        try
        {
            if (GCHandle.FromIntPtr(user).Target is SessionHandle s)
                s.Callbacks.OnFrame(bgra, width, height, stride);
        }
        catch
        {
        }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    static void OnEvent(int code, int quitReason, byte* text, nint user)
    {
        try
        {
            if (GCHandle.FromIntPtr(user).Target is SessionHandle s)
                s.Callbacks.OnEvent(code, quitReason, Utf8(text));
        }
        catch
        {
        }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    static void OnSessionLog(int level, byte* message, nint user)
    {
        try
        {
            if (GCHandle.FromIntPtr(user).Target is SessionHandle s)
                s.Callbacks.OnLog((BridgeLogLevel)level, Utf8(message) ?? "");
        }
        catch
        {
        }
    }

    // ---------------- Yardımcılar ----------------

    static byte[] Copy(byte* source, int length) => new Span<byte>(source, length).ToArray();

    static string? Utf8(byte* text) => text == null ? null : Marshal.PtrToStringUTF8((nint)text);

    static byte[] NullTerminated(string text)
    {
        int n = Encoding.UTF8.GetByteCount(text);
        byte[] buf = new byte[n + 1];
        Encoding.UTF8.GetBytes(text, buf);
        return buf;
    }

    /// <summary>Sabit uzunluklu addan ilk sıfır bayta kadar UTF-8 metin.</summary>
    public static string FixedName(ReadOnlySpan<byte> bytes)
    {
        int end = bytes.IndexOf((byte)0);
        return Encoding.UTF8.GetString(end < 0 ? bytes : bytes[..end]);
    }

    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    struct NativeRegistration
    {
        public fixed byte Name[0x20];
        public fixed byte RegistKey[0x10];
        public fixed byte Morning[0x10];
    }

    static class Native
    {
        [DllImport(LibraryName, EntryPoint = "nino_rp_init", CallingConvention = CallingConvention.Cdecl)]
        public static extern int Init();

        [DllImport(LibraryName, EntryPoint = "nino_rp_discover_ex", CallingConvention = CallingConvention.Cdecl)]
        public static extern int DiscoverEx(byte** targets, int count, int timeoutMs,
            delegate* unmanaged[Cdecl]<byte*, byte*, int, byte*, byte*, nint, void> cb, nint user);

        [DllImport(LibraryName, EntryPoint = "nino_rp_wake", CallingConvention = CallingConvention.Cdecl)]
        public static extern int Wake(byte* host, ulong credential);

        [DllImport(LibraryName, EntryPoint = "nino_rp_register", CallingConvention = CallingConvention.Cdecl)]
        public static extern int Register(byte* host, byte* accountId, uint pin, NativeRegistration* output, uint* reason,
            delegate* unmanaged[Cdecl]<int, byte*, nint, void> log, nint user);

        [DllImport(LibraryName, EntryPoint = "nino_rp_session_start", CallingConvention = CallingConvention.Cdecl)]
        public static extern nint SessionStart(byte* host, byte* registKey, byte* morning, byte* accountId, int maxFps,
            delegate* unmanaged[Cdecl]<byte*, int, int, int, nint, void> frame,
            delegate* unmanaged[Cdecl]<int, int, byte*, nint, void> evt,
            delegate* unmanaged[Cdecl]<int, byte*, nint, void> log, nint user);

        [DllImport(LibraryName, EntryPoint = "nino_rp_session_set_login_pin", CallingConvention = CallingConvention.Cdecl)]
        public static extern int SetLoginPin(nint session, byte* pin, nuint size);

        [DllImport(LibraryName, EntryPoint = "nino_rp_session_stop", CallingConvention = CallingConvention.Cdecl)]
        public static extern void SessionStop(nint session);
    }
}

/// <summary>Köprüye giden anahtarları sabit uzunluğa getirir.</summary>
public static class KeyBytes
{
    /// <summary>Başı kopyalanır, eksik kalan sıfırla doldurulur, fazlası kesilir.</summary>
    public static byte[] Fit(byte[]? source, int length)
    {
        byte[] result = new byte[length];
        if (source is not null)
            Array.Copy(source, result, Math.Min(source.Length, length));
        return result;
    }
}
