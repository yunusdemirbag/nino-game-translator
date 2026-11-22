// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;
using Nino.Core.Phone;

namespace Nino.Core.Tests.Phone;

public class PhoneLayoutTests
{
    static PhoneMessage M(string text, double l, double t, double r, double b, double line = 0.02) =>
        new(text, new Box(l, t, r, b), line);

    static readonly PhoneShape Phone = PhoneShape.Upright(new Box(0.59, 0.2, 0.79, 0.81));

    [Fact]
    public void OverlayColor()
    {
        var sampler = new FuncSampler((x, _) => x < 0.6075 ? new Rgb(233, 233, 236) : new Rgb(40, 40, 40));
        var o = PhoneLayout.Overlays([M("On my way", 0.61, 0.5, 0.7, 0.53), M("Casa De Donnie", 0.61, 0.6, 0.7, 0.63)],
            ["Geliyorum", "Casa De Donnie"], sampler);
        var one = Assert.Single(o);
        Assert.Equal("#e9e9ec", one.Fill.Hex);
        Assert.Equal("#2c2c2e", one.Ink);
        Assert.True(one.Box.Left < 0.61 && one.Box.Right > 0.7 && one.Box.Top < 0.5 && one.Box.Bottom > 0.53);
    }

    [Fact]
    public void Columns()
    {
        var (_, right) = PhoneLayout.Column(new Box(0.58, 0.197, 0.793, 0.854));
        Assert.True(right < 0.58);
        var (left, r2) = PhoneLayout.Column(new Box(0.39, 0.2, 0.61, 0.85));
        Assert.True(left > 0.61 && r2 <= 0.98);
    }

    [Fact]
    public void ChatPanelInOutBubbles()
    {
        var sampler = new FuncSampler((x, _) => x < 0.7 ? new Rgb(233, 233, 236) : new Rgb(200, 220, 245));
        var items = PhoneLayout.ChatPanel([M("On my way", 0.61, 0.5, 0.7, 0.53), M("Where at?", 0.72, 0.6, 0.77, 0.62)],
            ["Geliyorum", "Nerede?"], Phone, sampler, null);
        Assert.Equal(3, items.Count);
        var floor = items[0];
        Assert.True(floor.Backdrop);
        Assert.Equal(0.6, floor.Alpha);
        Assert.Equal(0.2, floor.Box.Top, 6);
        Assert.Equal(0.81, floor.Box.Bottom, 6);
        Assert.True(floor.Box.Right <= 0.59);
        var incoming = items[1];
        var outgoing = items[2];
        Assert.Equal(0.5, incoming.Box.Top, 3);
        Assert.Equal("#f8f8f9", incoming.Fill);
        Assert.Equal("#acccfe", outgoing.Fill);
        Assert.True(outgoing.Box.Left > incoming.Box.Left);
        foreach (var b in items.Skip(1))
        {
            Assert.Null(b.Angle);
            Assert.True(b.Side);
            Assert.Equal(0.95, b.Alpha);
            Assert.True(b.Box.Left >= floor.Box.Left && b.Box.Right <= floor.Box.Right);
        }
        var titled = PhoneLayout.ChatPanel([M("On my way", 0.61, 0.5, 0.7, 0.53)], ["Geliyorum"], Phone, sampler, "Lucia");
        Assert.Equal("Lucia", titled[0].Text);
    }

    [Fact]
    public void BluishLightSides()
    {
        var sampler = new FuncSampler((_, y) => y < 0.45 ? new Rgb(137, 154, 183) : new Rgb(120, 150, 215));
        var items = PhoneLayout.ChatPanel([M("Honestly if they didn't let us", 0.61, 0.4, 0.77, 0.43),
            M("Nah. Cal's busy with work stuff", 0.61, 0.5, 0.77, 0.53)], ["Açıkçası söylemek gerekirse", "Olmaz."], Phone,
            sampler, null);
        var floor = items[0];
        Assert.Equal(floor.Box.Left + 0.012, items[1].Box.Left, 6);
        Assert.Equal(floor.Box.Right - 0.012, items[2].Box.Right, 6);
    }

    [Fact]
    public void BubblesDoNotOverlap()
    {
        var sampler = new FuncSampler((_, _) => new Rgb(233, 233, 236));
        var items = PhoneLayout.ChatPanel([M("First message here", 0.61, 0.40, 0.7, 0.42),
            M("Second", 0.61, 0.43, 0.7, 0.45)],
            ["Çok uzun bir çeviri metni ki birkaç satıra sarılması gereksin diye uzatıldı", "İkinci"], Phone, sampler, null);
        Assert.True(items[2].Box.Top >= items[1].Box.Bottom - items[1].LineHeight!.Value * 0.3);
    }

    [Fact]
    public void AppBubble()
    {
        var sampler = new FuncSampler((_, y) => y < 0.45 ? new Rgb(155, 80, 187) : new Rgb(233, 233, 236));
        var items = PhoneLayout.AppBubbles([M("Savings Account", 0.61, 0.38, 0.72, 0.40, 0.017),
            M("buckme", 0.61, 0.28, 0.66, 0.30, 0.017)], ["Birikim Hesabı", "BuckMe mi?"], Phone, sampler);
        var one = Assert.Single(items);
        Assert.Equal("Birikim Hesabı", one.Text);
        Assert.Equal("#9b50bb", one.Fill);
        Assert.Equal("#ffffff", one.Ink);
        Assert.True(one.Box.Right <= 0.59);
        Assert.InRange(one.Box.CenterY, 0.388, 0.392);
        Assert.True(one.Side);
    }

    [Fact]
    public void AppBubbleWhiteNewsApp()
    {
        var sampler = new FuncSampler((x, y) => y is > 0.4 and < 0.42 && (int)(x * 400) % 3 == 0
            ? new Rgb(20, 20, 20) : new Rgb(250, 250, 250));
        var items = PhoneLayout.AppBubbles([M("Local news today", 0.61, 0.40, 0.72, 0.42, 0.017)], ["Bugünkü haberler"],
            Phone, sampler);
        var one = Assert.Single(items);
        Assert.Equal("#fafafa", one.Fill);
        Assert.Equal("#0c0c0c", one.Ink);
    }
}
