// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;
using Nino.Core.Library;
using Nino.Core.Phone;
using Nino.Core.Reading;
using Nino.Core.Tests.Reading;
using static Nino.Core.Tests.Phone.PhoneTestData;

namespace Nino.Core.Tests.Phone;

public class LineHookTests
{
    [Fact]
    public void DarkTextOnLight()
    {
        var box = new Box(0.2, 0.4, 0.6, 0.5);
        var white = new FuncSampler((x, _) => (int)Math.Floor(x * 200) % 4 == 0 ? new Rgb(250, 250, 250) : new Rgb(30, 30, 30));
        Assert.False(PhoneLineRules.IsDarkTextOnLight(white, box));
        var dark = new FuncSampler((x, _) => (int)Math.Floor(x * 200) % 4 == 0 ? new Rgb(30, 30, 30) : new Rgb(235, 235, 238));
        Assert.True(PhoneLineRules.IsDarkTextOnLight(dark, box));
    }

    static readonly Box Area = new(0.14, 0.66, 0.86, 0.97);

    static (OcrReading Reading, BgraFrame Region) InArea(string name, BgraFrame frame) =>
        (new OcrReading(Fixtures.Load(name).Lines.Where(l => l.Box!.Value.Top >= Area.Top && l.Box.Value.Bottom <= Area.Bottom
            && PhoneText.LetterCount(l.Text) >= 4).Select(l => l with { Box = l.Box!.Value.RelativeTo(Area) })),
            frame.CropRegion(Area));

    [RealFrameFact]
    public void RealWhiteSubtitleVsPhoneText()
    {
        var (reading, region) = InArea("gta6-altyazi-beyaz", SipsDecoder.Load("gta6-altyazi-beyaz"));
        var sampler = new FrameSampler(region);
        bool Dark(string part) => PhoneLineRules.IsDarkTextOnLight(sampler, reading.Lines.First(l => l.Text.Contains(part)).Box!.Value);
        Assert.False(Dark("gonna love it"));
        Assert.True(Dark("finder"));
        Assert.True(Dark("lockups"));
    }

    [RealFrameFact]
    public void RealNearBottomPhoneText()
    {
        var (reading, region) = InArea("gta6-telefon-yakin-alt", SipsDecoder.Load("gta6-telefon-yakin-alt"));
        var sampler = new FrameSampler(region);
        bool Dark(string part) => PhoneLineRules.IsDarkTextOnLight(sampler, reading.Lines.First(l => l.Text.Contains(part)).Box!.Value);
        Assert.True(Dark("plane"));
        Assert.True(Dark("good to her"));
    }

    static PhoneLineHooks Hooks(Func<IReadOnlyList<string>>? recent = null, Action<BgraFrame, IReadOnlyList<Box>>? seen = null,
        ManualMsClock? clock = null) =>
        new(clock ?? new ManualMsClock(0), () => true, () => false, recent ?? (() => []), seen, _ => null);

    [Fact]
    public void MaskedLinesDropped()
    {
        var hooks = Hooks();
        var area = new Box(0, 0, 1, 1);
        var reading = R(L("inside the phone", 0.55, 0.3, 0.7, 0.32), L("The bridge is closing soon.", 0.3, 0.88, 0.6, 0.92));
        var result = hooks.FilterLines(new PhoneLineContext(reading, BgraFrame.Blank(0, 0), area, new Box(0.5, 0.2, 0.8, 0.84), true));
        Assert.Equal(["The bridge is closing soon."], result.Lines.Select(l => l.Text));
    }

    [Fact]
    public void RecentMessagesDropLines()
    {
        var hooks = Hooks(() => ["Rosa: You took my car?! You better bring it back"]);
        var area = new Box(0, 0, 1, 1);
        var result = hooks.FilterLines(new PhoneLineContext(R(L("You took my car?! You better", 0.3, 0.85, 0.7, 0.9),
            L("Hop in the truck.", 0.3, 0.9, 0.7, 0.95), L("Upper line here now", 0.3, 0.5, 0.7, 0.55)),
            BgraFrame.Blank(0, 0), area, null, false));
        Assert.Equal(["Hop in the truck."], result.Lines.Select(l => l.Text));
    }

