// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows;
using System.Windows.Controls;
using Nino.App.Strings;
using Nino.Core.Settings;
using Nino.Core.Translation;
using Nino.Shell;
using Nino.Shell.Panels;
using Nino.Translation.Online;

namespace Nino.App.Views;

/// <summary>§5 Çeviri: motor, ücretsiz çeviri aygıtı, CPU iş parçacıkları, anahtar bölmesi ve Gelişmiş kartı.</summary>
internal sealed class TranslationSection(SettingsWindow host) : SettingsSection(host)
{
    const string OllamaDownload = "https://ollama.com/download";
    const string DeepLKeyPage = "https://www.deepl.com/pro-api";

    ComboBox? _engine;
    readonly StackPanel _engineBody = new();
    readonly StackPanel _keyPane = new() { Margin = new(0, 12, 0, 0) };
    TextBlock? _status;
    TextBlock? _error;
    Slider? _misread;
    Slider? _partial;
    int _render;

    public override string SectionTitle => L.Get("home.footer.translation");

    OnlineEngine Engine => SettingsRules.SelectedEngine(C.Settings);

    protected override void Build()
    {
        AddHeader();
        var card = new StackPanel();
        _engine = Ui.Combo(240);
        _engine.Items.Add(Ui.Item(OnlineEngine.Free, L.Get("translation.engine.free")));
        _engine.Items.Add(Ui.Item(OnlineEngine.DeepL, "DeepL"));
        _engine.Items.Add(Ui.Item(OnlineEngine.Gemini, "Google Gemini"));
        _engine.Items.Add(Ui.Item(OnlineEngine.OpenAi, "OpenAI"));
        _engine.Items.Add(Ui.Item(OnlineEngine.Claude, "Anthropic Claude"));
        _engine.Items.Add(Ui.Item(OnlineEngine.Local, L.Get("settings.translation.engine.local")));
        _engine.SelectTag(Engine);
        _engine.SelectionChanged += (_, _) =>
        {
            if (Guard.Busy || _engine.SelectedTag() is not OnlineEngine e) return;
            Write(s =>
            {
                if (e == OnlineEngine.Free) s.OnlineTranslation = false;
                else
                {
                    s.OnlineTranslation = true;
                    s.OnlineEngine = e;
                }
            });
            RenderEngine(clearResult: true);
        };
        card.Children.Add(Ui.Labeled(L.Get("translation.engine.title"), _engine).At(0, 0, 0, 12));
        card.Children.Add(_engineBody);
        AddCard(Ui.Card(null, card));
        AddCard(AdvancedCard());
        RenderEngine(clearResult: true);
    }

    static string EngineHintKey(OnlineEngine e) => e switch
    {
        OnlineEngine.DeepL => "settings.translation.engineHint.deepl",
        OnlineEngine.Gemini => "settings.translation.engineHint.gemini",
        OnlineEngine.OpenAi => "settings.translation.engineHint.openai",
        OnlineEngine.Claude => "settings.translation.engineHint.claude",
        OnlineEngine.Local => "settings.translation.engineHint.local",
        _ => "settings.translation.engineHint.free",
    };

    static AiService ServiceOf(OnlineEngine e) => e switch
    {
        OnlineEngine.Gemini => AiService.Gemini,
        OnlineEngine.OpenAi => AiService.OpenAi,
        OnlineEngine.Claude => AiService.Claude,
        _ => AiService.Local,
    };

    static string Brand(OnlineEngine e) => e switch
    {
        OnlineEngine.Gemini => "Gemini",
        OnlineEngine.OpenAi => "OpenAI",
        OnlineEngine.Claude => "Claude",
        OnlineEngine.DeepL => "DeepL",
        _ => L.Get("status.online.localModelName"),
    };

