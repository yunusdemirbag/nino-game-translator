// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Diagnostics;
using Nino.RemotePlay.Bridge;

namespace Nino.RemotePlay.Tests;

public class FinderTests
{
    [Fact]
    public void SubnetHostsOfSlash24()
    {
        var hosts = Ps5Finder.SubnetHosts(Ps5Finder.ToUInt("192.168.1.10"), 0xFFFFFF00);
        Assert.Equal(253, hosts.Count);
        Assert.Equal("192.168.1.1", Ps5Finder.ToText(hosts[0]));
        Assert.Equal("192.168.1.254", Ps5Finder.ToText(hosts[^1]));
        Assert.DoesNotContain(Ps5Finder.ToUInt("192.168.1.10"), hosts);
    }

    [Fact]
    public void SubnetSizeLimits()
    {
        Assert.Equal(1021, Ps5Finder.SubnetHosts(Ps5Finder.ToUInt("192.168.0.1"), 0xFFFFFC00).Count);
        Assert.Empty(Ps5Finder.SubnetHosts(Ps5Finder.ToUInt("192.168.0.1"), 0xFFFFF800));
        Assert.Empty(Ps5Finder.SubnetHosts(Ps5Finder.ToUInt("10.0.0.1"), 0xFFFF0000));
        Assert.Empty(Ps5Finder.SubnetHosts(Ps5Finder.ToUInt("10.0.0.1"), 0xFFFFFFFF));
    }

    [Fact]
    public void AddressConversions()
    {
        Assert.Equal(0xC0A8010Au, Ps5Finder.ToUInt("192.168.1.10"));
        Assert.Equal("192.168.1.10", Ps5Finder.ToText(0xC0A8010A));
        Assert.Equal("192.168.1.254", Ps5Finder.ToText(0xC0A801FE));
    }

    [Fact]
    public void LocalTargetsAlwaysEndWithBroadcast()
    {
        var targets = Ps5Finder.LocalTargets();
        Assert.Contains(Ps5Finder.Broadcast, targets);
        Assert.Equal(Ps5Finder.Broadcast, targets[^1]);
        Assert.Equal(targets.Distinct().Count(), targets.Count);
        Assert.False(targets.Contains("127.0.0.1"));

        var twice = Ps5Finder.TargetsFor([(Ps5Finder.ToUInt("192.168.1.10"), 0xFFFFFF00), (Ps5Finder.ToUInt("192.168.1.20"), 0xFFFFFF00)]);
        Assert.Equal(twice.Count, twice.Distinct().Count());
        Assert.Equal([Ps5Finder.Broadcast], Ps5Finder.TargetsFor([]));
    }

    [Fact]
    public void PickMovedConsole()
    {
        var a = new FoundPs5("192.168.1.5", "PS5-A", true);
        var b = new FoundPs5("192.168.1.6", "PS5-B", true);
        Assert.Equal(a, Ps5Finder.PickMoved([a], "başka ad"));
        Assert.Equal(b, Ps5Finder.PickMoved([a, b], "PS5-B"));
        Assert.Null(Ps5Finder.PickMoved([a, b], "başka ad"));
        Assert.Null(Ps5Finder.PickMoved([], "PS5-A"));
    }

    [Fact]
    public void RepliesAreCollapsedAndSorted()
    {
        var replies = new[]
        {
            new FoundPs5("192.168.1.9", "X", false),
            new FoundPs5("192.168.1.10", "Y", true),
            new FoundPs5("192.168.1.9", "X", true),
        };
        var list = Ps5Finder.Collapse(replies);
        Assert.Equal(2, list.Count);
        Assert.Equal("192.168.1.10", list[0].Host); // sıradan dizgi sıralaması
        Assert.True(list[1].Awake);                 // sonraki yanıt öncekinin yerine
        Assert.Equal("PS5 araması: bulunamadı", Ps5Finder.Summary([]));
        Assert.Equal("PS5 araması: Y 192.168.1.10, X 192.168.1.9 (dinlenmede)",
                     Ps5Finder.Summary([list[0], replies[0]]));
    }

