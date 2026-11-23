// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows;
using System.Windows.Automation;
using System.Windows.Automation.Peers;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;
using Nino.App.Controls;
using Glyphs = Nino.App.Controls.Glyphs;
using Nino.App.Strings;
using Nino.App.Theme;
using Nino.Core.Support;
using Nino.Shell;

namespace Nino.App.Views;

/// <summary>
/// Nino'ya Sor penceresi (yan pencereler tarifi §9): 440 × 680, başlık şeridi, mesaj listesi, yazma alanı. Sohbet
/// uygulama açık kaldıkça bellekte durur (<see cref="NinoController.Assistant"/>). Sahibi her zaman ana penceredir.
/// </summary>
public sealed class AskNinoWindow : Window
{
    static readonly string[] Suggestions =
        ["ask.suggestion.ps5TvPhone", "ask.suggestion.ps5MonitorPc", "ask.suggestion.xboxTv", "ask.suggestion.installTvApp"];

    readonly NinoController _c;
    readonly AssistantChat _chat;
    readonly PhotoAttachments _photos = new(SupportLimits.AssistantPhotoBytes);
    readonly NinoBot _headerBot = new() { Width = 44, Height = 44 };
    readonly StackPanel _messages = new() { Margin = new(16, 16, 16, 8) };
    readonly ScrollViewer _scroll;
    readonly WrapPanel _attachments = new() { Margin = new(0, 0, 0, 4) };
    readonly TextBlock _error;
    readonly TextBox _input;
    readonly Button _attach;
    readonly Button _send;
    bool _renderQueued;
    double _listWidth = 440;

    /// <summary>Tek pencere kuralıyla açar; sahibi ana pencere (verilmezse uygulamanın ana penceresi).</summary>
    public static AskNinoWindow Open(NinoController controller, Window? mainWindow = null) =>
        Ui.ShowSingle(mainWindow ?? Application.Current?.MainWindow, () => new AskNinoWindow(controller));