    void RenderEngine(bool clearResult) => Guard.Run(() =>
    {
        _render++;
        var s = C.Settings;
        var engine = Engine;
        _engineBody.Children.Clear();
        _engineBody.Children.Add(Ui.Hint(L.Get(EngineHintKey(engine))));

        // Ücretsiz çevirinin aygıtı.
        _engineBody.Children.Add(Ui.Body(L.Get("setup.better.deviceTitle")).At(0, 16, 0, 8));
        var device = Ui.Combo(240);
        device.Width = 240;
        device.HorizontalAlignment = HorizontalAlignment.Left;
        device.Items.Add(Ui.Item(TranslationDevice.Cpu, L.Get("setup.better.deviceCpu")));
        device.Items.Add(Ui.Item(TranslationDevice.Gpu, L.Get("setup.better.deviceGpu")));
        device.SelectTag(s.TranslationDevice);
        device.SelectionChanged += (_, _) =>
        {
            if (Guard.Busy || device.SelectedTag() is not TranslationDevice d) return;
            Write(x => x.TranslationDevice = d);
            RenderEngine(clearResult: false);
        };
        _engineBody.Children.Add(device);

        if (s.TranslationDevice == TranslationDevice.Cpu)
        {
            var cpus = Environment.ProcessorCount;
            var pane = new StackPanel { Margin = new(0, 12, 0, 0) };
            pane.Children.Add(Ui.Body(L.Get("settings.translation.cpuThreads")).At(0, 0, 0, 8));
            var threads = Ui.Combo(120);
            threads.MinWidth = 120;
            threads.Width = 120;
            threads.HorizontalAlignment = HorizontalAlignment.Left;
            foreach (var n in SettingsRules.CpuThreadOptions(cpus)) threads.Items.Add(Ui.Item(n, n.ToString(L.Catalog.Culture)));
            var selected = SettingsRules.NormalizeCpuThreads(s.CpuTranslationThreads, cpus);
            threads.SelectTag(selected);
            var warning = Ui.Error(L.Get("settings.translation.cpuThreadsWarning")).At(0, 8, 0, 0)
                .Shown(SettingsRules.CpuThreadsNearCapacity(selected, cpus));
            threads.SelectionChanged += (_, _) =>
            {
                if (Guard.Busy || threads.SelectedTag() is not int n) return;
                warning.Shown(SettingsRules.CpuThreadsNearCapacity(n, cpus));
                Write(x => x.CpuTranslationThreads = n);
            };
            pane.Children.Add(threads);
            pane.Children.Add(warning);
            _engineBody.Children.Add(pane);
        }
        _engineBody.Children.Add(Ui.Hint(L.Get("settings.translation.deviceHint")).At(0, 8, 0, 0));
        if (C.GpuFellBack) _engineBody.Children.Add(Ui.Error(L.Get("settings.translation.gpuFallback")).At(0, 8, 0, 0));
        if (engine != OnlineEngine.Free && TargetLanguages.Code(s.SourceLanguage) != "en")
            _engineBody.Children.Add(Ui.Hint(L.Get("settings.translation.englishOnlyHint")).At(0, 8, 0, 0));

        if (engine == OnlineEngine.Free)
        {
            var offer = Ui.Hint(L.Get("settings.translation.geminiOffer"));
            offer.VerticalAlignment = VerticalAlignment.Center;
            var get = Ui.Button(L.Get("setup.better.getFreeKey"), () =>
            {
                C.GetFreeGeminiKey();
                Guard.Run(() => _engine?.SelectTag(OnlineEngine.Gemini));
                RenderEngine(clearResult: true);
            });
            _engineBody.Children.Add(Ui.Split(offer, get).At(0, 12, 0, 0));
        }
        if (engine == OnlineEngine.Gemini)
        {
            _engineBody.Children.Add(Ui.Hint(L.Get("settings.translation.geminiPrivacy")).At(0, 8, 0, 0));
            _engineBody.Children.Add(Ui.Hint(L.Get("settings.translation.geminiLimit")).At(0, 8, 0, 0));
        }
        if (engine != OnlineEngine.Free)
        {
            RenderKeyPane(engine, clearResult);
            _engineBody.Children.Add(_keyPane);
        }
    });

