// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Library;

namespace Nino.Core.Tests.Pool;

public class PoolFilterTests
{
    [Fact]
    public void Temizlik() => Assert.Equal("Over here.", PoolFilter.Clean("  Over​\n  here.  "));

    [Theory]
    [InlineData("Run!")]
    [InlineData("Where are you headed, Marco?")]
    [InlineData("Frau Köhler is waiting upstairs.")]
    [InlineData("The bridge was built far too fast.")]
    [InlineData("Tell Rosa I signed the papers.")]
    [InlineData("You trust me, I trust you.")]
    [InlineData("THE BOSS WANTS A WORD!")]
    [InlineData("Get down!")]
    [InlineData("Who's out there?")]
    [InlineData("Gate number 4 is open")]
    [InlineData("We have to go before the storm hits")]
    [InlineData("Bring me 30 coins, Marco.")]
    [InlineData("Okay.")]
    public void Kabul(string line) => Assert.NotNull(PoolFilter.Prepare(line));

    [Theory]
    [InlineData("Oturum Açtı")]
    [InlineData("NightOwl_77 signed out")]
    [InlineData("250/250 HP 40%")]
    [InlineData("Oturum Kapattl")]
    [InlineData("Oturum Kapattl.")]
    [InlineData("Guncelleme Seqenekleri")]
    [InlineData("Guncelleme Seqenekleri.")]
    [InlineData("Konsolu Yeniden Baslat")]
    [InlineData("Konsolu Yeniden Baslat.")]
    [InlineData("Oyunu Kapat")]
    [InlineData("Medya Galerisi")]
    [InlineData("Kitaplik indiriliyor..")]
    [InlineData("Arkadaslar ve Medya")]
    [InlineData("kupalar ve arkadaslar listesi")]
    [InlineData("Yeni İçerik Bildirimleri")]
    [InlineData("Medya galerisine kaydedildi.")]
    [InlineData("Yeni kupa kazanıldı!")]
    [InlineData("Maria signed out.")]
    [InlineData("Trophy unlocked: Night Driver!")]
    [InlineData("Saving. Do not quit the game while the cloud save icon is visible.")]
    [InlineData("GO to the")]
    [InlineData("Bring the boat around to the")]
    [InlineData("ns the Story Mode menu.")]
    [InlineData("DOUBLE CASH THIS WEEK")]
    [InlineData("Photo Mode Options")]
    [InlineData("Main menu")]
    [InlineData("Hold on")]
    [InlineData("Hand me tk$9z first")]
    [InlineData("HP 80/120 SP 30/60")]
    [InlineData("...")]
    [InlineData("%%% ### !!!")]
    [InlineData("1234")]
    [InlineData("")]
    public void Ret(string line) => Assert.Null(PoolFilter.Prepare(line));

    [Fact]
    public void CokUzunRet() => Assert.Null(PoolFilter.Prepare(string.Concat(Enumerable.Repeat("Keep moving. ", 40))));

    [Theory]
    [InlineData("Through the dark forest, Tam zr$4k ran, looking for a way back to camp.", "Through the dark forest, Tam ran, looking for a way back to camp.")]
    [InlineData("Under the old bridge7xkq K waited, Watching the road.", "Under the old bridge K waited, Watching the road.")]
    [InlineData("She waited 7q, by the door.", "She waited, by the door.")]
    [InlineData("?! What are you doing here?", "What are you doing here?")]
    [InlineData("What are you doing here ?!", "What are you doing here?!")]
    [InlineData("Open the gate, Rosa. ?!", "Open the gate, Rosa.")]
    [InlineData("Hey, ?! the captain needs you.", "Hey, the captain needs you.")]
    [InlineData(". Open the gate.", "Open the gate.")]
    [InlineData("| Open the gate, Rosa.", "Open the gate, Rosa.")]
    [InlineData("Open the gate, Rosa. |", "Open the gate, Rosa.")]
    [InlineData("Leave it. l", "Leave it.")]
    [InlineData("l can't swim, Captain.", "I can't swim, Captain.")]
    [InlineData("| can't swim.", "I can't swim.")]
    [InlineData("l'm sure, l heard it.", "I'm sure, I heard it.")]
    [InlineData("|'ll wait outside.", "I'll wait outside.")]
    [InlineData("You and l've met before.", "You and I've met before.")]
    [InlineData("Who am l?", "Who am I?")]
    [InlineData("Who's next, |?", "Who's next, I?")]
    [InlineData("Wait for the 2nd car at 3:00pm with 9.5kg PS5.", "Wait for the 2nd car at 3:00pm with 9.5kg PS5.")]
    [InlineData("405 Turn right now please.", "Turn right now please.")]
    public void OcrCopuTemizligi(string input, string expected) => Assert.Equal(expected, OcrJunk.Clean(input));

    [Fact]
    public void SunucuAdresi()
    {
        Assert.Equal(PoolEndpoint.Live + "/", PoolEndpoint.Resolve(null, null).ToString());
        Assert.Equal("http://localhost:9000/", PoolEndpoint.Resolve(null, "http://localhost:9000\n").ToString());
        Assert.Equal("pool.example", PoolEndpoint.Resolve("https://pool.example", "http://localhost:9000").Host);
        Assert.Equal("localhost", PoolEndpoint.Resolve("ftp://x", "http://localhost:9000").Host);
        Assert.Equal("nino-pool/1 (windows; 4.0.0)", PoolEndpoint.UserAgent("4.0.0"));
    }
}
