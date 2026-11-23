// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;
using Nino.Core.Link;
using Nino.Core.Settings;
using Nino.RemotePlay;
using Nino.Shell.Platform;

namespace Nino.Shell.Tests;

/// <summary>Okuma hattının altyazısı TV'ye Mac'teki ek alanlarla gidiyor mu (kaynak, konuşan adı, konum, buzlu zemin).</summary>
public class TvShowWiringTests
{
    static async Task<SubtitleShown> FirstShownAsync(World w, string line)
    {
        w.Services.Model.Installed = true;
        var c = w.Open();
        await c.StartAsync();
        w.Services.ReaderFactory.Text = line;
        var src = w.Services.Ps5Sessions[0];
        src.Status(SourceStatus.Streaming);
        for (var i = 0; i < 12 && c.History.Count == 0; i++)
        {
            src.Frame(BgraFrame.Filled(64, 36, 90));
            await c.WaitForReadingAsync();
            w.Timers.Advance(TimeSpan.FromMilliseconds(400));
        }
        var shown = w.Services.Server.Of<SubtitleShown>().Where(s => s.Source is not null).ToList();
        Assert.NotEmpty(shown);
        return shown[^1];
    }

    [Fact]
    public async Task PipelineSubtitleCarriesSpeakerPositionSourceAndCover()
    {
        var w = new World(new AppSettings { AreaPreset = AreaPreset.Top, Region = RegionPresets.Top }).WithPs5().WithTv();
        int? quality = null;
        w.Services.ReaderFactory.Jpeg = (_, _, q) => { quality = q; return [1, 2, 3]; };
        var e = await FirstShownAsync(w, "BRENNA: Hold the door.");

        Assert.Equal("BRENNA: Hold the door.", e.Source);
        Assert.Equal("BRENNA", e.Speaker);
        Assert.StartsWith("BRENNA: ", e.Text);
        Assert.Equal(TvPosition.Top, e.Position);
        Assert.Equal("AQID", e.Cover);
        Assert.Equal(FrostCover.Quality, quality);
        var link = TvWire.LinkMessage(e, 1);
        Assert.Contains("\"speaker\":\"BRENNA\"", link);
        Assert.DoesNotContain("\"text\":\"BRENNA:", link);
    }

    [Fact]
    public async Task WithoutEncoderNoCoverAndBottomPosition()
    {
        var w = new World(new AppSettings { ShowSpeakerNames = false }).WithPs5().WithTv();
        var e = await FirstShownAsync(w, "BRENNA: Hold the door.");
        Assert.Null(e.Cover);
        Assert.Null(e.Speaker);
        Assert.Equal(TvPosition.Bottom, e.Position);
    }
}