    void RenderKeyPane(OnlineEngine engine, bool clearResult)
    {
        var keepStatus = clearResult ? null : _status?.Text;
        var keepError = clearResult ? null : _error?.Text;
        var keepStatusShown = !clearResult && _status?.Visibility == Visibility.Visible;
        var keepErrorShown = !clearResult && _error?.Visibility == Visibility.Visible;
        _keyPane.Children.Clear();
        var s = C.Settings;
        var hasKey = C.HasKey(engine);

        if (engine is OnlineEngine.Gemini or OnlineEngine.OpenAi or OnlineEngine.Claude)
        {
            var service = ServiceOf(engine);
            var models = Ui.Combo(240);
            foreach (var m in AiModelCatalog.Default.Models(service)) models.Items.Add(Ui.Item(m.Id, L.Get(m.TextKey)));
            var saved = engine switch
            {
                OnlineEngine.Gemini => s.GeminiModel,
                OnlineEngine.OpenAi => s.OpenAiModel,
                _ => s.ClaudeModel,
            };
            models.SelectTag(AiModelCatalog.Default.Resolve(service, saved)?.Id);
            models.SelectionChanged += (_, _) =>
            {
                if (Guard.Busy || models.SelectedTag() is not string id) return;
                Write(x =>
                {
                    if (engine == OnlineEngine.Gemini) x.GeminiModel = id;
                    else if (engine == OnlineEngine.OpenAi) x.OpenAiModel = id;
                    else x.ClaudeModel = id;
                });
            };
            _keyPane.Children.Add(Ui.Labeled(L.Get("translation.engine.model"), models).At(0, 0, 0, 12));
        }

        Button? saveButton = null;
        Button? testButton = null;
        Func<bool>? addressValid = null;
        Action? saveLocal = null;
        if (engine == OnlineEngine.Local)
        {
            var pane = new StackPanel { Margin = new(0, 0, 0, 12) };
            var grid = new Grid();
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.RowDefinitions.Add(new RowDefinition());
            grid.RowDefinitions.Add(new RowDefinition());
            var address = new TextBox { Text = s.LocalAiBaseUrl, Margin = new(0, 0, 0, 8) };
            var model = new TextBox { Text = s.LocalAiModel };
            AddGrid(grid, Ui.Body(L.Get("translation.local.address")).At(0, 0, 16, 8), 0, 0);
            AddGrid(grid, address, 0, 1);
            AddGrid(grid, Ui.Body(L.Get("translation.local.modelName")).At(0, 0, 16, 0), 1, 0);
            AddGrid(grid, model, 1, 1);
            pane.Children.Add(grid);
            var addressError = Ui.Error(L.Format("settings.translation.addressInvalid", LocalServer.OllamaUrl)).At(0, 8, 0, 0);
            addressValid = () => LocalServer.NormalizeAddress(address.Text) is not null;
            void Validate()
            {
                var ok = addressValid();
                addressError.Shown(!ok);
                if (saveButton is not null) saveButton.IsEnabled = ok;
                if (testButton is not null) testButton.IsEnabled = ok;
            }
            saveLocal = () =>
            {
                var a = address.Text.Trim();
                var m = model.Text.Trim();
                Validate();
                var now = C.Settings;
                if (a == now.LocalAiBaseUrl && m == now.LocalAiModel) return;
                Write(x =>
                {
                    x.LocalAiBaseUrl = a;
                    x.LocalAiModel = m;
                });
                _status?.Shown(false);
                _error?.Shown(false);
            };
            var save = saveLocal;
            address.Tag = save;
            model.Tag = save;
            address.LostFocus += (_, _) => save();
            model.LostFocus += (_, _) => save();
            address.TextChanged += (_, _) => Validate();
            var ollama = Ui.Button(L.Get("settings.translation.useOllama"), () =>
            {
                address.Text = LocalServer.OllamaUrl;
                save();
            });
            var lmStudio = Ui.Button(L.Get("settings.translation.useLmStudio"), () =>
            {
                address.Text = LocalServer.LmStudioUrl;
                save();
            }).At(8, 0, 0, 0);
            pane.Children.Add(Ui.Row(ollama, lmStudio).At(0, 8, 0, 0));
            pane.Children.Add(addressError);
            pane.Children.Add(Ui.Hint(L.Get("settings.translation.localHint")).At(0, 8, 0, 0));
            if (!hasKey) pane.Children.Add(Ui.Body(L.Get("translation.key.optional")).At(0, 12, 0, 0));
            _keyPane.Children.Add(pane);
            addressError.Shown(!addressValid());
        }

        var local = engine == OnlineEngine.Local;
        if (!hasKey)
        {
            var box = Ui.Secret(320);
            AutomationNames.Set(box, L.Get("translation.key.title"));
            var label = L.Get(local ? "translation.local.testConnection" : "setup.better.saveAndTest");
            saveButton = Ui.Button(label).At(12, 0, 0, 0);
            var button = saveButton;
            button.Click += async (_, _) =>
            {
                button.IsEnabled = false;
                if (local)
                {
                    saveLocal?.Invoke();
                    button.Content = L.Get("setup.better.testing");
                }
                var render = _render;
                await SaveAndTestAsync(engine, box.Password, () => box.Clear());
                if (render != _render) return;
                button.Content = label;
                button.IsEnabled = addressValid?.Invoke() ?? true;
            };
            _keyPane.Children.Add(Ui.Row(box, button));
            if (engine is not (OnlineEngine.DeepL or OnlineEngine.Local))
                _keyPane.Children.Add(Ui.Hint(L.Get("settings.translation.noKeyHint")).At(0, 8, 0, 0));
            var link = engine switch
            {
                OnlineEngine.Local => Ui.Link(L.Get("translation.local.downloadOllama"), OllamaDownload),
                OnlineEngine.DeepL => Ui.Link(L.Get("settings.translation.getDeeplKey"), DeepLKeyPage),
                _ => Ui.Link(L.Format("settings.translation.getApiKey", Brand(engine)), OnlineFailureText.KeyPage(ServiceOf(engine))),
            };
            _keyPane.Children.Add(link.At(0, 8, 0, 0));
        }
        else
        {
            var saved = Ui.Success(L.Get("translation.key.saved"));
            saved.VerticalAlignment = VerticalAlignment.Center;
            var right = Ui.Row(Ui.Button(L.Get("settings.translation.removeKey"), () =>
            {
                C.RemoveKey(engine);
                RenderEngine(clearResult: true);
            }).At(8, 0, 0, 0));
            if (engine != OnlineEngine.DeepL)
            {
                var label = L.Get(local ? "translation.local.testConnection" : "settings.translation.test");
                testButton = Ui.Button(label).At(8, 0, 0, 0);
                var button = testButton;
                button.Click += async (_, _) =>
                {
                    if (local) saveLocal?.Invoke();
                    button.IsEnabled = false;
                    button.Content = L.Get("setup.better.testing");
                    var render = _render;
                    var status = local ? await C.TryLocalServerAsync() : await C.CheckAiKeyAsync(engine);
                    if (render != _render) return;
                    ShowResult(engine, status);
                    button.Content = label;
                    button.IsEnabled = addressValid?.Invoke() ?? true;
                };
                right.Children.Add(button);
            }
            var grid = Ui.Split(saved, right, 0);
            _keyPane.Children.Add(grid);
        }
        if (addressValid is not null && !addressValid())
        {
            if (saveButton is not null) saveButton.IsEnabled = false;
            if (testButton is not null) testButton.IsEnabled = false;
        }

        _status = Ui.Hint("").At(0, 8, 0, 0).Shown(keepStatusShown);
        _error = Ui.Error().At(0, 8, 0, 0).Shown(keepErrorShown);
        if (keepStatus is not null) _status.Text = keepStatus;
        if (keepError is not null) _error.Text = keepError;
        _keyPane.Children.Add(_status);
        _keyPane.Children.Add(_error);

        if (engine == OnlineEngine.DeepL && hasKey) _ = ShowDeepLUsageAsync(_render);
    }

