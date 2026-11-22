// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Linux.Diagnostics;
using Nino.Linux.Hosting;
using Nino.Linux.Imaging;
using Nino.Linux.Ports;

namespace Nino.Linux.Tests;

public sealed class RawFrameCommandTests : IDisposable
{
    private readonly TempFolder temp = new();

    public void Dispose() => temp.Dispose();

    private sealed class FakeTools : IRawFrameServices
    {
        public bool ReaderAvailable { get; set; } = true;
        public bool ModelInstalled { get; set; }
        public List<bool> Probes { get; } = [];
        public int Downloads { get; private set; }
        public List<string> Translated { get; } = [];
        public string Subtitle { get; set; } = "Run!\nNow.";

        public RegionProbe Probe(BgraPicture frame, bool deep)
        {
            Probes.Add(deep);
            return new RegionProbe(12, frame.Width, frame.Height, ["Run!", "Now."], Subtitle);
        }

        public Task DownloadModelAsync() { Downloads++; ModelInstalled = true; return Task.CompletedTask; }

        public Task<string> TranslateAsync(string text) { Translated.Add(text); return Task.FromResult("Koş! Şimdi."); }
    }

    private string Frame(int bytes)
    {
        var path = temp.File("kare.bgra");
        File.WriteAllBytes(path, new byte[bytes]);
        return path;
    }

    [Fact]
    public async Task EksikArgumanVeKucukDosyaVeOkuyucuYok()
    {
        var output = new StringWriter();
        var errors = new StringWriter();
        Assert.Equal(RawFrameCommand.Usage, await RawFrameCommand.RunAsync(["--read-raw", "x"], () => new FakeTools(), output, errors));
        Assert.Equal(RawFrameCommand.TooSmall, await RawFrameCommand.RunAsync(["--read-raw", Frame(10), "4", "4"], () => new FakeTools(), output, errors));
        Assert.Equal(RawFrameCommand.NoReader, await RawFrameCommand.RunAsync(["--read-raw", Frame(64), "4", "4"],
            () => new FakeTools { ReaderAvailable = false }, output, errors));
    }

    [Fact]
    public async Task DortOkumaIkisiDerinSonraIkiCeviri()
    {
        var tools = new FakeTools();
        var output = new StringWriter();
        var code = await RawFrameCommand.RunAsync(["--read-raw", Frame(64), "4", "4", "--translate"], () => tools, output, new StringWriter());
        Assert.Equal(RawFrameCommand.Ok, code);
        Assert.Equal([true, true, false, false], tools.Probes);
        Assert.Equal(1, tools.Downloads);
        Assert.Equal(["Run! Now.", "Run! Now."], tools.Translated);
        var text = output.ToString();
        Assert.Contains("#1 derin: 12 ms (4×4 piksel)", text);
        Assert.Contains("#4 olağan", text);
        Assert.Contains("  altyazı > Run!", text);
        Assert.Contains("çeviri (ısınmış)", text);
    }

    [Fact]
    public async Task CeviriIstenmezseYaDaAltyaziBossaCevrilmez()
    {
        var tools = new FakeTools();
        await RawFrameCommand.RunAsync(["--read-raw", Frame(64), "4", "4"], () => tools, new StringWriter(), new StringWriter());
        Assert.Empty(tools.Translated);
        tools.Subtitle = " ";
        await RawFrameCommand.RunAsync(["--read-raw", Frame(64), "4", "4", "--translate"], () => tools, new StringWriter(), new StringWriter());
        Assert.Empty(tools.Translated);
    }
}
