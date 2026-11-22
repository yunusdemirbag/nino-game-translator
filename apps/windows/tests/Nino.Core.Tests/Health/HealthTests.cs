// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Net.NetworkInformation;
using Nino.Core.Health;
using Nino.Core.Tests.Data;
using Nino.Core.Text;

namespace Nino.Core.Tests.Health;

public sealed class HealthRecorderTests
{
    static readonly DateTimeOffset Start = new(2026, 11, 22, 18, 0, 0, TimeSpan.Zero);

    [Fact]
    public void Session_CountsAndKeepsAfterEnd()
    {
        var clock = new FakeClock(Start);
        var r = new HealthRecorder(clock);
        Assert.False(r.Snapshot().HasData);
        r.SessionStarted();
        r.Connecting();
        r.PictureArrived();
        clock.Advance(TimeSpan.FromMinutes(2));
        r.LineShown(TimeSpan.FromMilliseconds(400));
        r.LineShown(null);
        r.SessionEnded();
        clock.Advance(TimeSpan.FromMinutes(5));
        var s = r.Snapshot();
        Assert.True(s.HasData);
        Assert.False(s.Active);
        Assert.Equal(120, s.StreamedSeconds, 3);
        Assert.Equal(1, s.Connects);
        Assert.Equal(2, s.Lines);
        Assert.Equal(1, s.Translations);
        Assert.Equal(400, s.MedianTranslationMs);
        r.SessionStarted();
        Assert.Equal(0, r.Snapshot().Lines);
    }

    [Fact]
    public void UserStop_IsNotADrop()
    {
        var r = new HealthRecorder(new FakeClock(Start));
        r.SessionStarted();
        r.PictureArrived();
        r.Disconnected(null);
        var s = r.Snapshot();
        Assert.Equal(0, s.Drops);
        Assert.False(s.IsDisconnected);
        Assert.Null(s.LastReason);
    }

    [Fact]
    public void Example_DropAfter30Minutes()
    {
        var clock = new FakeClock(Start);
        var r = new HealthRecorder(clock);
        r.SessionStarted();
        r.Connecting();
        r.PictureArrived();
        clock.Advance(TimeSpan.FromMinutes(30));
        r.Disconnected("NotFound");
        clock.Advance(TimeSpan.FromSeconds(42));
        var s = r.Snapshot();
        Assert.True(s.IsDisconnected);
        Assert.Equal(1, s.Drops);
        Assert.Equal("NotFound", s.LastReason);
        Assert.Equal(Start.AddMinutes(30), s.DisconnectedSince);
        Assert.Equal(HealthLevel.Problem, HealthVerdicts.Connection(s));
        var cause = HealthCauses.Find(s, NetworkKind.Wifi)[0];
        Assert.Equal(HealthCauseKind.Dropped, cause.Kind);
        Assert.Equal("NotFound", cause.Reason);
        Assert.Contains("PS5 42 sn'den beri yok", HealthSummary.Lines(s, NetworkKind.Wifi)[0]);

        r.PictureArrived();
        s = r.Snapshot();
        Assert.False(s.IsDisconnected);
        Assert.Null(s.DisconnectedSince);
        Assert.Equal(HealthLevel.Good, HealthVerdicts.Connection(s));
    }

    [Fact]
    public void RemotePlayLines_CountStallOnce()
    {
        var clock = new FakeClock(Start);
        var r = new HealthRecorder(clock);
        r.SessionStarted();
        r.PictureArrived();
        r.RemotePlayLine("[chiaki info] Send Buffer re-sending packet 12");
        r.RemotePlayLine("Send Buffer overflow");
        r.RemotePlayLine("FEC failed");
        r.RemotePlayLine("Video FEC failure");
        r.RemotePlayLine("FEC failed");
        r.RemotePlayLine("Received IDR frame");
        r.RemotePlayLine("Video FEC failure");
        r.RemotePlayLine("corrupt frame reported");
        var s = r.Snapshot();
        Assert.Equal(1, s.Resends);
        Assert.Equal(1, s.Overflows);
        Assert.Equal(2, s.Stalls);
        Assert.Equal(1, s.CorruptFrames);
        Assert.Null(s.LossPerMinute);
        clock.Advance(TimeSpan.FromSeconds(30));
        s = r.Snapshot();
        Assert.Equal(4, s.LossPerMinute!.Value, 3);
        Assert.Equal(4, s.StallsPerMinute!.Value, 3);
    }