    static void AddGrid(Grid grid, FrameworkElement element, int row, int column)
    {
        element.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetRow(element, row);
        Grid.SetColumn(element, column);
        grid.Children.Add(element);
    }

    async Task SaveAndTestAsync(OnlineEngine engine, string key, Action clearBox)
    {
        KeyCheckStatus status;
        if (engine == OnlineEngine.DeepL) status = await C.SaveDeepLKeyAsync(key);
        else if (engine == OnlineEngine.Local) status = await C.TryLocalServerAsync(key);
        else status = await C.SaveAiKeyAsync(engine, key);
        var saved = engine == OnlineEngine.DeepL
            ? status is KeyCheckStatus.Valid or KeyCheckStatus.QuotaExhausted
            : status is KeyCheckStatus.Valid or KeyCheckStatus.QuotaExhausted or KeyCheckStatus.ModelRejected;
        if (saved && (engine != OnlineEngine.Local || key.Trim().Length > 0)) clearBox();
        Guard.Run(() => _engine?.SelectTag(Engine));
        RenderEngine(clearResult: true);
        if (engine == OnlineEngine.DeepL && status == KeyCheckStatus.Valid) return; // kullanım kendiliğinden gösterilir
        ShowResult(engine, status);
    }

    async Task ShowDeepLUsageAsync(int render)
    {
        DeepLUsageResult usage;
        try { usage = await C.DeepLUsageAsync(); }
        catch (Exception) { return; }
        if (render != _render) return;
        if (usage.Status == KeyCheckStatus.Valid && usage.Used is { } used && usage.Limit is { } limit)
            Show(L.Format("settings.translation.result.deeplUsage", SettingsPanelRules.Thousands(used, L.Catalog.Culture),
                SettingsPanelRules.Thousands(limit, L.Catalog.Culture)), error: false);
        else if (usage.Status != KeyCheckStatus.Valid) ShowResult(OnlineEngine.DeepL, usage.Status);
    }

