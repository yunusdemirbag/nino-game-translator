// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using Nino.App.Controls;
using Nino.App.Strings;
using Nino.Core.Design;
using Nino.RemotePlay;
using Nino.Shell;
using Nino.Shell.Panels;
using Nino.Shell.Platform;

namespace Nino.App.Views;

/// <summary>Bulunan yakalama aygıtı.</summary>
/// <param name="Id">Aygıt kimliği (şifreli depoda tercih olarak saklanır).</param>
/// <param name="Name">Gösterilen ad.</param>
public sealed record CardDevice(string Id, string Name);

/// <summary>
/// HDMI yakalama kartı denetimi (yan pencereler tarifi §8.1): siyah önizleme çerçevesi (canlı görüntü, yer tutucu, durum hapı),
/// ayrıntı satırı, Kamera Ayarları düğmesi ve aygıt listesi. Görsel ağaca girince başlar, çıkınca durur; çeviri
/// sürerken kart bırakılır. Ayarlar › Bağlantı'da 170, rehberin son sayfasında 220 yüksekliğinde.
/// </summary>
public sealed class CardPreview : StackPanel
{
    /// <summary>Bulunan yakalama aygıtları (Windows hizmetleri bağlar; bağlanmazsa aygıt sırası hiç görünmez).</summary>
    public static Func<IReadOnlyList<CardDevice>>? Devices { get; set; }

    /// <summary>Aygıt listesi değişince çağrılacak olay kancası (Windows hizmetleri tetikler).</summary>
    public static event Action? DevicesChanged;

    /// <summary>Aygıt listesi değişti (Windows hizmetleri çağırır).</summary>
    public static void RaiseDevicesChanged() => DevicesChanged?.Invoke();

    readonly NinoController _c;
    readonly Image _image = new() { Stretch = Stretch.Uniform };
    readonly StackPanel _placeholder = new() { VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center };
    readonly TextBlock _placeholderIcon;
    readonly TextBlock _placeholderText;
    readonly Ellipse _dot = new() { Width = 7, Height = 7, Margin = new(0, 0, 6, 0), VerticalAlignment = VerticalAlignment.Center };
    readonly TextBlock _pillText = new()
    {
        FontSize = 11,
        FontWeight = FontWeights.SemiBold,
        Foreground = Brushes.White,
        VerticalAlignment = VerticalAlignment.Center,
        TextWrapping = TextWrapping.NoWrap,
    };
    readonly StackPanel _detail = new() { Orientation = Orientation.Horizontal, Margin = new(0, 12, 0, 0) };
    readonly TextBlock _detailIcon;
    readonly TextBlock _detailText;
    readonly Button _cameraSettings;
    readonly StackPanel _deviceRow;
    readonly ComboBox _devices = Ui.Combo(260);
    readonly LoadGuard _guard = new();
    ICaptureCardSource? _source;
    WriteableBitmap? _bitmap;
    VideoFrame? _pending;
    bool _framePosted;
    CardCaptureState _state = CardCaptureState.Stopped;
    string? _deviceName;
    bool _inTree;

