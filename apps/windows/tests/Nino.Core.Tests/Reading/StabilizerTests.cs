// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;
using Nino.Core.Reading;

namespace Nino.Core.Tests.Reading;

public class StabilizerTests
{
    readonly ManualMsClock _clock = new();
    readonly Stabilizer _s;

    public StabilizerTests() => _s = new Stabilizer(_clock);

    static readonly StabilizerReaction None = StabilizerReaction.Nothing;
    static StabilizerReaction T(string text) => new(StabilizerAction.Translate, text);
    static StabilizerReaction R(string text) => new(StabilizerAction.Restore, text);
    static readonly StabilizerReaction Clear = new(StabilizerAction.Clear);

    StabilizerReaction F(string text, long advanceBefore = 0)
    {
        _clock.Advance(advanceBefore);
        return _s.Feed(text);
    }

    [Fact]
    public void StableAfterTwo()
    {
        Assert.Equal([None, T("We can not stay here"), None],
            new[] { F("We can not stay here"), F("We can not stay here"), F("We can not stay here") });
    }

    [Fact]
    public void PartialRereadsOfSentLines()
    {
        const string twoLines = "Under the pale lanterns, Tvi waited,\nhoping a horse would carry her north.";
        var bad = OcrJunk.Clean("Under the pale lanterns O waited,");
        Assert.Equal([T(twoLines), None, None, T("The night is still young.")],
            new[] { F(twoLines), F(bad), F(bad), F("The night is still young.") });
    }

    [Fact]
    public void GarbageWaitsThenDropped()
    {
        Assert.Equal(None, F("Gxt brrvwlk."));
        Assert.Equal(T("Go to school."), F("Go to school."));
        Assert.Equal(StabilizerNoteKind.GarbageDropped, _s.LastNote!.Value.Kind);
    }

    [Fact]
    public void GarbageNeedsTime()
    {
        const string g = "- Lka) and, we brkt. damn, I q";
        for (var i = 0; i < 5; i++) Assert.Equal(None, F(g, i == 0 ? 0 : 100));
        _clock.Advance(100);
        _clock.Advance(700);
        Assert.Equal(T(g), F(g));
    }

    [Fact]
    public void GrowingLine()
    {
        Assert.Equal([None, T("We can not stay"), T("We can not stay here tonight.")],
            new[] { F("We can not stay"), F("We can not stay"), F("We can not stay here tonight.") });
    }

    const string Full = "Damn, I only stopped by to check if there's anythin' I can carry for you.";
    const string Bad = "Damn, I stopped by to check if there anythinl I can carry fo ya.";

    [Fact]
    public void WorseRereadIgnored()
    {
        Assert.Equal([T(Full), None, None, None], new[] { F(Full), F(Bad), F(Full), F(Bad) });
        Assert.Equal(StabilizerNoteKind.BadReread, _s.LastNote!.Value.Kind);
    }

    [Fact]
    public void BetterRereadTranslated()
    {
        Assert.Equal([T(Bad), T(Full), None], new[] { F(Bad), F(Full), F(Bad) });
    }

    [Fact]
    public void SentencesTranslateOnFirstRead()
    {
        foreach (var line in new[] { "We can not stay here.", "Duck!", "Who is there?", "Maybe…", "\"Hide.\"" })
        {
            Assert.Equal(T(line), F(line));
            Assert.Equal(None, F(line));
        }
    }

    [Fact]
    public void SimilarRereadNotSent()
    {
        F("The rope will snap soon");
        Assert.Equal(T("The rope will snap soon"), F("The rope will snap soon"));
        Assert.Equal(None, F("The rope will snap spon"));
        Assert.Equal(None, F("The rope will snap spon"));
    }

    [Fact]
    public void CounterNeverStable()
    {
        for (var i = 0; i < 20; i++)
        {
            Assert.Equal(None, F("24 / 120"));
            Assert.Equal(None, F(""));
        }
    }

    [Fact]
    public void TypewriterSendsLast()
    {
        F("We can");
        F("We can not stay");
        Assert.Equal(T("We can not stay here tonight, sister."), F("We can not stay here tonight, sister."));
        Assert.Equal(None, F("We can not stay here tonight, sister."));
    }