    void ShowResult(OnlineEngine engine, KeyCheckStatus status)
    {
        if (engine == OnlineEngine.DeepL)
        {
            switch (status)
            {
                case KeyCheckStatus.QuotaExhausted: Show(L.Get("settings.translation.result.deeplQuota"), false); break;
                case KeyCheckStatus.InvalidKey: Show(L.Get("settings.translation.result.deeplRejected"), true); break;
                case KeyCheckStatus.Valid: Show(L.Get("status.online.working"), false); break;
                default: Show(L.Get("settings.translation.result.deeplUnreachable"), true); break;
            }
            return;
        }
        if (engine == OnlineEngine.Local)
        {
            var s = C.Settings;
            var server = LocalServer.Create(s.LocalAiBaseUrl, s.LocalAiModel);
            var model = (s.LocalAiModel ?? "").Trim();
            var address = server?.ShortAddress ?? (s.LocalAiBaseUrl ?? "").Trim();
            var kind = server?.Kind ?? LocalServerKind.Other;
            switch (status)
            {
                case KeyCheckStatus.Valid: Show(L.Get("status.online.working"), false); break;
                case KeyCheckStatus.InvalidKey: Show(L.Get("settings.translation.result.localKeyRejected"), true); break;
                case KeyCheckStatus.QuotaExhausted: Show(L.Get("settings.translation.result.localBusy"), true); break;
                case KeyCheckStatus.ModelRejected:
                    Show(kind == LocalServerKind.LmStudio
                        ? L.Format("settings.translation.result.lmStudioNoModel", model)
                        : L.Format("settings.translation.result.localNoModel", model), true);
                    break;
                default:
                    Show(kind switch
                    {
                        LocalServerKind.Ollama => L.Format("settings.translation.result.ollamaUnreachable", address, model),
                        LocalServerKind.LmStudio => L.Format("settings.translation.result.lmStudioUnreachable", address),
                        _ => L.Format("settings.translation.result.localUnreachable", address),
                    }, true);
                    break;
            }
            return;
        }
        var brand = Brand(engine);
        switch (status)
        {
            case KeyCheckStatus.Valid: Show(L.Get("status.online.working"), false); break;
            case KeyCheckStatus.InvalidKey: Show(L.Format("settings.translation.result.aiKeyRejected", brand), true); break;
            case KeyCheckStatus.QuotaExhausted: Show(L.Format("settings.translation.result.aiQuota", brand), true); break;
            case KeyCheckStatus.ModelRejected: Show(L.Format("translation.error.modelRejected", brand), true); break;
            default: Show(L.Format("translation.error.unreachable", brand), true); break;
        }
    }

