// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Data;
using Nino.RemotePlay;

namespace Nino.Shell;

// PSN girişi (§6.7), PS5 arama ve kaydı (§6.8), Xbox girişi ve konsolları (§6.6).
public sealed partial class NinoController
{
    string? _psnError;
    bool _psnBusy;
    IReadOnlyList<FoundPs5> _foundPs5 = [];
    bool _searchingPs5;
    bool _pairingPs5;
    string? _pairError;
    XboxSignInCode? _xboxCode;
    string? _xboxError;
    IReadOnlyList<StoredXboxConsole> _xboxConsoles = [];

    /// <summary>PSN girişinin hata iletisi (yoksa null).</summary>
    public string? PsnError => _psnError;

    /// <summary>PSN girişi sürüyor mu.</summary>
    public bool PsnBusy => _psnBusy;

    /// <summary>Bulunan PS5'ler.</summary>
    public IReadOnlyList<FoundPs5> FoundConsoles => _foundPs5;

    /// <summary>PS5 aranıyor mu.</summary>
    public bool SearchingPs5 => _searchingPs5;

    /// <summary>PS5 kaydı sürüyor mu.</summary>
    public bool PairingPs5 => _pairingPs5;

    /// <summary>PS5 kaydının hata iletisi.</summary>
    public string? PairError => _pairError;

    /// <summary>Eşleşme iletisi (PS5 adımında Bağlan düğmesinin altı); eşleşme yoksa boş.</summary>
    public string PairedMessage => _console is null
        ? ""
        : _text.Format("wizard.ps5.paired", _console.Name is { Length: > 0 } n ? n : "PS5", _console.Host);

    /// <summary>Xbox giriş kodu (giriş sürerken).</summary>
    public XboxSignInCode? XboxCode => _xboxCode;

    /// <summary>Xbox hatası.</summary>
    public string? XboxError => _xboxError;

    /// <summary>Hesaptaki Xbox'lar.</summary>
    public IReadOnlyList<StoredXboxConsole> XboxConsoles => _xboxConsoles;

    // ---- PSN ----

    /// <summary>
    /// PSN girişi: uygulama içi pencere varsa orada, yoksa tarayıcıda açılır (kullanıcı yönlendirme adresini yapıştırır).
    /// </summary>
    public async Task SignInToPsnAsync(CancellationToken cancellationToken = default)
    {
        if (_psnWindow is null)
        {
            OpenPsnSignInInBrowser();
            return;
        }
        _psnError = null;
        Refresh();
        PsnWindowOutcome outcome;
        try
        {
            outcome = await _psnWindow.SignInAsync(PsnSignIn.SignInUrl(), cancellationToken).ConfigureAwait(false);
        }
        catch (Exception e)
        {
            outcome = new PsnWindowOutcome(null, e.Message);
        }
        await OnUi();
        if (outcome.RedirectUrl is { } url)
        {
            await CompletePsnSignInAsync(url, cancellationToken).ConfigureAwait(false);
            await OnUi();
            return;
        }
        var problem = outcome.Problem;
        if (string.IsNullOrWhiteSpace(problem)) _psnError = _text.Get("wizard.psn.error.windowClosed");
        else if (problem.Contains("429", StringComparison.Ordinal)) _psnError = _text.Get("wizard.psn.error.rateLimited");
        else _psnError = $"{_text.Get("wizard.psn.error.pageFailed")} ({problem}) {LogHint()}";
        Refresh();
    }

    /// <summary>Sony'nin giriş sayfasını tarayıcıda açar.</summary>
    public void OpenPsnSignInInBrowser() => _browser.Open(PsnSignIn.SignInUrl());

