// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using System.Windows.Threading;
using Nino.App.Controls;
using Nino.App.Strings;
using Nino.Core.Support;
using Nino.Shell;

namespace Nino.App.Views;

/// <summary>
/// Hata bildirimi formu (Mac'teki gibi tek ekran): yazı alanı, resim ya da .txt için bırakma alanı (tıklayınca dosya
/// seçici; sürükle-bırak ve Ctrl+V), Gönder. Nino'nun tespitleri, cihaz özeti ve uygulama günlükleri gövdeye
/// kendiliğinden eklenir (ekranda gösterilmez). Taslak denetleyicide (<see cref="NinoController.ReportDraft"/>) durur.
/// </summary>
public sealed class ReportProblemForm : ContentControl
{
    static readonly Size Tile = new(96, 72);
    static readonly TimeSpan ThanksFor = TimeSpan.FromSeconds(1.6);

    readonly NinoController _c;
    readonly ReportDraft _draft;
    readonly Action _onDone;
    readonly TextBox _text;
    readonly Grid _editor;
    readonly ContentControl _zone = new() { Focusable = false };
    readonly TextBlock _attachError = Ui.Error().Shown(false);
    readonly TextBlock _sendError = Ui.Error().Shown(false);
    readonly ContentControl _footer = new() { Focusable = false, VerticalAlignment = VerticalAlignment.Center };
    readonly Button _send;
    readonly StackPanel _form;
    bool _targeted;
    bool _detached;
    DispatcherTimer? _thanks;

    /// <param name="controller">Denetleyici.</param>
    /// <param name="onDone">Gönderildikten 1,6 sn sonra çağrılır (pencere kapanır).</param>
    public ReportProblemForm(NinoController controller, Action onDone)
    {
        _c = controller;
        _draft = controller.ReportDraft;
        _onDone = onDone;
        Focusable = false;

        _text = new TextBox
        {
            AcceptsReturn = true,
            TextWrapping = TextWrapping.Wrap,
            MinHeight = 160,
            MaxLength = SupportLimits.Text,
            Padding = new(12, 10, 12, 10),
            VerticalContentAlignment = VerticalAlignment.Top,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            Text = _draft.Description,
        };
        _text.TextChanged += (_, _) => _draft.Description = _text.Text;
        _editor = Ui.WithPlaceholder(_text, L.Get("report.placeholder"), top: true);

        _send = Ui.Primary(L.Get("report.send"), () => _ = SendAsync());
        _send.MinWidth = 96;
        _send.MinHeight = 44;
        _send.VerticalAlignment = VerticalAlignment.Center;

        var bottom = new DockPanel { LastChildFill = true };
        DockPanel.SetDock(_send, Dock.Right);
        bottom.Children.Add(_send);
        _footer.Margin = new(0, 0, 12, 0);
        bottom.Children.Add(_footer);

        _form = new StackPanel();
        _form.Children.Add(_editor);
        _form.Children.Add(_zone.At(0, 16, 0, 0));
        _form.Children.Add(_attachError.At(0, 12, 0, 0));
        _form.Children.Add(_sendError.At(0, 12, 0, 0));
        _form.Children.Add(bottom.At(0, 16, 0, 0));

        _draft.Changed += Render;
        Loaded += (_, _) =>
        {
            if (_draft.Phase == ReportPhase.Sent) _draft.Reset();
            _text.Focus();
        };
        Render();
    }

    /// <summary>Penceresi kapandı: olaylar bırakılır; teşekkür sürüyorsa form sıfırlanır.</summary>
    public void Detach()
    {
        if (_detached) return;
        _detached = true;
        _draft.Changed -= Render;
        _thanks?.Stop();
        if (_draft.Phase == ReportPhase.Sent) _draft.Reset();
    }

    // ---- Çizim ----

