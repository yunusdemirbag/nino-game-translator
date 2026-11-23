// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;
using Nino.Core.Phone;
using Nino.Core.Reading;
using Nino.Core.Tests.Reading;
using static Nino.Core.Tests.Phone.PhoneTestData;

namespace Nino.Core.Tests.Phone;

public class PhoneReaderTests
{
    static readonly PhoneShape Kenton = new(new Box(0.58, 0.197, 0.793, 0.854), 0.58, 0, 0.213);
    static readonly BgraFrame Blank = BgraFrame.Blank(960, 540);

    static OcrReading KentonReading(double shift = 0, string last = "Sure, I'll be there soon.", params OcrLine[] extra) =>
        new(new[]
        {
            L("Kenton", 0.66, 0.22, 0.70, 0.24),
            L("Left the dive gear on yuh deck", 0.60, 0.372 + shift, 0.752, 0.394 + shift),
            L("bro. Good luck out there!", 0.60, 0.398 + shift, 0.70, 0.42 + shift),
            L(last, 0.667, 0.689 + shift, 0.766, 0.712 + shift),
        }.Concat(extra));

    sealed class Rig
    {
        public readonly ManualMsClock Clock = new(100_000);
        public readonly List<IReadOnlyList<ScreenItem>> Notes = [];
        public readonly List<string> Log = [];
        public int Gta6;
        public PhoneReader Reader = null!;

        public Rig(OverlayServices? services = null)
        {
            var s = (services ?? new OverlayServices()) with
            {
                Clock = Clock,
                Changed = () => { lock (Notes) Notes.Add(Reader.Items); },
                Log = l => { lock (Log) Log.Add(l); },
                Gta6Seen = () => Gta6++,
            };
            Reader = new PhoneReader(s);
        }

        public Task Read(OcrReading r, PhoneShape? phone = null, long? session = null) =>
            Reader.ProcessAsync(r, phone ?? Kenton, Blank, session);
    }

    [Fact]
    public async Task FirstReadWaitsSecondShowsThirdSilent()
    {
        var own = new PrefixTranslator("TR: ");
        var rig = new Rig(new OverlayServices { Own = own });
        await rig.Read(KentonReading());
        Assert.Empty(rig.Notes);
        await rig.Read(KentonReading());
        var items = Assert.Single(rig.Notes);
        Assert.Equal("Kenton", items[0].Text);
        Assert.True(items[0].Backdrop);
        Assert.Equal(["TR: Left the dive gear on yuh deck bro. Good luck out there!", "TR: Sure, I'll be there soon."],
            items.Skip(1).Select(i => i.Text));
        Assert.All(items.Skip(1), i => Assert.True(i.Side && i.Box.Right < Kenton.Box.Left));
        Assert.Contains("Sure, I'll be there soon.", rig.Reader.RecentMessages);
        Assert.True(rig.Gta6 > 0);
        await rig.Read(KentonReading());
        Assert.Single(rig.Notes);
        Assert.Equal(2, own.Calls);
        rig.Reader.Reset();
        Assert.Empty(rig.Reader.Items);
        Assert.Empty(rig.Reader.RecentMessages);
    }

    [Fact]
    public async Task PoolThenReadyTranslations()
    {
        var pool = new FakePool(l => "Havuz " + l);
        var fallback = new PrefixTranslator("Cihaz ");
        var own = new PrefixTranslator("Own ");
        var rig = new Rig(new OverlayServices { Pool = pool.Ask, Fallback = fallback, Own = own });
        await rig.Read(KentonReading());
        Assert.Empty(rig.Notes);
        await rig.Read(KentonReading());
        var req = Assert.Single(pool.Requests);
        Assert.Equal(2, req.Lines.Length);
        Assert.Empty(req.Context);
        Assert.Equal(0, own.Calls);
        Assert.All(rig.Reader.Items.Skip(1), i => Assert.StartsWith("Havuz ", i.Text));

        var rig2 = new Rig(new OverlayServices
        {
            Pool = pool.Ask, Fallback = fallback,
            Ready = t => t.StartsWith("Left", StringComparison.Ordinal) ? "Bilinen 1" : t.StartsWith("Sure", StringComparison.Ordinal) ? "Bilinen 2" : null,
        });
        await rig2.Read(KentonReading());
        Assert.Equal(["Bilinen 1", "Bilinen 2"], rig2.Reader.Items.Skip(1).Select(i => i.Text));
        Assert.Single(pool.Requests);
    }

