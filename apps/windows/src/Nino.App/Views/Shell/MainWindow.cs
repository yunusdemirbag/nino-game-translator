// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media.Imaging;
using System.Windows.Interop;
using Nino.App.Services;
using Nino.App.Startup;
using Nino.App.Strings;
using Nino.App.Theme;
using Nino.Core.Settings;
using Nino.Shell;

namespace Nino.App.Views;

/// <summary>
/// Tek ana pencere, kabuk (ana-ekran §2): 1040 × 720 (en az da bu), ekranın ortasında, sistem çerçevesi. Tek ızgarada
/// altta ekran yeri (kurulum ya da ana ekran), üstünde "Nino'ya Sor" robotu ve "çeviri başladı" balonu. Pencereye bağlı
/// işler: genel kısayollar (tutamaç oluşunca), uykudan uyanma, bilgisayardaki altyazı penceresi ve sonuç kutusu;
/// kapanınca hepsi bırakılır, denetleyici kapatılır.
/// </summary>
public sealed class MainWindow : Window
{
    /// <summary>Pencere boyu.</summary>
    public const double DefaultWidth = 1040, DefaultHeight = 720;

    readonly NinoController _controller;
    readonly bool _live;
    readonly GlobalHotkeys? _hotkeys;
    readonly PowerResumeWatch? _resume;
    readonly ContentControl _screen = new() { Focusable = false, IsTabStop = false };
    readonly RobotButton _robot = new();
    readonly StartedToast _toast = new();
    IReadOnlyList<IDisposable> _sideWindows = [];
    bool? _showingHome;
    bool _wasTranslating;
    bool _closed;

    /// <summary>Kabuğu kurar.</summary>
    /// <param name="controller">Denetleyici.</param>
    /// <param name="live">Gerçek açılış mı. Değilse pencere yalnız çizim içindir (ekran dökümü): kısayol, uyanma olayı ve
    /// yan pencere bağlanmaz, kapanınca denetleyici kapatılmaz.</param>
    public MainWindow(NinoController controller, bool live)
    {
        _controller = controller;
        _live = live;
        if (live)
        {
            _hotkeys = AppParts.Platform?.Hotkeys;
            _resume = AppParts.Platform?.Resume;
        }
        SetResourceReference(StyleProperty, "Window.Nino");
        Title = L.Get("app.error.title");
        try { Icon = BitmapFrame.Create(new Uri("pack://application:,,,/Assets/Nino.ico", UriKind.Absolute)); }
        catch (Exception) { }
        Width = DefaultWidth;
        Height = DefaultHeight;
        MinWidth = DefaultWidth;
        MinHeight = DefaultHeight;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        RightToLeft.ApplyTo(this);

        var root = new Grid();
        root.Children.Add(_screen);
        root.Children.Add(_robot);
        root.Children.Add(_toast);
        Content = root;

        _toast.HorizontalAlignment = HorizontalAlignment.Left;
        _toast.VerticalAlignment = VerticalAlignment.Bottom;
        _toast.Margin = new Thickness(36 + RobotButton.Size + 12, 0, 0, 84 + 6);
        _robot.VerticalAlignment = VerticalAlignment.Bottom;
        _robot.Click += (_, _) => ShellWindows.Show(ShellWindowKind.AskNino, this, _controller);

        _wasTranslating = controller.IsTranslating;
        ChooseScreen(force: true);
        controller.PropertyChanged += OnControllerChanged;

        if (live)
        {
            // Genel kısayollar pencerenin tutamacı oluşunca kurulur.
            SourceInitialized += (_, _) =>
                _hotkeys?.Attach(new WindowInteropHelper(this).Handle, action => _ = RunHotkeyAsync(action));
            if (_resume is not null) { _resume.Resumed += OnResumed; _resume.Suspending += OnSuspending; }
            Loaded += OnFirstLoaded;
        }
        Closed += OnClosed;
    }

    /// <summary>Denetleyici.</summary>
    public NinoController Controller => _controller;

    /// <summary>Ekran yerindeki görünüm (ana ekran ya da kurulum).</summary>
    public FrameworkElement? Screen => _screen.Content as FrameworkElement;

    void OnControllerChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (_closed) return;
        ChooseScreen(force: false);
        var translating = _controller.IsTranslating;
        if (translating != _wasTranslating)
        {
            _wasTranslating = translating;
            if (translating && _controller.IsSetupComplete) _toast.Show();
            else if (!translating) _toast.Hide(TimeSpan.FromSeconds(0.25));
        }
    }

    /// <summary>
    /// Kurulum bittiyse ana ekran, değilse sihirbaz. İlk açılışta zorla; sonra yalnız "ana ekran mı" değişince yeniden
    /// kurulur (sihirbaz kendi içini kendisi değiştirir).
    /// </summary>
    void ChooseScreen(bool force)
    {
        var home = _controller.IsSetupComplete;
        if (!force && _showingHome == home) return;
        _showingHome = home;
        if (_screen.Content is IDisposable old) old.Dispose();
        if (home)
        {
            _screen.Content = new HomeView(_controller);
            _robot.HorizontalAlignment = HorizontalAlignment.Left;
            _robot.Margin = new Thickness(36, 0, 0, 84);
        }
        else
        {
            _toast.HideNow();
            _screen.Content = ShellWindows.CreateSetupView(_controller) ?? new Grid();
            _robot.HorizontalAlignment = HorizontalAlignment.Right;
            _robot.Margin = new Thickness(0, 0, 44, 100);
        }
    }

    async Task RunHotkeyAsync(HotkeyAction action)
    {
        try { await _controller.RunHotkeyAsync(action); }
        catch (Exception e) { AppLogs.Current?.Error("Kısayol işi hata verdi", e); }
    }

    /// <summary>Uykudan uyanınca (arayüz iş parçacığında): bağlantılar hemen yenilenir.</summary>
    void OnSuspending()
    {
        if (!_closed) _controller.SystemSuspending();
    }

    void OnResumed()
    {
        if (!_closed) _controller.SystemResumed();
    }

    void OnFirstLoaded(object sender, RoutedEventArgs e)
    {
        Loaded -= OnFirstLoaded;
        _sideWindows = ShellWindows.AttachSideWindows(this, _controller, error =>
        {
            AppLogs.Current?.Error("Altyazı penceresi kurulamadı", error);
            Dispatcher.BeginInvoke(() =>
            {
                try { MessageBox.Show(this, L.Get("home.overlay.failed"), Title, MessageBoxButton.OK, MessageBoxImage.Warning); }
                catch (Exception shown) { AppLogs.Current?.Error("İleti gösterilemedi", shown); }
            });
        });
    }

    void OnClosed(object? sender, EventArgs e)
    {
        _closed = true;
        _controller.PropertyChanged -= OnControllerChanged;
        if (_screen.Content is IDisposable view) view.Dispose();
        if (!_live) return;
        if (_resume is not null) { _resume.Resumed -= OnResumed; _resume.Suspending -= OnSuspending; }
        foreach (var link in _sideWindows)
        {
            try { link.Dispose(); } catch (Exception) { }
        }
        _hotkeys?.Detach();
        try { _controller.DisposeAsync().AsTask().Wait(TimeSpan.FromSeconds(3)); }
        catch (Exception error) { AppLogs.Current?.Error("Denetleyici kapatılırken hata", error); }
    }
}