    void Render()
    {
        if (_detached) return;
        if (_draft.Phase == ReportPhase.Sent)
        {
            Content = Thanks();
            return;
        }
        if (!ReferenceEquals(Content, _form)) Content = _form;
        if (_text.Text != _draft.Description) _text.Text = _draft.Description;
        var sending = _draft.Phase == ReportPhase.Sending;
        _text.IsReadOnly = sending;
        _editor.Opacity = sending ? 0.6 : 1;
        _zone.Content = _draft.Attachments.Count == 0 ? EmptyZone() : FilledZone();
        _zone.IsEnabled = !sending;
        _attachError.Text = _draft.AttachError switch
        {
            ReportAttachmentFailure.Limit => L.Get("report.file.limit"),
            ReportAttachmentFailure.Unreadable => L.Get("report.file.unreadable"),
            _ => "",
        };
        _attachError.Shown(_draft.AttachError is not null);
        _sendError.Text = ErrorText(_draft.Error);
        _sendError.Shown(_draft.Error is not null);
        if (sending)
        {
            var label = Ui.Secondary(L.Get("report.sending"));
            label.VerticalAlignment = VerticalAlignment.Center;
            _footer.Content = Ui.Row(AboutContent.Spinner().At(0, 0, 8, 0), label);
        }
        else
        {
            _footer.Content = Ui.Caption(L.Get("report.footer")).Fg("textSecondaryBrush");
        }
        _send.IsEnabled = _draft.CanSend;
    }

    /// <summary>Gönderim hatasının metni.</summary>
    public static string ErrorText(ReportStatus? status) => status switch
    {
        null or ReportStatus.Sent => "",
        ReportStatus.Limited => L.Get("report.error.dailyLimit"),
        ReportStatus.TooLarge => L.Get("report.error.tooLarge"),
        ReportStatus.Rejected => L.Get("report.error.server"),
        _ => L.Get("report.error.offline"),
    };

