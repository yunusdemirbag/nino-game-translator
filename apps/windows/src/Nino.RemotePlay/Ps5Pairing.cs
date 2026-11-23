// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Globalization;
using Nino.RemotePlay.Bridge;

namespace Nino.RemotePlay;

/// <summary>Eşleşme sonucu (adları günlüğe yazılır).</summary>
public enum PairingOutcome
{
    Success,
    WrongAccount,
    WrongCode,
    InUse,
    VersionMismatch,
    ConsoleCrashed,
    BadAddress,
    NoAnswer,
    NoReply,
    Failed,
}

/// <summary>Eşleşme başarısız oldu.</summary>
public sealed class PairingException(PairingOutcome outcome, uint reason, string? detail)
    : RemotePlayException($"PS5 pairing failed: {outcome}" + (string.IsNullOrEmpty(detail) ? "" : $" ({detail})"))
{
    public PairingOutcome Outcome { get; } = outcome;

    /// <summary>PS5'in bildirdiği neden kodu (0: bildirmedi).</summary>
    public uint Reason { get; } = reason;

    public string? Detail => detail;

    /// <summary>PS5 kendi kodunu bildirdi mi (bildirdiyse güvenlik duvarı önerisi gerekmez).</summary>
    public bool ConsoleReported => Reason != 0;
}

/// <summary>PS5'in "Cihazı Eşleştir" ekranındaki sekiz rakamlı kodu okur.</summary>
public static class PairingCode
{
    /// <summary>
    /// Boşluk, <c>-</c>, <c>–</c>, <c>.</c>, <c>_</c> atlanır; geri kalan her karakter Unicode ondalık rakam olmalı ve tam
    /// 8 rakam olmalı. Değilse null.
    /// </summary>
    public static uint? TryParse(string? text)
    {
        if (text is null)
            return null;
        uint value = 0;
        int digits = 0;
        for (int i = 0; i < text.Length; i++)
        {
            char c = text[i];
            if (char.IsWhiteSpace(c) || c is '-' or '–' or '.' or '_')
                continue;
            int d;
            if (char.IsHighSurrogate(c) && i + 1 < text.Length)
            {
                if (CharUnicodeInfo.GetUnicodeCategory(text, i) != UnicodeCategory.DecimalDigitNumber)
                    return null;
                d = (int)CharUnicodeInfo.GetDecimalDigitValue(text, i);
                i++;
            }
            else
            {
                if (CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.DecimalDigitNumber)
                    return null;
                d = CharUnicodeInfo.GetDecimalDigitValue(c);
            }
            if (d < 0 || d > 9 || ++digits > 8)
                return null;
            value = value * 10 + (uint)d;
        }
        return digits == 8 ? value : null;
    }
}

/// <summary>PS5 ile eşleşme (kayıt). Sonuç sınıflaması ve "yanıt vermedi"de yeniden deneme.</summary>
public sealed class Ps5Pairing(IRemotePlayBridge bridge, RemotePlayLog log)
{
    public const int Attempts = 3;
    public static readonly TimeSpan RetryDelay = TimeSpan.FromMilliseconds(500);

    /// <summary>
    /// Eşleşir; başarıda adres = girilen adres olan kayıt döner, değilse <see cref="PairingException"/>.
    /// Uzun ömürlü iş parçacığında koşar; iptal yalnız beklemeyi bırakır.
    /// </summary>
    public Task<Ps5Console> PairAsync(string host, uint pin, byte[] accountId, CancellationToken cancel = default)
    {
        ArgumentNullException.ThrowIfNull(accountId);
        if (accountId.Length != 8)
            throw new ArgumentException("The account ID must be 8 bytes.", nameof(accountId));
        var work = Task.Factory.StartNew(() => Pair(host, pin, accountId), CancellationToken.None,
                                         TaskCreationOptions.LongRunning, TaskScheduler.Default);
        return work.WaitAsync(cancel);
    }

    Ps5Console Pair(string host, uint pin, byte[] accountId)
    {
        log.Nino($"PS5 kaydı başlıyor: {host}, hesap kimliği {Convert.ToBase64String(accountId)}");
        for (int attempt = 1; ; attempt++)
        {
            var errors = new List<string>();
            BridgeRegistration result = bridge.Register(host, accountId, pin, (level, line) =>
            {
                log.Chiaki(level, line);
                if (level == BridgeLogLevel.Error)
                    lock (errors)
                        errors.Add(line);
            });

            if (result.Code == 0)
            {
                var console = new Ps5Console(host, result.Name ?? "", KeyBytes.Fit(result.RegistKey, 16),
                                             KeyBytes.Fit(result.Morning, 16));
                log.Nino($"PS5 eşleşmesi kuruldu ({host}): {console.Name}");
                return console;
            }

            string[] lines;
            lock (errors)
                lines = errors.ToArray();
            var (outcome, detail) = Classify(result.Code, result.Reason, lines);
            log.Nino($"PS5 eşleşmesi kurulamadı ({host}, {attempt}. deneme): {outcome} {detail}".TrimEnd());
            if (outcome == PairingOutcome.NoAnswer && attempt < Attempts)
            {
                Thread.Sleep(RetryDelay);
                continue;
            }
            throw new PairingException(outcome, result.Code == 1 ? result.Reason : 0, detail);
        }
    }

    /// <summary>Köprü dönüşü, PS5'in nedeni ve hata satırlarından sonuç ve ayrıntı.</summary>
    public static (PairingOutcome Outcome, string? Detail) Classify(int code, uint reason, IReadOnlyList<string> errorLines)
    {
        if (code == 0)
            return (PairingOutcome.Success, null);
        if (code == 2)
            return (PairingOutcome.NoReply, "the PS5 did not reply in 30 seconds");
        if (code < 0)
            return (PairingOutcome.Failed, $"native error {code}");
        return (Outcome(reason, errorLines), Detail(errorLines));
    }

    public static PairingOutcome Outcome(uint reason, IReadOnlyList<string> errorLines)
    {
        switch (reason)
        {
            case 0x80108b02: return PairingOutcome.WrongAccount;
            case 0x80108b09: return PairingOutcome.WrongCode;
            case 0x80108b10: return PairingOutcome.InUse;
            case 0x80108b11: return PairingOutcome.VersionMismatch;
            case 0x80108b15: return PairingOutcome.ConsoleCrashed;
        }
        if (reason != 0)
            return PairingOutcome.Failed;
        if (Any(errorLines, "getaddrinfo"))
            return PairingOutcome.BadAddress;
        if (Any(errorLines, "search response", "connect for search", "send search", "Regist search failed",
                "connect for request", "Regist connect failed"))
            return PairingOutcome.NoAnswer;
        if (Any(errorLines, "response HTTP header", "receiving response content", "receive response content"))
            return PairingOutcome.NoReply;
        return PairingOutcome.Failed;
    }

    /// <summary>"Reported Application Reason: " satırının devamı; yoksa ilk hata satırı; yoksa null.</summary>
    public static string? Detail(IReadOnlyList<string> errorLines)
    {
        const string marker = "Reported Application Reason: ";
        foreach (string line in errorLines)
        {
            int at = line.IndexOf(marker, StringComparison.Ordinal);
            if (at >= 0)
                return line[(at + marker.Length)..];
        }
        return errorLines.Count > 0 ? errorLines[0] : null;
    }

    static bool Any(IReadOnlyList<string> lines, params string[] needles) =>
        lines.Any(l => needles.Any(n => l.Contains(n, StringComparison.Ordinal)));
}
