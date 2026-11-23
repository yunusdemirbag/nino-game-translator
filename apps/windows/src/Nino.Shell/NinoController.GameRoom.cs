// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Globalization;
using Nino.Core.Design;

namespace Nino.Shell;

// Ana ekrandaki oyun odası tabelası: ad sorusu (bir kez), kayıt, atlama, ayarlardan açma/kapama.
public sealed partial class NinoController
{
    /// <summary>Bu bilgisayarın bölgesi (ISO iki harf); bulunamazsa null.</summary>
    string? RegionCode
    {
        get
        {
            if (_services.RegionCode is { Length: > 0 } fromPlatform) return fromPlatform;
            try { return RegionInfo.CurrentRegion.TwoLetterISORegionName; }
            catch (Exception) { return null; }
        }
    }

    /// <summary>
    /// Ana ekran oda adını sormalı mı: kurulum bitti, daha önce sorulmadı ve bölge/dil uygun (Türkiye ya da Arapça).
    /// </summary>
    public bool ShouldAskGameRoomName =>
        IsSetupComplete && !_settings.GameRoomAsked && GameRoomSign.AsksName(RegionCode, _text.Language);

    /// <summary>Soru kutusundaki önerilen ad (hesap adının ilk sözcüğü); kayıtlı ad varsa o.</summary>
    public string SuggestedGameRoomName =>
        _settings.GameRoomName ?? GameRoomSign.SuggestedName(_services.AccountName ?? SafeUserName()) ?? "";

    /// <summary>Tabelada çizilecek metin; tabela kapalıysa ya da ad yoksa null.</summary>
    public GameRoomSignText? GameRoomSignText =>
        _settings.GameRoomSign ? GameRoomSign.Text(_settings.GameRoomName, _text.Language) : null;

    /// <summary>Soru kutusunda "Kaydet": ad yazılır, tabela açılır (ad boşsa atlama gibi davranır).</summary>
    public void SaveGameRoomName(string? name)
    {
        var clean = GameRoomSign.CleanName(name);
        ChangeSettings(s =>
        {
            s.GameRoomAsked = true;
            if (clean is null) return;
            s.GameRoomName = clean;
            s.GameRoomSign = true;
        });
    }

    /// <summary>Soru kutusunda "Atla": bir daha sorulmaz, tabela gösterilmez (ayarlardan açılabilir).</summary>
    public void SkipGameRoomName() => ChangeSettings(s => s.GameRoomAsked = true);

    /// <summary>Ayarlar: tabela anahtarı.</summary>
    public void SetGameRoomSign(bool on) => ChangeSettings(s =>
    {
        s.GameRoomSign = on;
        s.GameRoomAsked = true;
        if (on && s.GameRoomName is null) s.GameRoomName = GameRoomSign.SuggestedName(_services.AccountName ?? SafeUserName());
    });

    /// <summary>Ayarlar: oda adı (boş bırakılırsa ad silinir, tabela gösterilmez).</summary>
    public void SetGameRoomName(string? name) => ChangeSettings(s =>
    {
        s.GameRoomName = GameRoomSign.CleanName(name);
        s.GameRoomAsked = true;
    });

    static string? SafeUserName()
    {
        try { return Environment.UserName; }
        catch (Exception) { return null; }
    }
}
