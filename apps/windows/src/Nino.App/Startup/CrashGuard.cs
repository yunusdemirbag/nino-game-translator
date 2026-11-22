// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows;
using System.Windows.Threading;

namespace Nino.App.Startup;

/// <summary>
/// Açılıştan sonraki hatalar (kimlikler-veri.md §3.5). Ekran dökümü kipinde kurulmaz.
/// <list type="bullet">
/// <item>Arayüz iş parçacığındaki yakalanmamış hata: günlüğe yazılır, uygulama kapanmaz; ileti arayüz boşalınca
/// gösterilir. Aynı anda tek ileti; aynı ileti 30 sn içinde yinelenirse yalnız günlüğe.</item>
/// <item>Süreci kapatan arka plan hatası: "(uygulama kapanıyor)" notuyla günlüğe, hemen ileti.</item>
/// <item>Gözlenmemiş görev hatası: yalnız günlüğe, gözlenmiş sayılır.</item>
/// </list>
/// İleti gösterirken çıkan hata da yalnız günlüğe yazılır.
/// </summary>
public static class CrashGuard
{
    static readonly TimeSpan RepeatWindow = TimeSpan.FromSeconds(30);
    static bool _installed;
    static bool _showing;
    static string? _lastText;
    static DateTime _lastShown;

    /// <summary>Süreci kapatan hata anında (ölçümün çalışma işareti yalnız istisna sınıfını yazar).</summary>
    public static Action<Exception?>? Fatal { get; set; }

    /// <summary>Arayüzde yakalanıp yutulan hata (ölçüme yalnız kod olarak).</summary>
    public static Action<Exception>? Handled { get; set; }

    /// <summary>Gözcüleri kurar (bir kez).</summary>
    public static void Install(Application app)
    {
        if (_installed) return;
        _installed = true;
        app.DispatcherUnhandledException += OnDispatcherError;
        AppDomain.CurrentDomain.UnhandledException += OnFatalError;
        TaskScheduler.UnobservedTaskException += OnUnobservedTask;
    }

    static void OnDispatcherError(object sender, DispatcherUnhandledExceptionEventArgs e)
    {
        e.Handled = true;
        StartupErrorLog.Write("Yakalanmamış hata", e.Exception);
        try { Handled?.Invoke(e.Exception); } catch (Exception) { }
        var text = ErrorText.Unhandled(e.Exception);
        try
        {
            e.Dispatcher.BeginInvoke(DispatcherPriority.Background, () => ShowOnce(text));
        }
        catch (Exception shown)
        {
            StartupErrorLog.Write("Hata iletisi gösterilemedi", shown);
        }
    }

    static void ShowOnce(string text)
    {
        var now = DateTime.UtcNow;
        if (_showing) return;
        if (text == _lastText && now - _lastShown < RepeatWindow) return;
        _showing = true;
        _lastText = text;
        _lastShown = now;
        try { MessageBox.Show(text, StartupMessages.Title, MessageBoxButton.OK, MessageBoxImage.Error); }
        catch (Exception e) { StartupErrorLog.Write("Hata iletisi gösterilemedi", e); }
        finally { _showing = false; }
    }

    static void OnFatalError(object sender, UnhandledExceptionEventArgs e)
    {
        var fatal = e.ExceptionObject as Exception;
        try { Fatal?.Invoke(fatal); } catch (Exception) { }
        StartupErrorLog.Write("Yakalanmamış hata (uygulama kapanıyor)", fatal);
        try { MessageBox.Show(ErrorText.Crash(fatal), StartupMessages.Title, MessageBoxButton.OK, MessageBoxImage.Error); }
        catch (Exception shown) { StartupErrorLog.Write("Hata iletisi gösterilemedi", shown); }
    }

    static void OnUnobservedTask(object? sender, UnobservedTaskExceptionEventArgs e)
    {
        StartupErrorLog.Write("Gözlenmemiş görev hatası", e.Exception);
        e.SetObserved();
    }
}

/// <summary>
/// Hata iletileri. Açılış hatası sabit Türkçe/İngilizcedir; açılıştan sonraki hatalar arayüz dilinin kataloğundan
/// (12 dil), katalog okunamazsa yine sabit Türkçe/İngilizce (<see cref="StartupMessages"/>). Sonunda rapor ipucu: <c>hata.log</c>'un tam yolu ve sorunlar sayfası.
/// </summary>
public static class ErrorText
{
    /// <summary>Açılışta beklenmeyen hata: sabit Türkçe/İngilizce (katalog yüklenemese de gösterilsin).</summary>
    public static string Startup(Exception error) =>
        StartupMessages.StartupError(error, StartupErrorLog.DisplayPath, StartupMessages.Turkish);

    /// <summary>Arayüzde yakalanmamış hata.</summary>
    public static string Unhandled(Exception error) =>
        Compose("app.error.startup", error, () => StartupMessages.UnhandledError(error, StartupErrorLog.DisplayPath, StartupMessages.Turkish));

    /// <summary>Süreci kapatan hata.</summary>
    public static string Crash(Exception? error) =>
        Compose("app.error.crash", error, () => StartupMessages.Crash(error, StartupErrorLog.DisplayPath, StartupMessages.Turkish));

    static string Compose(string headKey, Exception? error, Func<string> fallback)
    {
        try
        {
            var nl = Environment.NewLine;
            var detail = error is null ? "" : $"{error.GetType().Name}: {error.Message}";
            return Strings.L.Get(headKey) + nl + detail + nl + nl
                + Strings.L.Format("app.error.reportHint", StartupErrorLog.DisplayPath) + nl + StartupMessages.IssuesUrl;
        }
        catch (Exception)
        {
            return fallback();
        }
    }
}