    [Fact]
    public void NetworkAndTv_CountOnlyWhileActive()
    {
        var r = new HealthRecorder(new FakeClock(Start));
        r.NetworkLost();
        r.TvDropped();
        r.SessionStarted();
        r.NetworkLost();
        r.TvDropped();
        r.TvDropped();
        var s = r.Snapshot();
        Assert.Equal(1, s.NetworkLosses);
        Assert.Equal(2, s.TvDrops);
    }

    [Fact]
    public void Median_KeepsLast200_UpperMiddle()
    {
        var r = new HealthRecorder(new FakeClock(Start));
        r.SessionStarted();
        r.LineShown(TimeSpan.FromMilliseconds(100));
        r.LineShown(TimeSpan.FromMilliseconds(300));
        Assert.Equal(300, r.Snapshot().MedianTranslationMs);
        for (var i = 0; i < 200; i++) r.LineShown(TimeSpan.FromMilliseconds(5000));
        var s = r.Snapshot();
        Assert.Equal(5000, s.MedianTranslationMs);
        Assert.Equal(202, s.Translations);
        Assert.Equal(5000, s.LongestTranslationMs);
    }
}

public sealed class HealthVerdictTests
{
    static HealthSnapshot Snap(double minutes = 10, int resends = 0, int stalls = 0, long? median = null,
        int attempts = 1, int connects = 1, int drops = 0, bool streaming = true, DateTimeOffset? down = null,
        int net = 0, int tv = 0, string? reason = null) => new()
    {
        Now = DateTimeOffset.UnixEpoch.AddHours(1),
        Active = true,
        StartedAt = DateTimeOffset.UnixEpoch,
        Streaming = streaming,
        StreamedSeconds = minutes * 60,
        Resends = resends,
        Stalls = stalls,
        MedianTranslationMs = median,
        ConnectAttempts = attempts,
        Connects = connects,
        Drops = drops,
        DisconnectedSince = down,
        NetworkLosses = net,
        TvDrops = tv,
        LastReason = reason,
    };

    [Theory]
    [InlineData(0.4, 10000, 0, HealthLevel.Unknown)]
    [InlineData(10, 1000, 0, HealthLevel.Problem)]
    [InlineData(10, 0, 40, HealthLevel.Problem)]
    [InlineData(10, 100, 0, HealthLevel.Warning)]
    [InlineData(10, 0, 25, HealthLevel.Warning)]
    [InlineData(10, 99, 24, HealthLevel.Good)]
    public void Picture(double minutes, int resends, int stalls, HealthLevel expected) =>
        Assert.Equal(expected, HealthVerdicts.Picture(Snap(minutes, resends, stalls)));

    [Fact]
    public void Connection()
    {
        Assert.Equal(HealthLevel.Unknown, HealthVerdicts.Connection(new HealthSnapshot()));
        Assert.Equal(HealthLevel.Unknown, HealthVerdicts.Connection(Snap(attempts: 1, connects: 0)));
        Assert.Equal(HealthLevel.Problem, HealthVerdicts.Connection(Snap(attempts: 2, connects: 0)));
        Assert.Equal(HealthLevel.Warning, HealthVerdicts.Connection(Snap(drops: 3)));
        Assert.Equal(HealthLevel.Good, HealthVerdicts.Connection(Snap(drops: 2)));
        Assert.Equal(HealthLevel.Problem,
            HealthVerdicts.Connection(Snap(streaming: false, down: DateTimeOffset.UnixEpoch)));
    }

    [Theory]
    [InlineData(null, HealthLevel.Unknown)]
    [InlineData(3000L, HealthLevel.Problem)]
    [InlineData(1500L, HealthLevel.Warning)]
    [InlineData(1499L, HealthLevel.Good)]
    public void Speed(long? median, HealthLevel expected) =>
        Assert.Equal(expected, HealthVerdicts.Speed(Snap(median: median)));