    [Fact]
    public void ClearsAfterGap()
    {
        F("Hello there");
        Assert.Equal(T("Hello there"), F("Hello there"));
        Assert.Equal(None, F(""));
        Assert.Equal(None, F("", 799));
        Assert.Equal(Clear, F("", 1));
        Assert.Equal(None, F(""));
    }

    [Fact]
    public void FlickerDoesNotClear()
    {
        F("Untie the rope");
        Assert.Equal(T("Untie the rope"), F("Untie the rope"));
        for (var round = 0; round < 3; round++)
        {
            for (var i = 0; i < 10; i++) Assert.Equal(None, F("", 50));
            for (var i = 0; i < 4; i++) Assert.Equal(None, F("Untie the rope", 50));
        }
    }

    [Fact]
    public void RestoresWithinWindow()
    {
        Assert.Equal(T("Untie the rope."), F("Untie the rope."));
        Assert.Equal(None, F(""));
        Assert.Equal(Clear, F("", 800));
        Assert.Equal(None, F("Untie the rope", 1500));
        Assert.Equal(R("Untie the rope."), F("Untie the rope"));
        Assert.Equal(None, F("Untie the rope."));
        Assert.Equal(None, F(""));
        Assert.Equal(Clear, F("", 800));
    }

    [Fact]
    public void RetranslatesAfterWindow()
    {
        F("Untie the rope.");
        F("");
        Assert.Equal(Clear, F("", 800));
        Assert.Equal(T("Untie the rope."), F("Untie the rope.", 1501));
    }

    [Fact]
    public void AlternatingLinesRestore()
    {
        Assert.Equal([T("Untie the rope."), T("Run!"), R("Untie the rope."), R("Run!")],
            new[] { F("Untie the rope."), F("Run!", 100), F("Untie the rope.", 100), F("Run!", 100) });
    }

    [Theory]
    [InlineData("Who sent you here?", "Who sent you here, stranger?")]
    [InlineData("Who sent you here, stranger?", "Who sent you here?")]
    [InlineData("We must reach the harbor before the storm breaks.", "We must reach the harbor before the storm breaks, sister.")]
    public void LongerOrShorterIsNew(string first, string second)
    {
        Assert.Equal(T(first), F(first));
        Assert.Equal(T(second), F(second, 50));
    }

    [Fact]
    public void FastPathSendsFirstRead()
    {
        _s.FastPath = true;
        const string first = "qv Well, I always knew who sent you here.";
        const string clean = "Well, I always knew who sent you here.";
        Assert.Equal([None, T(first), None], new[] { F(first), F(clean), F(clean) });
    }

    [Fact]
    public void FastPathUncleanWaits()
    {
        _s.FastPath = true;
        Assert.Equal(None, F("k ze & ue need it."));
        Assert.Equal(T("To be honest, sir, you owe me a favor..."), F("To be honest, sir, you owe me a favor..."));
        Assert.Equal(T("you two... how'd you two like a little extra coin?"), F("you two... how'd you two like a little extra coin?"));
    }

    [Theory]
    [InlineData("Mara: I found it.", true)]
    [InlineData("Ant-Man: Second wave!", true)]
    [InlineData("Walk down to the inn kept by Mrs. Lowe...", true)]
    [InlineData("k ze & ue need it.", false)]
    [InlineData("A _ there's a spare gold coin if you ask.", false)]
    [InlineData("7 Kt and hand the goods out for free.", false)]
    [InlineData("Ant-Man **: can't believe you found this!", false)]
    public void CleanRead(string text, bool clean) => Assert.Equal(clean, Stabilizer.IsCleanRead(text));

    [Fact]
    public void ResetClearsShown()
    {
        Assert.Equal(None, _s.Reset());
        F("Hello there");
        F("Hello there");
        Assert.Equal(Clear, _s.Reset());
        Assert.Equal(None, _s.Reset());
    }

    [Fact]
    public void ForgetRetriesOncePerSecond()
    {
        F("Untie the rope");
        Assert.Equal(T("Untie the rope"), F("Untie the rope"));
        _s.ForgetSent();
        for (var i = 0; i < 19; i++) Assert.Equal(None, F("Untie the rope", 50));
        Assert.Equal(T("Untie the rope"), F("Untie the rope", 50));
    }

