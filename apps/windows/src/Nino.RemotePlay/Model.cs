// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.RemotePlay;

/// <summary>Eşleşmiş PS5: adres, ad, 16 baytlık kayıt anahtarı (ASCII onaltılık) ve 16 baytlık oturum anahtarı.</summary>
public sealed record Ps5Console(string Host, string Name, byte[] RegistKey, byte[] Morning)
{
    /// <summary>
    /// Uyandırma anahtarı: kayıt anahtarının ilk sıfır baytına kadarki ASCII metni onaltılık 64 bit sayı olarak.
    /// Çözülemezse yok.
    /// </summary>
    public ulong? WakeCredential => ComputeWakeCredential(RegistKey);

    public Ps5Console WithHost(string host) => this with { Host = host };

    public static ulong? ComputeWakeCredential(byte[]? registKey)
    {
        if (registKey is null)
            return null;
        int end = Array.IndexOf(registKey, (byte)0);
        if (end < 0)
            end = registKey.Length;
        if (end == 0 || end > 16)
            return null;
        ulong value = 0;
        for (int i = 0; i < end; i++)
        {
            int digit = HexDigit(registKey[i]);
            if (digit < 0)
                return null;
            value = (value << 4) | (uint)digit;
        }
        return value;
    }

    static int HexDigit(byte c) => c switch
    {
        >= (byte)'0' and <= (byte)'9' => c - '0',
        >= (byte)'a' and <= (byte)'f' => c - 'a' + 10,
        >= (byte)'A' and <= (byte)'F' => c - 'A' + 10,
        _ => -1,
    };
}

/// <summary>Aramada bulunan PS5.</summary>
public sealed record FoundPs5(string Host, string Name, bool Awake, string? RunningAppTitleId = null, string? RunningAppName = null);

/// <summary>Kaynağın evresi.</summary>
public enum SourcePhase
{
    Connecting,
    Streaming,
    Disconnected,
}

/// <summary>
/// Kopma nedenleri. Adları günlüğe ve sağlık kaydına metin olarak yazılır; yazımlar değişmez.
/// <see cref="Rejected"/>: PS5 oturumu reddetti; ayrıntı "0x…" kodu ise kodlu ret, ayrıntı yoksa kodsuz ret.
/// </summary>
public enum DisconnectReason
{
    Stopped,
    ConsoleAsleep,
    InUse,
    Refused,
    Network,
    LoginPasscode,
    NotFound,
    Other,
    RegistrationInvalid,
    LoginPasscodeIncorrect,
    Rejected,
    RemotePlayDisabled,
}

/// <summary>Kaynağın durumu: evre ve (bağlı değilken) neden ve ayrıntı.</summary>
public sealed record SourceStatus(SourcePhase Phase, DisconnectReason? Reason = null, string? Detail = null)
{
    public static SourceStatus Connecting { get; } = new(SourcePhase.Connecting);
    public static SourceStatus Streaming { get; } = new(SourcePhase.Streaming);
    public static SourceStatus Down(DisconnectReason reason, string? detail = null) => new(SourcePhase.Disconnected, reason, detail);

    public override string ToString() => Phase switch
    {
        SourcePhase.Disconnected when Detail is { Length: > 0 } => $"{Phase} {Reason} {Detail}",
        SourcePhase.Disconnected => $"{Phase} {Reason}",
        _ => Phase.ToString(),
    };
}

/// <summary>Sıkı ya da dolgulu BGRA kare (piksel başına 4 bayt).</summary>
public sealed record VideoFrame(byte[] Bgra, int Width, int Height, int Stride);

/// <summary>
/// Okuma hattına kare veren görüntü kaynağı (PS5 yolu). Olaylar kaynağın kendi iş parçacığında gelir.
/// </summary>
public interface IVideoSource : IDisposable
{
    event Action<VideoFrame>? FrameArrived;
    event Action<SourceStatus>? StatusChanged;
    /// <summary>PS5 yeni bir adreste bulundu; yeni kayıt saklanmalı.</summary>
    event Action<Ps5Console>? ConsoleMoved;

    void Start();
    /// <summary>Bloklamaz.</summary>
    void Stop();
    /// <summary>Uykudan uyanma, ağ değişimi, güvenlik duvarı kuralı sonrası.</summary>
    void ReconnectNow();
}

/// <summary>Remote Play katmanının hatası (iletisi kullanıcıya/günlüğe gider).</summary>
public class RemotePlayException(string message, Exception? inner = null) : Exception(message, inner);

/// <summary>Yerel köprü (nino_native) bulunamadı ya da yüklenemedi.</summary>
public sealed class NativeLibraryMissingException(string? detail = null)
    : RemotePlayException("Nino's native Remote Play library (nino_native) could not be loaded"
                          + (string.IsNullOrEmpty(detail) ? "." : $": {detail}"));
