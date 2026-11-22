// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.RemotePlay.Bridge;

/// <summary>Köprü günlük düzeyleri (chiaki'nin).</summary>
public enum BridgeLogLevel
{
    Error = 0,
    Warning = 1,
    Info = 2,
}

/// <summary>Köprünün oturum olay kodları (sayılar sabit).</summary>
public static class BridgeEvent
{
    public const int Connected = 0;
    public const int Quit = 1;
    public const int LoginPasscode = 2;
}

/// <summary>Köprünün kapanma nedeni kodları (olay 1).</summary>
public static class BridgeQuit
{
    public const int Stopped = 0;
    public const int InUse = 1;
    public const int Refused = 2;
    public const int Network = 3;
    public const int Other = 4;
}

/// <summary>Kayıt işlevinin ham sonucu.</summary>
/// <param name="Code">0 başarı, 1 başarısız, 2 iptal (süre doldu), &lt;0 başlatılamadı.</param>
/// <param name="Reason">PS5'in bildirdiği neden kodu (yalnız Code 1'de; bilinmiyorsa 0).</param>
public sealed record BridgeRegistration(int Code, uint Reason, string? Name = null, byte[]? RegistKey = null, byte[]? Morning = null);

/// <summary>Oturum açma bilgisi. Anahtarlar köprüye sabit uzunlukta gider.</summary>
public sealed record BridgeSessionRequest(string Host, byte[] RegistKey, byte[] Morning, byte[] AccountId, int MaxFps);

/// <summary>Yerel oturumun geri çağrıları (köprünün iş parçacığında; hızlı dönmeli, istisna atmamalı).</summary>
public interface IBridgeSessionCallbacks
{
    /// <summary>BGRA kare; bellek yalnız çağrı süresince geçerlidir.</summary>
    unsafe void OnFrame(byte* bgra, int width, int height, int stride);
    void OnEvent(int code, int quitReason, string? reasonText);
    void OnLog(BridgeLogLevel level, string line);
}

/// <summary>Açık bir yerel oturum.</summary>
public interface IBridgeSession
{
    /// <summary>Giriş şifresini gönderir; 0 başarı. Olay geri çağrısının içinden çağrılmamalı.</summary>
    int SendLoginPasscode(byte[] passcode);

    /// <summary>Durdurur, iş parçacıklarını bekler (bloklar). Döndükten sonra geri çağrı gelmez. Bir kez.</summary>
    void Stop();
}

/// <summary>Yerel Remote Play köprüsü (nino_native). Testler sahte uygulama kullanır.</summary>
public interface IRemotePlayBridge
{
    /// <summary>Kütüphane yüklenebiliyor mu (yükler, bırakır).</summary>
    bool IsAvailable();

    /// <summary>Ağ yığınını bir kez hazırlar; hata olursa <see cref="RemotePlayException"/>.</summary>
    void EnsureInitialized();

    /// <summary>Bloklayarak arar; bulunan her yanıt (aynı PS5 birden çok kez gelebilir).</summary>
    IReadOnlyList<FoundPs5> Discover(IReadOnlyList<string> targets, int timeoutMs);

    /// <summary>Uyandırma paketini gönderir; köprü hatasında <see cref="RemotePlayException"/>.</summary>
    void Wake(string host, ulong credential);

    /// <summary>Bloklayarak (en çok ~30 sn) kayıt olur.</summary>
    BridgeRegistration Register(string host, byte[] accountId, uint pin, Action<BridgeLogLevel, string>? log);

    /// <summary>Oturum açar; açılamazsa null (neden hata satırı olarak <see cref="IBridgeSessionCallbacks.OnLog"/>'a gelir).</summary>
    IBridgeSession? StartSession(BridgeSessionRequest request, IBridgeSessionCallbacks callbacks);
}