    /// <summary>Yönlendirme adresinden (ya da onu içeren metinden) hesap kimliğini alır.</summary>
    public async Task<bool> CompletePsnSignInAsync(string redirect, CancellationToken cancellationToken = default)
    {
        var url = PsnSignIn.RedirectFromText(redirect) ?? redirect.Trim();
        _psnBusy = true;
        _psnError = null;
        Refresh();
        try
        {
            var id = await _services.AccountIdFromRedirectAsync(url, cancellationToken).ConfigureAwait(false);
            await OnUi();
            SaveAccountId(id);
            _logs.RemotePlay("PSN girişi tamam");
            return true;
        }
        catch (PsnSignInException e)
        {
            await OnUi();
            _logs.RemotePlay("PSN girişi olmadı: " + e.LogText);
            var key = e.Kind switch
            {
                PsnSignInFailure.Refused => "wizard.psn.error.rejected",
                PsnSignInFailure.RateLimited => "wizard.psn.error.rateLimited",
                PsnSignInFailure.Http => "wizard.psn.error.server",
                PsnSignInFailure.Network => "wizard.psn.error.network",
                PsnSignInFailure.BadResponse => "wizard.psn.error.badResponse",
                _ => "wizard.psn.error.notCompleted",
            };
            var details = new List<string>();
            if (e.HttpStatus is { } status) details.Add(_text.Format("wizard.psn.error.httpCode", status));
            if (!string.IsNullOrWhiteSpace(e.Detail)) details.Add(e.Detail!.Trim());
            var detail = details.Count > 0 ? $" ({string.Join(", ", details)})" : "";
            _psnError = $"{_text.Get(key)}{detail} {LogHint()}";
            return false;
        }
        catch (OperationCanceledException)
        {
            await OnUi();
            return false;
        }
        catch (Exception e)
        {
            await OnUi();
            _logs.RemotePlay("PSN girişi beklenmeyen hata: " + e);
            _psnError = $"{_text.Get("wizard.psn.error.notCompleted")} ({e.Message}) {LogHint()}";
            return false;
        }
        finally
        {
            _psnBusy = false;
            Refresh();
        }
    }

    /// <summary>Elle hesap kimliği (12 karakter base64, 8 bayt). Geçersizse hiçbir şey kaydedilmez.</summary>
    public bool SetManualAccountId(string? text)
    {
        if (PsnAccountId.FromManualText(text) is not { } id) return false;
        SaveAccountId(id);
        Refresh();
        return true;
    }

    void SaveAccountId(byte[] id)
    {
        _accountId = id;
        _secrets.Set(SecretKeys.AccountId, id);
    }

    // ---- PS5 arama ve kayıt ----

    /// <summary>PS5 arar (adres verilirse yalnız o).</summary>
    public async Task SearchPs5Async(string? host = null, CancellationToken cancellationToken = default)
    {
        if (_searchingPs5) return;
        _searchingPs5 = true;
        Refresh();
        try
        {
            var found = await _services.FindPs5Async(string.IsNullOrWhiteSpace(host) ? null : host.Trim(), cancellationToken)
                .ConfigureAwait(false);
            await OnUi();
            _foundPs5 = found;
        }
        catch (Exception e)
        {
            await OnUi();
            _logs.RemotePlay("PS5 araması hata verdi: " + e.Message);
            _foundPs5 = [];
        }
        finally
        {
            _searchingPs5 = false;
            Refresh();
        }
    }

    /// <summary>PS5'e kayıt (sekiz rakamlı kod). Başarıda true.</summary>
    public async Task<bool> PairPs5Async(string? host, string? code, CancellationToken cancellationToken = default)
    {
        if (_pairingPs5) return false;
        var address = host?.Trim() ?? "";
        if (address.Length == 0)
        {
            _pairError = _text.Get("wizard.ps5.error.notFound");
            Refresh();
            return false;
        }
        if (PairingCode.TryParse(code) is not { } pin)
        {
            _pairError = _text.Get("wizard.ps5.error.codeLength");
            Refresh();
            return false;
        }
        if (_accountId is not { } account)
        {
            _pairError = _text.Get("wizard.ps5.error.signInFirst");
            Refresh();
            return false;
        }

        _pairingPs5 = true;
        _pairError = null;
        Refresh();
        try
        {
            var console = await _services.RegisterPs5Async(address, account, pin, cancellationToken).ConfigureAwait(false);
            await OnUi();
            if (_firewall != FirewallHint.Working) _firewall = FirewallHint.None;
            SaveConsole(console);
            _logs.RemotePlay($"PS5 eşleşmesi saklandı ({console.Host}): {console.Name}");
            return true;
        }
        catch (PairingException e)
        {
            await OnUi();
            var key = e.Outcome switch
            {
                PairingOutcome.WrongAccount => "wizard.ps5.error.wrongAccount",
                PairingOutcome.NoAnswer => "wizard.ps5.error.noResponse",
                PairingOutcome.InUse => "wizard.ps5.error.inUse",
                PairingOutcome.ConsoleCrashed => "wizard.ps5.error.serviceCrashed",
                PairingOutcome.VersionMismatch => "wizard.ps5.error.versionMismatch",
                PairingOutcome.WrongCode => "wizard.ps5.error.wrongCode",
                PairingOutcome.NoReply => "wizard.ps5.error.timeout",
                PairingOutcome.BadAddress => "wizard.ps5.error.badAddress",
                _ => "wizard.ps5.error.other",
            };
            var detail = string.IsNullOrWhiteSpace(e.Detail) ? "" : $" ({e.Detail!.Trim()})";
            _pairError = $"{_text.Get(key)}{detail} {LogHint()}";
            _logs.RemotePlay($"PS5 kaydı olmadı: {e.Outcome}{detail}");
            if (!e.ConsoleReported && e.Outcome is not (PairingOutcome.WrongAccount or PairingOutcome.BadAddress))
                await CheckFirewallAfterPairingAsync().ConfigureAwait(false);
            return false;
        }
        catch (OperationCanceledException)
        {
            await OnUi();
            return false;
        }
        catch (Exception e)
        {
            await OnUi();
            _logs.RemotePlay("PS5 kaydı beklenmeyen hata: " + e);
            _pairError = $"{_text.Get("wizard.ps5.error.other")} ({e.Message}) {LogHint()}";
            await CheckFirewallAfterPairingAsync().ConfigureAwait(false);
            return false;
        }
        finally
        {
            await OnUi();
            _pairingPs5 = false;
            Refresh();
        }
    }

