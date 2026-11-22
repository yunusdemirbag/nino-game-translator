// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Collections.Specialized;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Nino.App.Strings;
using Nino.Core.Support;

namespace Nino.App.Views;

/// <summary>
/// Fotoğraf hazırlama (sağlık/bildirim tarifi §7.4): dosyadan ya da panodan açma (EXIF yönü, saydamlık beyaza,
/// 24 bit), JPEG'e sığdırma (kenar × kalite denemeleri). Açma arayüz iş parçacığında, kodlama arka planda.
/// </summary>
internal static class PhotoTools
{
    /// <summary>Dosya seçicinin süzgeci.</summary>
    public static string Filter => L.Get("common.photo.filterName") + "|" + PhotoFit.FilterPattern;

    /// <summary>Dosyadan ilk kare; açılamazsa null.</summary>
    public static BitmapSource? FromFile(string path)
    {
        try
        {
            using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
            var decoder = BitmapDecoder.Create(stream, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad);
            if (decoder.Frames.Count == 0) return null;
            var frame = decoder.Frames[0];
            return Prepare(Orient(frame, OrientationOf(frame)));
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or NotSupportedException
            or FileFormatException or ArgumentException or InvalidOperationException or System.Runtime.InteropServices.COMException
            or OverflowException)
        {
            return null;
        }
    }

    static int OrientationOf(BitmapFrame frame)
    {
        try
        {
            if (frame.Metadata is BitmapMetadata meta && meta.GetQuery("System.Photo.Orientation") is ushort o) return o;
        }
        catch (Exception) { }
        return 1;
    }

    static BitmapSource Orient(BitmapSource source, int orientation)
    {
        var angle = orientation switch
        {
            3 => 180,
            6 => 90,
            8 => 270,
            _ => 0,
        };
        return angle == 0 ? source : new TransformedBitmap(source, new RotateTransform(angle));
    }

    /// <summary>Saydamlık beyaz zemine çizilir, 24 bit renge çevrilir, dondurulur.</summary>
    static BitmapSource Prepare(BitmapSource source)
    {
        var w = source.PixelWidth;
        var h = source.PixelHeight;
        var visual = new DrawingVisual();
        using (var dc = visual.RenderOpen())
        {
            dc.DrawRectangle(Brushes.White, null, new Rect(0, 0, w, h));
            dc.DrawImage(source, new Rect(0, 0, w, h));
        }
        var target = new RenderTargetBitmap(w, h, 96, 96, PixelFormats.Pbgra32);
        target.Render(visual);
        var converted = new FormatConvertedBitmap(target, PixelFormats.Bgr24, null, 0);
        var result = new WriteableBitmap(converted);
        result.Freeze();
        return result;
    }

    /// <summary>Panodaki görüntüler: dosya listesi varsa uygun dosyalar, yoksa PNG ya da panonun görüntüsü.</summary>
    public static (IReadOnlyList<string> Files, BitmapSource? Image) FromClipboard()
    {
        try
        {
            if (Clipboard.ContainsFileDropList())
            {
                var list = Clipboard.GetFileDropList();
                return (list.Cast<string>().Where(PhotoFit.IsImageFile).ToList(), null);
            }
            if (Clipboard.GetData("PNG") is MemoryStream png)
            {
                var decoder = BitmapDecoder.Create(png, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad);
                if (decoder.Frames.Count > 0) return ([], Prepare(decoder.Frames[0]));
            }
            if (Clipboard.ContainsImage() && Clipboard.GetImage() is { } image) return ([], Prepare(image));
        }
        catch (Exception) { }
        return ([], null);
    }

    /// <summary>Panoda fotoğraf olarak eklenecek bir şey var mı.</summary>
    public static bool ClipboardHasPhoto()
    {
        try { return Clipboard.ContainsFileDropList() || Clipboard.ContainsImage() || Clipboard.ContainsData("PNG"); }
        catch (Exception) { return false; }
    }

    /// <summary>Panoda metin var mı.</summary>
    public static bool ClipboardHasText()
    {
        try { return Clipboard.ContainsText(); }
        catch (Exception) { return false; }
    }

    /// <summary>Sınırın altına sığan ilk JPEG (arka planda çağrılabilir; kaynak dondurulmuş olmalı).</summary>
    public static byte[]? ToJpeg(BitmapSource image, int limitBytes) => PhotoFit.Fit(new Encoder(image), limitBytes);

    /// <summary>JPEG'den küçük resim (en çok verilen genişlikte çözülür).</summary>
    public static ImageSource? Thumbnail(byte[] jpeg, int decodeWidth)
    {
        try
        {
            var image = new BitmapImage();
            image.BeginInit();
            image.StreamSource = new MemoryStream(jpeg);
            image.DecodePixelWidth = decodeWidth;
            image.CacheOption = BitmapCacheOption.OnLoad;
            image.EndInit();
            image.Freeze();
            return image;
        }
        catch (Exception) { return null; }
    }

    sealed class Encoder(BitmapSource image) : IJpegEncoder
    {
        public int Width => image.PixelWidth;

