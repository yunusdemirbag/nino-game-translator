// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.IO;
using System.Windows;
using System.Windows.Controls;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;
using Nino.App.Strings;
using Nino.App.Views.Setup;
using Nino.RemotePlay;
using Nino.Shell.Platform;

namespace Nino.App.Views;

/// <summary>Giriş penceresinin sonucu. Yönlendirme varsa sorun ve taşıma yok sayılır.</summary>
/// <param name="RedirectUrl">Sony'nin yönlendirme adresi (kod içerir); yoksa null.</param>
/// <param name="Problem">Pencerenin gördüğü sorun ("HTTP 503", "WebView2 …"); yoksa null.</param>
/// <param name="MoveToBrowser">Sony'nin sayfası uygulama içinde sunucusuna bağlanamadı: giriş tarayıcıya taşınmalı.</param>
public sealed record PsnSignInResult(string? RedirectUrl, string? Problem, bool MoveToBrowser);

/// <summary>
/// Uygulama içi PlayStation Network giriş penceresi (kaynaklar.md §1.4): WebView2, her girişte temiz profil
/// (<c>%LOCALAPPDATA%\Nino\webview\&lt;rastgele&gt;</c>), yönlendirmeyi gezinme başlarken yakalar, Sony'nin "sunucuya
/// bağlanılamıyor" sayfasını sayfa metninden tanır. Sahibinin ortasında, kiplidir; her giriş için yeni pencere kurulur.
/// </summary>
public sealed class PsnSignInWindow : Window
{
    /// <summary>Microsoft'un WebView2 indirme sayfası.</summary>
    public const string RuntimeDownloadUrl = "https://go.microsoft.com/fwlink/p/?LinkId=2124703";

    const string PagePrefix = "nino-page-text:";

    // Sayfanın görünür metnini (ilk 4000 karakter) değiştikçe, en çok 500 ms'de bir uygulamaya gönderir (yalnız üst
    // çerçeve). Sony arka plan isteği düşünce hatayı sayfayı yeniden yüklemeden gösterir; gezinme olayından anlaşılmaz.
    const string WatchScript = """
        (function () {
          if (window.top !== window) return;
          var last = null, timer = null, sentAt = 0;
          function send() {
            timer = null; sentAt = Date.now();
            var text = document.body ? (document.body.innerText || '') : '';
            text = text.slice(0, 4000);
            if (text === last) return;
            last = text;
            try { window.chrome.webview.postMessage('nino-page-text:' + text); } catch (e) { }
          }
          function schedule() {
            if (timer !== null) return;
            timer = setTimeout(send, Math.max(0, 500 - (Date.now() - sentAt)));
          }
          function start() {
            schedule();
            new MutationObserver(schedule).observe(document.documentElement,
              { subtree: true, childList: true, characterData: true });
          }
          if (document.readyState !== "loading") start(); else document.addEventListener("DOMContentLoaded", start);
        })();
        """;

    // Ortamlar tarayıcı süreci bitene kadar canlı tutulur (yoksa "süreç bitti" olayı gelmez, profil silinmez).
    static readonly List<CoreWebView2Environment> Alive = [];

    readonly string _signInUrl;
    readonly string _dataFolder;
    readonly Action<string>? _log;
    readonly WebView2 _web = new();
    string? _redirect;
    string? _problem;
    bool _moveToBrowser;
    bool _closing;

    /// <summary>Giriş penceresi.</summary>
    /// <param name="signInUrl">Sony'nin giriş sayfası.</param>
    /// <param name="dataFolder">Veri klasörü (%LOCALAPPDATA%\Nino); profil <c>webview\</c> altında kurulur.</param>
    /// <param name="log">remoteplay.log'a not (isteğe bağlı).</param>
    public PsnSignInWindow(string signInUrl, string dataFolder, Action<string>? log = null)
    {
        _signInUrl = signInUrl;
        _dataFolder = dataFolder;
        _log = log;
        SetResourceReference(StyleProperty, "Window.Nino");
        Title = L.Get("psnLogin.window.title");
        Width = 520;
        Height = 720;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        ShowInTaskbar = false;

        var cancel = SetupUi.Button(L.Get("common.cancel"), ButtonKind.Secondary, (_, _) => Close());
        cancel.IsCancel = true;
        var header = SetupUi.TopRow(SetupUi.Key("psnLogin.window.title", "Text.Headline"), cancel, new Thickness(16, 12, 16, 12));
        var dock = new DockPanel { LastChildFill = true };
        DockPanel.SetDock(header, Dock.Top);
        dock.Children.Add(header);
        dock.Children.Add(_web);
        Content = dock;

        Loaded += async (_, _) => await StartAsync();
        Closing += (_, _) => _closing = true;
        Closed += (_, _) =>
        {
            try { _web.Dispose(); } catch (Exception) { }
        };
    }

    /// <summary>Sonuç (pencere kapandıktan sonra).</summary>
    public PsnSignInResult Result => _redirect is not null
        ? new PsnSignInResult(_redirect, null, false)
        : new PsnSignInResult(null, _problem, _moveToBrowser);

    /// <summary>WebView2 çalışma ortamı bu bilgisayarda kurulu mu.</summary>
    public static bool IsRuntimeAvailable()
    {
        try { return CoreWebView2Environment.GetAvailableBrowserVersionString() is { Length: > 0 }; }
        catch (Exception) { return false; }
    }

