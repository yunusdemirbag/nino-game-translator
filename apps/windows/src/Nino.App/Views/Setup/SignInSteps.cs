// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using Nino.App.Strings;
using Nino.RemotePlay;
using Nino.Shell;
using Nino.Shell.Setup;

namespace Nino.App.Views.Setup;

/// <summary>
/// PSN girişi (kurulum.md §4, kaynaklar.md §1.4): uygulama içi giriş penceresi (WebView2), tarayıcıda giriş ve panodan
/// kendiliğinden alma, elle hesap kimliği.
/// </summary>
internal sealed class PsnSignInStep : StepPage
{
    readonly TextBlock _signedIn = SetupUi.Key("setup.signedIn", "Text.Success", SetupUi.Bottom(12));
    readonly Button _signIn;
    readonly TextBlock _error = SetupUi.Text("", "Text.Error", SetupUi.Top(12));
    readonly Button _browserButton;
    readonly StackPanel _browser;
    readonly TextBlock _reason = SetupUi.Key("psnLogin.movedToBrowser", "Text.Callout", SetupUi.Bottom(6));
    readonly TextBox _paste = new() { Width = 340 };
    readonly TextBlock _browserError = SetupUi.Text("", "Text.Error", SetupUi.Top(8));
    readonly Button _manualButton;
    readonly StackPanel _manual;
    readonly TextBox _manualId = new() { Width = 240, MaxLength = 24 };
    readonly TextBlock _manualError = SetupUi.Text("", "Text.Error", SetupUi.Top(8));
    string? _localError;
    string? _lastTried;
    bool _working;
    Window? _window;

    public PsnSignInStep(NinoController controller) : base(controller)
    {
        _signIn = SetupUi.Button("", ButtonKind.Primary, (_, _) => Fire.AndForget(SignInAsync));
        _browserButton = SetupUi.Button(L.Get("setup.psnSignIn.signInInBrowser"), ButtonKind.Secondary,
            (_, _) => OpenBrowserPath(automatic: false), SetupUi.Top(20));

        var saveRedirect = SetupUi.Button(L.Get("common.save"), ButtonKind.Primary, (_, _) => Fire.AndForget(SubmitAsync), SetupUi.M(12, 0, 0, 0));
        SetupUi.OnEnter(_paste, () => Fire.AndForget(SubmitAsync));
        var pasteRow = SetupUi.Row(_paste, saveRedirect);
        var reopen = SetupUi.Button(L.Get("setup.psnSignIn.openBrowserAgain"), ButtonKind.Secondary,
            (_, _) => C.OpenPsnSignInInBrowser(), SetupUi.Top(8));
        _browser = SetupUi.Stack(_reason, SetupUi.Key("setup.psnSignIn.browserSteps", "Text.Callout", SetupUi.Bottom(6)), pasteRow, reopen,
            _browserError);
        _browser.Margin = SetupUi.Top(20);
        _browser.Visibility = Visibility.Collapsed;

        _manualButton = SetupUi.Button(L.Get("setup.psnSignIn.enterIdManually"), ButtonKind.Secondary, (sender, _) =>
        {
            SetupUi.Show((UIElement)sender, false);
            SetupUi.Show(_manual!, true);
            _manualId.Focus();
        }, SetupUi.Top(12));
        var saveManual = SetupUi.Button(L.Get("common.save"), ButtonKind.Primary, (_, _) => SaveManual(), SetupUi.M(12, 0, 0, 0));
        SetupUi.OnEnter(_manualId, SaveManual);
        _manual = SetupUi.Stack(SetupUi.Key("setup.psnSignIn.manualHint", "Text.Callout", SetupUi.Bottom(6)), SetupUi.Row(_manualId, saveManual),
            _manualError);
        _manual.Margin = SetupUi.Top(20);
        _manual.Visibility = Visibility.Collapsed;

        Layout(L.Get("setup.psnSignIn.title"), L.Get("setup.psnSignIn.description"), SetupUi.Stack(
            _signedIn, _signIn, _error, _browserButton, _browser, _manualButton, _manual));
        Render();
    }

    protected override void Attached()
    {
        _window = Window.GetWindow(this);
        if (_window is not null) _window.Activated += OnWindowActivated;
    }