    public AskNinoWindow(NinoController controller)
    {
        _c = controller;
        _chat = controller.Assistant;
        Ui.Prepare(this, L.Get("home.robot.askNino"));
        Width = 440;
        Height = 680;
        MinWidth = 360;
        MinHeight = 460;

        var root = new DockPanel();

        // Başlık şeridi.
        var names = Ui.Column(Ui.Headline("Nino"), Ui.Caption(L.Get("ask.subtitle")));
        names.VerticalAlignment = VerticalAlignment.Center;
        names.Margin = new(12, 0, 0, 0);
        var newChatContent = Ui.Row(Ui.Icon(Glyphs.Add, 14, "accentTextBrush").At(0, 0, 8, 0),
            new TextBlock { Text = L.Get("ask.newChat"), VerticalAlignment = VerticalAlignment.Center });
        var newChat = new Button { Content = newChatContent, ToolTip = L.Get("ask.newChat"), VerticalAlignment = VerticalAlignment.Center }
            .Styled("Button.Ghost");
        AutomationNames.Set(newChat, L.Get("ask.newChat"));
        newChat.Click += (_, _) =>
        {
            _chat.NewChat();
            _photos.Clear();
            _input!.Clear();
            _input.Focus();
        };
        var headerRow = Ui.Split(Ui.Row(_headerBot, names), newChat);
        var header = new Border { Padding = new(16, 12, 12, 12), BorderThickness = new(0, 0, 0, 1), Child = headerRow };
        header.Res(Border.BorderBrushProperty, "borderBrush");
        DockPanel.SetDock(header, Dock.Top);
        root.Children.Add(header);

        // Yazma alanı.
        _error = Ui.Error().At(0, 0, 0, 8).Shown(false);
        _attach = new Button { Content = Glyphs.Attach, VerticalAlignment = VerticalAlignment.Bottom, ToolTip = L.Get("ask.attachTooltip") }
            .Styled("Button.Icon");
        AutomationNames.Set(_attach, L.Get("ask.attach"));
        _attach.Click += (_, _) => _photos.Pick(this, L.Get("ask.attach"));
        _input = new TextBox
        {
            AcceptsReturn = true,
            TextWrapping = TextWrapping.Wrap,
            MaxLength = SupportLimits.AssistantText,
            MaxHeight = 132,
            Padding = new(14, 9, 14, 9),
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            VerticalContentAlignment = VerticalAlignment.Top,
        };
        _input.PreviewKeyDown += (_, e) =>
        {
            if (e.Key == Key.Enter && !Keyboard.Modifiers.HasFlag(ModifierKeys.Shift))
            {
                e.Handled = true;
                SendTyped();
            }
        };
        _input.TextChanged += (_, _) => UpdateSend();
        var sendIcon = new TextBlock { Text = Glyphs.Send, FontSize = 16, Foreground = Brushes.White, HorizontalAlignment = HorizontalAlignment.Center }
            .Styled("Text.Icon");
        if (L.IsRightToLeft) sendIcon.RenderTransform = new ScaleTransform(-1, 1, 8, 8);
        _send = new Button
        {
            Content = sendIcon,
            Width = 40,
            Height = 40,
            MinHeight = 0,
            Padding = new(0),
            VerticalAlignment = VerticalAlignment.Bottom,
            ToolTip = L.Get("common.send"),
        }.Styled("Button.Primary");
        AutomationNames.Set(_send, L.Get("common.send"));
        _send.Click += (_, _) => SendTyped();
        var inputRow = new Grid();
        inputRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        inputRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        inputRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var inputBox = Ui.WithPlaceholder(_input, L.Get("ask.placeholder"), top: true);
        inputBox.Margin = new(8, 0, 8, 0);
        Grid.SetColumn(inputBox, 1);
        Grid.SetColumn(_send, 2);
        inputRow.Children.Add(_attach);
        inputRow.Children.Add(inputBox);
        inputRow.Children.Add(_send);
        var note = Ui.Caption(L.Get("ask.disclaimer")).At(0, 8, 0, 0);
        note.TextAlignment = TextAlignment.Center;
        var composer = new Border
        {
            Padding = new(12, 10, 12, 10),
            BorderThickness = new(0, 1, 0, 0),
            Child = Ui.Column(_attachments, _error, inputRow, note),
        };
        composer.Res(Border.BorderBrushProperty, "borderBrush");
        DockPanel.SetDock(composer, Dock.Bottom);
        root.Children.Add(composer);

        _scroll = new ScrollViewer
        {
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            Content = _messages,
        };
        _scroll.SizeChanged += (_, e) =>
        {
            if (Math.Abs(e.NewSize.Width - _listWidth) < 1) return;
            _listWidth = e.NewSize.Width;
            RenderSoon();
        };
        root.Children.Add(_scroll);
        Content = root;

        _photos.Blocked = () => false;
        _photos.Changed += () =>
        {
            RenderAttachments();
            UpdateSend();
        };
        _photos.Error += message =>
        {
            _error.Text = message ?? "";
            _error.Shown(message is not null);
        };
        _photos.Attach(this);
        PreviewKeyDown += (_, e) => _photos.TryPaste(e);

        _chat.Changed += OnChatChanged;
        Closed += (_, _) => _chat.Changed -= OnChatChanged;
        Loaded += (_, _) =>
        {
            Render();
            _input.Focus();
        };
        RenderAttachments();
        UpdateSend();
    }

    void OnChatChanged() => Dispatcher.BeginInvoke(RenderSoon);

    void RenderSoon()
    {
        if (_renderQueued) return;
        _renderQueued = true;
        Dispatcher.BeginInvoke(() =>
        {
            _renderQueued = false;
            Render();
        });
    }

    void UpdateSend()
    {
        _send.IsEnabled = _chat.CanSend(_input.Text, _photos.Photos.Count);
        _attach.IsEnabled = !_photos.IsFull;
    }

    void SendTyped()
    {
        if (_chat.IsWaiting) return;
        var text = _input.Text;
        var images = _photos.Photos.ToArray();
        if (!_chat.CanSend(text, images.Length)) return;
        _input.Clear();
        _photos.Clear();
        _error.Shown(false);
        _chat.Send(text, images);
    }