    UIElement EmptyZone()
    {
        var icon = Ui.Icon(_draft.Preparing > 0 ? "" : "", 24, _targeted ? "accentTextBrush" : "textSecondaryBrush");
        icon.HorizontalAlignment = HorizontalAlignment.Center;
        var title = Ui.Hint(L.Get("report.drop"));
        title.FontWeight = FontWeights.SemiBold;
        title.TextAlignment = TextAlignment.Center;
        title.Res(TextBlock.ForegroundProperty, "textPrimaryBrush");
        var hint = Ui.Caption(L.Get("report.dropHint")).Fg("textSecondaryBrush");
        hint.TextAlignment = TextAlignment.Center;
        var inside = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new(16) };
        inside.Children.Add(icon);
        inside.Children.Add(title.At(0, 8, 0, 0));
        inside.Children.Add(hint.At(0, 4, 0, 0));
        var b = ZoneButton(inside, 14);
        b.MinHeight = 116;
        AutomationNames.Set(b, L.Get("report.drop"));
        return b;
    }

    UIElement FilledZone()
    {
        var tiles = new WrapPanel();
        foreach (var item in _draft.Attachments)
        {
            var cell = new StackPanel { Width = Tile.Width, Margin = new(0, 0, 12, 8) };
            cell.Children.Add(item.Jpeg is { } jpeg ? PhotoTile(jpeg, item.Id) : TextTile(item.Id));
            var name = new TextBlock
            {
                Text = item.Name,
                FontSize = 10,
                TextTrimming = TextTrimming.CharacterEllipsis,
                TextAlignment = TextAlignment.Center,
                Margin = new(0, 4, 0, 0),
                ToolTip = item.Name,
            };
            name.Res(TextBlock.ForegroundProperty, "textSecondaryBrush");
            cell.Children.Add(name);
            tiles.Children.Add(cell);
        }
        if (_draft.CanAdd)
        {
            var plus = Ui.Icon(_draft.Preparing > 0 ? "" : "", 20, _targeted ? "accentTextBrush" : "textSecondaryBrush");
            plus.HorizontalAlignment = HorizontalAlignment.Center;
            plus.VerticalAlignment = VerticalAlignment.Center;
            var face = new Border { Width = Tile.Width, Height = Tile.Height, CornerRadius = new(12), Child = plus };
            face.SetResourceReference(Border.BackgroundProperty, "surface2Brush");
            var add = new Button { Content = face, Padding = new(0), MinHeight = 0, ToolTip = L.Get("report.drop"), Cursor = Cursors.Hand }
                .Styled("Button.Ghost");
            add.Margin = new(0, 0, 12, 8);
            add.VerticalAlignment = VerticalAlignment.Top;
            AutomationNames.Set(add, L.Get("report.drop"));
            add.Click += (_, _) => Choose();
            tiles.Children.Add(add);
        }
        var grid = new Grid();
        grid.Children.Add(DashedFrame(14));
        grid.Children.Add(new Border { Padding = new(12, 12, 0, 4), Child = tiles });
        return grid;
    }

    Button ZoneButton(UIElement inside, double radius)
    {
        var grid = new Grid();
        if (_targeted)
        {
            var soft = new Border { CornerRadius = new(radius) };
            soft.Res(Border.BackgroundProperty, "accentSoftBrush");
            grid.Children.Add(soft);
        }
        grid.Children.Add(DashedFrame(radius));
        grid.Children.Add(inside);
        var b = new Button
        {
            Content = grid,
            Padding = new(0),
            HorizontalContentAlignment = HorizontalAlignment.Stretch,
            VerticalContentAlignment = VerticalAlignment.Stretch,
            Cursor = Cursors.Hand,
        }.Styled("Button.Ghost");
        b.Click += (_, _) => Choose();
        return b;
    }

    /// <summary>Kesikli çerçeve (bırakma hedefindeyken düz, accent, 2 px).</summary>
    Rectangle DashedFrame(double radius)
    {
        var r = new Rectangle
        {
            RadiusX = radius,
            RadiusY = radius,
            StrokeThickness = _targeted ? 2 : 1,
            StrokeDashArray = _targeted ? null : new DoubleCollection { 6, 4 },
            IsHitTestVisible = false,
        };
        r.SetResourceReference(Shape.StrokeProperty, _targeted ? "accentBrush" : "borderBrush");
        return r;
    }

    Grid PhotoTile(byte[] jpeg, Guid id)
    {
        var image = new Image { Source = PhotoTools.Thumbnail(jpeg, 192), Stretch = Stretch.UniformToFill, Width = Tile.Width, Height = Tile.Height };
        image.Clip = new RectangleGeometry(new Rect(0, 0, Tile.Width, Tile.Height), 12, 12);
        var frame = new Border { Width = Tile.Width, Height = Tile.Height, CornerRadius = new(12), BorderThickness = new(1), Child = image };
        frame.Res(Border.BorderBrushProperty, "borderBrush");
        return WithRemove(frame, id);
    }

    Grid TextTile(Guid id)
    {
        var icon = Ui.Icon("", 26, "accentTextBrush");
        icon.HorizontalAlignment = HorizontalAlignment.Center;
        icon.VerticalAlignment = VerticalAlignment.Center;
        var face = new Border { Width = Tile.Width, Height = Tile.Height, CornerRadius = new(12), BorderThickness = new(1), Child = icon };
        face.Res(Border.BackgroundProperty, "accentSoftBrush");
        face.Res(Border.BorderBrushProperty, "borderBrush");
        return WithRemove(face, id);
    }

    Grid WithRemove(FrameworkElement face, Guid id)
    {
        var x = new TextBlock
        {
            Text = "",
            FontSize = 8,
            Foreground = Brushes.White,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
        }.Styled("Text.Icon");
        x.Foreground = Brushes.White;
        var dot = new Border
        {
            Width = 18,
            Height = 18,
            CornerRadius = new(9),
            Background = new SolidColorBrush(Color.FromArgb(0x8C, 0, 0, 0)),
            BorderBrush = new SolidColorBrush(Color.FromArgb(0xCC, 0xFF, 0xFF, 0xFF)),
            BorderThickness = new(1),
            Child = x,
        };
        var remove = new Button
        {
            Content = dot,
            Padding = new(0),
            MinHeight = 0,
            Margin = new(0, 4, 4, 0),
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Top,
            ToolTip = L.Get("report.file.remove"),
            Cursor = Cursors.Hand,
        }.Styled("Button.Ghost");
        AutomationNames.Set(remove, L.Get("report.file.remove"));
        remove.Click += (_, _) => _draft.Remove(id);
        var grid = new Grid { Width = Tile.Width, Height = Tile.Height };
        grid.Children.Add(face);
        grid.Children.Add(remove);
        return grid;
    }

    Border Thanks()
    {
        var tick = Ui.Icon("", 34, "successBrush");
        tick.HorizontalAlignment = HorizontalAlignment.Center;
        var text = Ui.Headline(L.Get("report.thanks")).At(0, 12, 0, 0);
        text.TextAlignment = TextAlignment.Center;
        var card = new Card { Content = Ui.Column(tick, text), Padding = new(16, 24, 16, 24) };
        if (_thanks is null || !_thanks.IsEnabled)
        {
            _thanks = new DispatcherTimer { Interval = ThanksFor };
            _thanks.Tick += (_, _) =>
            {
                _thanks.Stop();
                if (_detached) return;
                _draft.Reset();
                _onDone();
            };
            _thanks.Start();
        }
        return new Border { Child = card };
    }

    // ---- Ekler ----

    void Choose()
    {
        if (!_draft.CanAdd) return;
        var filter = L.Get("common.photo.filterName") + " / .txt|" + ReportAttachments.FilterPattern;
        var dialog = new Microsoft.Win32.OpenFileDialog { Title = L.Get("report.drop"), Filter = filter, Multiselect = true };
        if (dialog.ShowDialog(Window.GetWindow(this)) == true) _ = AddFilesAsync(dialog.FileNames, null);
    }

    /// <summary>Pencereye sürükle-bırak ve Ctrl+V (önizleme aşamasında; metin kutusu dosyayı kendisi almasın).</summary>
    public void AttachTo(Window window)
    {
        window.AllowDrop = true;
        window.PreviewDragEnter += OnDragOver;
        window.PreviewDragOver += OnDragOver;
        window.PreviewDragLeave += (_, e) =>
        {
            SetTargeted(false);
            e.Handled = true;
        };
        window.PreviewDrop += (_, e) =>
        {
            e.Handled = true;
            SetTargeted(false);
            if (_draft.Phase != ReportPhase.Editing || !e.Data.GetDataPresent(DataFormats.FileDrop)) return;
            if (!_draft.CanAdd)
            {
                _draft.MarkLimit();
                return;
            }
            if (e.Data.GetData(DataFormats.FileDrop) is string[] files) _ = AddFilesAsync(files, null);
        };
        window.PreviewKeyDown += OnKey;
    }

    void OnDragOver(object sender, DragEventArgs e)
    {
        var ok = _draft.Phase == ReportPhase.Editing && e.Data.GetDataPresent(DataFormats.FileDrop);
        e.Effects = ok ? DragDropEffects.Copy : DragDropEffects.None;
        SetTargeted(ok);
        e.Handled = true;
    }

    void SetTargeted(bool on)
    {
        if (_targeted == on) return;
        _targeted = on;
        Render();
    }

    void OnKey(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter && Keyboard.Modifiers == ModifierKeys.Control)
        {
            e.Handled = true;
            _ = SendAsync();
            return;
        }
        if (e.Key != Key.V || Keyboard.Modifiers != ModifierKeys.Control || _draft.Phase != ReportPhase.Editing) return;
        if (!PhotoTools.ClipboardHasPhoto()) return;
        if (Keyboard.FocusedElement is TextBox && PhotoTools.ClipboardHasText()) return;
        e.Handled = true;
        if (!_draft.CanAdd)
        {
            _draft.MarkLimit();
            return;
        }
        var (files, image) = PhotoTools.FromClipboard();
        if (files.Count > 0) _ = AddFilesAsync(files, null);
        else if (image is not null) _ = AddFilesAsync([], image);
        else _draft.Add([], failed: true);
    }

    /// <summary>Dosyaları (en çok 5) ve pano görüntüsünü hazırlayıp ekler; sınırları taslak uygular.</summary>
    async Task AddFilesAsync(IReadOnlyList<string> paths, BitmapSource? pasted)
    {
        var accepted = paths.Where(ReportAttachments.IsAccepted).ToList();
        var failed = accepted.Count < paths.Count || accepted.Count > ReportAttachments.MaxFiles;
        accepted = accepted.Take(ReportAttachments.MaxFiles).ToList();
        _draft.BeginPreparing();
        var items = new List<ReportAttachment>();
        var limited = false;
        try
        {
            if (pasted is not null)
            {
                var jpeg = await Task.Run(() => PhotoTools.ToJpeg(pasted, SupportLimits.ReportPhotoBytes));
                if (jpeg is null) failed = true;
                else items.Add(ReportAttachment.Image("image-1.jpg", jpeg));
            }
            foreach (var path in accepted)
            {
                var name = System.IO.Path.GetFileName(path);
                if (ReportAttachments.IsTextFile(path))
                {
                    var (text, tooBig) = await Task.Run(() => ReadText(path));
                    if (tooBig) limited = true;
                    else if (text is null) failed = true;
                    else items.Add(ReportAttachment.TextFile(name, text));
                    continue;
                }
                var image = PhotoTools.FromFile(path);
                var bytes = image is null ? null : await Task.Run(() => PhotoTools.ToJpeg(image, SupportLimits.ReportPhotoBytes));
                if (bytes is null) failed = true;
                else items.Add(ReportAttachment.Image(name, bytes));
            }
        }
        catch (Exception) { failed = true; }
        if (_detached) return;
        _draft.Add(items, failed, endPreparing: true);
        if (limited) _draft.MarkLimit();
    }

    static (string? Text, bool TooBig) ReadText(string path)
    {
        try
        {
            var info = new FileInfo(path);
            if (info.Length > ReportAttachments.MaxTextFileBytes) return (null, true);
            return (ReportAttachments.Decode(File.ReadAllBytes(path)), false);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or System.Security.SecurityException) { return (null, false); }
    }

    async Task SendAsync()
    {
        if (!_draft.CanSend) return;
        try { await _c.SendReportDraftAsync(); }
        catch (Exception) { }
    }
}