    public CardPreview(NinoController controller, double height)
    {
        _c = controller;
        var frame = new Grid { Height = height, FlowDirection = FlowDirection.LeftToRight, Background = Brushes.Black };
        frame.SizeChanged += (_, e) => frame.Clip = new RectangleGeometry(new Rect(e.NewSize), 14, 14);
        RenderOptions.SetBitmapScalingMode(_image, BitmapScalingMode.HighQuality);
        frame.Children.Add(_image);

        var soft = Ui.Frozen(Color.FromArgb(0xD9, 0xFF, 0xFF, 0xFF));
        _placeholderIcon = new TextBlock { FontSize = 30, Foreground = soft, HorizontalAlignment = HorizontalAlignment.Center }.Styled("Text.Icon");
        _placeholderText = new TextBlock
        {
            Foreground = soft,
            FontWeight = FontWeights.SemiBold,
            TextAlignment = TextAlignment.Center,
            TextWrapping = TextWrapping.Wrap,
            Margin = new(16, 8, 16, 0),
        };
        _placeholder.Children.Add(_placeholderIcon);
        _placeholder.Children.Add(_placeholderText);
        frame.Children.Add(_placeholder);

        var pill = new Border
        {
            Background = Ui.Frozen(Color.FromArgb(0x80, 0, 0, 0)),
            CornerRadius = new(12),
            Height = 24,
            Padding = new(10, 0, 10, 0),
            Margin = new(10),
            HorizontalAlignment = HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Top,
            Child = Ui.Row(_dot, _pillText),
        };
        frame.Children.Add(pill);
        Children.Add(frame);

        _detailIcon = Ui.Icon("", 16).At(0, 0, 8, 0);
        _detailText = Ui.Hint("");
        _detailText.VerticalAlignment = VerticalAlignment.Center;
        _detailText.MaxWidth = 640;
        _detail.Children.Add(_detailIcon);
        _detail.Children.Add(_detailText);
        Children.Add(_detail);

        _cameraSettings = Ui.Button(L.Get("cardGuide.preview.openCameraSettings"), () => Ui.Open("ms-settings:privacy-webcam"));
        _cameraSettings.Margin = new(0, 12, 0, 0);
        Children.Add(_cameraSettings);

        _devices.SelectionChanged += (_, _) =>
        {
            if (_guard.Busy) return;
            _c.SetPreferredCard(_devices.SelectedTag() as string);
            if (_source is not null)
            {
                StopSource();
                _bitmap = null;
                _image.Source = null;
                StartSource();
            }
        };
        _deviceRow = Ui.Labeled(L.Get("cardGuide.preview.deviceLabel"), _devices, 12);
        _deviceRow.Margin = new(0, 12, 0, 0);
        Children.Add(_deviceRow);

        Loaded += (_, _) =>
        {
            if (_inTree) return;
            _inTree = true;
            _c.PropertyChanged += OnControllerChanged;
            DevicesChanged += OnDevicesChanged;
            FillDevices();
            StartSource();
            Render();
        };
        Unloaded += (_, _) => Dispatcher.BeginInvoke(() =>
        {
            if (!IsLoaded) Leave();
        });
    }

    /// <summary>Denetimi bulunduğu panelden çıkarır ve kartı bırakır.</summary>
    public void Detach()
    {
        RemoveFromParent();
        Leave();
    }

    /// <summary>Denetimi panelinden çıkarır; hemen başka yere konursa kart bırakılmaz.</summary>
    public void RemoveFromParent()
    {
        if (Parent is Panel p) p.Children.Remove(this);
        else if (Parent is Decorator d) d.Child = null;
        else if (Parent is ContentControl cc) cc.Content = null;
    }

    void Leave()
    {
        if (!_inTree) return;
        _inTree = false;
        _c.PropertyChanged -= OnControllerChanged;
        DevicesChanged -= OnDevicesChanged;
        StopSource();
    }

    bool Busy => _c.IsTranslating || _c.IsStarting;