    [Fact]
    public async Task KnownFirstUnknownSecond()
    {
        var own = new PrefixTranslator("Own ");
        var rig = new Rig(new OverlayServices
        {
            Pool = new FakePool(_ => null).Ask, Fallback = new PrefixTranslator("Cihaz "), Own = own,
            Ready = t => t.StartsWith("Left", StringComparison.Ordinal) ? "Bilinen" : null,
        });
        await rig.Read(KentonReading());
        Assert.Equal(["Bilinen"], Assert.Single(rig.Notes).Skip(1).Select(i => i.Text));
        await rig.Read(KentonReading());
        Assert.Equal(2, rig.Notes.Count);
        Assert.Equal(["Bilinen", "Cihaz Sure, I'll be there soon."], rig.Notes[1].Skip(1).Select(i => i.Text));
        Assert.Equal(0, own.Calls);
    }

    [Fact]
    public async Task MemorySurvivesResetNotNewReader()
    {
        var pool = new FakePool(_ => "");
        var fallback = new PrefixTranslator("Cihaz ");
        var services = new OverlayServices { Pool = pool.Ask, Fallback = fallback };
        var rig = new Rig(services);
        await rig.Read(KentonReading());
        await rig.Read(KentonReading());
        Assert.Equal((1, 2), (pool.Requests.Count, fallback.Calls));
        Assert.Single(rig.Notes);
        rig.Reader.Reset();
        Assert.Equal(1, rig.Reader.Session);
        await rig.Read(KentonReading(), session: 1);
        Assert.All(rig.Reader.Items.Skip(1), i => Assert.StartsWith("Cihaz ", i.Text));
        Assert.Equal((1, 2), (pool.Requests.Count, fallback.Calls));

        var fresh = new Rig(services);
        await fresh.Read(KentonReading());
        await fresh.Read(KentonReading());
        Assert.Equal((2, 4), (pool.Requests.Count, fallback.Calls));
    }

    async Task<(Rig Rig, PrefixTranslator Own)> Shown()
    {
        var own = new PrefixTranslator("TR: ");
        var rig = new Rig(new OverlayServices { Own = own });
        await rig.Read(KentonReading());
        await rig.Read(KentonReading());
        Assert.Single(rig.Notes);
        return (rig, own);
    }

    [Fact]
    public async Task ScrolledReadStillShown()
    {
        var own = new PrefixTranslator("TR: ");
        var rig = new Rig(new OverlayServices { Own = own });
        await rig.Read(KentonReading());
        await rig.Read(KentonReading(0.03));
        Assert.Single(rig.Notes);
        Assert.Equal(2, own.Calls);
    }

    [Fact]
    public async Task SlightlyDifferentReadsKeepPanel()
    {
        var (rig, own) = await Shown();
        var items = rig.Reader.Items;
        await rig.Read(KentonReading(0.01, "Sure, I'll be there soon.' U"));
        await rig.Read(KentonReading(0.005, "Sure, Ill be there soon"));
        Assert.Single(rig.Notes);
        Assert.Equal(2, own.Calls);
        Assert.Equal(items, rig.Reader.Items);
    }

    [Fact]
    public async Task NewMessageNeedsTwoReads()
    {
        var (rig, _) = await Shown();
        var extra = L("Meet me by the lighthouse.", 0.60, 0.76, 0.72, 0.78);
        await rig.Read(KentonReading(0, "Sure, I'll be there soon.", extra));
        Assert.Single(rig.Notes);
        await rig.Read(KentonReading(0, "Sure, I'll be there soon.", extra));
        Assert.Equal(2, rig.Notes.Count);
        Assert.Contains(rig.Notes[1], i => i.Text == "TR: Meet me by the lighthouse.");
    }

    [Fact]
    public async Task ChatChangedClearsPanel()
    {
        var (rig, _) = await Shown();
        await rig.Read(R(L("Rosa", 0.665, 0.22, 0.70, 0.24), L("You still owe me for the boat.", 0.60, 0.40, 0.75, 0.42)));
        Assert.Empty(rig.Reader.Items);
        Assert.Empty(rig.Notes[^1]);
        Assert.Contains(rig.Log, l => l.StartsWith("telefon: başka bir konuşma açıldı (Kenton → Rosa)", StringComparison.Ordinal));
    }

