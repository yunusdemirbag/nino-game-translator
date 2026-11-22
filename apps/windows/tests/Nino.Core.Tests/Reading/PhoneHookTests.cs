// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;
using Nino.Core.Reading;

namespace Nino.Core.Tests.Reading;

/// <summary>Altyazı hattının telefon/harita kancası (telefon tarafı sahte).</summary>
public class PhoneHookTests
{
    sealed class FakeHooks : IPhoneLineHooks
    {
        public bool SearchPhone { get; set; } = true;
        public bool MapOpen { get; set; }
        public Box? Phone;
        public bool Throws;
        public List<PhoneLineContext> Contexts { get; } = [];
        public int Locates;

        public Box? LocatePhone(BgraFrame frame)
        {
            Locates++;
            return Phone;
        }

        public OcrReading FilterLines(PhoneLineContext context)
        {
            lock (Contexts) Contexts.Add(context);
            if (Throws) throw new InvalidOperationException("telefon");
            return context.Reading;
        }
    }

    static readonly Box Area = new(0.14, 0.62, 0.86, 0.97);

    static Harness Make(FakeHooks hooks, ITextReader reader, FakeTranslator t) =>
        new(reader, t, null, o => new SubtitlePipelineOptions { Log = o.Log, Phone = hooks });

    [Fact]
    public async Task MapOpenMeansNoSubtitle()
    {
        var t = new FakeTranslator();
        var h = Make(new FakeHooks { MapOpen = true }, new SequenceReader(Script.Repeat("Reach the truck before the guards wake up.", 3)), t);
        await h.Frames(3);
        Assert.Empty(t.Requests);
    }

    [Fact]
    public async Task OffCenterLinesDroppedWhileSearching()
    {
        var t = new FakeTranslator();
        var reader = new FuncReader(_ => new OcrReading([new OcrLine("The bridge is closing soon.", new Box(0.35, 0.5, 0.65, 0.6)),
            new OcrLine("Room Rates Today", new Box(0.80, 0.1, 0.95, 0.2))]));
        var h = Make(new FakeHooks(), reader, t);
        await h.Frame(area: Area);
        Assert.Equal(["The bridge is closing soon."], t.Requests);
    }

    [Fact]
    public async Task PhoneMaskedBeforeReading()
    {
        var hooks = new FakeHooks { Phone = new Box(0.5, 0.2, 0.8, 0.75) };
        BgraFrame? seen = null;
        var reader = new FuncReader(img => { seen = img; return OcrReading.Empty; });
        var h = Make(hooks, reader, new FakeTranslator());
        await h.Frame(frame: BgraFrame.Filled(200, 200, 255), area: new Box(0, 0.5, 1, 1));
        var ctx = Assert.Single(hooks.Contexts);
        Assert.True(ctx.PhoneFound);
        Assert.Equal(0.84, ctx.MaskBox!.Value.Bottom, 9); // max(0,75, min(0,75 + 0,15, 0,84))
        Assert.Equal(0, seen!.Pixels[seen.IndexOf(130, 10)]);
        Assert.Equal(255, seen.Pixels[seen.IndexOf(20, 10)]);
    }

    [Fact]
    public async Task RecentPhoneReusedForFiveSeconds()
    {
        var hooks = new FakeHooks { Phone = new Box(0.5, 0.2, 0.8, 0.5) };
        var h = Make(hooks, new SequenceReader(), new FakeTranslator());
        await h.Frame(0);
        hooks.Phone = null;
        h.Clock.Advance(5000);
        await h.Frame(0);
        Assert.False(hooks.Contexts[1].PhoneFound);
        Assert.Equal(0.65, hooks.Contexts[1].MaskBox!.Value.Bottom, 9);
        h.Clock.Advance(1);
        await h.Frame(0);
        Assert.Null(hooks.Contexts[2].MaskBox);
    }

    [Fact]
    public async Task ThrowingHookKeepsReading()
    {
        var t = new FakeTranslator();
        var h = Make(new FakeHooks { Throws = true, SearchPhone = true }, new SequenceReader("Untie the rope."), t);
        await h.Frame();
        Assert.Equal(["Untie the rope."], t.Requests);
    }

    [Fact]
    public async Task NoSearchNoHookCalls()
    {
        var hooks = new FakeHooks { SearchPhone = false };
        var t = new FakeTranslator();
        var h = Make(hooks, new SequenceReader("Untie the rope."), t);
        await h.Frame();
        Assert.Equal(0, hooks.Locates);
        Assert.Empty(hooks.Contexts);
        Assert.Single(t.Requests);
    }
}
