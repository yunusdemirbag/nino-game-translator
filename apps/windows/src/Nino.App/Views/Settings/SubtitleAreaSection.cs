// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows;
using System.Windows.Controls;
using Nino.App.Controls;
using Nino.App.Strings;
using Nino.Core.Settings;
using Nino.Core.Text;
using Nino.Shell;
using Nino.Shell.Panels;

namespace Nino.App.Views;

/// <summary>§8 Okuma alanları: altyazı bölgesi ve üç ek bölge, Tam ekran ve serbest seçim kartları.</summary>
internal sealed class SubtitleAreaSection(SettingsWindow host) : SettingsSection(host)
{
    SegmentBar? _which;
    StackPanel? _presetPane;
    SegmentBar? _preset;
    Grid? _custom;
    SliderRow? _top;
    SliderRow? _height;
    CheckBox? _use;
    StackPanel? _livePane;
    CheckBox? _live;
    StackPanel? _resultPane;
    SegmentBar? _result;
    RegionPicker? _picker;
    Button? _refresh;
    TextBlock? _hint;
    Card? _screenCard;
    TextBlock? _screenHint;
    Card? _freeCard;
    TextBlock? _freeHint;
    TextBlock? _pauseHint;
    SegmentBar? _freeTarget;
    DateTime _lastPicture = DateTime.MinValue;

    public override string SectionTitle => L.Get("settings.section.subtitleArea");

    int Slot => _which?.Selected ?? 0;

    static Region? Extra(AppSettings s, int slot) => slot switch
    {
        1 => s.ExtraRegion1,
        2 => s.ExtraRegion2,
        _ => s.ExtraRegion3,
    };

    static void SetExtra(AppSettings s, int slot, Region? r)
    {
        if (slot == 1) s.ExtraRegion1 = r;
        else if (slot == 2) s.ExtraRegion2 = r;
        else s.ExtraRegion3 = r;
    }

    static bool Live(AppSettings s, int slot) => slot switch
    {
        1 => s.ExtraLive1,
        2 => s.ExtraLive2,
        _ => s.ExtraLive3,
    };

    static void SetLive(AppSettings s, int slot, bool v)
    {
        if (slot == 1) s.ExtraLive1 = v;
        else if (slot == 2) s.ExtraLive2 = v;
        else s.ExtraLive3 = v;
    }

    static ResultTarget Target(AppSettings s, int slot) => slot switch
    {
        1 => s.ExtraTarget1,
        2 => s.ExtraTarget2,
        _ => s.ExtraTarget3,
    };

    static void SetTarget(AppSettings s, int slot, ResultTarget v)
    {
        if (slot == 1) s.ExtraTarget1 = v;
        else if (slot == 2) s.ExtraTarget2 = v;
        else s.ExtraTarget3 = v;
    }

    static HotkeyAction AreaAction(int slot) => slot switch
    {
        1 => HotkeyAction.ExtraRegion1,
        2 => HotkeyAction.ExtraRegion2,
        _ => HotkeyAction.ExtraRegion3,
    };

    static int TargetIndex(ResultTarget t) => t switch
    {
        ResultTarget.Computer => 1,
        ResultTarget.Both => 2,
        _ => 0,
    };

    static ResultTarget TargetOf(int i) => i switch
    {
        1 => ResultTarget.Computer,
        2 => ResultTarget.Both,
        _ => ResultTarget.Tv,
    };

    static SegmentBar TargetBar() =>
        new(false, L.Get("settings.area.target.tv"), L.Get("settings.area.target.pc"), L.Get("settings.area.target.both"));