    /// <summary>
    /// Pencereyi arayüz iş parçacığında, sahibinin üstünde kipli açar; kapanınca sonucu verir. İptal pencereyi kapatır.
    /// </summary>
    public static Task<PsnSignInResult> ShowAsync(Window? owner, string signInUrl, string dataFolder,
        Action<string>? log = null, CancellationToken cancellationToken = default)
    {
        var app = Application.Current ?? throw new InvalidOperationException("WPF uygulaması yok");
        return app.Dispatcher.InvokeAsync(() =>
        {
            var window = new PsnSignInWindow(signInUrl, dataFolder, log);
            var parent = owner ?? SetupUi.ActiveWindow();
            if (parent is { IsLoaded: true } && !ReferenceEquals(parent, window)) window.Owner = parent;
            using var registration = cancellationToken.Register(() => app.Dispatcher.BeginInvoke(() =>
            {
                if (window.IsLoaded) window.Close();
            }));
            window.ShowDialog();
            return window.Result;
        }).Task;
    }

    async Task StartAsync()
    {
        try
        {
            var root = Path.Combine(_dataFolder, "webview");
            CleanOldProfiles(root);
            var profile = Path.Combine(root, Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(profile);
            var environment = await CoreWebView2Environment.CreateAsync(null, profile);
            lock (Alive) Alive.Add(environment);
            environment.BrowserProcessExited += (_, _) =>
            {
                lock (Alive) Alive.Remove(environment);
                TryDelete(profile);
            };
            await _web.EnsureCoreWebView2Async(environment);
            if (_closing) return;
            var core = _web.CoreWebView2;
            await core.AddScriptToExecuteOnDocumentCreatedAsync(WatchScript);
            core.NavigationStarting += OnNavigationStarting;
            core.NavigationCompleted += OnNavigationCompleted;
            core.WebMessageReceived += OnWebMessage;
            core.ProcessFailed += (_, e) => Fail("WebView2 " + e.ProcessFailedKind);
            core.Navigate(_signInUrl);
        }
        catch (Exception e)
        {
            Fail("WebView2: " + e.Message);
        }
    }

    void OnNavigationStarting(object? sender, CoreWebView2NavigationStartingEventArgs e)
    {
        if (!PsnSignIn.IsRedirect(e.Uri)) return;
        e.Cancel = true;
        _redirect = e.Uri;
        CloseSoon();
    }

    void OnNavigationCompleted(object? sender, CoreWebView2NavigationCompletedEventArgs e)
    {
        if (_redirect is not null) return;
        string? problem;
        if (!e.IsSuccess)
        {
            if (e.WebErrorStatus == CoreWebView2WebErrorStatus.OperationCanceled) return;
            problem = e.HttpStatusCode >= 400 ? "HTTP " + e.HttpStatusCode : e.WebErrorStatus.ToString();
        }
        else problem = e.HttpStatusCode >= 400 ? $"HTTP {e.HttpStatusCode}" : null;
        _problem = problem;
        if (problem is not null) _log?.Invoke("PSN giriş sayfası: " + problem);
    }

    void OnWebMessage(object? sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        string? message;
        try { message = e.TryGetWebMessageAsString() ?? ""; }
        catch (Exception) { return; }
        if (message is null || !message.StartsWith(PagePrefix, StringComparison.Ordinal)) return;
        var host = Uri.TryCreate(e.Source, UriKind.Absolute, out var source) ? source.Host : "";
        if (!PsnSignIn.IsSonyHost(host) || !PsnSignIn.IsCannotConnectPage(message[PagePrefix.Length..])) return;
        _moveToBrowser = true;
        _problem = "Sony's sign-in page reported a server connection error";
        _log?.Invoke($"PSN oturum sayfası Sony sunucusuna erişemedi ({host}); oturum açma tarayıcıda sürecek");
        CloseSoon();
    }

    void Fail(string problem)
    {
        _problem = problem;
        _log?.Invoke("PSN giriş sayfası: " + problem);
        CloseSoon();
    }

    void CloseSoon() => Dispatcher.BeginInvoke(() =>
    {
        if (!_closing) Close();
    });

    static void CleanOldProfiles(string root)
    {
        try
        {
            if (!Directory.Exists(root)) return;
            foreach (var folder in Directory.GetDirectories(root)) TryDelete(folder);
        }
        catch (Exception) { }
    }

    static void TryDelete(string folder)
    {
        try { Directory.Delete(folder, true); }
        catch (Exception) { }
    }
}

/// <summary>
/// Denetleyicinin <see cref="IPsnSignInWindow"/>'u (ShellOptions.PsnWindow): her girişte yeni bir
/// <see cref="PsnSignInWindow"/> açar. "Tarayıcıya taşı" sonucu denetleyiciye sorun metni olarak geçer; sihirbazın PSN
/// adımı pencereyi doğrudan açar ve taşımayı kendisi işler.
/// </summary>
/// <param name="dataFolder">Veri klasörü (%LOCALAPPDATA%\Nino).</param>
/// <param name="log">remoteplay.log'a not (isteğe bağlı).</param>
public sealed class PsnSignInHost(string dataFolder, Action<string>? log = null) : IPsnSignInWindow
{
    /// <inheritdoc />
    public async Task<PsnWindowOutcome> SignInAsync(string signInUrl, CancellationToken cancellationToken = default)
    {
        if (!PsnSignInWindow.IsRuntimeAvailable())
        {
            SetupUi.Open(PsnSignInWindow.RuntimeDownloadUrl);
            log?.Invoke("PSN oturumu: bu bilgisayarda WebView2 yok");
            return new PsnWindowOutcome(null, "WebView2");
        }
        var result = await PsnSignInWindow.ShowAsync(null, signInUrl, dataFolder, log, cancellationToken);
        return new PsnWindowOutcome(result.RedirectUrl, result.Problem);
    }
}
