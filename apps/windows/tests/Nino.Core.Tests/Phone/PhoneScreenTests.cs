// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;
using Nino.Core.Phone;
using Nino.Core.Reading;
using static Nino.Core.Tests.Phone.PhoneTestData;

namespace Nino.Core.Tests.Phone;

public class PhoneScreenTests
{
    static PhoneShape P(double l, double t, double r, double b) => PhoneShape.Upright(new Box(l, t, r, b));

    [Fact]
    public void ChatTitleExamples()
    {
        var c1 = PhoneScreen.Read(R(L("Kenton", 0.653, 0.233, 0.690, 0.248),
            L("Hey Rosa! Nice seeing u today", 0.595, 0.351, 0.750, 0.377)), P(0.575, 0.215, 0.783, 0.859));
        Assert.True(c1.IsChat);
        Assert.Equal("Kenton", c1.Title);

        var c2 = PhoneScreen.Read(R(L("Suggested", 0.608, 0.230, 0.661, 0.249), L("Donnie", 0.635, 0.272, 0.669, 0.285),
            L("Go get em", 0.635, 0.297, 0.685, 0.313), L("Pete's Bait Shop", 0.634, 0.347, 0.725, 0.367),
            L("Hey Rosa. All good? I heard", 0.634, 0.371, 0.772, 0.391)), P(0.583, 0.207, 0.792, 0.852));
        Assert.False(c2.IsChat);

        var c3 = PhoneScreen.Read(R(L("Marina, Coral Bay", 0.64, 0.21, 0.74, 0.23),
            L("Dear Ms. Varga. Please review the", 0.61, 0.55, 0.76, 0.57)), P(0.59, 0.2, 0.79, 0.81));
        Assert.True(c3.IsChat);
        Assert.Equal("Marina, Coral Bay", c3.Title);
    }

    [Fact]
    public void ChatMessagesKenton()
    {
        var c = PhoneScreen.Read(R(
            L("Kenton", 0.66, 0.22, 0.70, 0.24),
            L("Bahía del Faro Viejo", 0.63, 0.295, 0.755, 0.315),
            L("Left the dive gear on yuh deck", 0.60, 0.372, 0.752, 0.394),
            L("bro. Good luck out there!", 0.60, 0.398, 0.70, 0.42),
            L("New message", 0.648, 0.503, 0.718, 0.522),
            L("Still can't believe u dug up those", 0.60, 0.558, 0.753, 0.58),
            L("old coins. U got the magic touch.", 0.60, 0.582, 0.754, 0.604),
            L("Need u back out on the", 0.60, 0.607, 0.731, 0.629),
            L("reef tmrw.", 0.60, 0.632, 0.662, 0.652),
            L("Sure, I'll be there soon.", 0.667, 0.689, 0.766, 0.712)), P(0.58, 0.197, 0.793, 0.854));
        Assert.True(c.IsChat);
        Assert.Equal(["Left the dive gear on yuh deck bro. Good luck out there!",
            "Still can't believe u dug up those old coins. U got the magic touch. Need u back out on the reef tmrw.",
            "Sure, I'll be there soon."], c.Messages.Select(m => m.Text));
    }

    [Fact]
    public void ChatMessagesLabelsDropped()
    {
        var c = PhoneScreen.Read(R(
            L("Kenton", 0.653, 0.233, 0.690, 0.248),
            L("Typing", 0.620, 0.296, 0.734, 0.322),
            L("Location Shared", 0.624, 0.478, 0.707, 0.496),
            L("Here r the coords bro. Those", 0.595, 0.557, 0.736, 0.576),
            L("reefs look like a solid spot", 0.595, 0.581, 0.747, 0.602),
            L("Casa de la", 0.626, 0.646, 0.734, 0.665),
            L("Ópera Vieja", 0.625, 0.668, 0.681, 0.694)), P(0.575, 0.215, 0.783, 0.859));
        Assert.Equal(["Here r the coords bro. Those reefs look like a solid spot"], c.Messages.Select(m => m.Text));
    }

    [Fact]
    public void RowFragmentsJoin()
    {
        var c = PhoneScreen.ChatMessages(R(L("On my way", 0.61, 0.5, 0.68, 0.52), L("to you!", 0.69, 0.501, 0.73, 0.52)),
            P(0.58, 0.197, 0.793, 0.854), null);
        Assert.Equal("On my way to you!", Assert.Single(c).Text);
    }

    [Fact]
    public void Lists()
    {
        var plain = new OcrReading([new OcrLine("Harbor Bait & Tackle"), new OcrLine("Cancel Ryde"), new OcrLine("Choose Ryde"),
            new OcrLine("Cost")]);
        Assert.False(PhoneScreen.IsMessageList(plain));
        var cards = new OcrReading([new OcrLine("Donnie"), new OcrLine("You got my plane?! You be..."), new OcrLine("Brian"),
            new OcrLine("Remember, you get your h...")]);
        Assert.True(PhoneScreen.IsMessageList(cards));
        var chats = R(L("Messages", 0.64, 0.22, 0.72, 0.24), L("Andy", 0.62, 0.30, 0.65, 0.32),
            L("OK see u at noon", 0.62, 0.325, 0.74, 0.345), L("Cal", 0.62, 0.38, 0.64, 0.40),
            L("Tell them we went sailing", 0.62, 0.405, 0.77, 0.425), L("Lucia", 0.62, 0.46, 0.65, 0.48),
            L("u still awake?", 0.62, 0.485, 0.72, 0.505));
        Assert.True(PhoneScreen.IsChatList(chats));
        Assert.Empty(PhoneScreen.Read(chats, P(0.59, 0.2, 0.79, 0.81)).Messages);
    }

    [Fact]
    public void AppLines()
    {
        var phone = P(0.59, 0.2, 0.79, 0.81);
        var lines = PhoneScreen.AppLines(R(L("$500", 0.70, 0.33, 0.77, 0.36), L("◆ Checking Account", 0.61, 0.38, 0.72, 0.40),
            L("$1,250 to next goal", 0.64, 0.65, 0.74, 0.67)), phone);
        Assert.Equal(["Checking Account", "$1,250 to next goal"], lines.Select(l => l.Text));
        Assert.Empty(PhoneScreen.AppLines(R(L("△ CLOSE", 0.62, 0.5, 0.70, 0.52)), phone));
        Assert.Single(PhoneScreen.AppLines(R(L("◆ Checking Account", 0.61, 0.38, 0.72, 0.40)), phone));
    }

    [Fact]
    public void AppLinesContinue()
    {
        var phone = P(0.59, 0.2, 0.79, 0.81);
        var lines = PhoneScreen.AppLines(R(L("Local man finds treasure", 0.61, 0.40, 0.77, 0.42),
            L("off the coast", 0.61, 0.425, 0.70, 0.445), L("By Ana Ruiz", 0.61, 0.50, 0.68, 0.52),
            L("Weather today", 0.61, 0.525, 0.70, 0.545)), phone);
        Assert.Equal(["Local man finds treasure off the coast", "By Ana Ruiz", "Weather today"], lines.Select(l => l.Text));
    }
}
