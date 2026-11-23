// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Data;
using Nino.Core.Settings;
using Nino.Core.Tv;
using Nino.RemotePlay;

namespace Nino.Shell;

// Kurulum sihirbazı (tarif §6): adımlar, devam koşulları, İlerle/Geri, kısa yollar, konsol türü, sıfırlamalar.
public sealed partial class NinoController
{
    byte[]? _accountId;
    Ps5Console? _console;
    StoredConsoleKind _kind;
    bool _kindLocked;
    string? _xboxToken;
    StoredXboxConsole? _xboxConsole;
    TvRecord? _tv;
    long _xboxGeneration;

    SetupStep _step;
    bool _fromGameWindowShortcut;
    bool _fromXboxShortcut;
    bool _cardGuideOpen;

    void LoadStoredState()
    {
        _accountId = _secrets.Get<byte[]>(SecretKeys.AccountId) is { Length: 8 } id ? id : null;
        _console = RemotePlayRecords.ConsoleFromJson(_secrets.Get<System.Text.Json.Nodes.JsonObject>(SecretKeys.Console));
        _kind = _secrets.TryGet<StoredConsoleKind>(SecretKeys.ConsoleKind, out var k) ? k : StoredConsoleKind.PlayStation;
        _kindLocked = _secrets.TryGet<bool>(SecretKeys.ConsoleKindLocked, out var locked) && locked;
        _xboxToken = _secrets.Get<string>(SecretKeys.XboxToken) is { Length: > 0 } t ? t : null;
        _xboxConsole = _secrets.Get<StoredXboxConsole>(SecretKeys.XboxConsole);
        _tv = _secrets.Get<StoredTv>(SecretKeys.Tv) is { } tv ? new TvRecord(tv.Name, tv.Host, (TvBrand)(int)tv.Brand) : null;
    }

    void SaveConsole(Ps5Console console)
    {
        _console = console;
        _secrets.Set(SecretKeys.Console, RemotePlayRecords.ConsoleToJson(console));
    }

    void SaveTv(TvRecord tv)
    {
        _tv = tv;
        _secrets.Set(SecretKeys.Tv, new StoredTv { Name = tv.Name, Host = tv.Host, Brand = (StoredTvBrand)(int)tv.Brand });
    }

    // ---- "Kurulum bitti mi" (§6.1) ----

    bool ConsoleReady => _kind == StoredConsoleKind.Xbox
        ? _xboxToken is not null && _xboxConsole is not null
        : _accountId is not null && _console is not null;

    bool TvPairedNow => _secrets.Contains(SecretKeys.Tv) && _secrets.Contains(SecretKeys.TvKey);

    SetupStep FirstStep()
    {
        if (_kind == StoredConsoleKind.PlayStation && _settings.FrameSource != FrameSource.Ps5) return SetupStep.Done;
        bool? stored = _secrets.TryGet<bool>(SecretKeys.SetupComplete, out var s) ? s : null;
        bool complete;
        if (stored is null)
        {
            complete = ConsoleReady && TvPairedNow;
            _secrets.Set(SecretKeys.SetupComplete, complete);
        }
        else complete = ConsoleReady && stored.Value;
        if (complete || (_settings.VideoSource != VideoSource.Ps5 && stored == true)) return SetupStep.Done;
        return ConsoleReady ? SetupStep.Tv : SetupStep.Welcome;
    }

    // ---- Okunan durum ----

    /// <summary>Sihirbazın adımı.</summary>
    public SetupStep Step => _step;

    /// <summary>Kurulum bitti mi (ana ekran gösterilir).</summary>
    public bool IsSetupComplete => _step == SetupStep.Done;

    /// <summary>Toplam adım sayısı (Xbox'ta bir eksik).</summary>
    public int StepCount => (int)SetupStep.Done - (IsXbox ? 1 : 0);