    [Fact]
    public void ForgetOnlyBlocksFailedLine()
    {
        F("Untie the rope");
        F("Untie the rope");
        _s.ForgetSent();
        Assert.Equal(T("Run!"), F("Run!"));
    }

    [Theory]
    [InlineData("I can open that gate for you yet.", "I can't open that gate for you yet.")]
    [InlineData("She swore she would trust them with this.", "She swore she would never trust them with this.")]
    [InlineData("Wait for me by the bridge at 8.", "Wait for me by the bridge at 9.")]
    public void MeaningCorrections(string first, string fix)
    {
        Assert.Equal(T(first), F(first));
        Assert.Equal(T(fix), F(fix));
    }

    [Theory]
    [InlineData("I can open that gate for you yet.", "I can't open that gate for you yet.")]
    [InlineData("Wait for me by the bridge at 8.", "Wait for me by the bridge at 9.")]
    public void MeaningCorrectionsFastPath(string first, string fix)
    {
        _s.FastPath = true;
        Assert.Equal(T(first), F(first));
        Assert.Equal(T(fix), F(fix));
        Assert.Equal(None, F(fix));
    }

    [Fact]
    public void NumberChanges()
    {
        Assert.Equal([T("I got 3 arrows left."), None, T("I got 1 arrow left."), None],
            new[] { F("I got 3 arrows left."), F("1 got 3 arrows left."), F("I got 1 arrow left."), F("1 got 1 arrow left.") });
    }

    static readonly Box Place = new(0.3, 0.6, 0.7, 0.85);
    const int Point = 8 * 64 + 30;

    static byte[] Sig(Action<byte[]>? change = null)
    {
        var s = Enumerable.Repeat((byte)120, 768).ToArray();
        change?.Invoke(s);
        return s;
    }

    [Fact]
    public void UnmovedSpotKeepsLine()
    {
        Assert.Equal(T("Untie the rope."), _s.Feed("Untie the rope.", Sig(), Place));
        var noisy = Sig(s => { s[0] = 250; s[5] = 10; s[Point] = 130; });
        for (var t = 50; t <= 3000; t += 50)
        {
            _clock.Advance(50);
            Assert.Equal(None, _s.Feed("", noisy));
        }
        Assert.Equal(None, _s.Feed("Untie the rope.", Sig(), Place));
        for (var t = 50; t <= 3000; t += 50)
        {
            _clock.Advance(50);
            Assert.Equal(None, _s.Feed("", noisy));
        }
    }

    [Fact]
    public void MovedSpotClears()
    {
        _s.Feed("Untie the rope.", Sig(), Place);
        var moved = Sig(s => s[Point] = 180);
        Assert.Equal(None, _s.Feed("", moved));
        _clock.Advance(799);
        Assert.Equal(None, _s.Feed("", moved));
        _clock.Advance(1);
        Assert.Equal(Clear, _s.Feed("", moved));
    }

    [Fact]
    public void LaterMoveClears()
    {
        _s.Feed("Untie the rope.", Sig(), Place);
        _clock.Advance(2000);
        Assert.Equal(None, _s.Feed("", Sig()));
        _clock.Advance(1000);
        var moved = Sig(s => s[Point] = 60);
        Assert.Equal(None, _s.Feed("", moved));
        _clock.Advance(799);
        Assert.Equal(None, _s.Feed("", moved));
        _clock.Advance(1);
        Assert.Equal(Clear, _s.Feed("", moved));
    }

    [Fact]
    public void UnmovedSpotHeldAtMostFourSeconds()
    {
        _s.Feed("Untie the rope.", Sig(), Place);
        Assert.Equal(None, _s.Feed("", Sig()));
        _clock.Advance(3999);
        Assert.Equal(None, _s.Feed("", Sig()));
        _clock.Advance(1);
        Assert.Equal(Clear, _s.Feed("", Sig()));
    }

    [Fact]
    public void MissingSignatureOrBoxClearsSoon()
    {
        _s.Feed("Untie the rope.", Sig(), null);
        Assert.Equal(None, _s.Feed("", Sig()));
        _clock.Advance(800);
        Assert.Equal(Clear, _s.Feed("", Sig()));

        _clock.Advance(5000);
        _s.Feed("Row now, sister!", null, Place);
        Assert.Equal(None, _s.Feed("", Sig()));
        _clock.Advance(800);
        Assert.Equal(Clear, _s.Feed("", Sig()));
    }

