// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Settings;
using Nino.Shell.Platform;
using Nino.Shell.WindowsRules;

namespace Nino.Shell.Tests.WindowsRules;

// Kaynak kuralları (kaynaklar §2–§3) ve küçük sistem kuralları (kimlikler-veri §10, §12) örnekleri.
public sealed class CaptureAndSystemRulesTests
{
    static CaptureDevice D(string name, string? container = null) => new(name, name, container);

    [Theory]
    [InlineData("Laptop IR Camera|AVerMedia Live Gamer 4K|Logitech StreamCam", "AVerMedia Live Gamer 4K")]
    [InlineData("Dell HD Camera Module|UVC Capture Device", "UVC Capture Device")]
    [InlineData("Acer Webcam HD|Logitech C922 Pro", null)]
    [InlineData("Rear Camera|Generic 1080P|Other", "Generic 1080P")]
    public void PicksCard(string names, string? expected)
    {
        var list = names.Split('|').Select(n => D(n)).ToList();
        Assert.Equal(expected, CaptureCardRules.PickVideo(list, null)?.Name);
    }

    [Fact]
    public void PicksPreferredOrFallsBack()
    {
        var list = new[] { new CaptureDevice("a", "Capture A"), new CaptureDevice("b", "Capture B") };
        Assert.Null(CaptureCardRules.PickVideo([], null));
        Assert.Equal("b", CaptureCardRules.PickVideo(list, "b")?.Id);
        Assert.Equal("a", CaptureCardRules.PickVideo(list, "gone")?.Id);
    }

    [Fact]
    public void PicksCardAudio()
    {
        var card = new CaptureDevice("v", "Live Gamer Ultra", "{1234}");
        var audio = new[] { new CaptureDevice("m", "Microphone (Realtek)", "{9999}"), new CaptureDevice("d", "Line In (Card Audio)", "{1234}") };
        Assert.Equal("Line In (Card Audio)", CaptureCardRules.PickAudio(card, audio)?.Name);

        var camLink = new CaptureDevice("v", "Cam Link 4K");
        Assert.Equal("Cam Link 4K", CaptureCardRules.PickAudio(camLink, [D("Microphone"), D("Cam Link 4K")])?.Name);
        Assert.Null(CaptureCardRules.PickAudio(camLink, [D("Microphone")]));

        const string sys = "{00000000-0000-0000-FFFF-FFFFFFFFFFFF}";
        var integrated = new CaptureDevice("v", "Integrated HDMI Capture", sys);
        Assert.Null(CaptureCardRules.PickAudio(integrated, [new CaptureDevice("m", "Microphone", sys)]));
    }

    [Fact]
    public void PicksFormat()
    {
        var formats = new[]
        {
            new CaptureFormat(3840, 2160, 30, "NV12"), new CaptureFormat(1920, 1080, 30, "NV12"),
            new CaptureFormat(1920, 1080, 60, "MJPG"), new CaptureFormat(1920, 1080, 59.94, "YUY2"),
            new CaptureFormat(1280, 720, 60, "NV12"),
        };
        Assert.Equal(new CaptureFormat(1920, 1080, 59.94, "YUY2"), CaptureCardRules.PickFormat(formats));
        var second = new[]
        {
            new CaptureFormat(3840, 2160, 30, "NV12"), new CaptureFormat(1280, 720, 60, "NV12"),
            new CaptureFormat(640, 480, 60, "YUY2"),
        };
        Assert.Equal(new CaptureFormat(1280, 720, 60, "NV12"), CaptureCardRules.PickFormat(second));
        Assert.Null(CaptureCardRules.PickFormat(Array.Empty<CaptureFormat>()));
    }

    [Theory]
    [InlineData(0, double.NegativeInfinity, true)]
    [InlineData(0.05, 0, false)]
    [InlineData(0.1, 0, true)]
    public void ReadCadence(double now, double last, bool due) => Assert.Equal(due, CaptureCardRules.ReadDue(now, last));

    [Fact]
    public void BlackFrames()
    {
        Assert.True(CaptureCardRules.IsBlack(new byte[640 * 360 * 4], 640, 360, 640 * 4));
        Assert.True(CaptureCardRules.IsBlack(Filled(640 * 360 * 4, 20), 640, 360, 640 * 4));
        Assert.False(CaptureCardRules.IsBlack(Filled(640 * 360 * 4, 40), 640, 360, 640 * 4));
        Assert.True(CaptureCardRules.IsBlack(new byte[700 * 4 * 360], 640, 360, 700 * 4));
        var green = new byte[640 * 360 * 4];
        green[(16 * 640 + 16) * 4 + 1] = 200;
        Assert.False(CaptureCardRules.IsBlack(green, 640, 360, 640 * 4));
    }