/// <summary>Hata bildirimi penceresi (Mac'in 640'lık sayfası): başlık ve Kapat üstte, form kayar.</summary>
public sealed class ReportProblemWindow : Window
{
    readonly ReportProblemForm _form;

    /// <summary>Tek pencere kuralıyla açar.</summary>
    public static ReportProblemWindow Open(NinoController controller, Window? owner) =>
        Ui.ShowSingle(owner, () => new ReportProblemWindow(controller));

    public ReportProblemWindow(NinoController controller)
    {
        Ui.Prepare(this, L.Get("report.title"));
        Width = 640;
        Height = Math.Min(672, Math.Max(480, SystemParameters.WorkArea.Height - 40));
        ResizeMode = ResizeMode.NoResize;

        _form = new ReportProblemForm(controller, Close);
        var root = new DockPanel { Margin = new(24), LastChildFill = true };
        var title = Ui.Display(L.Get("report.title"));
        title.VerticalAlignment = VerticalAlignment.Center;
        var close = Ui.Button(L.Get("common.close"), Close);
        close.IsCancel = true;
        close.VerticalAlignment = VerticalAlignment.Center;
        var head = new DockPanel { Margin = new(0, 0, 0, 16) };
        DockPanel.SetDock(close, Dock.Right);
        head.Children.Add(close);
        head.Children.Add(title);
        DockPanel.SetDock(head, Dock.Top);
        root.Children.Add(head);
        root.Children.Add(new ScrollViewer
        {
            Content = new Border { Child = _form, Padding = new(0, 0, 0, 8) },
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            Focusable = false,
        });
        Content = root;
        _form.AttachTo(this);
        Closed += (_, _) => _form.Detach();
    }
}
