// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows;
using System.Windows.Controls;
using Nino.App.Controls;
using Nino.App.Strings;
using Nino.Core.Settings;
using Nino.Core.Translation;
using Nino.Shell;
using Nino.Shell.Panels;
using Nino.Translation.Online;

namespace Nino.App.Views;

/// <summary>
/// Çeviri (Mac'le aynı sıra): "Nino Game Translator Kütüphanesi Aktif" kartı (Nino robotu + kütüphanedeki oyunlar),
/// dil kartı, Windows'a özgü ücretsiz çeviri aygıtı kartı (CPU/GPU, iş parçacığı) ve en altta API anahtarları
/// akordiyonu (Gemini, DeepL, OpenAI, Claude, yerel model; aynı anda bir satır açık). "Gelişmiş" kartı yok.
/// </summary>
internal sealed class TranslationSection(SettingsWindow host) : SettingsSection(host)
{
    static readonly string[] Sources = ["en", "ja", "de", "fr", "es"];

    readonly StackPanel _library = new();
    readonly StackPanel _device = new();
    readonly StackPanel _api = new();
    readonly Dictionary<OnlineEngine, (string Key, object[] Args, bool Error)> _results = [];
    readonly HashSet<OnlineEngine> _testing = [];
    TextBlock? _nonTurkish;
    OnlineEngine? _open;
    bool _localAdvanced;
    int _render;

    public override SettingsPage Page => SettingsPage.Translation;

    protected override void Build()
    {
        AddHeader();
        AddCard(new Card { Content = _library });
        RenderLibrary();
        AddCard(Ui.Card(null, LanguageRows()));
        AddCard(Ui.Card(L.Get("setup.better.deviceTitle"), _device));
        RenderDevice();
        AddCard(Ui.Card(L.Get("settings.api.title"), _api));
        RenderApi();
    }

    // ---- Kütüphane kartı ----