    static byte[] Filled(int n, byte v)
    {
        var b = new byte[n];
        Array.Fill(b, v);
        return b;
    }

    [Fact]
    public void BlackWatchNeedsFourSeconds()
    {
        var w = new BlackPictureWatch();
        Assert.False(w.Feed(true, 10));
        Assert.False(w.Feed(true, 13.9));
        Assert.True(w.Feed(true, 14));
        Assert.False(w.Feed(false, 14.1));
        Assert.False(w.Feed(true, 15));
        Assert.False(w.Feed(true, 18.5));
        Assert.True(w.Feed(true, 19));
    }

    [Fact]
    public void StallWatchBacksOff()
    {
        var s = new CardStallWatch();
        Assert.Null(s.Tick(10, 9));
        Assert.Equal(3, s.Tick(13, 10));
        Assert.Equal(6, s.Interval);
        Assert.Null(s.Tick(18, 10));
        Assert.Equal(9, s.Tick(19, 10));
        Assert.Equal(12, s.Interval);
        Assert.Null(s.Tick(20, 19));
        Assert.Equal(3, s.Interval);
        for (var i = 0; i < 10; i++) s.Tick(1000 + i * 100, 0);
        Assert.Equal(30, s.Interval);
    }

    [Fact]
    public void OutputIsAlways1080p()
    {
        var src = new byte[4 * 2 * 4];
        src[0] = 7;
        var outFrame = CaptureCardRules.ToOutput(src, 4, 2, 16);
        Assert.Equal(1920 * 1080 * 4, outFrame.Length);
        Assert.Equal(7, outFrame[0]);
        var same = new byte[1920 * 1080 * 4];
        same[^4] = 9;
        Assert.Equal(9, CaptureCardRules.ToOutput(same, 1920, 1080, 1920 * 4)[^4]);
    }

    [Fact]
    public void WindowGrabFallsBackToScreenCopy()
    {
        var g = new WindowGrabState();
        for (var i = 1; i < 30; i++)
        {
            Assert.True(g.TryWindowFirst());
            Assert.Equal(WindowGrabStep.SendBlack, g.AfterWindow(false, out _));
        }
        Assert.Equal(WindowGrabStep.CopyScreen, g.AfterWindow(false, out _));
        Assert.False(g.AfterScreen(screenBlack: true));
        Assert.Equal(0, g.BlackCount);
        for (var i = 0; i < 30; i++) g.AfterWindow(false, out _);
        Assert.True(g.AfterScreen(screenBlack: false));
        Assert.True(g.ScreenCopy);
        var tries = Enumerable.Range(0, 40).Count(_ => g.TryWindowFirst());
        Assert.Equal(2, tries);
        Assert.Equal(WindowGrabStep.UseWindow, g.AfterWindow(true, out var left));
        Assert.True(left);
        Assert.False(g.ScreenCopy);
    }

    [Fact]
    public void GameWindowBlackSampling()
    {
        var area = new PixelRect(0, 0, 90, 90);
        var buf = new byte[90 * 90 * 4];
        Assert.True(GameWindowCaptureRules.IsBlack(buf, 90 * 4, area));
        buf[(40 * 90 + 40) * 4 + 2] = 1;
        Assert.False(GameWindowCaptureRules.IsBlack(buf, 90 * 4, area));
    }

    [Fact]
    public void GameAreaOnScreenAddsOrigin()
    {
        Assert.Equal(new PixelRect(360, 0, 1280, 720), GameWindowCaptureRules.GameAreaOnScreen(new PixelRect(0, 0, 2000, 720)));
        Assert.Equal(new PixelRect(-1600, 100, 1280, 720), GameWindowCaptureRules.GameAreaOnScreen(new PixelRect(-1600, 100, 1280, 720)));
        Assert.Equal(new PixelRect(520, 0, 2400, 1350), GameWindowCaptureRules.GameAreaOnScreen(new PixelRect(0, 0, 3440, 1350)));
    }

    [Fact]
    public void CaptureWindowRulesPickAndList()
    {
        var windows = new[]
        {
            new WindowCandidate("RemotePlay", "PS Remote Play", 1280, 720),
            new WindowCandidate("chiaki", "chiaki-ng", 1600, 900),
            new WindowCandidate("RemotePlay", "small", 390, 300),
            new WindowCandidate("obs64", "Projector", 1920, 1080),
            new WindowCandidate("obs64", "", 1920, 1080),
            new WindowCandidate("obs64", "Projector", 1920, 1080),
        };
        Assert.Equal("chiaki", CaptureWindowRules.Pick(windows, CaptureWindowRules.Processes(RemotePlayApp.Automatic))?.ProcessName);
        Assert.Equal("PS Remote Play", CaptureWindowRules.Pick(windows, CaptureWindowRules.Processes(RemotePlayApp.SonyRemotePlay))?.Title);
        Assert.Null(CaptureWindowRules.Pick(windows, ["obs64"], "projector"));
        Assert.NotNull(CaptureWindowRules.Pick(windows, ["OBS64"], "Projector"));
        var list = CaptureWindowRules.Listing(windows);
        Assert.Equal(["chiaki", "obs64", "RemotePlay"], list.Select(w => w.ProcessName));
    }

