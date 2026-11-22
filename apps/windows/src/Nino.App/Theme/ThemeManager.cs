// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows;
using System.Windows.Media;
using Microsoft.Win32;
using Nino.Core.Design;
using Nino.Core.Settings;

namespace Nino.App.Theme;

/// <summary>
/// Tasarım belirteçlerini uygulama kaynaklarına koyar ve görünümü (Sistem / Açık / Koyu) uygular.
/// <para>Kaynak adları (hepsine <c>DynamicResource</c> ile bağlanın):</para>
/// <list type="bullet">
/// <item><c>&lt;ad&gt;Color</c> (Color) ve <c>&lt;ad&gt;Brush</c> (dondurulmuş fırça): bütün belirteç renkleri ve sabit renkler.</item>
/// <item><c>space.&lt;ad&gt;</c> (double) ve <c>pad.&lt;ad&gt;</c> (dört yana eşit Thickness).</item>
/// <item><c>radius.&lt;ad&gt;</c> (CornerRadius) ve <c>radiusValue.&lt;ad&gt;</c> (double).</item>
/// <item><c>size.&lt;ad&gt;</c> (double), <c>fontSize.&lt;ad&gt;</c> (double).</item>
/// </list>
/// Tema değişince yalnız renk kaynakları değiştirilir; ölçüler ve yazılar aynı kalır.
/// </summary>
public static class ThemeManager
{
    /// <summary>Temadan bağımsız sabit renkler (tasarım dili §1.2).</summary>
    public static IReadOnlyDictionary<string, Color> FixedColors { get; } = new Dictionary<string, Color>
    {
        ["flagRed"] = Color.FromRgb(0xE3, 0x0A, 0x17),
        ["flagRedDark"] = Color.FromRgb(0xA8, 0x05, 0x14),
        ["ledBlue"] = Color.FromRgb(0x1F, 0x5C, 0xFF),
        ["downloadGreen"] = Color.FromRgb(0x7B, 0xE8, 0x7B),
        ["robotCircle"] = Color.FromArgb(0xF5, 0xFF, 0xFF, 0xFF),
        ["robotCircleBorder"] = Color.FromArgb(0x1F, 0x0B, 0x16, 0x33),
        ["bubble"] = Color.FromArgb(0x8C, 0x00, 0x00, 0x00),
        ["bubbleBorder"] = Color.FromArgb(0x24, 0xFF, 0xFF, 0xFF),
    };

    private static Appearance? _applied;
    private static bool _appliedDark;
    private static bool _listening;
    private static ResourceDictionary? _target;

    /// <summary>Şu an koyu renkler mi kurulu.</summary>
    public static bool IsDark => _appliedDark;

    /// <summary>Uygulanan görünüm (henüz uygulanmadıysa null).</summary>
    public static Appearance? Current => _applied;

    /// <summary>Renkler yeniden kurulunca (arayüz iş parçacığında) çağrılır; argüman: koyu mu.</summary>
    public static event EventHandler<bool>? ThemeChanged;

    /// <summary>
    /// Ölçüleri ve renkleri uygulamanın kaynaklarına koyar. İlk pencereden önce, <c>InitializeComponent</c>'ten sonra
    /// bir kez çağrılır. Windows'un teması değişince "Sistem" görünümünde renkler kendiliğinden yenilenir.
    /// </summary>
    public static void Install(Application app, Appearance appearance = Appearance.System)
    {
        _target = app.Resources;
        AddMetrics(_target, DesignTokens.Default);
        NinoFonts.AddResources(_target);
        Apply(appearance);
        if (!_listening)
        {
            _listening = true;
            SystemEvents.UserPreferenceChanged += OnUserPreferenceChanged;
            app.Exit += (_, _) => SystemEvents.UserPreferenceChanged -= OnUserPreferenceChanged;
        }
    }