    [Fact]
    public async Task GroupChatSenderNotTranslated()
    {
        var pool = new FakePool(l => "Havuz " + l);
        var rig = new Rig(new OverlayServices { Pool = pool.Ask, Fallback = new PrefixTranslator("Cihaz ") });
        var r = R(L("Boat Crew", 0.655, 0.22, 0.715, 0.24), L("Cal", 0.60, 0.30, 0.62, 0.315),
            L("Anyone got a lighter?", 0.60, 0.35, 0.70, 0.37), L("It's in the truck, by", 0.667, 0.50, 0.766, 0.52),
            L("the cooler.", 0.667, 0.525, 0.72, 0.545));
        await rig.Read(r);
        await rig.Read(r);
        var req = Assert.Single(pool.Requests);
        Assert.DoesNotContain("Cal", req.Lines);
        Assert.Contains("Anyone got a lighter?", req.Lines);
        Assert.Contains("It's in the truck, by the cooler.", req.Lines);
        Assert.Empty(req.Context); // ilk bilinmeyen ilk mesaj: önünde bağlam yok
    }

    [Fact]
    public async Task LowercaseCutFirstMessage()
    {
        async Task<string[]> Sent(double top)
        {
            var pool = new FakePool(l => "Havuz " + l);
            var rig = new Rig(new OverlayServices { Pool = pool.Ask });
            var r = R(L("Kenton", 0.66, 0.22, 0.70, 0.24), L("lol glad the trip went well", 0.60, top, 0.752, top + 0.022),
                L("Sure, I'll be there soon.", 0.667, 0.689, 0.766, 0.712));
            await rig.Read(r);
            await rig.Read(r);
            return pool.Requests.SelectMany(q => q.Lines).ToArray();
        }
        Assert.Contains("lol glad the trip went well", await Sent(0.372));
        Assert.DoesNotContain("lol glad the trip went well", await Sent(0.26));
    }

    [Fact]
    public async Task ChatListShowsNothing()
    {
        var own = new PrefixTranslator("TR: ");
        var rig = new Rig(new OverlayServices { Own = own });
        var r = R(L("Messages", 0.64, 0.22, 0.72, 0.24), L("Andy", 0.62, 0.30, 0.65, 0.32),
            L("OK see u at noon", 0.62, 0.325, 0.74, 0.345), L("Cal", 0.62, 0.38, 0.64, 0.40),
            L("Tell them we went sailing", 0.62, 0.405, 0.77, 0.425), L("Lucia", 0.62, 0.46, 0.65, 0.48),
            L("u still awake?", 0.62, 0.485, 0.72, 0.505));
        var phone = PhoneShape.Upright(new Box(0.59, 0.2, 0.79, 0.81));
        await rig.Read(r, phone);
        await rig.Read(r, phone);
        Assert.Empty(rig.Notes);
        Assert.Equal(0, own.Calls);
    }

    [Fact]
    public async Task AppScreenWithGlossary()
    {
        var own = new PrefixTranslator("TR: ");
        var rig = new Rig(new OverlayServices { Own = own, Glossary = true });
        var phone = PhoneShape.Upright(new Box(0.59, 0.2, 0.79, 0.81));
        var r = R(L("$500", 0.70, 0.33, 0.77, 0.36), L("◆ Savings Account", 0.61, 0.38, 0.72, 0.40),
            L("$1,250 to next goal", 0.64, 0.65, 0.74, 0.67));
        await rig.Read(r, phone);
        await rig.Read(r, phone);
        var items = Assert.Single(rig.Notes);
        Assert.Equal(["Birikim Hesabı", "Sonraki hedefe $1.250"], items.Select(i => i.Text));
        Assert.DoesNotContain(items, i => i.Backdrop);
        Assert.Equal(0, own.Calls);
    }

    [Fact]
    public async Task MapButtonClearsOverlay()
    {
        var (rig, _) = await Shown();
        await rig.Read(R(L("RECENTER", 0.85, 0.85, 0.93, 0.87)));
        Assert.Empty(rig.Reader.Items);
    }

    [Fact]
    public void MemoryFindsLongerKey()
    {
        var memory = new Dictionary<string, string>
        {
            ["still can t believe u found them doubloons"] = "uzun",
            ["ok"] = "tamam",
        };
        Assert.Equal("uzun", PhoneReader.FindIn(memory, "still can t believe u found"));
        Assert.Null(PhoneReader.FindIn(memory, "still can t"));
        Assert.Equal("tamam", PhoneReader.FindIn(memory, "ok"));
    }