    void Show(string text, bool error)
    {
        if (_status is null || _error is null) return;
        _status.Text = error ? "" : text;
        _error.Text = error ? text : "";
        _status.Shown(!error);
        _error.Shown(error);
    }

    // ---- Gelişmiş ----

    FrameworkElement AdvancedCard()
    {
        var s = C.Settings;
        var body = new StackPanel();
        var fast = Ui.Toggle(L.Get("settings.translation.fastDetection"));
        fast.IsChecked = s.FastSubtitleDetection;
        fast.Checked += (_, _) => Write(x => x.FastSubtitleDetection = true);
        fast.Unchecked += (_, _) => Write(x => x.FastSubtitleDetection = false);
        body.Children.Add(fast);
        body.Children.Add(Ui.Hint(L.Get("settings.translation.fastDetectionHint")).At(0, 6, 0, 16));
        body.Children.Add(Ui.Hint(L.Get("settings.translation.waitsHint")).At(0, 0, 0, 16));

        _misread = WaitRow(body, "settings.translation.misreadWait", "settings.translation.misreadWaitHint", s.MisreadWaitMs,
            ms => Write(x => x.MisreadWaitMs = ms));
        _partial = WaitRow(body, "settings.translation.partialWait", "settings.translation.partialWaitHint", s.PartialWaitMs,
            ms => Write(x => x.PartialWaitMs = ms));
        body.Children.Add(Ui.Button(L.Get("settings.restoreDefaults"), () =>
        {
            _misread.Value = 0.8;
            _partial.Value = 0.3;
        }));
        return Ui.Card(L.Get("settings.translation.advanced"), body);
    }

    Slider WaitRow(StackPanel into, string labelKey, string hintKey, int ms, Action<int> write)
    {
        into.Children.Add(Ui.Body(L.Get(labelKey)).At(0, 0, 0, 8));
        var row = new SliderRow(null, null, 0, 1, true, 56);
        row.Slider.TickFrequency = 0.1;
        row.Slider.IsSnapToTickEnabled = true;
        row.Slider.SmallChange = 0.1;
        row.Slider.LargeChange = 0.1;
        row.Slider.Margin = new(0, 0, 12, 0);
        row.Slider.Value = Math.Clamp(ms / 1000.0, 0, 1);
        void Label(double v) => row.ValueText!.Text =
            L.Format("settings.translation.waitSeconds", SettingsPanelRules.Seconds(SettingsRules.SecondsToWaitMs(v), L.Catalog.Culture));
        Label(row.Slider.Value);
        row.Slider.ValueChanged += (_, e) =>
        {
            Label(e.NewValue);
            write(SettingsRules.SecondsToWaitMs(e.NewValue));
        };
        into.Children.Add(row);
        into.Children.Add(Ui.Hint(L.Get(hintKey)).At(0, 0, 0, 16));
        return row.Slider;
    }

    public override void ControllerChanged(string property)
    {
        if (property is nameof(NinoController.GpuFellBack)) RenderEngine(clearResult: false);
    }
}
