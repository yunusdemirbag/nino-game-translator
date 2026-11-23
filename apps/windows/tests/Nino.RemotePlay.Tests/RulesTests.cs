// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.RemotePlay.Bridge;

namespace Nino.RemotePlay.Tests;

public class RulesTests
{
    [Theory]
    [InlineData(" 1234 ", "1234")]
    [InlineData("0007", "0007")]
    [InlineData(null, null)]
    [InlineData("", null)]
    [InlineData("123", null)]
    [InlineData("12345", null)]
    [InlineData("12a4", null)]
    [InlineData("١٢٣٤", null)]
    public void PasscodeNormalization(string? input, string? expected) => Assert.Equal(expected, LoginPasscode.Normalize(input));

    [Fact]
    public void PasscodeResponses()
    {
        var withCode = new PasscodeResponder("1234");
        Assert.Equal(new byte[] { 0x31, 0x32, 0x33, 0x34 }, withCode.Respond(false, out _));
        // Aynı şifre ikinci kez gönderilmez.
        Assert.Null(withCode.Respond(false, out var again));
        Assert.Equal(DisconnectReason.LoginPasscodeIncorrect, again);

        Assert.Null(new PasscodeResponder("1234").Respond(true, out var wrong));
        Assert.Equal(DisconnectReason.LoginPasscodeIncorrect, wrong);

        Assert.Null(new PasscodeResponder(null).Respond(false, out var missing));
        Assert.Equal(DisconnectReason.LoginPasscode, missing);
        Assert.Null(new PasscodeResponder("12a4").Respond(false, out missing));
        Assert.Equal(DisconnectReason.LoginPasscode, missing);
    }

    [Fact]
    public void BridgeQuitReasons()
    {
        Assert.Equal(new ReasonHint(DisconnectReason.Stopped), SessionRules.FromBridge(0, null));
        Assert.Equal(new ReasonHint(DisconnectReason.InUse), SessionRules.FromBridge(1, null));
        Assert.Equal(new ReasonHint(DisconnectReason.Refused), SessionRules.FromBridge(2, "ignored"));
        Assert.Equal(new ReasonHint(DisconnectReason.Network), SessionRules.FromBridge(3, null));
        Assert.Equal(new ReasonHint(DisconnectReason.Other, "Version Mismatch"), SessionRules.FromBridge(4, "Version Mismatch"));
    }

    [Theory]
    [InlineData("Reported Application Reason: 0x80108b09 (Regist failed, probably invalid PIN)", DisconnectReason.RegistrationInvalid, null)]
    [InlineData("Reported Application Reason: 0x80108B02 (Invalid PSN ID)", DisconnectReason.RegistrationInvalid, null)]
    [InlineData("Reported Application Reason: 0x80108b26 (unknown)", DisconnectReason.RegistrationInvalid, null)]
    [InlineData("Reported Application Reason: 0x80108b12 (unknown)", DisconnectReason.RemotePlayDisabled, null)]
    [InlineData("Session request connect failed eventually.", DisconnectReason.Network, null)]
    [InlineData("Failed to receive session request response", DisconnectReason.Network, null)]
    [InlineData("Failed to send session request", DisconnectReason.Network, null)]
    [InlineData("Reported Application Reason: 0x80108bff (unknown)", DisconnectReason.Rejected, "0x80108bff")]
    public void SessionRequestHints(string line, DisconnectReason reason, string? detail) =>
        Assert.Equal(new ReasonHint(reason, detail), SessionRules.HintFromLine(line));

    [Theory]
    [InlineData("Reported Application Reason: not-a-code")]
    [InlineData("Session request successful")]
    [InlineData("Failed to parse session request response")]
    [InlineData(null)]
    public void NoHint(string? line) => Assert.Null(SessionRules.HintFromLine(line));

    [Fact]
    public void QuitMerge()
    {
        var hint = new ReasonHint(DisconnectReason.RegistrationInvalid);
        Assert.Equal(hint, SessionRules.Merge(4, "Unknown Session Request Error", hint));
        Assert.Equal(new ReasonHint(DisconnectReason.Rejected), SessionRules.Merge(4, "Unknown Session Request Error", null));
        Assert.Equal(new ReasonHint(DisconnectReason.Other, "Version Mismatch"), SessionRules.Merge(4, "Version Mismatch", hint));
        Assert.Equal(new ReasonHint(DisconnectReason.InUse), SessionRules.Merge(1, null, hint));
    }