    [Fact]
    public void Network_FollowsPictureOnWifi()
    {
        var bad = Snap(resends: 2000);
        Assert.Equal(HealthLevel.Good, HealthVerdicts.Network(NetworkKind.Wired, bad));
        Assert.Equal(HealthLevel.Problem, HealthVerdicts.Network(NetworkKind.Offline, Snap()));
        Assert.Equal(HealthLevel.Unknown, HealthVerdicts.Network(NetworkKind.Unknown, Snap()));
        Assert.Equal(HealthLevel.Problem, HealthVerdicts.Network(NetworkKind.Wifi, bad));
        Assert.Equal(HealthLevel.Unknown, HealthVerdicts.Network(NetworkKind.Other, Snap(minutes: 0.1)));
    }

    [Fact]
    public void NetworkDetector()
    {
        Assert.Equal(NetworkKind.Offline, NetworkKindDetector.Decide([]));
        Assert.Equal(NetworkKind.Offline, NetworkKindDetector.Decide(
            [new NetworkAdapter(true, false, false, NetworkInterfaceType.Ethernet),
             new NetworkAdapter(true, true, true, NetworkInterfaceType.Loopback)]));
        Assert.Equal(NetworkKind.Wired, NetworkKindDetector.Decide(
            [new NetworkAdapter(true, false, true, NetworkInterfaceType.Wireless80211),
             new NetworkAdapter(true, false, true, NetworkInterfaceType.GigabitEthernet)]));
        Assert.Equal(NetworkKind.Wifi, NetworkKindDetector.Decide(
            [new NetworkAdapter(true, false, true, NetworkInterfaceType.Wireless80211)]));
        Assert.Equal(NetworkKind.Other, NetworkKindDetector.Decide(
            [new NetworkAdapter(true, false, true, NetworkInterfaceType.Ppp)]));
        Assert.Equal("wifi", NetworkKind.Wifi.Wire());
        Assert.Equal("offline", NetworkKind.Offline.Wire());
    }

    [Fact]
    public void Causes_Order()
    {
        Assert.Empty(HealthCauses.Find(new HealthSnapshot(), NetworkKind.Wifi));
        Assert.Equal([HealthCauseKind.Offline],
            HealthCauses.Find(new HealthSnapshot(), NetworkKind.Offline).Select(c => c.Kind));

        // Ağ yokken PS5 kopması ayrıca sebep değil.
        var down = Snap(streaming: false, down: DateTimeOffset.UnixEpoch, drops: 1, net: 1, reason: "Network");
        Assert.Equal([HealthCauseKind.Offline], HealthCauses.Find(down, NetworkKind.Offline).Select(c => c.Kind));
        // Ağ gitti sonra kopma: ağ kaybından sonra.
        var first = HealthCauses.Find(down, NetworkKind.Wifi)[0];
        Assert.Equal(HealthCauseKind.DroppedAfterNetwork, first.Kind);
        Assert.Equal("Network", first.Reason);

        Assert.Equal(HealthCauseKind.ConsoleAsleep,
            HealthCauses.Find(Snap(streaming: false, down: DateTimeOffset.UnixEpoch, reason: "ConsoleAsleep"),
                NetworkKind.Wired)[0].Kind);
        Assert.Equal(HealthCauseKind.OtherDevice,
            HealthCauses.Find(Snap(streaming: false, down: DateTimeOffset.UnixEpoch, reason: "InUse"),
                NetworkKind.Wired)[0].Kind);
        Assert.Equal(HealthCauseKind.Unreachable,
            HealthCauses.Find(Snap(attempts: 2, connects: 0, streaming: false), NetworkKind.Wired)[0].Kind);

        var flapping = HealthCauses.Find(Snap(net: 2, drops: 4), NetworkKind.Wifi);
        Assert.Equal([HealthCauseKind.NetworkFlapping], flapping.Select(c => c.Kind));
        Assert.Equal(2, flapping[0].Count);

        Assert.Equal([HealthCauseKind.FrequentDrops], HealthCauses.Find(Snap(drops: 3), NetworkKind.Wired).Select(c => c.Kind));
        var lossy = HealthCauses.Find(Snap(resends: 5000, drops: 3, median: 2000, tv: 1), NetworkKind.Wifi);
        Assert.Equal([HealthCauseKind.PictureLossWifi, HealthCauseKind.SlowTranslation, HealthCauseKind.TvDropped],
            lossy.Select(c => c.Kind));
        Assert.True(lossy[0].Severe);
        Assert.Equal(HealthCauseKind.PictureLoss, HealthCauses.Find(Snap(resends: 200), NetworkKind.Wired)[0].Kind);

        var tv = HealthCauses.Find(Snap(tv: 1), NetworkKind.Wired);
        Assert.Single(tv);
        Assert.Equal(1, tv[0].Count);
    }