        public int Height => image.PixelHeight;

        public byte[]? Encode(int width, int height, int quality)
        {
            try
            {
                BitmapSource scaled = width == image.PixelWidth && height == image.PixelHeight
                    ? image
                    : new TransformedBitmap(image, new ScaleTransform((double)width / image.PixelWidth, (double)height / image.PixelHeight));
                var encoder = new JpegBitmapEncoder { QualityLevel = Math.Clamp(quality, 1, 100) };
                encoder.Frames.Add(BitmapFrame.Create(scaled));
                using var ms = new MemoryStream();
                encoder.Save(ms);
                return ms.ToArray();
            }
            catch (Exception) { return null; }
        }
    }
}

/// <summary>
/// En çok 3 fotoğraflık ek listesi (sorun bildirme ve Nino'ya Sor): dosya seçici, sürükle-bırak, Ctrl+V. Ekleme sırayla;
/// biri açılamazsa en sonda tek hata. Değişince <see cref="Changed"/>.
/// </summary>
internal sealed class PhotoAttachments(int limitBytes)
{
    readonly List<byte[]> _photos = [];
    int _adding;

    public IReadOnlyList<byte[]> Photos => _photos;

    public bool IsFull => _photos.Count >= SupportLimits.Images;

    public bool IsAdding => _adding > 0;

    /// <summary>Gönderiliyor gibi bir nedenle ekleme kapalı mı (pencere söyler).</summary>
    public Func<bool> Blocked { get; set; } = () => false;

    public event Action? Changed;

    /// <summary>Hata (null: gizle).</summary>
    public event Action<string?>? Error;

    public void Remove(byte[] photo)
    {
        _photos.Remove(photo);
        Changed?.Invoke();
    }

    public void Clear()
    {
        _photos.Clear();
        Changed?.Invoke();
    }

    /// <summary>Dosya seçici (çoklu).</summary>
    public void Pick(Window owner, string title)
    {
        if (IsFull || Blocked()) return;
        var dialog = new Microsoft.Win32.OpenFileDialog { Title = title, Filter = PhotoTools.Filter, Multiselect = true };
        if (dialog.ShowDialog(owner) == true) _ = AddAsync(dialog.FileNames, null);
    }

    /// <summary>Pencereye sürükle-bırak (önizleme aşamasında; metin kutuları dosyayı kendileri almasın).</summary>
    public void Attach(Window window)
    {
        window.AllowDrop = true;
        window.PreviewDragEnter += OnDragOver;
        window.PreviewDragOver += OnDragOver;
        window.PreviewDrop += (_, e) =>
        {
            e.Handled = true;
            if (IsFull || Blocked() || !e.Data.GetDataPresent(DataFormats.FileDrop)) return;
            if (e.Data.GetData(DataFormats.FileDrop) is string[] files)
                _ = AddAsync(files.Where(PhotoFit.IsImageFile).ToArray(), null);
        };
    }

    void OnDragOver(object sender, DragEventArgs e)
    {
        e.Effects = !IsFull && !Blocked() && e.Data.GetDataPresent(DataFormats.FileDrop) ? DragDropEffects.Copy : DragDropEffects.None;
        e.Handled = true;
    }

    /// <summary>Ctrl+V: panoda görüntü ya da dosya varsa ve (odak metin kutusunda değilse ya da panoda metin yoksa) eklenir.</summary>
    public bool TryPaste(KeyEventArgs e)
    {
        if (e.Key != Key.V || Keyboard.Modifiers != ModifierKeys.Control) return false;
        if (!PhotoTools.ClipboardHasPhoto()) return false;
        var inTextBox = Keyboard.FocusedElement is TextBox;
        if (inTextBox && PhotoTools.ClipboardHasText()) return false;
        e.Handled = true;
        if (IsFull || Blocked()) return true;
        var (files, image) = PhotoTools.FromClipboard();
        if (files.Count > 0) _ = AddAsync(files, null);
        else if (image is not null) _ = AddAsync([], image);
        else Error?.Invoke(L.Get("common.photo.openFailed"));
        return true;
    }

    async Task AddAsync(IReadOnlyList<string> files, BitmapSource? image)
    {
        Error?.Invoke(null);
        _adding++;
        var failed = false;
        try
        {
            var sources = new List<Func<BitmapSource?>>();
            if (image is not null) sources.Add(() => image);
            foreach (var f in files) sources.Add(() => PhotoTools.FromFile(f));
            foreach (var open in sources)
            {
                if (IsFull) break;
                var opened = open();
                if (opened is null)
                {
                    failed = true;
                    continue;
                }
                var jpeg = await Task.Run(() => PhotoTools.ToJpeg(opened, limitBytes));
                if (jpeg is null)
                {
                    failed = true;
                    continue;
                }
                if (IsFull) break;
                _photos.Add(jpeg);
                Changed?.Invoke();
            }
        }
        finally { _adding--; }
        if (failed) Error?.Invoke(L.Get("common.photo.openFailed"));
    }
}