    /// <summary>Gösterilen adım numarası.</summary>
    public int StepNumber
    {
        get
        {
            var n = (int)_step + 1;
            if (IsXbox && _step > SetupStep.SecondAccount) n--;
            return Math.Min(n, StepCount);
        }
    }

    /// <summary>Konsol türü.</summary>
    public StoredConsoleKind ConsoleKind => _kind;

    /// <summary>Konsol türü Xbox mu.</summary>
    public bool IsXbox => _kind == StoredConsoleKind.Xbox;

    /// <summary>Konsol türü kilitli mi.</summary>
    public bool ConsoleKindLocked => _kindLocked;

    /// <summary>HDMI yakalama kartı rehberi açık mı (sihirbazda adım alanının yerine).</summary>
    public bool CardGuideOpen => _cardGuideOpen;

    /// <summary>PSN hesabı var mı.</summary>
    public bool HasAccount => _accountId is not null;

    /// <summary>Kayıtlı PS5 var mı.</summary>
    public bool HasConsole => _console is not null;

    /// <summary>Eşleşen PS5'in adı.</summary>
    public string? ConsoleName => _console?.Name;

    /// <summary>Eşleşen PS5'in adresi.</summary>
    public string? ConsoleHost => _console?.Host;

    /// <summary>Xbox jetonu var mı.</summary>
    public bool HasXboxToken => _xboxToken is not null;

    /// <summary>Seçili Xbox.</summary>
    public StoredXboxConsole? XboxConsole => _xboxConsole;

    /// <summary>Xbox yayını bu derlemede var mı.</summary>
    public bool XboxAvailable => _services.Xbox is not null;

    /// <summary>Eşleşen TV.</summary>
    public TvRecord? Tv => _tv;

    /// <summary>TV eşleşmiş mi (kayıt ve jeton).</summary>
    public bool TvPaired => _tv is not null && _secrets.Contains(SecretKeys.TvKey);

    /// <summary>Bu adımda Devam'a basılabilir mi (§6.3).</summary>
    public bool CanContinue => _step switch
    {
        SetupStep.PsnSignIn => IsXbox ? _xboxToken is not null : _accountId is not null,
        SetupStep.Console => IsXbox ? _xboxConsole is not null : _console is not null,
        SetupStep.Tv => TvPaired || _settings.Output == SubtitleOutput.Computer,
        SetupStep.Model => ModelInstalled,
        SetupStep.Done => false,
        _ => true,
    };

    /// <summary>
    /// Ayarlar'da hesap bağlama düğmesi görünür mü: görüntü PS5'ten okunacak ama hesap ya da PS5 yok.
    /// </summary>
    public bool AccountLinkNeeded =>
        !IsXbox && _settings.VideoSource == VideoSource.Ps5 && _settings.FrameSource == FrameSource.Ps5
        && (_accountId is null || _console is null);

    // ---- Adım değişimi ----

    void SetStep(SetupStep step)
    {
        if (_step == step) return;
        _step = step;
        if (_firewall != FirewallHint.Working) _firewall = FirewallHint.None;
        if (step == SetupStep.Done) _secrets.Set(SecretKeys.SetupComplete, true);
        if (step == SetupStep.Tv && _tv is not null && _tvApp.Kind == TvAppKind.Unknown) Background(RecheckTvAppAsync);
    }

    /// <summary>İlerle (§6.4).</summary>
    public void Advance()
    {
        if (!CanContinue || _step == SetupStep.Done) return;
        if (_step == SetupStep.Welcome)
        {
            StartModelDownload();
            _kindLocked = true;
            _secrets.Set(SecretKeys.ConsoleKindLocked, true);
            _secrets.Set(SecretKeys.ConsoleKind, _kind);
            if (_settings.VideoSource != VideoSource.Ps5)
            {
                var next = _settings.Clone();
                next.VideoSource = VideoSource.Ps5;
                UpdateSettings(next);
            }
            _cardGuideOpen = false;
            SetStep(IsXbox ? SetupStep.PsnSignIn : SetupStep.SecondAccount);
        }
        else SetStep(_step + 1);
        Refresh();
    }