    [Fact]
    public void InstallCandidatesSonyFirst()
    {
        var c = CaptureWindowRules.InstallCandidates(RemotePlayApp.Automatic, "PF", "PF86", "LAD");
        Assert.EndsWith("RemotePlay.exe", c[0]);
        Assert.StartsWith("PF86", c[0]);
        Assert.Equal(8, c.Count);
        Assert.Contains(Path.Combine("LAD", "Programs", "chiaki-ng", "chiaki-ng.exe"), c);
    }

    [Fact]
    public void MostlyBlackSampling()
    {
        var b = new byte[4 * 997 * 10];
        Assert.True(CaptureWindowRules.IsMostlyBlack(b));
        b[4 * 997 * 3 + 1] = 10;
        Assert.False(CaptureWindowRules.IsMostlyBlack(b));
    }

    [Theory]
    [InlineData("{\"tag_name\":\"v4.0.1\"}", "4.0.0", "4.0.1")]
    [InlineData("{\"tag_name\":\"vv4.0.1\"}", "4.0.0", "4.0.1")]
    [InlineData("{\"tag_name\":\"4.0.0\"}", "4.0.0", null)]
    [InlineData("{\"tag_name\":\"0.1.0-beta.10\"}", "0.1.0-beta.9", "0.1.0-beta.10")]
    [InlineData("{\"name\":\"x\"}", "4.0.0", null)]
    [InlineData("not json", "4.0.0", null)]
    [InlineData("[1]", "4.0.0", null)]
    public void LatestReleaseCheck(string json, string current, string? expected) =>
        Assert.Equal(expected, UpdateSource.NewerFromLatestJson(json, current));

    [Fact]
    public void ExecutionStateFlags()
    {
        Assert.Equal(0x80000000u, ExecutionStateRules.Flags(false, false, false));
        Assert.Equal(0x80000001u, ExecutionStateRules.Flags(true, false, false));
        Assert.Equal(0x80000003u, ExecutionStateRules.Flags(true, true, false));
        Assert.Equal(0x80000000u, ExecutionStateRules.Flags(false, true, false));
        Assert.Equal(0x80000003u, ExecutionStateRules.Flags(false, false, true));
    }

    [Fact]
    public void HotkeyIdsAndModifiers()
    {
        Assert.Equal(0x4353, HotkeyIds.For(0));
        Assert.Equal(0x4353 + 15, HotkeyIds.For(15));
        Assert.Equal(0x4000u | 2u | 4u, HotkeyIds.Modifiers(KeyModifiers.Control | KeyModifiers.Shift));
    }

    [Fact]
    public void HotkeyFailureNoteOnlyOnChange()
    {
        var note = new HotkeyFailureNote();
        var key = new HotkeyKey(KeyModifiers.None, 0x61);
        Assert.Equal("Bu kısayollar başka bir uygulamada kayıtlı olduğu için Nino'ya verilemedi: Num 1", note.Update([key]));
        Assert.Null(note.Update([key]));
        Assert.Null(note.Update([]));
        Assert.NotNull(note.Update([key]));
    }

    [Fact]
    public void SpellCacheCountsErrorsAsKnownAndClears()
    {
        var calls = 0;
        var dict = new CachedSpellDictionary(w =>
        {
            calls++;
            return w == "boom" ? throw new InvalidOperationException() : w == "xq" ? false : w == "none" ? null : true;
        });
        Assert.True(dict.Contains("hello"));
        Assert.True(dict.Contains("hello"));
        Assert.Equal(1, calls);
        Assert.False(dict.Contains("xq"));
        Assert.True(dict.Contains("boom"));
        Assert.True(dict.Contains("none"));
        Assert.True(dict.Contains("XQ"));
        Assert.Equal(5, calls);
        for (var i = 0; i < CachedSpellDictionary.CacheLimit + 5; i++) dict.Contains("w" + i);
        Assert.True(dict.CachedCount <= CachedSpellDictionary.CacheLimit);
    }

    [Fact]
    public void OcrLanguageCandidates()
    {
        Assert.Equal(["en", "tr-TR"], OcrLanguageRules.Candidates("en", ["tr-TR", "EN"]));
        Assert.True(OcrLanguageRules.UsesSpelling("en-US"));
        Assert.False(OcrLanguageRules.UsesSpelling("ja"));
    }
}
