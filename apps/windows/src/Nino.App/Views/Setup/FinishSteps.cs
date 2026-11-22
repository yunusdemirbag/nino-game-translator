// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows;
using System.Windows.Controls;
using Nino.App.Controls;
using Nino.App.Strings;
using Nino.Core.Settings;
using Nino.Shell;
using Nino.Translation.Online;

namespace Nino.App.Views.Setup;

/// <summary>Model indirme adımı (kurulum.md §9).</summary>
internal sealed class ModelStep : StepPage
{
    readonly StackPanel _downloading;
    readonly ProgressBar _progress = new() { Minimum = 0, Maximum = 1 };
    readonly TextBlock _ready = SetupUi.Key("setup.model.ready", "Text.Success");
    readonly StackPanel _failed;

    public ModelStep(NinoController controller) : base(controller)
    {
        _downloading = SetupUi.Stack(SetupUi.Key("home.card.model.downloading", "Text.Callout", SetupUi.Bottom(8)), _progress);
        _failed = SetupUi.Stack(SetupUi.Key("setup.model.downloadFailed", "Text.Error", SetupUi.Bottom(12)),
            SetupUi.Button(L.Get("common.retry"), ButtonKind.Primary, (_, _) => C.StartModelDownload()));
        Layout(L.Get("setup.model.title"), L.Get("setup.model.description"), SetupUi.Stack(_downloading, _ready, _failed));
        Render();
    }

    protected override void OnFirstShown()
    {
        C.StartModelDownload();
        Render();
    }

    protected override void OnChanged(string property)
    {
        if (property is nameof(NinoController.ModelDownloading) or nameof(NinoController.ModelProgress)
            or nameof(NinoController.ModelInstalled) or nameof(NinoController.ModelError))
            Render();
    }

    void Render()
    {
        var downloading = C.ModelDownloading;
        SetupUi.Show(_downloading, downloading);
        _progress.Value = Math.Clamp(C.ModelProgress, 0, 1);
        SetupUi.Show(_ready, !downloading && C.ModelInstalled);
        SetupUi.Show(_failed, !downloading && !C.ModelInstalled && C.ModelError is not null);
    }
}

/// <summary>Deneyelim (kurulum.md §10): deneme altyazısı, "görüyor musunuz", ilerlemenin tek yolu "Evet".</summary>
internal sealed class TestStep : StepPage
{
    readonly Button _send;
    readonly Card _question;
    readonly Button _yes;

    public TestStep(NinoController controller) : base(controller)
    {
        // Altyazı bilgisayar ekranına gidiyorsa ("TV'm yok") metinler değişir.
        var screen = !C.ShowsOnTv;
        _send = SetupUi.Button(L.Get("setup.try.sendSample"), ButtonKind.Primary, (_, _) => Send());
        var adjust = SetupUi.Button(L.Get("setup.try.adjustWindow"), ButtonKind.Secondary, (_, _) => C.AdjustMode = true,
            SetupUi.M(12, 0, 0, 0));
        SetupUi.Show(adjust, screen);
        _yes = SetupUi.Button(L.Get("setup.try.yesISeeIt"), ButtonKind.Primary, (_, _) =>
        {
            C.AdjustMode = false;
            C.Advance();
        });
        var no = SetupUi.Button(L.Get("common.no"), ButtonKind.Secondary, (_, _) => C.GoToStep(SetupStep.Tv), SetupUi.M(12, 0, 0, 0));
        _question = SetupUi.Card(SetupUi.Stack(SetupUi.Row(_yes, no),
            SetupUi.Key(screen ? "setup.try.notSeenScreen" : "setup.try.notSeenTv", "Text.Callout", SetupUi.Top(12))),
            L.Get(screen ? "setup.try.questionScreen" : "setup.try.questionTv"), SetupUi.Top(20));
        _question.Visibility = Visibility.Collapsed;
        Layout(L.Get("setup.try.title"), L.Get(screen ? "setup.try.descriptionScreen" : "setup.try.descriptionTv"),
            SetupUi.Stack(SetupUi.Row(_send, adjust), _question, SetupUi.Key("setup.try.poolHint", "Text.Callout", SetupUi.Top(20))));
    }

    void Send()
    {
        Fire.AndForget(() => C.SendTestSubtitleAsync());
        SetupUi.SetKind(_send, ButtonKind.Secondary);
        SetupUi.Show(_question, true);
        _yes.IsDefault = true;
    }
}

/// <summary>Daha doğal çeviri (kurulum.md §11): ücretsiz çeviri aygıtı ve isteğe bağlı ücretsiz Gemini anahtarı.</summary>
internal sealed class BetterTranslationStep : StepPage
{
    readonly ComboBox _device = new() { Width = 240, HorizontalAlignment = HorizontalAlignment.Left };
    readonly TextBlock _gpuFallback = SetupUi.Key("setup.better.gpuFallback", "Text.Callout", SetupUi.Top(8));
    readonly TextBlock _ready = SetupUi.Key("setup.better.geminiReady", "Text.Success", SetupUi.M(0, 16, 0, 16));
    readonly StackPanel _newKey;
    readonly PasswordBox _key = new() { Width = 320, VerticalAlignment = VerticalAlignment.Center };
    readonly Button _save;
    readonly TextBlock _status = SetupUi.Text("", "Text.Callout", SetupUi.Top(12));
    readonly TextBlock _error = SetupUi.Text("", "Text.Error", SetupUi.Top(12));
    bool _testing;
    bool _syncing;