    /// <summary>Geri (§6.4).</summary>
    public void Back()
    {
        var card = _settings.VideoSource == VideoSource.Card;
        if (_fromGameWindowShortcut && _step == SetupStep.Model) SetStep(SetupStep.Welcome);
        else if (_fromXboxShortcut && _step == SetupStep.Tv) SetStep(SetupStep.Welcome);
        else if (card && (_step == SetupStep.Tv || (_step == SetupStep.Test && !ShowsOnTv)))
        {
            SetStep(SetupStep.Welcome);
            _cardGuideOpen = true;
        }
        else if (_step != SetupStep.Welcome)
            SetStep(IsXbox && _step == SetupStep.PsnSignIn ? SetupStep.Welcome : _step - 1);
        Refresh();
    }

    /// <summary>Adımı doğrudan değiştirir (ana ekrandan TV ya da konsol adımına dönüş).</summary>
    public void GoToStep(SetupStep step)
    {
        SetStep(step);
        Refresh();
    }

    // ---- Kısa yollar (§6.5) ----

    void ChangeSettings(Action<AppSettings> change)
    {
        var next = _settings.Clone();
        change(next);
        UpdateSettings(next);
    }

    /// <summary>"Yerel bilgisayarda PS Remote Play ile oynuyorum".</summary>
    public void UseGameWindowHere()
    {
        ChangeSettings(s =>
        {
            s.VideoSource = VideoSource.Window;
            s.GameConsole = GameConsole.Ps5;
            s.Output = SubtitleOutput.Computer;
        });
        _fromGameWindowShortcut = true;
        _fromXboxShortcut = false;
        SetStep(SetupStep.Model);
        StartModelDownload();
        Refresh();
    }

    /// <summary>Xbox seçeneği (Xbox penceresi).</summary>
    public void UseXboxWindow()
    {
        ChangeSettings(s =>
        {
            s.VideoSource = VideoSource.Window;
            s.GameConsole = GameConsole.Xbox;
            s.Output = SubtitleOutput.Tv;
        });
        _fromXboxShortcut = true;
        _fromGameWindowShortcut = false;
        SetStep(SetupStep.Tv);
        StartModelDownload();
        Refresh();
    }

    /// <summary>"HDMI kartım var": rehber açılır.</summary>
    public void OpenCardGuide()
    {
        _cardGuideOpen = true;
        StartModelDownload();
        Refresh();
    }

    /// <summary>Rehberden vazgeç: karşılamaya dönülür.</summary>
    public void CancelCardGuide()
    {
        _cardGuideOpen = false;
        SetStep(SetupStep.Welcome);
        Refresh();
    }

    /// <summary>
    /// Rehber bitti: kaynak kart, yer TV ya da bilgisayar. Sihirbazdan açıldıysa adım ilerler; Ayarlar'dan
    /// (rehber açık değilken) yalnız seçim kaydedilir.
    /// </summary>
    public void FinishCardGuide(bool onTv)
    {
        ChangeSettings(s =>
        {
            s.VideoSource = VideoSource.Card;
            s.Output = onTv ? SubtitleOutput.Tv : SubtitleOutput.Computer;
        });
        if (_cardGuideOpen)
        {
            _cardGuideOpen = false;
            if (onTv && !TvPaired) SetStep(SetupStep.Tv);
            else SetStep(ModelInstalled ? SetupStep.Test : SetupStep.Model);
        }
        Refresh();
    }

    /// <summary>"İkinci hesabım yok": Remote Play penceresinden oku.</summary>
    public void UseRemotePlayWindow()
    {
        ChangeSettings(s =>
        {
            s.FrameSource = FrameSource.RemotePlayWindow;
            if (!TvPaired) s.Output = SubtitleOutput.Computer;
        });
        SetStep(SetupStep.Done);
        Refresh();
    }