    void RenderAttachments()
    {
        _attachments.Children.Clear();
        foreach (var photo in _photos.Photos)
        {
            var image = new Image { Source = PhotoTools.Thumbnail(photo, 112), Stretch = Stretch.UniformToFill, Width = 56, Height = 56 };
            image.Clip = new RectangleGeometry(new Rect(0, 0, 56, 56), 10, 10);
            var remove = new Button
            {
                Content = "✕",
                FontSize = 10,
                Width = 22,
                Height = 22,
                MinHeight = 0,
                Padding = new(0),
                HorizontalAlignment = HorizontalAlignment.Right,
                VerticalAlignment = VerticalAlignment.Top,
                Margin = new(0, 3, 3, 0),
                ToolTip = L.Get("common.photo.remove"),
            }.Styled("Button.Secondary");
            AutomationNames.Set(remove, L.Get("common.photo.remove"));
            var captured = photo;
            remove.Click += (_, _) => _photos.Remove(captured);
            var cell = new Grid { Margin = new(0, 0, 8, 6) };
            cell.Children.Add(image);
            cell.Children.Add(remove);
            _attachments.Children.Add(cell);
        }
        _attachments.Shown(_photos.Photos.Count > 0);
    }

    double BubbleWidth => Math.Max(220, (_listWidth - 32) * 0.78 - 40);

    void Render()
    {
        var waiting = _chat.IsWaiting;
        _headerBot.IsThinking = waiting;
        _messages.Children.Clear();
        _messages.Children.Add(RobotRow(Ui.Column(ReplyText(L.Get("ask.greeting"), out _)), thinking: false));
        var entries = _chat.Entries;
        if (entries.Count == 0 && !waiting)
        {
            var pills = new WrapPanel { Margin = new(36, 0, 0, 12) };
            foreach (var key in Suggestions)
            {
                var text = L.Get(key);
                var chip = new Button { Content = text, MinHeight = 34, Padding = new(14, 0, 14, 0), Margin = new(0, 0, 8, 8) }
                    .Styled("Button.Secondary");
                chip.Fg("accentTextBrush");
                chip.Click += (_, _) => _chat.Send(text);
                pills.Children.Add(chip);
            }
            _messages.Children.Add(pills);
        }
        TextBlock? live = null;
        string? liveText = null;
        for (var i = 0; i < entries.Count; i++)
        {
            switch (entries[i])
            {
                case UserChatEntry user:
                    _messages.Children.Add(UserBubble(user));
                    break;
                case NinoChatEntry nino:
                {
                    var body = ReplyText(nino.Text, out var first);
                    var content = Ui.Column(body);
                    if (!string.IsNullOrEmpty(nino.ReportId)) content.Children.Add(Badge());
                    if (i == entries.Count - 1 && nino.Options.Count > 0)
                        content.Children.Add(OptionButtons(nino.Options, enabled: !waiting));
                    _messages.Children.Add(RobotRow(content, thinking: false));
                    live = first;
                    liveText = nino.Text;
                    break;
                }
                case AlertChatEntry alert:
                {
                    var text = L.Get(alert.TextKey);
                    var body = ReplyText(text, out var first);
                    var content = Ui.Column(body);
                    if (alert.OffersReport)
                        content.Children.Add(ActionButton(L.Get("settings.about.reportProblem"), primary: true,
                            () => ReportProblemWindow.Open(_c, this)));
                    else if (alert.Retriable && i == entries.Count - 1 && !waiting)
                        content.Children.Add(ActionButton(L.Get("common.retry"), primary: false, () => _chat.Retry()));
                    _messages.Children.Add(RobotRow(content, thinking: false));
                    live = first;
                    liveText = text;
                    break;
                }
            }
        }
        if (waiting) _messages.Children.Add(TypingRow());
        if (live is not null && liveText is not null)
        {
            AutomationProperties.SetLiveSetting(live, AutomationLiveSetting.Polite);
            AutomationProperties.SetName(live, L.Format("ask.liveRegion", liveText));
            var target = live;
            target.Loaded += (_, _) => UIElementAutomationPeer.CreatePeerForElement(target)?.RaiseAutomationEvent(AutomationEvents.LiveRegionChanged);
        }
        UpdateSend();
        Dispatcher.BeginInvoke(_scroll.ScrollToEnd, System.Windows.Threading.DispatcherPriority.Background);
    }