    [NeedsNative]
    public async Task NativeSearchOfLoopbackReturnsEmpty()
    {
        var finder = new Ps5Finder(NativeBridge.Shared);
        var watch = Stopwatch.StartNew();
        var found = await finder.SearchAsync("127.0.0.1", TimeSpan.FromMilliseconds(600));
        watch.Stop();
        Assert.Empty(found);
        Assert.InRange(watch.ElapsedMilliseconds, 400, 5000);
        Assert.Empty(NativeBridge.Shared.Discover(["not-an-address"], 100));
    }
}

public class PairingTests
{
    [Theory]
    [InlineData("12345678", 12345678u)]
    [InlineData("1234 5678", 12345678u)]
    [InlineData(" 1234-5678\n", 12345678u)]
    [InlineData("１２３４５６７８", 12345678u)]
    [InlineData("١٢٣٤٥٦٧٨", 12345678u)]
    [InlineData("01234567", 1234567u)]
    [InlineData("1234.5678", 12345678u)]
    [InlineData("1234_56–78", 12345678u)]
    public void CodeParses(string text, uint expected) => Assert.Equal(expected, PairingCode.TryParse(text));

    [Theory]
    [InlineData("")]
    [InlineData(null)]
    [InlineData("1234567")]
    [InlineData("123456789")]
    [InlineData("1234567O")]
    [InlineData("1234567½")]
    public void CodeIsRejected(string? text) => Assert.Null(PairingCode.TryParse(text));

    [Fact]
    public void ReasonCodesAreClassified()
    {
        Assert.Equal(PairingOutcome.WrongAccount, Ps5Pairing.Classify(1, 0x80108b02, []).Outcome);
        Assert.Equal(PairingOutcome.WrongCode, Ps5Pairing.Classify(1, 0x80108b09, []).Outcome);
        Assert.Equal(PairingOutcome.InUse, Ps5Pairing.Classify(1, 0x80108b10, []).Outcome);
        Assert.Equal(PairingOutcome.VersionMismatch, Ps5Pairing.Classify(1, 0x80108b11, []).Outcome);
        Assert.Equal(PairingOutcome.ConsoleCrashed, Ps5Pairing.Classify(1, 0x80108b15, []).Outcome);
        Assert.Equal(PairingOutcome.Failed, Ps5Pairing.Classify(1, 0x80108bff, []).Outcome);
        Assert.Equal(PairingOutcome.Failed, Ps5Pairing.Classify(1, 0, []).Outcome);
        // Kod istendiyse konsol zaten bulunmuş, yani bulma adımı tamam.
        Assert.Equal(PairingOutcome.WrongCode,
                     Ps5Pairing.Classify(1, 0x80108b09, ["Regist timed out waiting for search response"]).Outcome);
        Assert.Equal((PairingOutcome.NoReply, "the PS5 did not reply in 30 seconds"), Ps5Pairing.Classify(2, 0, []));
        Assert.Equal((PairingOutcome.Failed, "native error -1"), Ps5Pairing.Classify(-1, 0, []));
    }

    [Theory]
    [InlineData("Regist failed to send search: Unknown error", "Regist search failed", PairingOutcome.NoAnswer)]
    [InlineData("Regist connect failed: 10060", "Regist eventually failed to connect for request", PairingOutcome.NoAnswer)]
    [InlineData("Regist eventually failed to connect for search", "Regist search failed", PairingOutcome.NoAnswer)]
    [InlineData("Regist failed to getaddrinfo on 192.168.1.", "Regist eventually failed", PairingOutcome.BadAddress)]
    [InlineData("Regist failed to receive response HTTP header", "Regist eventually failed", PairingOutcome.NoReply)]
    [InlineData("Regist timed out receiving response content", "Regist eventually failed", PairingOutcome.NoReply)]
    [InlineData("Regist response is missing RegistKey (or it was invalid)", "Regist eventually failed", PairingOutcome.Failed)]
    [InlineData("Regist timed out waiting for search response", "Regist search failed", PairingOutcome.NoAnswer)]
    public void ErrorLinesAreClassified(string first, string second, PairingOutcome expected) =>
        Assert.Equal(expected, Ps5Pairing.Classify(1, 0, [first, second]).Outcome);