    /// <summary>"OBS / oyun penceresi seç": seçilen pencereden oku (pencere Ayarlar'da seçilir).</summary>
    public void UseChosenWindow()
    {
        ChangeSettings(s =>
        {
            s.FrameSource = FrameSource.ChosenWindow;
            if (!TvPaired) s.Output = SubtitleOutput.Computer;
        });
        SetStep(SetupStep.Done);
        Refresh();
    }

    /// <summary>"TV'm yok": altyazı bilgisayarda, sonra İlerle.</summary>
    public void NoTv()
    {
        ChangeSettings(s => s.Output = SubtitleOutput.Computer);
        Advance();
    }

    /// <summary>Ayarlar › Bağlantı'da konsol: Xbox'a geçerken PS5 yolu oyun penceresine döner; kart kalır.</summary>
    public void SetGameConsole(GameConsole console)
    {
        if (_settings.GameConsole == console) return;
        ChangeSettings(s =>
        {
            s.GameConsole = console;
            if (console == GameConsole.Xbox && s.VideoSource == VideoSource.Ps5) s.VideoSource = VideoSource.Window;
        });
    }

    /// <summary>Ayarlar'da hesap bağlama düğmesi: sihirbaz İkinci hesap adımından açılır.</summary>
    public void LinkAccount()
    {
        SetStep(SetupStep.SecondAccount);
        Refresh();
    }

    /// <summary>Konsol türü (yalnız Karşılama'da, kilitli değilken; Xbox için hizmet gerekir).</summary>
    public void SetConsoleKind(StoredConsoleKind kind)
    {
        if (_step != SetupStep.Welcome || _kindLocked || _kind == kind) return;
        if (kind == StoredConsoleKind.Xbox && _services.Xbox is null) return;
        _kind = kind;
        _secrets.Set(SecretKeys.ConsoleKind, kind);
        Refresh();
    }

    // ---- Sıfırlamalar (§6.10) ----

    /// <summary>Tümünü sıfırla.</summary>
    public void ResetEverything()
    {
        Stop();
        _xboxGeneration++;
        try { _services.Xbox?.Clear(); } catch (Exception e) { _logs.Error("Xbox temizlenemedi", e); }
        _secrets.RemoveAll(SecretKeys.ResetEverything);
        _accountId = null;
        _console = null;
        _kind = StoredConsoleKind.PlayStation;
        _kindLocked = false;
        _xboxToken = null;
        _xboxConsole = null;
        _tv = null;
        SetTvApp(TvAppStatus.Unknown);
        _cardGuideOpen = false;
        _fromGameWindowShortcut = _fromXboxShortcut = false;
        _step = SetupStep.Welcome;
        Refresh();
    }

    /// <summary>Yeniden kurulum (TV adımından): PS5 hesabı ve eşleşmesi kalır.</summary>
    public void ResetFromTv()
    {
        Stop();
        _secrets.RemoveAll(SecretKeys.ResetTv);
        _tv = null;
        SetTvApp(TvAppStatus.Unknown);
        if (_settings.Output == SubtitleOutput.Computer) ChangeSettings(s => s.Output = SubtitleOutput.Tv);
        _step = SetupStep.Tv;
        Refresh();
    }

    // ---- PS5 oturum şifresi ----

    /// <summary>Kayıtlı giriş şifresi var mı.</summary>
    public bool HasLoginPasscode => _secrets.Contains(SecretKeys.LoginPasscode);

    /// <summary>Giriş şifresini kaydeder (yalnız 4 rakam, kırpılarak).</summary>
    public bool SaveLoginPasscode(string? text)
    {
        if (SecretKeys.NormalizePasscode(text) is not { } code) return false;
        _secrets.Set(SecretKeys.LoginPasscode, code);
        Refresh();
        return true;
    }

    /// <summary>Giriş şifresini kaldırır.</summary>
    public void RemoveLoginPasscode()
    {
        _secrets.Remove(SecretKeys.LoginPasscode);
        Refresh();
    }
}