    [Fact]
    public void PhoneAppTextAdoptedAndDropped()
    {
        var seen = new List<IReadOnlyList<Box>>();
        var clock = new ManualMsClock(0);
        var hooks = Hooks(seen: (_, b) => seen.Add(b), clock: clock);
        var frame = BgraFrame.Blank(960, 540);
        Assert.Null(hooks.LocatePhone(frame));
        var area = new Box(0, 0.5, 1, 1);
        var result = hooks.FilterLines(new PhoneLineContext(R(L("Trip Detail View", 0.6, 0.2, 0.75, 0.24), L("Let's go.", 0.4, 0.8, 0.6, 0.9)),
            BgraFrame.Blank(0, 0), area, null, false));
        Assert.Equal(["Let's go."], result.Lines.Select(l => l.Text));
        var boxes = Assert.Single(seen);
        Assert.Equal(0.6, boxes[0].Top, 6);
        Assert.NotNull(hooks.Tracker.Last);
    }

    [Fact]
    public async Task PipelineSendsNothingWhilePhoneShown()
    {
        // Karanlık kare, ortada beyaz telefon; okuma telefonun mesajları (kareye göre 0,66–0,71).
        var frame = Solid(960, 540, 20);
        Paint(frame, (int)(0.58 * 960), (int)(0.2 * 540), (int)(0.79 * 960), (int)(0.85 * 540), 240, 240, 240);
        var area = new Box(0.14, 0.62, 0.86, 0.97);
        var lines = new[]
        {
            L("Still can't believe u dug up those", 0.60, 0.66, 0.75, 0.68),
            L("old coins. U got the magic touch.", 0.60, 0.69, 0.75, 0.71),
        }.Select(l => l with { Box = l.Box!.Value.RelativeTo(area) }).ToArray();

        async Task<int> Run(bool search)
        {
            var t = new FakeTranslator();
            var hooks = new PhoneLineHooks(new ManualMsClock(0), () => search, () => false, () => []);
            var h = new Harness(new FuncReader(_ => new OcrReading(lines)), t, null,
                o => new SubtitlePipelineOptions { Log = o.Log, Phone = hooks });
            for (var i = 0; i < 6; i++) await h.Frame(frame: frame, area: area);
            return t.Requests.Count;
        }
        Assert.Equal(0, await Run(true));
        Assert.True(await Run(false) > 0);
    }

    [Fact]
    public void PhoneGameDecision()
    {
        Assert.True(PhoneGame.IsPhoneGame(false, "en", true, GameSource.Ps5, false));
        Assert.False(PhoneGame.IsPhoneGame(true, "en", true, GameSource.Ps5, true));
        Assert.False(PhoneGame.IsPhoneGame(false, "ja", true, null, true));
        Assert.True(PhoneGame.IsPhoneGame(false, "en", false, null, true));
        Assert.True(PhoneGame.IsPhoneGame(false, "en", false, GameSource.Pack, true));
        Assert.False(PhoneGame.IsPhoneGame(false, "en", false, GameSource.User, true));
        Assert.False(PhoneGame.IsPhoneGame(false, "en", false, null, false));
        Assert.True(PhoneGame.PoolFirstAllows(PoolFirstConfig.Default, "tr"));
        Assert.False(PhoneGame.PoolFirstAllows(PoolFirstConfig.Default, "en"));
        Assert.Equal("GTA 6", PhoneGame.PoolGame("Elden Ring", "GTA 6", g => g == "GTA 6"));
        Assert.Equal("Pack", PhoneGame.PoolGame("Known", "Pack", _ => false));
        Assert.Equal("Known", PhoneGame.PoolGame("Known", null, _ => false));
    }

    [Fact]
    public void Gta6FromScreen()
    {
        var sense = new GameSense();
        var log = new List<string>();
        Assert.False(PhoneGame.NoteGta6(sense, false));
        Assert.True(PhoneGame.NoteGta6(sense, true, log.Add));
        Assert.Equal(GameSource.Screen, sense.Source);
        Assert.True(sense.Asked);
        Assert.Equal("ekrandaki yazılara bakılarak oyun GTA 6 sayıldı", Assert.Single(log));
        Assert.False(PhoneGame.NoteGta6(sense, true));
        var user = new GameSense();
        user.SetUser("Elden Ring");
        Assert.False(PhoneGame.NoteGta6(user, true));
        var same = new GameSense();
        same.SetScreen("Grand Theft Auto VI");
        Assert.False(PhoneGame.NoteGta6(same, true));
    }
}