    /// <summary>
    /// Görünümü uygular. Aynı görünüm ikinci kez uygulanmaz ("Sistem"de Windows'un teması yeniden okunur). Arka iş
    /// parçacığından çağrılırsa arayüz iş parçacığına aktarılır.
    /// </summary>
    public static void Apply(Appearance appearance)
    {
        var dispatcher = Application.Current?.Dispatcher;
        if (dispatcher is not null && !dispatcher.CheckAccess())
        {
            dispatcher.BeginInvoke(() => Apply(appearance));
            return;
        }
        var dark = appearance switch
        {
            Appearance.Dark => true,
            Appearance.Light => false,
            _ => SystemUsesDarkTheme(),
        };
        if (_applied == appearance && _appliedDark == dark) return;
        _applied = appearance;
        _appliedDark = dark;
        if (_target is not null) AddColors(_target, DesignTokens.Default, dark);
        ThemeChanged?.Invoke(null, dark);
    }

    /// <summary>Windows'un uygulama teması koyu mu: <c>AppsUseLightTheme</c> tamsayı 0 ise koyu; yoksa ya da başka değerse açık.</summary>
    public static bool SystemUsesDarkTheme()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            return key?.GetValue("AppsUseLightTheme") is int value && value == 0;
        }
        catch (Exception e) when (e is System.Security.SecurityException or UnauthorizedAccessException or System.IO.IOException)
        {
            return false;
        }
    }

    private static void OnUserPreferenceChanged(object? sender, UserPreferenceChangedEventArgs e)
    {
        if (e.Category != UserPreferenceCategory.General) return;
        var dispatcher = Application.Current?.Dispatcher;
        if (dispatcher is null) return;
        dispatcher.BeginInvoke(() =>
        {
            // Henüz uygulanmadıysa ya da "Sistem" ise renkler yeniden okunur.
            if (_applied is null or Appearance.System)
            {
                var dark = SystemUsesDarkTheme();
                if (_applied is null || dark != _appliedDark)
                {
                    _applied = Appearance.System;
                    _appliedDark = dark;
                    if (_target is not null) AddColors(_target, DesignTokens.Default, dark);
                    ThemeChanged?.Invoke(null, dark);
                }
            }
        });
    }

    /// <summary>Belirteç rengini o anki temada verir (kod içinden çizim yapanlar için).</summary>
    public static Color ColorOf(string name) => ToColor(DesignTokens.Default.Color(name).Pick(_appliedDark));

    /// <summary>"#RRGGBB" → WPF rengi.</summary>
    public static Color ToColor(string hex)
    {
        var (r, g, b) = ColorMath.ParseBytes(hex);
        return Color.FromRgb(r, g, b);
    }

    private static SolidColorBrush Frozen(Color color)
    {
        var brush = new SolidColorBrush(color);
        brush.Freeze();
        return brush;
    }

    private static void AddColors(ResourceDictionary into, DesignTokens tokens, bool dark)
    {
        foreach (var (name, pair) in tokens.Colors)
        {
            var color = ToColor(pair.Pick(dark));
            into[DesignTokens.ColorKey(name)] = color;
            into[DesignTokens.BrushKey(name)] = Frozen(color);
        }
        foreach (var (name, color) in FixedColors)
        {
            into[DesignTokens.ColorKey(name)] = color;
            into[DesignTokens.BrushKey(name)] = Frozen(color);
        }
    }

    private static void AddMetrics(ResourceDictionary into, DesignTokens tokens)
    {
        foreach (var (name, value) in tokens.Space)
        {
            into["space." + name] = value;
            into["pad." + name] = new Thickness(value);
        }
        foreach (var (name, value) in tokens.Radius)
        {
            into["radius." + name] = new CornerRadius(value);
            into["radiusValue." + name] = value;
        }
        foreach (var (name, value) in tokens.Size) into["size." + name] = value;
        foreach (var (name, font) in tokens.Fonts) into["fontSize." + name] = font.Size;
    }
}