    protected override void Detached()
    {
        if (_window is not null) _window.Activated -= OnWindowActivated;
        _window = null;
    }

    protected override void OnChanged(string property)
    {
        if (property is nameof(NinoController.HasAccount) or nameof(NinoController.PsnBusy) or nameof(NinoController.PsnError))
            Render();
    }

    void Render()
    {
        SetupUi.Show(_signedIn, C.HasAccount);
        _signIn.Content = L.Get(C.HasAccount ? "psnLogin.signInAgain" : "psnLogin.signIn");
        SetupUi.SetKind(_signIn, C.HasAccount ? ButtonKind.Secondary : ButtonKind.Primary);
        _signIn.IsEnabled = !_working && !C.PsnBusy;
        SetupUi.SetText(_error, _localError ?? C.PsnError);
    }

    bool Busy => _working || C.PsnBusy;

    async Task SignInAsync()
    {
        if (Busy) return;
        _localError = null;
        if (!PsnSignInWindow.IsRuntimeAvailable())
        {
            _localError = L.Get("setup.psnSignIn.webView2Missing");
            SetupUi.Open(PsnSignInWindow.RuntimeDownloadUrl);
            C.NoteRemotePlay("PSN oturumu: bu bilgisayarda WebView2 yok");
            Render();
            return;
        }
        _working = true;
        Render();
        try
        {
            var result = await PsnSignInWindow.ShowAsync(Window.GetWindow(this), PsnSignIn.SignInUrl(), SetupUi.DataFolder,
                C.NoteRemotePlay);
            if (result.RedirectUrl is { } url)
            {
                _working = false;
                await C.CompletePsnSignInAsync(url);
            }
            else if (result.MoveToBrowser)
            {
                _localError = null;
                OpenBrowserPath(automatic: true);
            }
            else _localError = C.PsnWindowClosedText(result.Problem);
        }
        finally
        {
            _working = false;
            Render();
        }
    }

    void OpenBrowserPath(bool automatic)
    {
        SetupUi.Show(_browserButton, false);
        SetupUi.Show(_browser, true);
        SetupUi.Show(_reason, automatic);
        SetupUi.SetText(_browserError, null);
        // Panoda eski girişten kalan yönlendirme varsa kendiliğinden denenmesin.
        _lastTried = PsnSignIn.RedirectFromText(SetupUi.TryReadClipboard());
        C.OpenPsnSignInInBrowser();
        _paste.Focus();
    }

    void OnWindowActivated(object? sender, EventArgs e)
    {
        if (_browser.Visibility != Visibility.Visible || Busy) return;
        var text = SetupUi.TryReadClipboard();
        if (PsnSignIn.RedirectFromText(text) is not { } redirect || redirect == _lastTried) return;
        _paste.Text = redirect;
        Fire.AndForget(SubmitAsync);
    }

    async Task SubmitAsync()
    {
        if (Busy) return;
        if (PsnSignIn.RedirectFromText(_paste.Text) is not { } redirect)
        {
            SetupUi.SetText(_browserError, L.Get("psnLogin.paste.noCode"));
            return;
        }
        SetupUi.SetText(_browserError, null);
        _lastTried = redirect;
        _localError = null;
        _working = true;
        Render();
        bool ok;
        try { ok = await C.CompletePsnSignInAsync(redirect); }
        finally
        {
            _working = false;
            Render();
        }
        if (!ok || !C.HasAccount || C.PsnError is not null) return;
        _paste.Text = "";
        SetupUi.Show(_browser, false);
        SetupUi.Show(_browserButton, true);
        // Tek kullanımlık kod panoda kalmasın.
        if (PsnSignIn.RedirectFromText(SetupUi.TryReadClipboard()) is not null) SetupUi.TryClearClipboard();
    }

    void SaveManual()
    {
        if (C.SetManualAccountId(_manualId.Text))
        {
            SetupUi.SetText(_manualError, null);
            _localError = null;
            Render();
        }
        else SetupUi.SetText(_manualError, L.Get("setup.psnSignIn.invalidId"));
    }
}