    [Fact]
    public async Task OfferFrameUsesTrackerAndOcr()
    {
        var clock = new ManualMsClock(0);
        var own = new PrefixTranslator("TR: ");
        var notes = 0;
        var ocr = new FuncReader(_ => new OcrReading(KentonReading().Lines.Select(l => l with { Box = l.Box!.Value.RelativeTo(Kenton.Box) })));
        PhoneReader reader = null!;
        reader = new PhoneReader(new OverlayServices { Clock = clock, Own = own, Ocr = ocr, Changed = () => notes++ }, _ => Kenton);
        reader.OfferFrame(Blank);
        await reader.Running!;
        clock.Advance(300);
        reader.OfferFrame(Blank); // 600 ms dolmadı
        Assert.Equal(1, ocr.Calls);
        clock.Advance(400);
        reader.OfferFrame(Blank);
        await reader.Running!;
        Assert.Equal(2, ocr.Calls);
        Assert.Equal(1, notes);
        Assert.Equal(3, reader.Items.Count);
    }

    [Fact]
    public async Task PausedClearsOverlay()
    {
        var paused = false;
        var clock = new ManualMsClock(0);
        var ocr = new FuncReader(_ => new OcrReading(KentonReading().Lines.Select(l => l with { Box = l.Box!.Value.RelativeTo(Kenton.Box) })));
        var reader = new PhoneReader(new OverlayServices
        {
            Clock = clock, Own = new PrefixTranslator("TR: "), Ocr = ocr, Paused = () => paused,
        }, _ => Kenton);
        for (var i = 0; i < 2; i++)
        {
            reader.OfferFrame(Blank);
            await reader.Running!;
            clock.Advance(1100);
        }
        Assert.NotEmpty(reader.Items);
        paused = true;
        reader.OfferFrame(Blank);
        await reader.Running!;
        Assert.Empty(reader.Items);
    }

    [Fact]
    public async Task StuckOcrIsAbandoned()
    {
        // Takılan yazı tanıma telefonu oturum boyunca kör etmez: StuckMs sonra bırakılır; geç dönen okumanın sonucu atılır.
        var clock = new ManualMsClock(0);
        using var release = new ManualResetEventSlim(false);
        var first = true;
        var ocr = new FuncReader(_ =>
        {
            if (first)
            {
                first = false;
                release.Wait(TimeSpan.FromSeconds(10));
            }
            return new OcrReading(KentonReading().Lines.Select(l => l with { Box = l.Box!.Value.RelativeTo(Kenton.Box) }));
        });
        var reader = new PhoneReader(new OverlayServices { Clock = clock, Own = new PrefixTranslator("TR: "), Ocr = ocr }, _ => Kenton);
        reader.OfferFrame(Blank);
        var stuck = reader.Running!;
        SpinWait.SpinUntil(() => ocr.Calls == 1, 5000);
        clock.Advance(PhoneReader.ReadEveryMs + 1);
        reader.OfferFrame(Blank);
        Assert.Same(stuck, reader.Running);
        clock.Advance(PhoneReader.StuckMs);
        reader.OfferFrame(Blank);
        Assert.NotSame(stuck, reader.Running);
        await reader.Running!;
        Assert.Equal(2, ocr.Calls);
        release.Set();
        await stuck;
        for (var i = 0; i < 2; i++)
        {
            clock.Advance(PhoneReader.ReadEveryWithOverlayMs + 1);
            reader.OfferFrame(Blank);
            await reader.Running!;
        }
        Assert.Equal(4, ocr.Calls);
        Assert.Equal(3, reader.Items.Count);
    }

    [Fact]
    public async Task SlowTranslationDoesNotOverlapTours()
    {
        // Çeviri adımı süre sınırına sayılmaz: yavaş sunucuda yeni tur başlamaz.
        var clock = new ManualMsClock(0);
        var slow = new PendingTranslator();
        var ocr = new FuncReader(_ => new OcrReading(KentonReading().Lines.Select(l => l with { Box = l.Box!.Value.RelativeTo(Kenton.Box) })));
        var reader = new PhoneReader(new OverlayServices { Clock = clock, Own = slow, Ocr = ocr }, _ => Kenton);
        reader.OfferFrame(Blank);
        await reader.Running!;
        clock.Advance(PhoneReader.ReadEveryMs + 1);
        reader.OfferFrame(Blank);
        var translating = reader.Running!;
        SpinWait.SpinUntil(() => slow.Requests.Count > 0, 5000);
        Assert.NotEmpty(slow.Requests);
        clock.Advance(PhoneReader.StuckMs * 3);
        reader.OfferFrame(Blank);
        Assert.Same(translating, reader.Running);
        Assert.Equal(2, ocr.Calls);
    }
}