    [Fact]
    public void Card_AllGoodOnlyWhileStreaming()
    {
        Assert.True(HealthCauseCard.Build(Snap(), NetworkKind.Wired).AllGood);
        Assert.False(HealthCauseCard.Build(Snap(streaming: false), NetworkKind.Wired).Visible);
        Assert.False(HealthCauseCard.Build(Snap(tv: 1), NetworkKind.Wired).AllGood);
    }

    [Fact]
    public void Summary_SixLines()
    {
        var s = Snap(minutes: 31.2, resends: 300, stalls: 12, median: 820) with
        {
            Overflows = 7, CorruptFrames = 5, Lines = 40, Translations = 30, LongestTranslationMs = 2100,
            NetworkLosses = 3, TvDrops = 0, LastReason = "NotFound",
        };
        var lines = HealthSummary.Lines(s, NetworkKind.Wifi);
        Assert.Equal(6, lines.Count);
        Assert.Equal("ağ: wifi, oturumdaki ağ kaybı 3, TV kaybı 0", lines[0]);
        Assert.Equal("akış: 31.2 dk, bağlanma denemesi 1, bağlandı 1, akışta kopma 0", lines[1]);
        Assert.Equal("son kopma sebebi: NotFound", lines[2]);
        Assert.Equal("tekrar istenen paket 300, dolan tampon 7, dakikada 9.8 kayıp", lines[3]);
        Assert.Equal("görüntü durması 12 (0.4/dk), bozuk kare 5", lines[4]);
        Assert.Equal("40 satır okundu, 30 çevrildi; çeviri süresi ortanca 820 ms, en uzun 2100 ms", lines[5]);
        Assert.StartsWith("sağlık: ağ: wifi", HealthSummary.LogLine(s, NetworkKind.Wifi));
        Assert.Contains(" · akış: ", HealthSummary.LogLine(s, NetworkKind.Wifi));

        var empty = HealthSummary.Lines(new HealthSnapshot(), NetworkKind.Unknown);
        Assert.Equal("son kopma sebebi: -", empty[2]);
        Assert.EndsWith("dakikada - kayıp", empty[3]);
        Assert.Contains("ortanca -", empty[5]);
    }
}

public sealed class HealthTextTests
{
    static readonly ITextSource Tr = TextCatalog.For("tr");
    static readonly ITextSource En = TextCatalog.For("en");

    public static TheoryData<HealthCause> AllCauses() =>
    [
        new HealthCause(HealthCauseKind.Offline),
        new HealthCause(HealthCauseKind.DroppedAfterNetwork),
        new HealthCause(HealthCauseKind.ConsoleAsleep),
        new HealthCause(HealthCauseKind.OtherDevice),
        new HealthCause(HealthCauseKind.Dropped),
        new HealthCause(HealthCauseKind.Unreachable),
        new HealthCause(HealthCauseKind.NetworkFlapping, 2),
        new HealthCause(HealthCauseKind.PictureLossWifi),
        new HealthCause(HealthCauseKind.PictureLoss),
        new HealthCause(HealthCauseKind.FrequentDrops, 2),
        new HealthCause(HealthCauseKind.SlowTranslation, MedianMs: 2350),
        new HealthCause(HealthCauseKind.TvDropped, 2),
    ];

    [Theory]
    [MemberData(nameof(AllCauses))]
    public void Turkish_IsOwn_NoMac(HealthCause cause)
    {
        foreach (var text in new[] { cause.Title(Tr), cause.Advice(Tr) })
        {
            Assert.DoesNotContain("Mac", text);
            Assert.DoesNotContain("health.cause", text);
            Assert.DoesNotContain("%", text);
        }
        Assert.NotEqual(cause.Title(En), cause.Title(Tr));
        Assert.NotEqual(cause.Advice(En), cause.Advice(Tr));
        if (cause.Count > 0) Assert.Contains("2 kez", cause.Advice(Tr));
    }

