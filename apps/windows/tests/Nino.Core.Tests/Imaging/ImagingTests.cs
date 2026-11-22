// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;
using Nino.Core.Settings;

namespace Nino.Core.Tests.Imaging;

public class BoxTests
{
    [Fact]
    public void PlacesAndUnites()
    {
        var area = new Box(0.1, 0.6, 0.9, 1.0);
        var placed = new Box(0.25, 0.5, 0.75, 0.6).PlaceIn(area);
        Assert.Equal(0.3, placed.Left, 9);
        Assert.Equal(0.8, placed.Top, 9);
        Assert.Equal(0.7, placed.Right, 9);
        Assert.Equal(0.84, placed.Bottom, 9);
        var u = new Box(0.1, 0.2, 0.3, 0.4).Union(new Box(0.2, 0.1, 0.5, 0.3));
        Assert.Equal(new Box(0.1, 0.1, 0.5, 0.4), u);
        Assert.Equal(new Box(0.14, 0.62, 0.86, 0.97), Box.FromRegion(new Region()));
    }
}

public class FrameTests
{
    [Fact]
    public void CopiesWithStride()
    {
        var src = new byte[2 * 12];
        for (var i = 0; i < src.Length; i++) src[i] = (byte)i;
        var f = BgraFrame.CopyFrom(src, 2, 2, 12);
        Assert.Equal(8, f.Stride);
        Assert.Equal(new byte[] { 0, 1, 2, 3, 4, 5, 6, 7, 12, 13, 14, 15, 16, 17, 18, 19 }, f.Pixels);
    }

    [Fact]
    public void CropsDefaultRegionOf1080p()
    {
        var f = BgraFrame.Blank(1920, 1080).CropRegion(Box.FromRegion(new Region()));
        Assert.InRange(f.Width, 1382, 1384);
        Assert.InRange(f.Height, 378, 379);
    }

    [Fact]
    public void CropKeepsCorner()
    {
        var f = BgraFrame.Blank(10, 10);
        f.Pixels[f.IndexOf(9, 9)] = 200;
        var c = f.CropRegion(Box.FromRegion(new Region(0.5, 1, 0.5, 1)));
        Assert.Equal(200, c.Pixels[c.IndexOf(c.Width - 1, c.Height - 1)]);
    }

    [Fact]
    public void CropClamps()
    {
        var f = BgraFrame.Blank(10, 10).Crop(-5, 8, 50, 50);
        Assert.Equal(10, f.Width);
        Assert.Equal(2, f.Height);
    }

    [Fact]
    public void UpscalesBilinear()
    {
        var f = BgraFrame.Blank(2, 1);
        f.SetPixel(0, 0, 0, 0, 0, 0);
        f.SetPixel(1, 0, 100, 100, 100, 100);
        var u = f.Upscale(2);
        Assert.Equal(4, u.Width);
        Assert.Equal(2, u.Height);
        // tx=0: sx = 0.25−0.5 < 0 → 0 → 0; tx=1: sx=0.25 → 25; tx=2: sx=0.75 → 75; tx=3: sx=1 → 100.
        Assert.Equal(new byte[] { 0, 25, 75, 100 }, Enumerable.Range(0, 4).Select(x => u.Pixels[u.IndexOf(x, 0)]).ToArray());
        var g = BgraFrame.Blank(2, 1);
        g.SetPixel(1, 0, 10, 10, 10, 10);
        // 2.5 → 2 ve 7.5 → 8 (en yakın çift).
        var v = g.Upscale(2);
        Assert.Equal(new byte[] { 0, 2, 8, 10 }, Enumerable.Range(0, 4).Select(x => v.Pixels[v.IndexOf(x, 0)]).ToArray());
    }

    [Fact]
    public void MasksPhone()
    {
        var region = BgraFrame.Filled(200, 100, 255);
        var area = new Box(0, 0.5, 1, 1);
        var masked = region.MaskBlack(new Box(0.5, 0.2, 0.8, 0.75), area);
        Assert.Equal(0, masked.Pixels[masked.IndexOf(130, 10)]);
        Assert.Equal(255, masked.Pixels[masked.IndexOf(130, 10) + 3]);
        Assert.Equal(255, masked.Pixels[masked.IndexOf(130, 80)]);
        Assert.Equal(255, masked.Pixels[masked.IndexOf(20, 10)]);
        Assert.Same(region, region.MaskBlack(new Box(0.1, 0.0, 0.2, 0.3), area));
        Assert.Same(region, region.MaskBlack(new Box(0.1, 0.6, 0.2, 0.7), new Box(0, 0.5, 0, 1)));
    }