    protected override void Build()
    {
        AddHeader();
        var body = new StackPanel();
        _which = new SegmentBar(false, L.Get("settings.area.subtitles"), L.Get("settings.area.area1"), L.Get("settings.area.area2"),
            L.Get("settings.area.area3")) { Margin = new(0, 0, 0, 12) };
        _which.Selected = 0;
        _which.Changed += _ => Guard.Run(ShowSlot);
        body.Children.Add(_which);

        // Hazır bölge.
        _presetPane = new StackPanel { Margin = new(0, 0, 0, 12) };
        _presetPane.Children.Add(Ui.Body(L.Get("settings.area.preset.label")).At(0, 0, 0, 8));
        _preset = new SegmentBar(false, L.Get("settings.area.preset.bottom"), L.Get("settings.area.preset.top"),
            L.Get("reading.areaPreset.full"), L.Get("reading.areaPreset.custom"));
        _preset.Changed += i =>
        {
            var preset = (AreaPreset)i;
            Write(s => RegionPresets.Apply(s, preset));
            Guard.Run(() =>
            {
                _picker!.Show(C.Settings.Region);
                MarkPreset();
            });
        };
        _presetPane.Children.Add(_preset);
        _custom = new Grid { Margin = new(0, 12, 0, 0) };
        _custom.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        _custom.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        _custom.RowDefinitions.Add(new RowDefinition());
        _custom.RowDefinitions.Add(new RowDefinition { Height = new GridLength(8) });
        _custom.RowDefinitions.Add(new RowDefinition());
        _top = new SliderRow(null, null, 0, 95, true, 56);
        _top.Slider.SmallChange = 1;
        _top.Slider.LargeChange = 5;
        _height = new SliderRow(null, null, 5, 100, true, 56);
        _height.Slider.SmallChange = 1;
        _height.Slider.LargeChange = 5;
        AddCustomRow(0, L.Get("settings.area.verticalPosition"), _top);
        AddCustomRow(2, L.Get("reading.area.height"), _height);
        _top.Slider.ValueChanged += (_, _) => CustomSlidersChanged();
        _height.Slider.ValueChanged += (_, _) => CustomSlidersChanged();
        _presetPane.Children.Add(_custom);
        body.Children.Add(_presetPane);

        // Ek bölge: kullan, sürekli oku, sonuç yeri.
        _use = Ui.Toggle(L.Get("settings.area.useThisArea")).At(0, 0, 0, 12);
        _use.Checked += (_, _) => UseChanged(true);
        _use.Unchecked += (_, _) => UseChanged(false);
        body.Children.Add(_use);
        _livePane = new StackPanel { Margin = new(0, 0, 0, 12) };
        _live = Ui.Toggle(L.Get("settings.area.keepReading"));
        _live.Checked += (_, _) => Write(s => SetLive(s, Slot, true));
        _live.Unchecked += (_, _) => Write(s => SetLive(s, Slot, false));
        _livePane.Children.Add(_live);
        _livePane.Children.Add(Ui.Hint(L.Get("settings.area.keepReadingHint")).At(0, 6, 0, 0));
        var corners = new WrapPanel { Margin = new(0, 10, 0, 0) };
        foreach (var (key, region) in new[]
                 {
                     ("reading.extraPreset.quest", RegionPresets.ExtraQuest),
                     ("reading.extraPreset.notification", RegionPresets.ExtraNotification),
                     ("settings.area.corner.phone", RegionPresets.ExtraPhone),
                 })
            corners.Children.Add(Ui.Button(L.Get(key), () => UseCorner(region)).At(0, 0, 8, 8));
        _livePane.Children.Add(corners);
        body.Children.Add(_livePane);
        _resultPane = new StackPanel { Margin = new(0, 0, 0, 12) };
        _resultPane.Children.Add(Ui.Body(L.Get("settings.area.showResult")).At(0, 0, 0, 8));
        _result = TargetBar();
        _result.Changed += i => Write(s => SetTarget(s, Slot, TargetOf(i)));
        _resultPane.Children.Add(_result);
        body.Children.Add(_resultPane);

        _picker = new RegionPicker();
        _picker.RegionChanged += PickerChanged;
        body.Children.Add(_picker);
        _refresh = Ui.Button("", RefreshPictureNow).At(0, 12, 0, 0);
        body.Children.Add(_refresh);
        _hint = Ui.Hint("").At(0, 12, 0, 0);
        body.Children.Add(_hint);
        AddCard(Ui.Card(null, body));

        _screenHint = Ui.Hint("");
        _screenCard = AddCard(Ui.Card("", _screenHint));
        _freeHint = Ui.Hint("").At(0, 0, 0, 12);
        _freeTarget = TargetBar();
        _freeTarget.Margin = new(0, 0, 0, 12);
        _freeTarget.Changed += i => Write(s => s.FreeAreaTarget = TargetOf(i));
        _pauseHint = Ui.Hint("").At(0, 0, 0, 8);
        _freeCard = AddCard(Ui.Card("", _freeHint, Ui.Body(L.Get("settings.area.showResult")).At(0, 0, 0, 8), _freeTarget, _pauseHint,
            Ui.Hint(L.Get("settings.area.shortcutsHint"))));

        _picker.SetFrame(C.LastFrame);
        _lastPicture = DateTime.UtcNow;
        ShowSlot();
        UpdateTexts();
    }

    void AddCustomRow(int row, string label, SliderRow slider)
    {
        var text = Ui.Body(label);
        text.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetRow(text, row);
        Grid.SetRow(slider, row);
        Grid.SetColumn(slider, 1);
        _custom!.Children.Add(text);
        _custom.Children.Add(slider);
    }

    void ShowSlot()
    {
        var s = C.Settings;
        var slot = Slot;
        var subtitles = slot == 0;
        _presetPane!.Shown(subtitles);
        _use!.Shown(!subtitles);
        _livePane!.Shown(!subtitles);
        _resultPane!.Shown(!subtitles);
        if (subtitles)
        {
            MarkPreset();
            _picker!.IsEnabled = true;
            _picker.ResetRegion = RegionPresets.Bottom;
            _picker.Show(s.Region);
        }
        else
        {
            var region = Extra(s, slot);
            _use!.IsChecked = region is not null;
            _live!.IsChecked = Live(s, slot);
            _result!.Selected = TargetIndex(Target(s, slot));
            _picker!.IsEnabled = region is not null;
            _picker.ResetRegion = SettingsPanelRules.ExtraStartRegion(slot);
            _picker.Show(region ?? SettingsPanelRules.ExtraStartRegion(slot));
        }
        UpdateHint();
    }