    [Fact]
    public void SlowTranslation_UsesLocalDecimal()
    {
        var cause = new HealthCause(HealthCauseKind.SlowTranslation, MedianMs: 2350);
        Assert.Contains("2,4", cause.Advice(Tr));
        Assert.Contains("2.4", cause.Advice(En));
    }

    [Fact]
    public void ProblemNames_Turkish()
    {
        foreach (var kind in Enum.GetValues<ProblemKind>())
        {
            var record = new ProblemRecord { Kind = kind };
            Assert.NotEqual(record.ShortName(En), record.ShortName(Tr));
            Assert.DoesNotContain("Mac", record.ShortName(Tr));
            Assert.DoesNotContain("health.problem", record.ShortName(Tr));
        }
    }

    [Fact]
    public void CheckRows_TextsResolve()
    {
        var snap = new HealthSnapshot
        {
            Now = DateTimeOffset.UnixEpoch.AddMinutes(20), Active = true, StartedAt = DateTimeOffset.UnixEpoch,
            StreamedSeconds = 600, ConnectAttempts = 3, Connects = 1, Drops = 1, LastReason = "ConsoleAsleep",
            DisconnectedSince = DateTimeOffset.UnixEpoch.AddMinutes(17), Resends = 2000, Stalls = 30,
            MedianTranslationMs = 3200, Translations = 9, Lines = 12,
        };
        var rows = HealthChecks.Build(new HealthCheckInput(snap, NetworkKind.Wifi, true, true, 0, true), Tr);
        Assert.Equal(5, rows.Count);
        Assert.All(rows, r => Assert.Equal(HealthLevel.Problem, r.Level));
        Assert.All(rows, r => Assert.NotNull(r.Advice));
        Assert.All(rows, r => Assert.DoesNotContain("health.", r.Value + r.Name + r.Advice));
        Assert.Equal(Tr.Get("health.check.network.wifi"), rows[0].Value);
        Assert.Equal(Tr.Format("health.check.ps5.disconnectedFor", 3L), rows[1].Value);
        Assert.Equal(Tr.Get("health.check.ps5.advice.asleep"), rows[1].Advice);
        Assert.Contains("200", rows[2].Value);
        Assert.Contains("3,0", rows[2].Value);
        Assert.Contains("3,2", rows[3].Value);
        Assert.Equal(Tr.Get("health.check.speed.advice.freeEngine"), rows[3].Advice);
        Assert.Equal(Tr.Get("status.common.notConnected"), rows[4].Value);
        Assert.Null(HealthChecks.Hint(snap, Tr));

        var none = HealthChecks.Build(new HealthCheckInput(new HealthSnapshot(), null, false, false, 0, false), Tr);
        Assert.All(none, r => Assert.Equal(HealthLevel.Unknown, r.Level));
        Assert.Equal(Tr.Get("translation.key.testing"), none[0].Value);
        Assert.Equal(Tr.Get("health.check.notStarted"), none[1].Value);
        Assert.Equal(Tr.Get("health.check.tv.notSent"), none[4].Value);
        Assert.Equal(Tr.Get("health.checks.hint.noData"), HealthChecks.Hint(new HealthSnapshot(), Tr));
        Assert.Equal(Tr.Get("health.level.unknown"), none[0].LevelText(Tr));
    }

    [Fact]
    public void Ps5Advice_ByReason()
    {
        Assert.Equal("health.check.ps5.advice.pairing", HealthChecks.Ps5AdviceKey("Rejected"));
        Assert.Equal("health.check.ps5.advice.loginPasscode", HealthChecks.Ps5AdviceKey("LoginPasscodeIncorrect"));
        Assert.Equal("health.check.ps5.advice.notFound", HealthChecks.Ps5AdviceKey("NotFound"));
        Assert.Equal("health.check.ps5.advice.other", HealthChecks.Ps5AdviceKey(null));
    }
}