    [Fact]
    public void NotFoundClassification()
    {
        const string host = "192.168.1.70";
        Assert.Equal(new ReasonHint(DisconnectReason.NotFound, host), SessionRules.Classify(new(DisconnectReason.Network), false, host));
        Assert.Equal(new ReasonHint(DisconnectReason.NotFound, host), SessionRules.Classify(new(DisconnectReason.Other, "x"), false, host));
        Assert.Equal(new ReasonHint(DisconnectReason.Network), SessionRules.Classify(new(DisconnectReason.Network), true, host));
        Assert.Equal(new ReasonHint(DisconnectReason.InUse), SessionRules.Classify(new(DisconnectReason.InUse), false, host));
        var coded = new ReasonHint(DisconnectReason.Rejected, "0x80108bff");
        Assert.Equal(coded, SessionRules.Classify(coded, false, host));
        Assert.Equal(new ReasonHint(DisconnectReason.RegistrationInvalid),
                     SessionRules.Classify(new(DisconnectReason.RegistrationInvalid), false, host));
    }

    [Fact]
    public void ReasonNamesAreStable()
    {
        string[] expected = ["Stopped", "ConsoleAsleep", "InUse", "Refused", "Network", "LoginPasscode", "NotFound", "Other",
                             "RegistrationInvalid", "LoginPasscodeIncorrect", "Rejected", "RemotePlayDisabled"];
        Assert.Equal(expected.OrderBy(s => s), Enum.GetNames<DisconnectReason>().OrderBy(s => s));
        Assert.True(SessionRules.GivesUp(DisconnectReason.RegistrationInvalid));
        Assert.True(SessionRules.GivesUp(DisconnectReason.LoginPasscodeIncorrect));
        Assert.False(SessionRules.GivesUp(DisconnectReason.Network));
    }

    [Fact]
    public void BackoffSequence()
    {
        var b = new RetryBackoff();
        Assert.Equal(new[] { 2, 4, 8, 16, 30, 30, 30 }, Enumerable.Range(0, 7).Select(_ => (int)b.Next().TotalSeconds));
        b.Reset();
        b.Next();
        b.Next();
        b.Reset();
        Assert.Equal(2, (int)b.Next().TotalSeconds);
    }

    [Fact]
    public void PictureWatchdogRules()
    {
        var w = new PictureWatchdog();
        w.Connected(0);
        for (int s = 1; s <= 120; s++)
            w.Picture(s * 1000);
        Assert.Null(w.Stalled(127_000));
        Assert.Equal(8000, w.Stalled(128_000));

        w = new PictureWatchdog();
        w.Connected(0);
        w.Picture(1000);
        w.Picture(2500);
        Assert.Null(w.Stalled(9000));

        w = new PictureWatchdog();
        w.Connected(0);
        Assert.NotNull(w.Stalled(8000));

        w = new PictureWatchdog();
        w.Picture(0);
        Assert.Null(w.Stalled(600_000));

        w = new PictureWatchdog();
        w.Connected(0);
        w.Finish();
        Assert.Null(w.Stalled(600_000));
    }
}

public class FrameDispatcherTests
{
    [Fact]
    public void BusyHandlerSkipsFramesAndCopiesTight()
    {
        using var release = new ManualResetEventSlim();
        var delivered = new List<VideoFrame>();
        using var first = new ManualResetEventSlim();
        using var dispatcher = new FrameDispatcher(f =>
        {
            lock (delivered)
                delivered.Add(f);
            first.Set();
            release.Wait(5000);
        });

        byte[] padded = [1, 2, 3, 4, 5, 6, 7, 8, 0, 0, 0, 0, 9, 10, 11, 12, 13, 14, 15, 16, 0, 0, 0, 0];
        Assert.True(dispatcher.Offer(padded, 2, 2, 12));
        Assert.True(first.Wait(5000));
        Assert.False(dispatcher.Offer(padded, 2, 2, 12)); // işleyici meşgul: atlanır
        release.Set();
        Thread.Sleep(100);
        Assert.True(dispatcher.Offer(padded, 2, 2, 12));
        Assert.True(Wait.Until(() => { lock (delivered) return delivered.Count == 2; }));
        Thread.Sleep(50);
        lock (delivered)
        {
            Assert.Equal(2, delivered.Count);
            Assert.Equal(8, delivered[0].Stride);
            Assert.Equal(Enumerable.Range(1, 16).Select(i => (byte)i), delivered[0].Bgra);
        }
    }