/// <summary>Microsoft girişi (kurulum.md §5; Xbox): cihaz kodu, bağlantı, girişin bitmesini bekleme.</summary>
internal sealed class MicrosoftSignInStep : StepPage
{
    readonly TextBlock _signedIn = SetupUi.Key("setup.signedIn", "Text.Success", SetupUi.Bottom(12));
    readonly Button _signIn;
    readonly StackPanel _codeSection;
    readonly TextBox _code = new()
    {
        IsReadOnly = true,
        BorderThickness = new Thickness(0),
        Background = System.Windows.Media.Brushes.Transparent,
        FontSize = 30,
        FontWeight = FontWeights.Bold,
        Cursor = Cursors.Hand,
        Padding = new Thickness(0),
        Margin = SetupUi.Bottom(4),
        HorizontalAlignment = HorizontalAlignment.Left,
    };
    readonly TextBlock _link = SetupUi.Text("", "Text.Body", SetupUi.Bottom(8));
    readonly TextBlock _steps = SetupUi.Text("", "Text.Callout");
    readonly TextBlock _status = SetupUi.Text("", "Text.Callout");
    readonly TextBlock _error = SetupUi.Text("", "Text.Error", SetupUi.Top(12));
    bool _working;
    string? _url;

    public MicrosoftSignInStep(NinoController controller) : base(controller)
    {
        _signIn = SetupUi.Button(L.Get("setup.msSignIn.signIn"), ButtonKind.Primary, (_, _) => Fire.AndForget(SignInAsync));
        _code.PreviewMouseLeftButtonUp += (_, _) =>
        {
            SetupUi.TryCopy(_code.Text);
            _code.SelectAll();
        };
        _codeSection = SetupUi.Stack(SetupUi.Key("setup.msSignIn.codeLabel", "Text.Callout", SetupUi.Bottom(4)), _code, _link, _steps);
        _codeSection.Margin = SetupUi.M(0, 16, 0, 8);
        _codeSection.Visibility = Visibility.Collapsed;
        SetupUi.SetText(_status, null);
        SetupUi.SetText(_error, null);
        Layout(L.Get("setup.msSignIn.title"), L.Get("setup.msSignIn.description"), SetupUi.Stack(
            _signedIn, _signIn, _codeSection, _status, _error));
        SetupUi.Show(_signedIn, C.HasXboxToken);
    }

    protected override void OnChanged(string property)
    {
        if (property == nameof(NinoController.HasXboxToken)) SetupUi.Show(_signedIn, C.HasXboxToken);
        if (property == nameof(NinoController.XboxCode) && _working && C.XboxCode is { } code) ShowCode(code.UserCode, code.Url);
    }

    async Task SignInAsync()
    {
        if (_working) return;
        _working = true;
        _signIn.IsEnabled = false;
        SetupUi.SetText(_error, null);
        SetupUi.SetText(_status, L.Get("setup.msSignIn.statusOpening"));
        try
        {
            await C.SignInToXboxAsync();
            SetupUi.Show(_codeSection, false);
            if (C.XboxError is { Length: > 0 } error)
            {
                SetupUi.SetText(_error, error);
                SetupUi.SetText(_status, L.Get("setup.msSignIn.statusFailed"));
            }
            else if (C.HasXboxToken) SetupUi.SetText(_status, L.Get("setup.msSignIn.statusDone"));
        }
        finally
        {
            _working = false;
            _signIn.IsEnabled = true;
        }
    }

    void ShowCode(string userCode, string url)
    {
        _url = url;
        _code.Text = userCode;
        SetupUi.TryCopy(userCode);
        var link = new Hyperlink(new Run(MicrosoftLink.Display(url)));
        link.Click += (_, _) =>
        {
            SetupUi.TryCopy(_code.Text);
            if (_url is not null) SetupUi.Open(_url);
        };
        _link.Inlines.Clear();
        _link.Inlines.Add(link);
        _steps.Text = string.Join("\n", L.Get("setup.msSignIn.step1"), L.Get("setup.msSignIn.step2"), L.Get("setup.msSignIn.step3"));
        SetupUi.Show(_codeSection, true);
        SetupUi.SetText(_status, L.Get("setup.msSignIn.statusWaiting"));
    }
}