    void RenderLibrary()
    {
        _library.Children.Clear();
        var bot = new NinoBot { Width = 72, Height = 84, Blinks = false, Floats = false, VerticalAlignment = VerticalAlignment.Center };
        var text = new StackPanel { Margin = new(16, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
        var check = Ui.Icon(Glyphs.CompletedSolid, 16, "successBrush").At(0, 0, 6, 0);
        check.VerticalAlignment = VerticalAlignment.Center;
        text.Children.Add(Ui.Row(check, Ui.Headline(L.Get("settings.library.title"))));
        text.Children.Add(Ui.Hint(L.Get("settings.library.detail")).At(0, 6, 0, 0));
        var (shown, more) = SettingsLibrary.Shown(SettingsLibrary.GameNames(C.Packs));
        var games = new StackPanel { Margin = new(0, 4, 0, 0) };
        foreach (var name in shown)
        {
            var icon = Ui.Icon(Glyphs.Game, 11, "accentTextBrush").At(0, 0, 8, 0);
            icon.VerticalAlignment = VerticalAlignment.Center;
            var label = Ui.Hint(name);
            label.FontWeight = FontWeights.SemiBold;
            label.Fg("textPrimaryBrush");
            games.Children.Add(Ui.Row(icon, label).At(0, 2, 0, 2));
        }
        if (more > 0) games.Children.Add(Ui.Hint(L.Format("settings.library.more", more)));
        text.Children.Add(games);
        if (C.PlayingGame is { Length: > 0 } game)
        {
            var now = Ui.Hint(L.Format("settings.library.now", game)).At(0, 6, 0, 0);
            now.FontWeight = FontWeights.SemiBold;
            now.Fg("accentTextBrush");
            text.Children.Add(now);
        }
        var row = new DockPanel();
        DockPanel.SetDock(bot, Dock.Left);
        row.Children.Add(bot);
        row.Children.Add(text);
        _library.Children.Add(row);
    }

    // ---- Dil kartı ----

    FrameworkElement LanguageRows()
    {
        var s = C.Settings;
        var body = new StackPanel();
        var game = Ui.Combo(200);
        foreach (var code in Sources.Where(C.CanTranslateFrom))
            game.Items.Add(Ui.Item(code, L.Get("settings.translation.lang." + code)));
        game.SelectTag(TargetLanguages.Code(s.SourceLanguage));
        if (game.SelectedIndex < 0 && game.Items.Count > 0) game.SelectedIndex = 0;
        game.SelectionChanged += (_, _) =>
        {
            if (game.SelectedTag() is string code) Write(x => x.SourceLanguage = code);
            RenderApi();
        };
        body.Children.Add(PickerRow(L.Get("settings.translation.gameLanguage"), game).At(0, 0, 0, 12));

        var target = Ui.Combo(200);
        var label = new FrameworkElementFactory(typeof(LanguageLabel));
        label.SetBinding(LanguageLabel.CodeProperty, new System.Windows.Data.Binding());
        target.ItemTemplate = new DataTemplate { VisualTree = label };
        foreach (var language in TargetLanguages.All) target.Items.Add(language.Code);
        target.SelectedItem = TargetLanguages.Find(s.TargetLanguage)?.Code ?? "tr";
        target.SelectionChanged += (_, _) =>
        {
            if (target.SelectedItem is not string code) return;
            Write(x => x.TargetLanguage = code);
            UpdateLanguageHint();
        };
        body.Children.Add(PickerRow(L.Get("settings.translation.targetLanguage"), target));
        _nonTurkish = Ui.Hint(L.Get("settings.language.nonTurkishHint")).At(0, 12, 0, 0);
        body.Children.Add(_nonTurkish);
        UpdateLanguageHint();
        return body;
    }

    static Grid PickerRow(string title, FrameworkElement picker)
    {
        var text = Ui.Body(title);
        text.VerticalAlignment = VerticalAlignment.Center;
        picker.VerticalAlignment = VerticalAlignment.Center;
        return Ui.Split(text, picker);
    }

    void UpdateLanguageHint() => _nonTurkish?.Shown(TargetLanguages.Code(C.Settings.TargetLanguage) != "tr");

    // ---- Cihaz içi çevirinin aygıtı (Windows'a özgü) ----

    void RenderDevice() => Guard.Run(() =>
    {
        var s = C.Settings;
        _device.Children.Clear();
        var device = Ui.Combo(200);
        device.Items.Add(Ui.Item(TranslationDevice.Cpu, L.Get("setup.better.deviceCpu")));
        device.Items.Add(Ui.Item(TranslationDevice.Gpu, L.Get("setup.better.deviceGpu")));
        device.SelectTag(s.TranslationDevice);
        device.SelectionChanged += (_, _) =>
        {
            if (Guard.Busy || device.SelectedTag() is not TranslationDevice d) return;
            Write(x => x.TranslationDevice = d);
            RenderDevice();
        };
        _device.Children.Add(device);
        device.HorizontalAlignment = HorizontalAlignment.Left;
        if (s.TranslationDevice == TranslationDevice.Cpu)
        {
            var cpus = Environment.ProcessorCount;
            var threads = Ui.Combo(120);
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
            _device.Children.Add(PickerRow(L.Get("settings.translation.cpuThreads"), threads).At(0, 12, 0, 0));
            _device.Children.Add(warning);
        }
        _device.Children.Add(Ui.Hint(L.Get("settings.translation.deviceHint")).At(0, 8, 0, 0));
        if (C.GpuFellBack) _device.Children.Add(Ui.Error(L.Get("settings.translation.gpuFallback")).At(0, 8, 0, 0));
    });

    // ---- API anahtarları ----

    void RenderApi() => Guard.Run(() =>
    {
        _render++;
        _api.Children.Clear();
        _api.Children.Add(Ui.Hint(L.Get("settings.api.message")));
        if (TargetLanguages.Code(C.Settings.SourceLanguage) != "en")
            _api.Children.Add(Ui.Hint(L.Get("settings.translation.englishOnly")).At(0, 8, 0, 0));
        var rows = new StackPanel { Margin = new(0, 8, 0, 0) };
        for (var i = 0; i < ApiProviders.Order.Count; i++)
        {
            if (i > 0) rows.Children.Add(new Separator());
            rows.Children.Add(ProviderRow(ApiProviders.Order[i]));
        }
        _api.Children.Add(rows);
    });

    ApiProviderState StateOf(OnlineEngine engine) =>
        ApiProviders.State(engine, SettingsRules.SelectedEngine(C.Settings), C.HasKey(engine));

    FrameworkElement ProviderRow(OnlineEngine engine)
    {
        var state = StateOf(engine);
        var open = _open == engine;
        var name = Ui.Headline(engine == OnlineEngine.Local ? L.Get("settings.translation.localName") : ApiProviders.Brand(engine));
        name.VerticalAlignment = VerticalAlignment.Center;
        var dot = new StatusDot { Tone = ApiProviders.Tone(state), VerticalAlignment = VerticalAlignment.Center };
        var status = Ui.Hint(L.Get(ApiProviders.StatusKey(state))).At(6, 0, 6, 0);
        status.VerticalAlignment = VerticalAlignment.Center;
        var chevron = Ui.Icon(open ? "" : Glyphs.ChevronDown, 10);
        chevron.VerticalAlignment = VerticalAlignment.Center;
        var header = Ui.Split(name, Ui.Row(dot, status, chevron));
        var button = new Button { Content = header }.Styled("Settings.PlainRow");
        AutomationNames.Set(button, name.Text);
        button.Click += (_, _) =>
        {
            _open = ApiProviders.Toggle(_open, engine);
            RenderApi();
        };
        var panel = new StackPanel();
        panel.Children.Add(button);
        if (open)
        {
            var body = new StackPanel { Margin = new(0, 0, 0, 12) };
            switch (engine)
            {
                case OnlineEngine.DeepL: DeepLFields(body); break;
                case OnlineEngine.Local: LocalFields(body); break;
                default:
                    AiFields(body, engine);
                    if (engine == OnlineEngine.Gemini)
                        body.Children.Add(Ui.Hint(L.Get("settings.translation.geminiPrivacy")).At(0, 8, 0, 0));
                    break;
            }
            switch (ApiProviders.Action(engine, state))
            {
                case ApiProviderAction.Use:
                    var use = Ui.Primary(L.Get("settings.api.use"), () =>
                    {
                        Write(s => ApiProviders.Choose(s, engine));
                        RenderApi();
                    }).At(0, 12, 0, 0);
                    use.HorizontalAlignment = HorizontalAlignment.Left;
                    use.IsEnabled = ApiProviders.CanUse(engine, C.Settings);
                    body.Children.Add(use);
                    break;
                case ApiProviderAction.Stop:
                    var stop = Ui.Button(L.Get("settings.api.stop"), () =>
                    {
                        Write(s => ApiProviders.Choose(s, null));
                        RenderApi();
                    }).At(0, 12, 0, 0);
                    stop.HorizontalAlignment = HorizontalAlignment.Left;
                    body.Children.Add(stop);
                    break;
            }
            panel.Children.Add(body);
        }
        return panel;
    }

    static AiService ServiceOf(OnlineEngine e) => e switch
    {
        OnlineEngine.Gemini => AiService.Gemini,
        OnlineEngine.OpenAi => AiService.OpenAi,
        OnlineEngine.Claude => AiService.Claude,
        _ => AiService.Local,
    };

    void AddResult(StackPanel into, OnlineEngine engine)
    {
        if (!_results.TryGetValue(engine, out var r)) return;
        var text = L.Format(r.Key, r.Args);
        into.Children.Add((r.Error ? Ui.Error(text) : Ui.Hint(text)).At(0, 8, 0, 0));
    }

    /// <summary>Kayıtlı anahtar satırı: "Anahtar saklandı" + Dene + Anahtarı Kaldır.</summary>
    FrameworkElement SavedRow(OnlineEngine engine, Func<Task> test)
    {
        var saved = Ui.Success(L.Get("settings.key.saved"));
        saved.VerticalAlignment = VerticalAlignment.Center;
        var testing = _testing.Contains(engine);
        var tryIt = Ui.Button(L.Get(testing ? "settings.key.testing" : "settings.key.test"), () => _ = test());
        tryIt.IsEnabled = !testing;
        var remove = Ui.Button(L.Get("settings.key.remove"), () =>
        {
            C.RemoveKey(engine);
            _results.Remove(engine);
            RenderApi();
        }).At(8, 0, 0, 0);
        return Ui.Split(saved, Ui.Row(tryIt, remove));
    }

    /// <summary>Anahtar alanı + "Kaydet ve Sına" ve altında anahtar edinme bağlantısı.</summary>
    FrameworkElement EntryRow(OnlineEngine engine, string placeholder, Func<string, Task> save)
    {
        var box = Ui.Secret(0);
        box.Width = double.NaN;
        var testing = _testing.Contains(engine);
        var button = Ui.Button(L.Get(testing ? "settings.key.testing" : "settings.key.saveAndTest"));
        button.IsEnabled = false;
        void Submit()
        {
            var key = box.Password.Trim();
            if (key.Length == 0 || _testing.Contains(engine)) return;
            _ = save(key);
        }
        button.Click += (_, _) => Submit();
        box.PasswordChanged += (_, _) => button.IsEnabled = box.Password.Trim().Length > 0 && !testing;
        box.Tag = (Action)Submit;
        return Ui.Split(Ui.SecretWithPlaceholder(box, placeholder), button, 8);
    }

    async Task RunAsync(OnlineEngine engine, Func<Task<KeyCheckStatus>> work, Func<KeyCheckStatus, string?>? sample = null)
    {
        _testing.Add(engine);
        _results.Remove(engine);
        RenderApi();
        KeyCheckStatus status;
        try { status = await work(); }
        catch (Exception) { status = KeyCheckStatus.Unreachable; }
        _testing.Remove(engine);
        _results[engine] = ApiProviders.Result(engine, status, C.Settings, sample?.Invoke(status));
        RenderApi();
    }

    void AiFields(StackPanel body, OnlineEngine engine)
    {
        if (C.HasKey(engine)) body.Children.Add(SavedRow(engine, () => RunAsync(engine, () => C.CheckAiKeyAsync(engine))));
        else
        {
            body.Children.Add(EntryRow(engine, L.Get("settings.key.placeholder"), key => RunAsync(engine, () => C.SaveAiKeyAsync(engine, key))));
            body.Children.Add(Ui.Link(L.Format("settings.key.getKey", ApiProviders.Brand(engine)),
                OnlineFailureText.KeyPage(ServiceOf(engine))).At(0, 8, 0, 0));
        }
        AddResult(body, engine);

        var service = ServiceOf(engine);
        var models = Ui.Combo(220);
        var list = AiModelCatalog.Default.Models(service);
        for (var i = 0; i < list.Count; i++)
            models.Items.Add(Ui.Item(list[i].Id, L.Get(i == 0 ? "settings.key.model.fast" : "settings.key.model.quality")));
        var s = C.Settings;
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
        body.Children.Add(PickerRow(L.Get("settings.key.model"), models).At(0, 12, 0, 0));
    }

    void DeepLFields(StackPanel body)
    {
        const string page = "https://www.deepl.com/pro-api";
        if (C.HasKey(OnlineEngine.DeepL))
        {
            body.Children.Add(SavedRow(OnlineEngine.DeepL, () => DeepLUsageAsync(_render)));
            if (!_results.ContainsKey(OnlineEngine.DeepL) && !_testing.Contains(OnlineEngine.DeepL))
                Dispatcher.BeginInvoke(() => _ = DeepLUsageAsync(_render));
        }
        else
        {
            body.Children.Add(EntryRow(OnlineEngine.DeepL, L.Get("settings.key.deeplPlaceholder"),
                key => RunAsync(OnlineEngine.DeepL, () => C.SaveDeepLKeyAsync(key))));
            body.Children.Add(Ui.Link(L.Get("settings.key.getDeepL"), page).At(0, 8, 0, 0));
        }
        AddResult(body, OnlineEngine.DeepL);
    }

    async Task DeepLUsageAsync(int render)
    {
        if (_testing.Contains(OnlineEngine.DeepL)) return;
        _testing.Add(OnlineEngine.DeepL);
        if (render == _render) RenderApi();
        DeepLUsageResult? usage = null;
        try { usage = await C.DeepLUsageAsync(); }
        catch (Exception) { }
        _testing.Remove(OnlineEngine.DeepL);
        if (usage is { Status: KeyCheckStatus.Valid, Used: { } used, Limit: { } limit })
            _results[OnlineEngine.DeepL] = ("settings.deepl.usage",
                [SettingsPanelRules.Thousands(used, L.Catalog.Culture), SettingsPanelRules.Thousands(limit, L.Catalog.Culture)], false);
        else _results[OnlineEngine.DeepL] = ApiProviders.Result(OnlineEngine.DeepL, usage?.Status ?? KeyCheckStatus.Unreachable, C.Settings);
        RenderApi();
    }

    void LocalFields(StackPanel body)
    {
        var s = C.Settings;
        var valid = LocalServer.NormalizeAddress(s.LocalAiBaseUrl) is not null;
        var testing = _testing.Contains(OnlineEngine.Local);
        PasswordBox? keyBox = null;
        var test = Ui.Button(L.Get(testing ? "settings.key.testing" : "settings.local.test"), () =>
        {
            var typed = keyBox?.Password.Trim();
            _ = RunAsync(OnlineEngine.Local, () => C.TryLocalServerAsync(typed is { Length: > 0 } ? typed : null));
        });
        test.HorizontalAlignment = HorizontalAlignment.Left;
        test.IsEnabled = !testing && valid;
        body.Children.Add(test);
        AddResult(body, OnlineEngine.Local);

        // Sunucu ayarları (açılır grup).
        var toggle = new Button
        {
            Content = Ui.Row(Ui.Icon(_localAdvanced ? Glyphs.ChevronDown : "", 10).At(0, 0, 6, 0),
                Ui.Caption(L.Get("settings.local.server")).Fg("textSecondaryBrush")),
        }.Styled("Settings.PlainRow");
        toggle.Margin = new(0, 8, 0, 0);
        toggle.Click += (_, _) =>
        {
            _localAdvanced = !_localAdvanced;
            RenderApi();
        };
        body.Children.Add(toggle);
        if (!_localAdvanced) return;

        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.RowDefinitions.Add(new RowDefinition());
        grid.RowDefinitions.Add(new RowDefinition());
        var address = new TextBox { Text = s.LocalAiBaseUrl, Margin = new(0, 0, 0, 8), FontFamily = new System.Windows.Media.FontFamily("Consolas") };
        var model = new TextBox { Text = s.LocalAiModel, FontFamily = new System.Windows.Media.FontFamily("Consolas") };
        AddGrid(grid, Ui.Body(L.Get("settings.local.address")).At(0, 0, 12, 8), 0, 0);
        AddGrid(grid, Ui.WithPlaceholder(address, LocalServer.OllamaUrl, top: false), 0, 1);
        AddGrid(grid, Ui.Body(L.Get("settings.local.modelName")).At(0, 0, 12, 0), 1, 0);
        AddGrid(grid, Ui.WithPlaceholder(model, SettingsRules.DefaultLocalModel, top: false), 1, 1);
        body.Children.Add(grid);
        void Commit()
        {
            var a = address.Text.Trim();
            var m = model.Text.Trim();
            var now = C.Settings;
            if ((a.Length == 0 || a == now.LocalAiBaseUrl) && (m.Length == 0 || m == now.LocalAiModel)) return;
            Write(x =>
            {
                if (a.Length > 0) x.LocalAiBaseUrl = a;
                if (m.Length > 0) x.LocalAiModel = m;
            });
            _results.Remove(OnlineEngine.Local);
            Dispatcher.BeginInvoke(RenderApi);
        }
        address.Tag = (Action)Commit;
        model.Tag = (Action)Commit;
        address.LostFocus += (_, _) => Commit();
        model.LostFocus += (_, _) => Commit();
        var ollama = Ui.Button(L.Get("settings.local.useOllama"), () =>
        {
            address.Text = LocalServer.OllamaUrl;
            Commit();
        });
        var lmStudio = Ui.Button(L.Get("settings.local.useLMStudio"), () =>
        {
            address.Text = LocalServer.LmStudioUrl;
            Commit();
        }).At(8, 0, 0, 0);
        body.Children.Add(Ui.Row(ollama, lmStudio).At(0, 8, 0, 0));
        if (!valid) body.Children.Add(Ui.Error(L.Format("settings.local.badAddress", LocalServer.OllamaUrl)).At(0, 8, 0, 0));
        body.Children.Add(Ui.Hint(L.Get("settings.local.nameHint")).At(0, 8, 0, 0));
        body.Children.Add(Ui.Link(L.Get("settings.local.download"), "https://ollama.com/download").At(0, 8, 0, 0));
        if (C.HasKey(OnlineEngine.Local))
        {
            var saved = Ui.Success(L.Get("settings.key.saved"));
            saved.VerticalAlignment = VerticalAlignment.Center;
            body.Children.Add(Ui.Split(saved, Ui.Button(L.Get("settings.key.remove"), () =>
            {
                C.RemoveKey(OnlineEngine.Local);
                RenderApi();
            })).At(0, 8, 0, 0));
        }
        else
        {
            keyBox = Ui.Secret(0);
            keyBox.Width = double.NaN;
            body.Children.Add(Ui.SecretWithPlaceholder(keyBox, L.Get("settings.local.keyPlaceholder")).At(0, 8, 0, 0));
        }
    }

    static void AddGrid(Grid grid, FrameworkElement element, int row, int column)
    {
        element.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetRow(element, row);
        Grid.SetColumn(element, column);
        grid.Children.Add(element);
    }

    public override void ControllerChanged(string property)
    {
        switch (property)
        {
            case nameof(NinoController.GpuFellBack):
                RenderDevice();
                break;
            case nameof(NinoController.Packs) or nameof(NinoController.PlayingGame):
                RenderLibrary();
                break;
            case nameof(NinoController.Settings):
                UpdateLanguageHint();
                if (!_api.IsKeyboardFocusWithin) RenderApi();
                break;
        }
    }
}