    [Fact]
    public void DetailComesFromReasonLineOrFirstError()
    {
        Assert.Equal("0x80108b09 (Regist Failed)", Ps5Pairing.Detail(
            ["Regist received HTTP code 403", "Reported Application Reason: 0x80108b09 (Regist Failed)", "Regist eventually failed"]));
        Assert.Equal("Regist received HTTP code 500", Ps5Pairing.Detail(["Regist received HTTP code 500", "Regist eventually failed"]));
        Assert.Null(Ps5Pairing.Detail([]));
    }

    [Fact]
    public async Task PairingNeedsEightByteAccount()
    {
        var pairing = new Ps5Pairing(new FakeBridge(), RemotePlayLog.Silent());
        await Assert.ThrowsAsync<ArgumentException>(() => pairing.PairAsync("192.168.1.2", 12345678, [1, 2, 3, 4]));
    }

    [Fact]
    public async Task NoAnswerIsRetriedThreeTimes()
    {
        var bridge = new FakeBridge();
        bridge.RegisterErrorLines.Add("Regist timed out waiting for search response");
        var pairing = new Ps5Pairing(bridge, RemotePlayLog.Silent());
        var e = await Assert.ThrowsAsync<PairingException>(() => pairing.PairAsync("192.168.1.2", 12345678, Samples.Account));
        Assert.Equal(PairingOutcome.NoAnswer, e.Outcome);
        Assert.Equal(3, bridge.RegisterCalls);
        Assert.False(e.ConsoleReported);
    }

    [Fact]
    public async Task OtherFailuresAreNotRetried()
    {
        var bridge = new FakeBridge { OnRegister = _ => new BridgeRegistration(1, 0x80108b02) };
        bridge.RegisterErrorLines.Add("Reported Application Reason: 0x80108b02 (Invalid PSN ID)");
        var pairing = new Ps5Pairing(bridge, RemotePlayLog.Silent());
        var e = await Assert.ThrowsAsync<PairingException>(() => pairing.PairAsync("192.168.1.2", 12345678, Samples.Account));
        Assert.Equal(PairingOutcome.WrongAccount, e.Outcome);
        Assert.Equal("0x80108b02 (Invalid PSN ID)", e.Detail);
        Assert.Equal(0x80108b02u, e.Reason);
        Assert.True(e.ConsoleReported);
        Assert.Equal(1, bridge.RegisterCalls);
    }

    [Fact]
    public async Task SuccessKeepsEnteredAddress()
    {
        byte[] key = "abcdef12\0\0\0\0\0\0\0\0"u8.ToArray();
        byte[] morning = Enumerable.Range(1, 16).Select(i => (byte)i).ToArray();
        var bridge = new FakeBridge
        {
            OnRegister = n => n < 2 ? new BridgeRegistration(1, 0) : new BridgeRegistration(0, 0, "PS5-777", key, morning),
        };
        bridge.RegisterErrorLines.Add("Regist search failed");
        var lines = new List<string>();
        var log = RemotePlayLog.Silent();
        log.LineAdded += l => { lock (lines) lines.Add(l); };
        var console = await new Ps5Pairing(bridge, log).PairAsync("192.168.1.44", 12345678, Samples.Account);
        Assert.Equal("192.168.1.44", console.Host);
        Assert.Equal("PS5-777", console.Name);
        Assert.Equal(key, console.RegistKey);
        Assert.Equal(morning, console.Morning);
        Assert.Equal(2, bridge.RegisterCalls);
        lock (lines)
        {
            Assert.Contains("[nino] PS5 eşleştirmesi başladı (192.168.1.44); hesap kimliği AQEBAQEBAQE=", lines);
            Assert.Contains("[chiaki error] Regist search failed", lines);
            Assert.Contains("[nino] PS5 eşleşmesi kuruldu (192.168.1.44): PS5-777", lines);
        }
    }

    [NeedsNative]
    public async Task NativePairingWithLoopbackGetsNoAnswer()
    {
        var pairing = new Ps5Pairing(NativeBridge.Shared, RemotePlayLog.Silent());
        var e = await Assert.ThrowsAsync<PairingException>(() => pairing.PairAsync("127.0.0.1", 12345678, Samples.Account));
        Assert.Equal(PairingOutcome.NoAnswer, e.Outcome);
    }
}