    [Fact]
    public void HandlerErrorsAreReportedAndDispatchContinues()
    {
        int calls = 0;
        var errors = new List<Exception>();
        using var dispatcher = new FrameDispatcher(_ =>
        {
            Interlocked.Increment(ref calls);
            throw new InvalidOperationException("boom");
        }, e => { lock (errors) errors.Add(e); });
        byte[] px = new byte[4];
        dispatcher.Offer(px, 1, 1, 4);
        Assert.True(Wait.Until(() => Volatile.Read(ref calls) == 1));
        Assert.True(Wait.Until(() => dispatcher.Offer(px, 1, 1, 4)));
        Assert.True(Wait.Until(() => Volatile.Read(ref calls) == 2));
        lock (errors)
            Assert.NotEmpty(errors);
        Assert.False(dispatcher.Offer(px, 2, 1, 4)); // adım genişlikten kısa
    }
}

public class LogTests
{
    [Fact]
    public void LinesArePrefixedAndWritten()
    {
        string dir = Path.Combine(Path.GetTempPath(), "nino-rp-" + Guid.NewGuid().ToString("N"));
        string file = Path.Combine(dir, RemotePlayLog.FileName);
        var seen = new List<string>();
        try
        {
            using (var log = new RemotePlayLog(file))
            {
                log.LineAdded += l => seen.Add(l);
                log.LineAdded += _ => throw new InvalidOperationException("listener failure must not escape");
                log.Chiaki(BridgeLogLevel.Error, "FEC failed");
                log.Chiaki(BridgeLogLevel.Warning, "w");
                log.Chiaki(BridgeLogLevel.Info, "i");
                log.Nino("PS5 oturumu: Streaming");
                log.Flush(TimeSpan.FromSeconds(5));
            }
            Assert.Equal(["[chiaki error] FEC failed", "[chiaki warning] w", "[chiaki info] i", "[nino] PS5 oturumu: Streaming"], seen);
            string[] lines = File.ReadAllLines(file);
            Assert.Equal(4, lines.Length);
            Assert.Matches(@"^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] \[chiaki error\] FEC failed$", lines[0]);
        }
        finally
        {
            if (Directory.Exists(dir))
                Directory.Delete(dir, true);
        }
    }

    [Fact]
    public void TrimKeepsSecondHalf()
    {
        string file = Path.GetTempFileName();
        try
        {
            File.WriteAllText(file, string.Concat(Enumerable.Range(0, 100).Select(i => $"line {i:000}\n")));
            RemotePlayLog.TrimFirstHalf(file);
            string[] lines = File.ReadAllLines(file);
            Assert.True(lines.Length is >= 49 and <= 50);
            Assert.Equal("line 099", lines[^1]);
            Assert.StartsWith("line ", lines[0]);
        }
        finally
        {
            File.Delete(file);
        }
    }

    [Fact]
    public void StallNotes()
    {
        var notes = new PictureStallNotes();
        Assert.Null(notes.Interpret("[chiaki info] Received IDR frame, resuming decode", 0));
        Assert.Equal("görüntü durdu (FEC hatası), IDR karesi bekleniyor", notes.Interpret("[chiaki info] FEC failed, waiting for IDR frame", 1000));
        Assert.Null(notes.Interpret("[chiaki warning] Video FEC failure, already waiting for requested IDR", 1500));
        Assert.Equal("görüntü yeniden geldi (IDR karesi), 700 ms ara", notes.Interpret("[chiaki info] Received IDR frame, resuming decode", 1700));
        notes.Interpret("FEC failed", 2000);
        Assert.Equal("IDR karesi beklenmeyecek; görüntü gelmediği için PS5 oturumu baştan açılıyor (9000 ms ara)",
                     notes.Interpret("[nino] PS5'ten 9 sn'dir görüntü gelmiyor (bağlantı sürüyor); PS5 oturumu baştan açılıyor", 11000));
        Assert.Equal("IDR karesi beklenmeyecek; görüntü gelmediği için PS5 oturumu baştan açılıyor",
                     notes.Interpret("PS5'ten 8 sn'dir görüntü gelmiyor", 20000));
    }
}
