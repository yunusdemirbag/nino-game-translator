// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Globalization;
using System.Text;
using Nino.RemotePlay.Bridge;

namespace Nino.RemotePlay;

/// <summary>PS5 oturum şifresi (4 hane).</summary>
public static class LoginPasscode
{
    /// <summary>Baştaki/sondaki boşluk atılır; tam 4 ASCII rakam olmalı; değilse null.</summary>
    public static string? Normalize(string? text)
    {
        if (text is null)
            return null;
        string t = text.Trim();
        return t.Length == 4 && t.All(char.IsAsciiDigit) ? t : null;
    }
}

/// <summary>PS5 şifre istediğinde ne yapılacağı. Bir oturum boyunca aynı şifre ikinci kez gönderilmez.</summary>
public sealed class PasscodeResponder(string? passcode)
{
    readonly string? passcode = LoginPasscode.Normalize(passcode);
    bool sent;

    /// <summary>Gönderilecek baytlar; null ise <paramref name="reason"/> şifre gerekli ya da şifre yanlış.</summary>
    public byte[]? Respond(bool previousWasIncorrect, out DisconnectReason reason)
    {
        lock (this)
        {
            reason = DisconnectReason.LoginPasscode;
            if (previousWasIncorrect || sent)
            {
                reason = DisconnectReason.LoginPasscodeIncorrect;
                return null;
            }
            if (passcode is null)
                return null;
            sent = true;
            return Encoding.ASCII.GetBytes(passcode);
        }
    }
}

/// <summary>Bir neden ve isteğe bağlı ayrıntı.</summary>
public readonly record struct ReasonHint(DisconnectReason Reason, string? Detail = null);

/// <summary>Köprünün kapanma nedenlerinden kullanıcı nedenlerine.</summary>
public static class SessionRules
{
    public const string UnknownSessionRequestError = "Unknown Session Request Error";

    /// <summary>Köprü nedeni: 0 durduruldu, 1 kullanımda, 2 reddetti, 3 ağ, 4 diğer (metin köprünün).</summary>
    public static ReasonHint FromBridge(int quitReason, string? text) => quitReason switch
    {
        BridgeQuit.Stopped => new(DisconnectReason.Stopped),
        BridgeQuit.InUse => new(DisconnectReason.InUse),
        BridgeQuit.Refused => new(DisconnectReason.Refused),
        BridgeQuit.Network => new(DisconnectReason.Network),
        _ => new(DisconnectReason.Other, string.IsNullOrEmpty(text) ? null : text),
    };

    /// <summary>
    /// Oturum isteği ipucu (hata düzeyindeki satırdan). Oturum isteği düşünce chiaki yalnız
    /// "Unknown Session Request Error" der; gerçek neden az önceki satırdadır.
    /// </summary>
    public static ReasonHint? HintFromLine(string? line)
    {
        if (line is null)
            return null;
        const string reasonTag = "Reported Application Reason:";
        int at = line.IndexOf(reasonTag, StringComparison.Ordinal);
        if (at >= 0)
        {
            string rest = line[(at + reasonTag.Length)..].TrimStart();
            int space = rest.IndexOfAny([' ', '\t']);
            string word = space < 0 ? rest : rest[..space];
            if (word.StartsWith("0x", StringComparison.OrdinalIgnoreCase))
                word = word[2..];
            if (!uint.TryParse(word, NumberStyles.AllowHexSpecifier, CultureInfo.InvariantCulture, out uint code))
                return null;
            return code switch
            {
                0x80108b12 => new ReasonHint(DisconnectReason.RemotePlayDisabled),
                0x80108b09 or 0x80108b02 or 0x80108b26 => new ReasonHint(DisconnectReason.RegistrationInvalid),
                _ => new ReasonHint(DisconnectReason.Rejected, "0x" + code.ToString("x8", CultureInfo.InvariantCulture)),
            };
        }
        if (line.Contains("Session request connect failed eventually", StringComparison.Ordinal)
            || line.Contains("Failed to send session request", StringComparison.Ordinal)
            || line.Contains("Failed to receive session request response", StringComparison.Ordinal))
            return new ReasonHint(DisconnectReason.Network);
        return null;
    }

