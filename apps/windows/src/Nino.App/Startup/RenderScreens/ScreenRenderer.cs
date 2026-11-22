// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Nino.App.Theme;
using Nino.Core.Settings;
using Nino.Shell;

namespace Nino.App.Startup;

/// <summary>
/// <c>Nino.exe --render-screens &lt;klasör&gt;</c> (ana-ekran §11): pencere göstermeden bütün ekranları önce açık,
/// sonra koyu temada PNG'ye döker ve kapanır. Görüntüler 2 kat çözünürlükte (192 dpi); zemine pencere zemini konur,
/// ana yazı rengi pencereden kalıtılır. Her ekran ekran dışında (−10000, −10000) çerçevesiz, görev çubuğunda görünmeyen
/// bir pencerede gösterilip 600 ms beklenir (yüklenirken başlayan aramalar yansısın). Bir ekranın hatası diğerlerini
/// durdurmaz; hatalar klasördeki <c>errors.txt</c>'ye eklenir. Eskisiyle ekran ekran karşılaştırma aracıdır.
/// </summary>
public static class ScreenRenderer
{
    /// <summary>Çizim çözünürlüğü.</summary>
    public const double Dpi = 192;

    static readonly TimeSpan Settle = TimeSpan.FromMilliseconds(600);

    /// <summary>Bütün ekranları döker; çıkış kodu 0.</summary>
    public static int Run(App app, string folder)
    {
        app.ShutdownMode = ShutdownMode.OnExplicitShutdown; // pencereler açılıp kapanırken uygulama kapanmasın
        app.Dispatcher.BeginInvoke(async () =>
        {
            try { await RenderAllAsync(app.Dispatcher, folder); }
            catch (Exception e) { RenderErrors.Append(folder, "Ekran dökümü durdu: " + e); }
            app.Shutdown(0);
        });
        return app.Run();
    }

    static async Task RenderAllAsync(Dispatcher dispatcher, string folder)
    {
        Directory.CreateDirectory(folder);
        Action<Action> post = a => dispatcher.BeginInvoke(a);
        foreach (var (appearance, suffix) in new[] { (Appearance.Light, "acik"), (Appearance.Dark, "koyu") })
        {
            ThemeManager.Apply(appearance);
            foreach (var entry in ScreenCatalog.All())
            {
                var file = $"{entry.FileStem}-{suffix}.png";
                try { await RenderAsync(entry, Path.Combine(folder, file), post); }
                catch (Exception e) { RenderErrors.Append(folder, $"{file}: {e}"); }
            }
        }
    }

    static async Task RenderAsync(ScreenEntry entry, string path, Action<Action> post)
    {
        var controller = RenderFakes.Create(entry.SetupDone, post);
        Window? window = null;
        try
        {
            var made = entry.Create(controller) ?? throw new InvalidOperationException("Bu ekran bu derlemede yok.");
            window = made as Window ?? new Window { Content = made };
            if (made is not Window) window.SetResourceReference(FrameworkElement.StyleProperty, "Window.Nino");
            window.WindowStyle = WindowStyle.None;
            window.ResizeMode = ResizeMode.NoResize;
            window.ShowInTaskbar = false;
            window.ShowActivated = false;
            window.WindowStartupLocation = WindowStartupLocation.Manual;
            window.Left = -10000;
            window.Top = -10000;
            window.MinWidth = 0;
            window.MinHeight = 0;
            window.Width = entry.Width;
            window.Height = entry.Height;
            window.SizeToContent = SizeToContent.Manual;
            RightToLeft.ApplyTo(window);
            window.Show();
            await Task.Delay(Settle);
            Save(window, entry.Width, entry.Height, path);
        }
        finally
        {
            try { window?.Close(); } catch (Exception) { }
            try { await controller.DisposeAsync(); } catch (Exception) { }
        }
    }

    static void Save(Window window, double width, double height, string path)
    {
        window.UpdateLayout();
        var content = window.Content as Visual ?? throw new InvalidOperationException("Pencerenin içeriği yok.");
        var visual = new DrawingVisual();
        using (var dc = visual.RenderOpen())
        {
            var rect = new Rect(0, 0, width, height);
            dc.DrawRectangle(window.Background ?? Brushes.White, null, rect);
            // Görünür sınır kutusu değil yerleşim dikdörtgeni çizilir (kenar boşluğu, gölge ve bulanıklık kaydırmasın).
            var brush = new VisualBrush(content)
            {
                Stretch = Stretch.None,
                ViewboxUnits = BrushMappingMode.Absolute,
                Viewbox = rect,
                ViewportUnits = BrushMappingMode.Absolute,
                Viewport = rect,
            };
            dc.DrawRectangle(brush, null, rect);
        }
        var scale = Dpi / 96;
        var bitmap = new RenderTargetBitmap((int)Math.Round(width * scale), (int)Math.Round(height * scale), Dpi, Dpi,
            PixelFormats.Pbgra32);
        bitmap.Render(visual);
        var png = new PngBitmapEncoder();
        png.Frames.Add(BitmapFrame.Create(bitmap));
        using var stream = File.Create(path);
        png.Save(stream);
    }
}