    /// <summary>
    /// Teşhis sorusunun seçenekleri: balonun altında sarılarak dizilen ikincil haplar; basınca etiket aynen gönderilir.
    /// Sağdan sola arayüzde ya da Arapça yazılı seçenekte akış sağdan sola.
    /// </summary>
    WrapPanel OptionButtons(IReadOnlyList<string> options, bool enabled)
    {
        var panel = new WrapPanel { Margin = new(0, 10, 0, 0), MaxWidth = BubbleWidth, HorizontalAlignment = HorizontalAlignment.Left };
        if (L.IsRightToLeft || options.Any(o => RightToLeft.ForText(o) == FlowDirection.RightToLeft))
            panel.FlowDirection = FlowDirection.RightToLeft;
        foreach (var label in options)
        {
            var text = new TextBlock { Text = label, TextWrapping = TextWrapping.Wrap, FlowDirection = RightToLeft.ForText(label) };
            var chip = new Button { Content = text, MinHeight = 34, Padding = new(14, 0, 14, 0), Margin = new(0, 0, 8, 8), IsEnabled = enabled }
                .Styled("Button.Secondary");
            chip.Fg("accentTextBrush");
            AutomationNames.Set(chip, label);
            var captured = label;
            chip.Click += (_, _) => _chat.Choose(captured);
            panel.Children.Add(chip);
        }
        return panel;
    }

    static Button ActionButton(string text, bool primary, Action click)
    {
        var b = Ui.Button(text, click, primary ? "Button.Primary" : "Button.Secondary");
        b.MinHeight = 34;
        b.Padding = new(16, 0, 16, 0);
        b.Margin = new(0, 10, 0, 0);
        return b;
    }

    static FrameworkElement Badge()
    {
        var text = new TextBlock { Text = L.Get("ask.reportSent"), FontSize = 12, FontWeight = FontWeights.SemiBold };
        text.Res(TextBlock.ForegroundProperty, "successBrush");
        var pill = new Border
        {
            CornerRadius = new(999),
            Padding = new(10, 3, 10, 3),
            Margin = new(0, 6, 0, 0),
            HorizontalAlignment = HorizontalAlignment.Left,
            Child = text,
        };
        pill.Res(Border.BackgroundProperty, "successSoftBrush");
        return pill;
    }

    FrameworkElement RobotRow(StackPanel content, bool thinking)
    {
        var bot = new NinoBot { Width = 28, Height = 28, Blinks = false, IsThinking = thinking, VerticalAlignment = VerticalAlignment.Bottom };
        bot.Margin = new(0, 0, 8, 2);
        var bubble = Bubble(content, user: false);
        var stack = new StackPanel { Children = { bubble } };
        if (content.Children.Count > 1)
        {
            // Rozet ve düğmeler balonun altında dursun.
            var extras = content.Children.Cast<UIElement>().Skip(1).ToList();
            foreach (var e in extras) content.Children.Remove(e);
            foreach (var e in extras) stack.Children.Add(e);
        }
        var row = new DockPanel { Margin = new(0, 0, 0, 12), HorizontalAlignment = HorizontalAlignment.Left };
        DockPanel.SetDock(bot, Dock.Left);
        row.Children.Add(bot);
        row.Children.Add(stack);
        return row;
    }

    Border Bubble(UIElement child, bool user)
    {
        var b = new Border
        {
            Padding = new(14, 10, 14, 10),
            CornerRadius = user ? new(18, 18, 6, 18) : new(18, 18, 18, 6),
            MaxWidth = BubbleWidth,
            HorizontalAlignment = user ? HorizontalAlignment.Right : HorizontalAlignment.Left,
            Child = child,
        };
        b.Res(Border.BackgroundProperty, user ? "accentBrush" : "surface2Brush");
        return b;
    }

    FrameworkElement UserBubble(UserChatEntry entry)
    {
        var content = new StackPanel();
        if (entry.Images.Count > 0)
        {
            var images = new WrapPanel();
            foreach (var jpeg in entry.Images)
            {
                var image = new Image { Source = PhotoTools.Thumbnail(jpeg, 192), Width = 96, Height = 96, Stretch = Stretch.UniformToFill };
                image.Clip = new RectangleGeometry(new Rect(0, 0, 96, 96), 10, 10);
                image.Margin = new(0, 0, 6, 6);
                images.Children.Add(image);
            }
            content.Children.Add(images);
        }
        if (entry.Text.Length > 0)
        {
            var text = new TextBlock { Text = entry.Text, TextWrapping = TextWrapping.Wrap, Foreground = Brushes.White };
            text.Res(TextBlock.ForegroundProperty, "onAccentBrush");
            if (entry.Images.Count > 0) text.Margin = new(0, 8 - 6, 0, 0);
            content.Children.Add(text);
        }
        var bubble = Bubble(content, user: true);
        bubble.Margin = new(48, 0, 0, 12);
        return bubble;
    }