    /// <summary>Eşleşmeden kısa süre sonra ekran çağırır: yalnız PS5 adımındaysa ve konsol kayıtlıysa İlerle.</summary>
    public void ContinueAfterPairing()
    {
        if (_step == SetupStep.Console && _console is not null) Advance();
    }

    // ---- Xbox (§6.6) ----

    /// <summary>Microsoft girişini başlatır: kod alınır, adres tarayıcıda açılır, giriş bitince jeton kaydedilir.</summary>
    public async Task SignInToXboxAsync(CancellationToken cancellationToken = default)
    {
        if (_services.Xbox is not { } xbox)
        {
            _xboxError = _text.Get("wizard.xbox.error.unavailable");
            Refresh();
            return;
        }
        var generation = _xboxGeneration;
        _xboxError = null;
        try
        {
            var code = await xbox.BeginSignInAsync(cancellationToken).ConfigureAwait(false);
            await OnUi();
            _xboxCode = code;
            _browser.Open(code.Url);
            Refresh();
            var token = await xbox.FinishSignInAsync(cancellationToken).ConfigureAwait(false);
            await OnUi();
            if (generation != _xboxGeneration) return;
            _xboxToken = token;
            _secrets.Set(SecretKeys.XboxToken, token);
        }
        catch (Exception e) when (e is not OperationCanceledException)
        {
            await OnUi();
            _xboxError = _text.Get("xboxLogin.incomplete") + " (" + e.Message + ")";
        }
        finally
        {
            _xboxCode = null;
            Refresh();
        }
    }

    /// <summary>Hesaptaki Xbox'ları sorar; kayıtlı Xbox aynı kimlikle farklı adla varsa ad düzeltilir.</summary>
    public async Task FindXboxConsolesAsync(CancellationToken cancellationToken = default)
    {
        if (_services.Xbox is not { } xbox)
        {
            _xboxError = _text.Get("wizard.xbox.error.unavailable");
            Refresh();
            return;
        }
        if (_xboxToken is not { } token)
        {
            _xboxError = _text.Get("wizard.xbox.error.signInNotFinished");
            Refresh();
            return;
        }
        try
        {
            var list = await xbox.FindConsolesAsync(token, cancellationToken).ConfigureAwait(false);
            await OnUi();
            _xboxConsoles = list;
            FixXboxName(list);
            _xboxError = null;
        }
        catch (Exception e) when (e is not OperationCanceledException)
        {
            await OnUi();
            _xboxError = e.Message;
        }
        Refresh();
    }

    void FixXboxName(IReadOnlyList<StoredXboxConsole> list)
    {
        if (_xboxConsole is not { } saved) return;
        if (list.FirstOrDefault(c => c.Id == saved.Id && c.Name != saved.Name) is { } fresh)
        {
            _xboxConsole = saved with { Name = fresh.Name };
            _secrets.Set(SecretKeys.XboxConsole, _xboxConsole);
        }
    }

    /// <summary>Xbox seçer (yayını kapalı konsol seçilemez).</summary>
    public bool SelectXboxConsole(StoredXboxConsole console)
    {
        if (!console.StreamingEnabled) return false;
        _xboxConsole = console;
        _secrets.Set(SecretKeys.XboxConsole, console);
        Refresh();
        return true;
    }

    void OnXboxTokenRefreshed(string token)
    {
        if (token == _xboxToken || !IsXbox) return;
        _xboxToken = token;
        _secrets.Set(SecretKeys.XboxToken, token);
    }
}
