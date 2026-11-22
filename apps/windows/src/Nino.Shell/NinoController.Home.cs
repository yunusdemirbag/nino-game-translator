// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Settings;

namespace Nino.Shell;

// Ana ekranın okuduğu küçük ek durumlar (ana-ekran.md §3.3, §3.4).
public sealed partial class NinoController
{
    /// <summary>Seçili çevrimiçi motorun ekrandaki adı ("DeepL", "Gemini", "Yerel model" …; ana ekran kart 8 başlığı).</summary>
    public string OnlineEngineName => EngineDisplayName();

    /// <summary>Ana ekran biçimi (salon ya da cam anahtar).</summary>
    public HomeStyle HomeStyle => _settings.HomeStyle;

    /// <summary>Salon sahnesi Xbox'lı mı: ayarlardaki oyun konsolu Xbox ya da kurulumda Xbox seçildi.</summary>
    public bool HomeSceneIsXbox => _settings.GameConsole == GameConsole.Xbox || IsXbox;

    /// <summary>Oyunun dili (ayarlardaki kaynak dil kodu; yazı tanıma paketi bunun için kurulur).</summary>
    public string SourceLanguage => _settings.SourceLanguage;
}