    void MarkPreset()
    {
        var s = C.Settings;
        _preset!.Selected = (int)s.AreaPreset;
        var custom = s.AreaPreset == AreaPreset.Custom;
        _custom!.Shown(custom);
        _top!.Slider.Value = SettingsPanelRules.SliderPercent(RegionPresets.Position(s.Region), 0, 95);
        _height!.Slider.Value = SettingsPanelRules.SliderPercent(RegionPresets.Height(s.Region), 5, 100);
        UpdateSliderTexts();
    }

    void UpdateSliderTexts()
    {
        _top!.ValueText!.Text = L.Format("settings.area.percentValue", (long)Math.Round(_top.Slider.Value));
        _height!.ValueText!.Text = L.Format("settings.area.percentValue", (long)Math.Round(_height.Slider.Value));
    }

    void CustomSlidersChanged()
    {
        if (_top is null || _height is null) return;
        UpdateSliderTexts();
        if (Guard.Busy) return;
        var region = RegionPresets.FromSliders(C.Settings.Region, Math.Round(_top.Slider.Value), Math.Round(_height.Slider.Value));
        Write(s =>
        {
            s.AreaPreset = AreaPreset.Custom;
            s.Region = region;
        });
        Guard.Run(() => _picker!.Show(region));
    }

    void PickerChanged(Region region)
    {
        var slot = Slot;
        if (slot == 0)
        {
            Write(s =>
            {
                s.Region = region;
                s.AreaPreset = RegionPresets.Detect(region);
            });
            Guard.Run(MarkPreset);
        }
        else Write(s => SetExtra(s, slot, region));
    }

    void UseChanged(bool on)
    {
        if (Guard.Busy) return;
        var slot = Slot;
        _picker!.IsEnabled = on;
        var region = _picker.Region;
        Write(s => SetExtra(s, slot, on ? region : null));
    }

    void UseCorner(Region region)
    {
        var slot = Slot;
        if (slot == 0) return;
        Guard.Run(() =>
        {
            _use!.IsChecked = true;
            _picker!.IsEnabled = true;
            _picker.Show(region);
        });
        Write(s => SetExtra(s, slot, region));
    }

    void UpdateHint()
    {
        if (_hint is null) return;
        var s = C.Settings;
        _hint.Text = Slot == 0
            ? L.Get("settings.area.subtitleHint")
            : ShortcutText.ForSentence(L.Catalog, "settings.area.extraHint", s.Hotkeys, AreaAction(Slot));
    }

    void UpdateTexts()
    {
        var s = C.Settings;
        var h = s.Hotkeys;
        _refresh!.Content = L.Format("settings.area.refreshPicture", ShortcutText.ForTitle(L.Catalog, h, HotkeyAction.Snapshot));
        _screenCard!.Header = L.Format("settings.area.translateScreenTitle", ShortcutText.ForTitle(L.Catalog, h, HotkeyAction.Screen));
        _screenHint!.Text = ShortcutText.ForSentence(L.Catalog, "settings.area.translateScreenHint", h, HotkeyAction.Screen);
        _freeCard!.Header = L.Format("settings.area.freeAreaTitle", ShortcutText.ForTitle(L.Catalog, h, HotkeyAction.FreeArea));
        _freeHint!.Text = ShortcutText.ForSentence(L.Catalog, "settings.area.freeAreaHint", h, HotkeyAction.FreeArea);
        _pauseHint!.Text = ShortcutText.ForSentence(L.Catalog, "settings.area.pauseHint", h, HotkeyAction.PauseSubtitles);
        Guard.Run(() => _freeTarget!.Selected = TargetIndex(s.FreeAreaTarget));
        UpdateHint();
    }

    public override void ControllerChanged(string property)
    {
        if (property == nameof(NinoController.Settings)) UpdateTexts();
    }

    /// <summary>Son kare değişti: bu bölüm seçiliyse, sürüklenmiyorsa ve 1 sn geçtiyse önizleme yenilenir.</summary>
    public void FrameArrived()
    {
        if (!IsBuilt || _picker is null || !Host.IsCurrent(this) || _picker.IsDragging) return;
        if ((DateTime.UtcNow - _lastPicture).TotalMilliseconds < 1000) return;
        RefreshPictureNow();
    }

    /// <summary>Önizleme hemen son kareyle yenilenir (çerçeve olduğu gibi kalır).</summary>
    public void RefreshPictureNow()
    {
        if (_picker is null) return;
        _lastPicture = DateTime.UtcNow;
        _picker.SetFrame(C.LastFrame);
    }
}