    /// <summary>
    /// Köprü nedeni 4 ve metin tam "Unknown Session Request Error" ise ipucu, ipucu yoksa kodsuz ret; başka her durumda
    /// yalnız köprü nedeni.
    /// </summary>
    public static ReasonHint Merge(int quitReason, string? text, ReasonHint? hint)
    {
        if (quitReason == BridgeQuit.Other && text == UnknownSessionRequestError)
            return hint ?? new ReasonHint(DisconnectReason.Rejected);
        return FromBridge(quitReason, text);
    }

    /// <summary>Son aramada PS5 yanıt vermediyse ağ ve diğer "bulunamadı" olur (ayrıntı kayıtlı adres).</summary>
    public static ReasonHint Classify(ReasonHint reason, bool lastSearchAnswered, string host)
    {
        if (!lastSearchAnswered && reason.Reason is DisconnectReason.Network or DisconnectReason.Other)
            return new ReasonHint(DisconnectReason.NotFound, host);
        return reason;
    }

    /// <summary>Bu nedenlerde yeniden denenmez.</summary>
    public static bool GivesUp(DisconnectReason reason) =>
        reason is DisconnectReason.RegistrationInvalid or DisconnectReason.RemotePlayDisabled
            or DisconnectReason.LoginPasscode or DisconnectReason.LoginPasscodeIncorrect;

    /// <summary>Güvenlik duvarı önerisi sayılmayan nedenler (PS5 bize ulaştı ya da sorun başka).</summary>
    public static bool ExcludesFirewallHint(DisconnectReason reason) =>
        reason is DisconnectReason.ConsoleAsleep or DisconnectReason.InUse or DisconnectReason.Refused
            or DisconnectReason.LoginPasscode or DisconnectReason.LoginPasscodeIncorrect
            or DisconnectReason.RegistrationInvalid or DisconnectReason.Rejected or DisconnectReason.RemotePlayDisabled;
}

/// <summary>Yeniden deneme gecikmesi: 2, 4, 8, 16, 30, 30, … sn.</summary>
public sealed class RetryBackoff
{
    int count;

    public TimeSpan Next()
    {
        int n = Interlocked.Increment(ref count);
        if (n > 5)
        {
            Interlocked.Exchange(ref count, 5);
            n = 5;
        }
        return TimeSpan.FromSeconds(n >= 5 ? 30 : 1 << n);
    }

    public void Reset() => Interlocked.Exchange(ref count, 0);
}

/// <summary>
/// Görüntü bekçisi: bağlıyken son görüntüden (ya da bağlanmadan) bu yana ≥ 8 sn geçtiyse oturum yeniden kurulur
/// (chiaki istenen IDR de bozuk gelince bir daha istemez; bağlantı açık kalır ama kare gelmez).
/// </summary>
public sealed class PictureWatchdog
{
    public const long StallMs = 8000;

    readonly object gate = new();
    bool connected;
    bool finished;
    long lastMs;

    public void Connected(long nowMs)
    {
        lock (gate)
        {
            connected = true;
            finished = false;
            lastMs = nowMs;
        }
    }

    public void Picture(long nowMs)
    {
        lock (gate)
            if (connected && !finished)
                lastMs = nowMs;
    }

    public void Finish()
    {
        lock (gate)
            finished = true;
    }

    /// <summary>Görüntüsüz geçen süre (ms) eşiği aştıysa o süre, değilse null.</summary>
    public long? Stalled(long nowMs)
    {
        lock (gate)
        {
            if (!connected || finished)
                return null;
            long gap = nowMs - lastMs;
            return gap >= StallMs ? gap : null;
        }
    }
}
