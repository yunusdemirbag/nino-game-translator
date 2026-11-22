// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Support;

namespace Nino.Core.Tests.Support;

public class SiteLinksTests
{
    const string Base = "https://yunusdemirbag.github.io/nino-game-translator/";

    [Theory]
    [InlineData("tr", Base + "#kurulum")]
    [InlineData("tr-TR", Base + "#kurulum")]
    [InlineData("ar", Base + "ar/kurulum")]
    [InlineData("en", Base + "#english")]
    [InlineData("vi", Base + "#english")]
    [InlineData(null, Base + "#english")]
    public void GenelRehberDileGore(string? language, string expected) => Assert.Equal(expected, SiteLinks.Setup(language));

    [Fact]
    public void AndroidTvTurkcedeKendiBolumune()
    {
        Assert.Equal(Base + "#android-tv-elle", SiteLinks.TvApp("tr", androidTv: true));
        Assert.Equal(Base + "#kurulum", SiteLinks.TvApp("tr", androidTv: false));
        Assert.Equal(Base + "ar/kurulum", SiteLinks.TvApp("ar", androidTv: true));
        Assert.Equal(Base + "#english", SiteLinks.TvApp("nl", androidTv: true));
    }

    [Fact]
    public void BaglantilarYalnizNinoSitesine()
    {
        Assert.StartsWith("https://", SiteLinks.SiteBase);
        Assert.EndsWith("/", SiteLinks.SiteBase);
        Assert.DoesNotContain("github.com/", SiteLinks.Setup("tr"));
    }
}