    [Fact]
    public void Signature()
    {
        var a = RegionSignature.Of(BgraFrame.Filled(640, 120, 50));
        Assert.Equal(768, a.Length);
        Assert.Equal(a, RegionSignature.Of(BgraFrame.Filled(640, 120, 50)));
        Assert.NotEqual(a, RegionSignature.Of(BgraFrame.Filled(640, 120, 200)));
        Assert.All(RegionSignature.Of(BgraFrame.Blank(0, 0)), b => Assert.Equal(0, b));
    }

    [Fact]
    public void SignatureChangeWithinBox()
    {
        var prev = Enumerable.Repeat((byte)120, 768).ToArray();
        var box = new Box(0.3, 0.6, 0.7, 0.85);
        var cur = (byte[])prev.Clone();
        cur[0] = 250;
        cur[8 * 64 + 10] = 250;
        Assert.True(RegionSignature.Changed(prev, cur));
        Assert.False(RegionSignature.Changed(prev, cur, within: box));
        cur[8 * 64 + 30] = 180;
        Assert.True(RegionSignature.Changed(prev, cur, within: box));
        cur[8 * 64 + 30] = 130;
        Assert.False(RegionSignature.Changed(prev, cur, within: box));
        Assert.True(RegionSignature.Changed(prev, new byte[10]));
    }
}

public class FilterTests
{
    [Fact]
    public void WhiteTextKeepsOutlinedLetters()
    {
        var f = BgraFrame.Blank(60, 20);
        for (var y = 0; y < 20; y++)
            for (var x = 0; x < 60; x++)
            {
                byte v = x < 30 ? (byte)230 : x is >= 40 and <= 43 ? (byte)20 : x is >= 44 and <= 47 ? (byte)250 : (byte)150;
                f.SetPixel(x, y, v, v, v);
            }
        var w = TextImageFilters.WhiteText(f, radius: 3);
        Assert.Equal(255, w.Pixels[w.IndexOf(5, 10)]);
        Assert.Equal(0, w.Pixels[w.IndexOf(45, 10)]);
        Assert.Equal(255, w.Pixels[w.IndexOf(41, 10)]);
        Assert.Equal(255, w.Pixels[w.IndexOf(45, 10) + 3]);
    }

    [Fact]
    public void ShadowLooksOnlyDownRight()
    {
        var f = BgraFrame.Blank(20, 1);
        for (var x = 0; x < 20; x++) f.SetPixel(x, 0, 230, 230, 230);
        f.SetPixel(10, 0, 20, 20, 20);
        var s = TextImageFilters.ShadowText(f, 3, 200, 60, 80);
        Assert.Equal(0, s.Pixels[s.IndexOf(8, 0)]);
        Assert.Equal(255, s.Pixels[s.IndexOf(12, 0)]);
        Assert.Equal(255, s.Pixels[s.IndexOf(10, 0)]);
    }

    [Fact]
    public void ColoredShadow()
    {
        var f = BgraFrame.Blank(4, 1);
        f.SetPixel(0, 0, 40, 200, 250);
        f.SetPixel(1, 0, 10, 10, 10);
        Assert.Equal(0, TextImageFilters.ShadowText(f, 3, 200, 60, 80, colored: true).Pixels[0]);
        Assert.Equal(255, TextImageFilters.ShadowText(f, 3, 200, 60, 80, colored: false).Pixels[0]);
    }

    [Fact]
    public void AutoLevelStretchesDimFrames()
    {
        var dim = BgraFrame.Filled(100, 100, 125);
        var leveled = TextImageFilters.AutoLevel(dim);
        Assert.Equal(250, leveled.Pixels[0]);
        Assert.Equal(255, leveled.Pixels[3]);
        var bright = BgraFrame.Filled(10, 10, 240);
        Assert.Same(bright, TextImageFilters.AutoLevel(bright));
        var dark = BgraFrame.Filled(10, 10, 30);
        Assert.Same(dark, TextImageFilters.AutoLevel(dark));
    }
}