    public BetterTranslationStep(NinoController controller) : base(controller)
    {
        _device.Items.Add(new ComboBoxItem { Content = L.Get("setup.better.deviceCpu"), Tag = TranslationDevice.Cpu });
        _device.Items.Add(new ComboBoxItem { Content = L.Get("setup.better.deviceGpu"), Tag = TranslationDevice.Gpu });
        _device.SelectionChanged += (_, _) => DeviceChosen();
        _gpuFallback.SetResourceReference(TextBlock.ForegroundProperty, "warningBrush");
        var deviceCard = SetupUi.Card(SetupUi.Stack(
            SetupUi.Key("setup.better.deviceTitle", "Text.Headline", SetupUi.Bottom(8)),
            _device,
            SetupUi.Key("setup.better.deviceHint", "Text.Callout", SetupUi.Top(8)),
            _gpuFallback));

        _save = SetupUi.Button(L.Get("setup.better.saveAndTest"), ButtonKind.Secondary, (_, _) => Fire.AndForget(SaveAsync),
            SetupUi.M(12, 0, 0, 0));
        _save.VerticalAlignment = VerticalAlignment.Center;
        _key.PasswordChanged += (_, _) => UpdateSave();
        SetupUi.OnEnter(_key, () =>
        {
            if (_save.IsEnabled) Fire.AndForget(SaveAsync);
        });
        var keyRow = SetupUi.Row(_key, _save);
        keyRow.Margin = SetupUi.Top(16);
        var steps = SetupUi.Card(SetupUi.Stack(
            SetupUi.Numbered(1, L.Get("setup.better.step1")),
            SetupUi.Numbered(2, L.Get("setup.better.step2")),
            SetupUi.Numbered(3, L.Get("setup.better.step3")),
            SetupUi.Button(L.Get("setup.better.getFreeKey"), ButtonKind.Primary, (_, _) => C.GetFreeGeminiKey(), SetupUi.Top(8))));
        _newKey = SetupUi.Stack(steps, keyRow);

        SetupUi.SetText(_status, null);
        SetupUi.SetText(_error, null);
        Layout(L.Get("setup.better.title"), L.Get("setup.better.description"), SetupUi.Stack(
            deviceCard, _ready, _newKey, _status, _error,
            SetupUi.Key("setup.better.privacyHint", "Text.Callout", SetupUi.Top(16)),
            SetupUi.Key("setup.better.limitHint", "Text.Callout", SetupUi.Top(8))));
        SyncDevice();
        RenderSections();
        UpdateSave();
    }

    protected override void OnChanged(string property)
    {
        if (property is nameof(NinoController.UsingFreeGemini)) RenderSections();
        if (property is nameof(NinoController.GpuFellBack)) SetupUi.Show(_gpuFallback, C.GpuFellBack);
        if (property == nameof(NinoController.Settings)) SyncDevice();
    }

    void SyncDevice()
    {
        _syncing = true;
        try
        {
            var device = C.Settings.TranslationDevice;
            foreach (ComboBoxItem item in _device.Items)
                if (item.Tag is TranslationDevice d && d == device) _device.SelectedItem = item;
            SetupUi.Show(_gpuFallback, C.GpuFellBack);
        }
        finally { _syncing = false; }
    }

    void DeviceChosen()
    {
        if (_syncing || _device.SelectedItem is not ComboBoxItem { Tag: TranslationDevice device }) return;
        var settings = C.Settings;
        if (settings.TranslationDevice == device) return;
        settings.TranslationDevice = device;
        C.UpdateSettings(settings);
    }

    void RenderSections()
    {
        SetupUi.Show(_ready, C.UsingFreeGemini);
        SetupUi.Show(_newKey, !C.UsingFreeGemini);
    }

    void UpdateSave() => _save.IsEnabled = !_testing && _key.Password.Trim().Length > 0;

    async Task SaveAsync()
    {
        if (_testing) return;
        _testing = true;
        _save.Content = L.Get("setup.better.testing");
        UpdateSave();
        SetupUi.SetText(_status, null);
        SetupUi.SetText(_error, null);
        try
        {
            var status = await C.SaveAiKeyAsync(OnlineEngine.Gemini, _key.Password);
            if (status is KeyCheckStatus.Valid or KeyCheckStatus.QuotaExhausted or KeyCheckStatus.ModelRejected) _key.Clear();
            // Denetleyici örnek çeviriyi vermiyor: örnek yeri boş kalır (tarif: "örnek yoksa boş").
            if (status == KeyCheckStatus.Valid) SetupUi.SetText(_status, L.Format("setup.better.workingSample", ""));
            else SetupUi.SetText(_error, C.DescribeKeyCheck(status));
            RenderSections();
        }
        catch (Exception e)
        {
            SetupUi.SetText(_error, e.Message);
        }
        finally
        {
            _testing = false;
            _save.Content = L.Get("setup.better.saveAndTest");
            UpdateSave();
        }
    }
}
