// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Settings;

namespace Nino.Core.Tests.Reading;

/// <summary>Okunan bölgenin hazır seçimleri (okuma hattı tarifi 2. bölüm §4; kod ayarlar tarafında).</summary>
public class AreaPresetTests
{
    [Theory]
    [InlineData(0.62, 0.97, 0.14, 0.86, AreaPreset.Bottom)]
    [InlineData(0.0305, 0.3795, 0.14, 0.86, AreaPreset.Top)]
    [InlineData(0, 1, 0, 1, AreaPreset.Full)]
    [InlineData(0.62, 0.97, 0.14, 0.87, AreaPreset.Custom)]
    [InlineData(0.5, 0.9, 0.1, 0.9, AreaPreset.Custom)]
    public void Detects(double top, double bottom, double left, double right, AreaPreset preset) =>
        Assert.Equal(preset, RegionPresets.Detect(new Region(top, bottom, left, right)));

    [Fact]
    public void Sliders()
    {
        Assert.Equal(60, RegionPresets.Position(new Region(0.6, 0.9, 0, 1)), 9);
        Assert.Equal(30, RegionPresets.Height(new Region(0.6, 0.9, 0, 1)), 9);
        var r = RegionPresets.FromSliders(new Region(0.62, 0.97, 0.2, 0.8), 40, 25);
        Assert.Equal((0.4, 0.65, 0.2, 0.8), (Math.Round(r.Top, 9), Math.Round(r.Bottom, 9), r.Left, r.Right));
        var start = new Region(0.62, 0.97, 0.2, 0.8);
        Assert.Equal(0.05, Math.Round(RegionPresets.FromSliders(start, 50, 1).Bottom - RegionPresets.FromSliders(start, 50, 1).Top, 9));
        Assert.Equal((0.0, 1.0), (RegionPresets.FromSliders(start, 10, 150).Top, RegionPresets.FromSliders(start, 10, 150).Bottom));
        var up = RegionPresets.FromSliders(start, 90, 30);
        Assert.Equal((0.7, 1.0), (Math.Round(up.Top, 9), Math.Round(up.Bottom, 9)));
        var neg = RegionPresets.FromSliders(start, -20, 30);
        Assert.Equal((0.0, 0.3), (neg.Top, Math.Round(neg.Bottom, 9)));
    }
}