    /// <summary>Robot metni: paragraflar, numaralı adımlar ve maddeler (asılı girinti), bağlantılar.</summary>
    StackPanel ReplyText(string text, out TextBlock? first)
    {
        first = null;
        var panel = new StackPanel();
        var blocks = ReplyBlocks.Parse(text);
        ReplyBlockKind? previous = null;
        foreach (var block in blocks)
        {
            var body = Inlines(block);
            first ??= body;
            FrameworkElement element = block.Kind == ReplyBlockKind.Paragraph ? body : ListItem(block, body);
            var bothList = previous is ReplyBlockKind.Step or ReplyBlockKind.Bullet && block.Kind is ReplyBlockKind.Step or ReplyBlockKind.Bullet;
            element.Margin = new(0, previous is null ? 0 : bothList ? 8 : 10, 0, 0);
            panel.Children.Add(element);
            previous = block.Kind;
        }
        if (blocks.Count == 0)
        {
            var empty = new TextBlock { Text = text, TextWrapping = TextWrapping.Wrap };
            first = empty;
            panel.Children.Add(empty);
        }
        return panel;
    }

    static TextBlock Inlines(ReplyBlock block)
    {
        var t = new TextBlock { TextWrapping = TextWrapping.Wrap };
        foreach (var part in block.Inlines)
        {
            if (part.Link is { } uri)
            {
                var link = new Hyperlink(new Run(part.Text)) { NavigateUri = uri, ToolTip = uri.AbsoluteUri };
                link.RequestNavigate += (_, e) =>
                {
                    Ui.Open(e.Uri.AbsoluteUri);
                    e.Handled = true;
                };
                t.Inlines.Add(link);
            }
            else t.Inlines.Add(new Run(part.Text));
        }
        return t;
    }

    static FrameworkElement ListItem(ReplyBlock block, TextBlock body)
    {
        FrameworkElement marker;
        if (block.Kind == ReplyBlockKind.Step)
        {
            var number = new TextBlock
            {
                Text = block.Number.ToString(L.Catalog.Culture),
                FontSize = 11.5,
                FontWeight = FontWeights.Bold,
                Foreground = Brushes.White,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
                TextWrapping = TextWrapping.NoWrap,
            };
            var badge = new Border
            {
                Height = 21,
                MinWidth = 21,
                CornerRadius = new(10.5),
                Padding = block.Number >= 10 ? new(4, 0, 4, 0) : new(0),
                Child = number,
                VerticalAlignment = VerticalAlignment.Top,
            };
            badge.Res(Border.BackgroundProperty, "accentBrush");
            marker = badge;
        }
        else
        {
            var dot = new Ellipse { Width = 6, Height = 6, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
            dot.Res(Shape.FillProperty, "accentBrush");
            marker = new Grid { Width = 21, Height = 21, VerticalAlignment = VerticalAlignment.Top, Children = { dot } };
        }
        marker.Margin = new(0, 0, 8, 0);
        body.Margin = new(0, 1, 0, 0);
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        Grid.SetColumn(body, 1);
        grid.Children.Add(marker);
        grid.Children.Add(body);
        return grid;
    }

    FrameworkElement TypingRow()
    {
        var dots = new StackPanel { Orientation = Orientation.Horizontal, Margin = new(2, 5, 2, 5) };
        for (var i = 0; i < 3; i++)
        {
            var dot = new Ellipse { Width = 7, Height = 7, Opacity = 0.35, Margin = new(i == 0 ? 0 : 5, 0, 0, 0) };
            dot.Res(Shape.FillProperty, "textSecondaryBrush");
            if (!Motion.IsReduced)
            {
                var animation = new DoubleAnimation(0.25, 1, TimeSpan.FromMilliseconds(420))
                {
                    AutoReverse = true,
                    RepeatBehavior = RepeatBehavior.Forever,
                    BeginTime = TimeSpan.FromMilliseconds(160 * i),
                };
                dot.BeginAnimation(OpacityProperty, animation);
            }
            dots.Children.Add(dot);
        }
        AutomationProperties.SetName(dots, L.Get("ask.typing"));
        AutomationProperties.SetLiveSetting(dots, AutomationLiveSetting.Polite);
        return RobotRow(Ui.Column(dots), thinking: true);
    }
}