    void OnControllerChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is not (nameof(NinoController.IsTranslating) or nameof(NinoController.IsStarting)
            or nameof(NinoController.CardState))) return;
        if (Busy) StopSource();
        else if (_source is null && _inTree) StartSource();
        Render();
    }

    void OnDevicesChanged() => Dispatcher.BeginInvoke(() =>
    {
        FillDevices();
        if (_source is not null)
        {
            _image.Source = null;
            _bitmap = null;
            StopSource();
            StartSource();
        }
        Render();
    });

    void FillDevices() => _guard.Run(() =>
    {
        IReadOnlyList<CardDevice> list;
        try { list = Devices?.Invoke() ?? []; }
        catch (Exception) { list = []; }
        _devices.Items.Clear();
        _devices.Items.Add(Ui.Item("", L.Get("cardGuide.preview.automatic")));
        foreach (var d in list) _devices.Items.Add(Ui.Item(d.Id, d.Name));
        var preferred = _c.PreferredCardId;
        _devices.SelectTag(preferred is not null && list.Any(d => d.Id == preferred) ? preferred : "");
        _deviceRow.Visibility = list.Count > 1 ? Visibility.Visible : Visibility.Collapsed;
    });

    void StartSource()
    {
        if (_source is not null || Busy || !_inTree) return;
        _source = _c.CreateCardPreview();
        if (_source is null)
        {
            _state = CardCaptureState.NoCard;
            return;
        }
        _source.CardStatusChanged += OnCardStatus;
        _source.FrameArrived += OnFrame;
        try { _source.Start(); }
        catch (Exception)
        {
            StopSource();
            _state = CardCaptureState.NoCard;
        }
    }

    void StopSource()
    {
        var source = _source;
        _source = null;
        if (source is null) return;
        source.CardStatusChanged -= OnCardStatus;
        source.FrameArrived -= OnFrame;
        try
        {
            source.Stop();
            source.Dispose();
        }
        catch (Exception) { }
        _pending = null;
        _state = CardCaptureState.Stopped;
    }

    void OnCardStatus(CardStatus status) => Dispatcher.BeginInvoke(() =>
    {
        _state = status.State;
        _deviceName = status.DeviceName;
        if (_state is not (CardCaptureState.Capturing or CardCaptureState.BlackPicture)) _image.Source = null;
        Render();
    });

    void OnFrame(VideoFrame frame)
    {
        // Kaynak arabelleği yeniden kullanabilir: kare olay içinde kopyalanır.
        var copy = new VideoFrame(frame.Bgra.AsSpan(0, Math.Min(frame.Bgra.Length, frame.Stride * frame.Height)).ToArray(),
            frame.Width, frame.Height, frame.Stride);
        Volatile.Write(ref _pending, copy);
        if (Interlocked.Exchange(ref _framePosted, true)) return;
        Dispatcher.BeginInvoke(() =>
        {
            Volatile.Write(ref _framePosted, false);
            if (Interlocked.Exchange(ref _pending, null) is not { } f || _source is null) return;
            try
            {
                if (_bitmap is null || _bitmap.PixelWidth != f.Width || _bitmap.PixelHeight != f.Height)
                {
                    _bitmap = new WriteableBitmap(f.Width, f.Height, 96, 96, PixelFormats.Bgra32, null);
                    _image.Source = _bitmap;
                }
                _bitmap.WritePixels(new Int32Rect(0, 0, f.Width, f.Height), f.Bgra, f.Stride, 0);
                if (_image.Source != _bitmap) _image.Source = _bitmap;
            }
            catch (Exception) { }
        });
    }

    void Render()
    {
        if (Busy)
        {
            _image.Source = null;
            _placeholder.Visibility = Visibility.Visible;
            _placeholderIcon.Text = Glyphs.Connect;
            _placeholderText.Text = L.Get("cardGuide.preview.offWhileTranslating");
            SetDot(StatusTone.Idle);
            _pillText.Text = _c.CardState.DeviceName is { Length: > 0 } name ? name : L.Get("status.card.defaultName");
            _detail.Visibility = Visibility.Collapsed;
            _cameraSettings.Visibility = Visibility.Collapsed;
            _deviceRow.IsEnabled = false;
            return;
        }
        _deviceRow.IsEnabled = true;
        var look = CardPreviewLook.For(_state);
        SetDot(look.Tone);
        _pillText.Text = look.PillKey is { } key ? L.Get(key) : _deviceName ?? L.Get("status.card.defaultName");
        _placeholder.Visibility = look.PlaceholderVisible ? Visibility.Visible : Visibility.Collapsed;
        _placeholderIcon.Text = look.PlaceholderLock ? Glyphs.Lock : Glyphs.Connect;
        _placeholderText.Text = L.Get(look.PlaceholderKey);
        if (look.DetailKey is { } detail)
        {
            _detail.Visibility = Visibility.Visible;
            _detailIcon.Text = look.DetailOk ? Glyphs.CheckMark : Glyphs.Warning;
            var brush = look.DetailOk ? "successBrush" : "warningBrush";
            _detailIcon.Res(TextBlock.ForegroundProperty, brush);
            _detailText.Res(TextBlock.ForegroundProperty, brush);
            _detailText.Text = L.Get(detail);
        }
        else _detail.Visibility = Visibility.Collapsed;
        _cameraSettings.Visibility = look.ShowCameraSettings ? Visibility.Visible : Visibility.Collapsed;
    }

    void SetDot(StatusTone tone) => _dot.Res(Shape.FillProperty, StatusToneColors.DotColor(tone) + "Brush");
}
