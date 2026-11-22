// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Data;
using Nino.Core.Tv;

namespace Nino.Shell.Tests;

/// <summary>
/// Kullanıcı raporu: kurulumun TV adımında "Android TV" seçilince hiçbir şey olmuyordu. Android TV'de adres bilinmez
/// (TV uygulaması bilgisayarı kendisi bulur); seçim adressiz kayıtla eşleşmeli ve TV adımı ilerleyebilmeli.
/// </summary>
public class AndroidTvChoiceTests
{
    static TvRecord Choice => new("Android TV", "", TvBrand.AndroidTv);

    [Fact]
    public async Task AdressizAndroidTvSecimiEslesir()
    {
        var w = new World().WithPs5();
        var c = w.Open();
        Assert.Equal(SetupStep.Tv, c.Step);
        Assert.True(await c.PairTvAsync(Choice));
        Assert.True(c.TvPaired);
        Assert.Equal(TvBrand.AndroidTv, c.Tv?.Brand);
        Assert.Null(c.TvPairError);
    }

    [Fact]
    public void BosAdresleYerelAdresVeAcilisParametresiHataVermez()
    {
        Assert.Null(LocalNetwork.RouteSource(""));
        Assert.Null(LocalNetwork.RouteSource(null));
        var ex = Record.Exception(() => LocalNetwork.AddressNear(""));
        Assert.Null(ex);
    }

    [Fact]
    public async Task GercekEslestirmeAndroidTvIcinTvyeBaglanmayaCalismaz()
    {
        // Gerçek eşleştirme yolu: Android TV'de uzaktan kumanda bağlantısı açılmaz, sonuç hemen başarılıdır.
        var result = await TvPairing.PairAsync(Choice, null, "{}",
            (_, _, _) => throw new InvalidOperationException("Android TV'ye bağlanılmamalı"));
        Assert.True(result.Launched);
    }
}