    [Fact]
    public void SameLanguage()
    {
        Assert.False(Stabilizer.ShouldSend("Kapıyı Aç Feneri Yak", "Kapıyı Aç Feneri Yak"));
        Assert.True(Stabilizer.ShouldSend("Open the door", "Kapıyı aç"));
    }
}

public class GateAndPlanTests
{
    [Fact]
    public void GateLetsOneIn()
    {
        var g = new FrameGate();
        var a = g.TryEnter(0);
        Assert.Equal(GateOutcome.Entered, a.Outcome);
        Assert.Equal(GateOutcome.Busy, g.TryEnter(100).Outcome);
        g.Exit(a.Ticket);
        Assert.Equal(GateOutcome.Entered, g.TryEnter(200).Outcome);
    }

    [Fact]
    public void GateResetForgetsOldEntry()
    {
        var g = new FrameGate();
        var a = g.TryEnter(0);
        g.Reset();
        var b = g.TryEnter(50);
        Assert.Equal(GateOutcome.Entered, b.Outcome);
        g.Exit(a.Ticket);
        Assert.True(g.IsBusy);
        Assert.Equal(GateOutcome.Busy, g.TryEnter(60).Outcome);
    }

    [Fact]
    public void GateDetectsStuck()
    {
        var g = new FrameGate(1000);
        g.TryEnter(0);
        Assert.Equal(GateOutcome.Busy, g.TryEnter(999).Outcome);
        var s = g.TryEnter(1000);
        Assert.Equal(GateOutcome.Stuck, s.Outcome);
        Assert.Equal(1000, s.ElapsedMs);
        Assert.Equal(GateOutcome.Entered, g.TryEnter(1001).Outcome);
        Assert.Equal(15_000, FrameGate.WindowsStuckMs);
    }

    static byte[] Sig(int bump = 0)
    {
        var s = Enumerable.Repeat((byte)40, 16).ToArray();
        s[3] = (byte)(40 + bump);
        return s;
    }

    [Fact]
    public void PlanReusesUnchanged()
    {
        var p = ReadPlan.ForApp(false);
        var d = p.Next(Sig());
        Assert.False(d.Reuse);
        Assert.True(d.Deep);
        p.Record("Hello there");
        d = p.Next(Sig());
        Assert.True(d.Reuse);
        Assert.Equal("Hello there", d.LastText);
        p.Record("");
        Assert.True(p.Next(Sig(8)).Reuse);
        p.Record("Hel");
        d = p.Next(Sig(48));
        Assert.False(d.Reuse);
        Assert.False(d.Deep);
    }

    [Fact]
    public void PlanReuseLimit()
    {
        var p = new ReadPlan(16, 2, 2);
        Assert.False(p.Next(Sig()).Reuse);
        p.Record("a line");
        Assert.True(p.Next(Sig()).Reuse);
        Assert.True(p.Next(Sig()).Reuse);
        var d = p.Next(Sig());
        Assert.False(d.Reuse);
        Assert.False(d.Deep);

        var fast = ReadPlan.ForApp(true);
        fast.Next(Sig());
        fast.Record("");
        Assert.True(fast.Next(Sig()).Reuse);
        Assert.True(fast.Next(Sig()).Reuse);
        Assert.False(fast.Next(Sig()).Reuse);
    }

    [Fact]
    public void PlanDeepEveryThird()
    {
        var p = ReadPlan.ForApp(false);
        var flags = new List<bool>();
        for (var i = 0; i < 6; i++)
        {
            var d = p.Next(Sig(i % 2 == 0 ? 0 : 100));
            Assert.False(d.Reuse);
            flags.Add(d.Deep);
            p.Record("");
        }
        Assert.Equal([true, false, false, true, false, false], flags);
        p.Reset();
        var first = p.Next(Sig());
        Assert.False(first.Reuse);
        Assert.True(first.Deep);
    }

    [Fact]
    public void AlwaysPlanReads()
    {
        var p = ReadPlan.Always();
        p.Next(Sig());
        p.Record("x");
        var d = p.Next(Sig());
        Assert.False(d.Reuse);
        Assert.True(d.Deep);
    }
}
