// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import NinoCore
import SwiftUI

// Çeviri (ayarlar.md §7): kütüphane kartı, dil kartı ve API anahtarları (sağlayıcı akordiyonu).

struct TranslationSettings: View {
    let state: AppState
    let ui: SettingsUIState

    var body: some View {
        VStack(alignment: .leading, spacing: NinoSpacing.m) {
            SettingsLibraryCard(state: state)
            NinoCard { LanguageRows(state: state) }
            ProviderCard(state: state, ui: ui)
        }
    }
}

// MARK: - Kütüphane kartı

/// "Nino Game Translator Kütüphanesi Aktif": kütüphane her zaman açıktır, altında kütüphanedeki oyunlar.
struct SettingsLibraryCard: View {
    let state: AppState
    @Environment(\.locale) private var locale

    static let shownLimit = 8

    var body: some View {
        let names = NinoLibrary.gameNames(state.settingsStatus.gamePacks)
        NinoLibraryCard(title: SettingsText.string("settings.library.title", locale),
                        detail: SettingsText.string("settings.library.detail", locale)) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(names.prefix(Self.shownLimit), id: \.self) { name in
                    HStack(spacing: NinoSpacing.s) {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(NinoColor.accentText)
                            .accessibilityHidden(true)
                        Text(verbatim: name).font(.nino(.callout).weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if names.count > Self.shownLimit {
                    Text(SettingsText.string("settings.library.more %d", locale, names.count - Self.shownLimit))
                        .font(.nino(.callout)).foregroundStyle(NinoColor.textSecondary)
                }
            }
            .padding(.top, 2)
            // Algılanan oyun yalnız bilgi olarak (seçim yok); algılanmadıysa satır yok.
            if let game = state.game {
                Text(SettingsText.string("settings.library.now %@", locale, game.name))
                    .font(.nino(.callout).weight(.semibold))
                    .foregroundStyle(NinoColor.accentText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
    }
}

// MARK: - Dil kartı (§7.1; gizli Dil bölümü de bunu kullanır)

struct LanguageRows: View {
    let state: AppState
    @Environment(\.locale) private var locale

    static let gameLanguages = ["en", "ja", "de", "fr", "es"]

    var body: some View {
        SettingsPickerRow(title: SettingsText.string("settings.translation.gameLanguage", locale),
                          selection: Binding(get: { state.settings.sourceLanguage },
                                             set: { state.settings.sourceLanguage = $0 }),
                          options: Self.gameLanguages.map { ($0, SettingsText.string("settings.translation.lang.\($0)", locale)) })
        SettingsPickerRow(title: SettingsText.string("settings.translation.targetLanguage", locale),
                          selection: Binding(get: { state.settings.targetLanguage },
                                             set: { state.settings.targetLanguage = $0 }),
                          options: MacSettings.targetLanguages.map { ($0, Self.targetLabel($0)) })
        if state.settings.targetLanguage != "tr" {
            SHint("settings.translation.nonTurkishHint")
        }
    }

    /// "bayrak + iki boşluk + dilin kendi adı" (çevrilmez).
    static func targetLabel(_ code: String) -> String {
        let flags = ["tr": "🇹🇷", "ar": "🇸🇦", "hi": "🇮🇳", "id": "🇮🇩", "th": "🇹🇭", "vi": "🇻🇳", "ur": "🇵🇰",
                     "bn": "🇧🇩", "ms": "🇲🇾", "tl": "🇵🇭", "nl": "🇳🇱"]
        let name = TargetLanguage.find(code)?.nativeName ?? code
        return (flags[code] ?? "") + "  " + name
    }
}

// MARK: - API anahtarları (§7.3)

/// Sağlayıcı akordiyonu: her sağlayıcı tek satır (ad + durum noktası), tıklanınca açılır; aynı anda bir tane açık.
/// Anahtar yokken çeviri kütüphane, havuz ve cihaz içi çeviriyle sürer (seçim gerekmez).
struct ProviderCard: View {
    let state: AppState
    let ui: SettingsUIState
    @Environment(\.locale) private var locale

    static let providers: [MacSettings.OnlineEngine] = [.gemini, .deepl, .openai, .claude, .local]

    var body: some View {
        NinoCard(title: SettingsText.string("settings.api.title", locale)) {
            Text(SettingsText.string("settings.api.message", locale))
                .font(.nino(.callout))
                .foregroundStyle(NinoColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if state.settings.sourceLanguage != "en" {
                SHint("settings.translation.englishOnly")
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(Self.providers.enumerated()), id: \.element) { index, engine in
                    if index > 0 { Divider() }
                    ProviderRow(state: state, ui: ui, engine: engine)
                }
            }
        }
    }

    static func brand(_ engine: MacSettings.OnlineEngine) -> String {
        switch engine {
        case .deepl: return "DeepL"
        case .gemini: return "Gemini"
        case .openai: return "OpenAI"
        case .claude: return "Claude"
        case .local: return "Ollama"
        }
    }
}

/// Akordiyonun bir satırı: başlık düğmesi ve açıkken sağlayıcının alanları.
struct ProviderRow: View {
    let state: AppState
    let ui: SettingsUIState
    let engine: MacSettings.OnlineEngine
    @Environment(\.locale) private var locale

    enum Status { case inUse, saved, none, off }

    private var isOpen: Bool { ui.openProvider == engine }
    private var inUse: Bool { SettingsRules.selectedEngine(state.settings) == engine }

    var status: Status {
        if inUse { return .inUse }
        if engine == .local { return .off }
        return state.settingsStatus.savedKeys.contains(engine) ? .saved : .none
    }

    private var name: String {
        engine == .local ? SettingsText.string("settings.translation.localName", locale) : ProviderCard.brand(engine)
    }

    private var statusText: String {
        switch status {
        case .inUse: return SettingsText.string("settings.api.inUse", locale)
        case .saved: return SettingsText.string("settings.api.saved", locale)
        case .none: return SettingsText.string("settings.api.none", locale)
        case .off: return SettingsText.string("settings.api.off", locale)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(NinoMotion.spring(0.3, 0.85)) { ui.openProvider = isOpen ? nil : engine }
            } label: {
                HStack(spacing: NinoSpacing.s) {
                    Text(verbatim: name).font(.nino(.headline)).foregroundStyle(NinoColor.textPrimary)
                    Spacer(minLength: NinoSpacing.s)
                    NinoStatusDot(status == .inUse || status == .saved ? .good : .idle)
                    Text(statusText).font(.nino(.callout)).foregroundStyle(NinoColor.textSecondary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(NinoColor.textSecondary)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                        .padding(.leading, 2)
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityValue(Text(verbatim: isOpen ? "1" : "0"))
            if isOpen {
                VStack(alignment: .leading, spacing: NinoSpacing.m) {
                    fields
                    useButton
                }
                .padding(.bottom, NinoSpacing.m)
                .transition(.opacity)
            }
        }
    }

    @ViewBuilder private var fields: some View {
        switch engine {
        case .gemini:
            AIKeySection(state: state, engine: .gemini)
            SHint("settings.translation.geminiPrivacy")
        case .openai, .claude: AIKeySection(state: state, engine: engine)
        case .deepl: DeepLKeySection(state: state)
        case .local: LocalModelSection(state: state, ui: ui)
        }
    }

    /// Anahtarı kayıtlı ama kullanılmayan sağlayıcıyı (ya da yerel modeli) devreye alır; yerel model bırakılabilir.
    @ViewBuilder private var useButton: some View {
        switch status {
        case .saved, .off:
            Button { state.settings = SettingsRules.choosing(engine: engine, in: state.settings) } label: {
                SText("settings.api.use")
            }
            .buttonStyle(.nino(.primary))
            .disabled(engine == .local && LocalModelServer.normalize(state.settings.localAIBaseURL) == nil)
        case .inUse where engine == .local:
            Button { state.settings = SettingsRules.choosing(engine: nil, in: state.settings) } label: {
                SText("settings.api.stop")
            }
            .buttonStyle(.nino(.secondary))
        case .inUse, .none:
            EmptyView()
        }
    }
}

/// Anahtar edinme bağlantısı; ekran görüntüsünde (Link çizilemez) aynı görünüşte düz yazı.
struct SettingsLink: View {
    let title: String
    let url: URL
    @Environment(\.ninoStaticRendering) private var isStatic

    var body: some View {
        Group {
            if isStatic {
                Text(title).foregroundStyle(NinoColor.accentText)
            } else {
                Link(title, destination: url)
            }
        }
        .font(.nino(.callout).weight(.semibold))
    }
}

// MARK: - Motor hata metinleri (§7.8; ana ekran da kullanır)

public enum SettingsEngineText {
    /// Bir motor hatasının arayüz dilindeki metni.
    public static func failure(_ failure: EngineFailure, engine: MacSettings.OnlineEngine, settings: MacSettings,
                               locale: Locale, now: Date = Date()) -> String {
        let name = ProviderCard.brand(engine)
        let address = settings.localAIBaseURL
        let model = LocalModelServer.modelName(settings.localAIModel)
        switch failure {
        case .badKey: return SettingsText.string("settings.engine.badKey %@", locale, name)
        case .quota:
            if engine == .gemini {
                let reset = SettingsRules.nextPacificMidnight(after: now)
                let time = reset.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale))
                return SettingsText.string("settings.engine.geminiQuota %@", locale, time)
            }
            return SettingsText.string("settings.engine.quota %@", locale, name)
        case .modelRejected: return SettingsText.string("settings.engine.model %@", locale, name)
        case .unreachable: return SettingsText.string("settings.engine.unreachable %@", locale, name)
        case .localBadKey: return SettingsText.string("settings.engine.local.badKey", locale)
        case .localBusy: return SettingsText.string("settings.engine.local.busy", locale)
        case .localModelMissing:
            if SettingsRules.localServerKind(address) == .lmStudio {
                return SettingsText.string("settings.engine.local.missingLMStudio %@", locale, model)
            }
            return SettingsText.string("settings.engine.local.missing %@", locale, model)
        case .localUnreachable:
            switch SettingsRules.localServerKind(address) {
            case .ollama: return SettingsText.string("settings.engine.local.ollamaDown %@ %@", locale, address, model)
            case .lmStudio: return SettingsText.string("settings.engine.local.lmStudioDown %@", locale, address)
            case .other: return SettingsText.string("settings.engine.local.otherDown %@", locale, address)
            }
        }
    }

    /// "Çalışıyor."
    public static func works(locale: Locale) -> String { SettingsText.string("settings.engine.works", locale) }
}

/// Deneme sonucu satırı.
struct EngineTestResult: View {
    let state: AppState
    let engine: MacSettings.OnlineEngine
    @Environment(\.locale) private var locale

    var body: some View {
        switch state.settingsStatus.engineTests[engine] {
        case .works(let sample)?:
            Text(SettingsText.string("settings.key.works %@", locale, sample))
                .font(.nino(.callout)).foregroundStyle(NinoColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        case .failed(let failure)?:
            NinoErrorLabel(SettingsEngineText.failure(failure, engine: engine, settings: state.settings, locale: locale))
        case .testing?, nil:
            EmptyView()
        }
    }
}

// MARK: - Yapay zekâ anahtarı (§7.5)

struct AIKeySection: View {
    let state: AppState
    let engine: MacSettings.OnlineEngine
    @State private var key = ""
    @Environment(\.locale) private var locale

    private var testing: Bool { state.settingsStatus.engineTests[engine] == .testing }
    private var saved: Bool { state.settingsStatus.savedKeys.contains(engine) }

    private var models: [String] {
        let catalog = MacSettings.ModelCatalog.standard
        switch engine {
        case .gemini: return catalog.gemini
        case .openai: return catalog.openAI
        case .claude: return catalog.claude
        case .deepl, .local: return []
        }
    }

    private var modelBinding: Binding<String> {
        Binding(get: {
            let value: String
            switch engine {
            case .gemini: value = state.settings.geminiModel
            case .openai: value = state.settings.openAIModel
            case .claude: value = state.settings.claudeModel
            case .deepl, .local: value = ""
            }
            return models.contains(value) ? value : (models.first ?? "")
        }, set: { value in
            switch engine {
            case .gemini: state.settings.geminiModel = value
            case .openai: state.settings.openAIModel = value
            case .claude: state.settings.claudeModel = value
            case .deepl, .local: break
            }
        })
    }

    private static let keyPages: [MacSettings.OnlineEngine: String] = [
        .gemini: "https://aistudio.google.com/apikey",
        .openai: "https://platform.openai.com/api-keys",
        .claude: "https://platform.claude.com/settings/keys",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: NinoSpacing.m) {
            if saved {
                HStack(spacing: NinoSpacing.s) {
                    NinoOKLabel(SettingsText.string("settings.key.saved", locale))
                    Spacer(minLength: NinoSpacing.s)
                    Button { state.testTranslationEngine(engine) } label: {
                        SText(testing ? "settings.key.testing" : "settings.key.test")
                    }
                    .buttonStyle(.nino(.secondary))
                    .disabled(testing)
                    Button { state.removeTranslationKey(for: engine) } label: { SText("settings.key.remove") }
                        .buttonStyle(.nino(.secondary))
                }
            } else {
                HStack(spacing: NinoSpacing.s) {
                    SettingsField(placeholder: SettingsText.string("settings.key.placeholder", locale), text: $key,
                                  secure: true, onSubmit: save)
                    Button(action: save) {
                        SText(testing ? "settings.key.testing" : "settings.key.saveAndTest")
                    }
                    .buttonStyle(.nino(.secondary))
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty || testing)
                }
                if let page = Self.keyPages[engine], let url = URL(string: page) {
                    SettingsLink(title: SettingsText.string("settings.key.getKey %@", locale, ProviderCard.brand(engine)),
                                 url: url)
                }
            }
            EngineTestResult(state: state, engine: engine)
            SettingsPickerRow(title: SettingsText.string("settings.key.model", locale), selection: modelBinding,
                              options: models.enumerated().map { index, id in
                                  (id, SettingsText.string(index == 0 ? "settings.key.model.fast" : "settings.key.model.quality",
                                                           locale))
                              })
        }
        .onChange(of: saved) { _, isSaved in if isSaved { key = "" } }
    }

    private func save() {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !testing else { return }
        state.saveTranslationKey(trimmed, for: engine)
    }
}

// MARK: - DeepL (§7.6)

struct DeepLKeySection: View {
    let state: AppState
    @State private var key = ""
    @Environment(\.locale) private var locale
    @Environment(\.ninoStaticRendering) private var isStatic

    private var saved: Bool { state.settingsStatus.savedKeys.contains(.deepl) }
    private var checking: Bool { state.settingsStatus.deepLUsage == .checking }

    var body: some View {
        VStack(alignment: .leading, spacing: NinoSpacing.m) {
            if saved {
                HStack(spacing: NinoSpacing.s) {
                    NinoOKLabel(SettingsText.string("settings.key.saved", locale))
                    Spacer(minLength: NinoSpacing.s)
                    Button { state.refreshDeepLUsage() } label: {
                        SText(checking ? "settings.key.testing" : "settings.key.test")
                    }
                    .buttonStyle(.nino(.secondary))
                    .disabled(checking)
                    Button { state.removeTranslationKey(for: .deepl) } label: { SText("settings.key.remove") }
                        .buttonStyle(.nino(.secondary))
                }
            } else {
                HStack(spacing: NinoSpacing.s) {
                    SettingsField(placeholder: SettingsText.string("settings.key.deeplPlaceholder", locale), text: $key,
                                  secure: true, onSubmit: save)
                    Button(action: save) { SText(checking ? "settings.key.testing" : "settings.key.saveAndTest") }
                        .buttonStyle(.nino(.secondary))
                        .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty || checking)
                }
                if let url = URL(string: "https://www.deepl.com/pro-api") {
                    SettingsLink(title: SettingsText.string("settings.key.getDeepL", locale), url: url)
                }
            }
            usage
        }
        .onAppear { if saved, !isStatic { state.refreshDeepLUsage() } }
        .onChange(of: saved) { _, isSaved in if isSaved { key = "" } }
    }

    @ViewBuilder private var usage: some View {
        switch state.settingsStatus.deepLUsage {
        case .used(let characters, let limit)?:
            let used = characters.formatted(.number.locale(locale))
            let total = limit.formatted(.number.locale(locale))
            Text(SettingsText.string("settings.deepl.usage %@ %@", locale, used, total))
                .font(.nino(.callout)).foregroundStyle(NinoColor.textSecondary)
        case .limitReached?: usageLine("settings.deepl.limit")
        case .badKey?: usageLine("settings.deepl.badKey")
        case .unreachable?: usageLine("settings.deepl.unreachable")
        case .checking?, nil: EmptyView()
        }
    }

    private func usageLine(_ key: String) -> some View {
        Text(SettingsText.string(key, locale))
            .font(.nino(.callout)).foregroundStyle(NinoColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func save() {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        state.saveTranslationKey(trimmed, for: .deepl)
    }
}

// MARK: - Yerel model (§7.7)

struct LocalModelSection: View {
    let state: AppState
    let ui: SettingsUIState
    @State private var address = ""
    @State private var model = ""
    @State private var key = ""
    @Environment(\.locale) private var locale
    @Environment(\.ninoStaticRendering) private var isStatic

    private var status: SettingsStatus { state.settingsStatus }
    private var kind: LocalModelServer.Kind { SettingsRules.localServerKind(state.settings.localAIBaseURL) }
    private var testing: Bool { status.engineTests[.local] == .testing }
    private var downloading: Bool { status.localDownload != nil }
    private var addressValid: Bool { LocalModelServer.normalize(state.settings.localAIBaseURL) != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: NinoSpacing.m) {
            if kind == .ollama {
                localServerState
                ForEach(SettingsRules.suggestedLocalModels) { suggestion in
                    modelRow(suggestion)
                }
                if status.localDownloadFailed {
                    NinoErrorLabel(SettingsText.string("settings.local.downloadFailed", locale))
                }
            }
            Button(action: test) { SText(testing ? "settings.key.testing" : "settings.local.test") }
                .buttonStyle(.nino(.secondary))
                .disabled(testing || downloading || !addressValid)
            EngineTestResult(state: state, engine: .local)
            SettingsDisclosure(title: SettingsText.string("settings.local.server", locale),
                               isExpanded: Binding(get: { ui.localAdvancedExpanded },
                                                   set: { ui.localAdvancedExpanded = $0 })) {
                advanced
            }
        }
        .onAppear {
            address = state.settings.localAIBaseURL
            model = state.settings.localAIModel
            if kind == .ollama, !isStatic { state.checkOllama() }
        }
        .onDisappear(perform: commitFields)
    }

    // MARK: Ollama durumu

    /// Yerel model sunucusunun durumu (denetleniyor / çalışıyor / kurulu değil …).
    @ViewBuilder
    private var localServerState: some View {
        HStack(alignment: .top, spacing: NinoSpacing.s) {
            switch status.ollama {
            case .checking:
                SettingsSpinner()
                SText("settings.local.searching").foregroundStyle(NinoColor.textSecondary)
            case .running:
                Image(systemName: NinoSymbol.okFill).foregroundStyle(NinoColor.success)
                SText("settings.local.running")
            case .notRunning:
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(NinoColor.warning)
                VStack(alignment: .leading, spacing: 2) {
                    SText("settings.local.notRunning").fontWeight(.semibold)
                    SText("settings.local.getOllama").font(.nino(.callout)).foregroundStyle(NinoColor.textSecondary)
                }
                Spacer(minLength: NinoSpacing.s)
                if let url = URL(string: "https://ollama.com/download") {
                    Link(destination: url) { SText("settings.local.download") }
                        .buttonStyle(.nino(.secondary))
                }
                Button { state.checkOllama() } label: { SText("settings.local.checkAgain") }
                    .buttonStyle(.nino(.secondary))
            }
        }
    }

    private func modelRow(_ suggestion: SuggestedLocalModel) -> some View {
        let selected = LocalModelServer.sameModel(state.settings.localAIModel, suggestion.id)
        let installed = status.installedLocalModels.contains { LocalModelServer.sameModel($0, suggestion.id) }
        let shape = NinoRadius.shape(NinoRadius.control)
        return HStack(spacing: NinoSpacing.m) {
            SettingsRadio(selected: selected)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: NinoSpacing.s) {
                    Text(verbatim: suggestion.name).font(.nino(.headline))
                    if suggestion.recommended { RecommendedPill() }
                }
                SText(suggestion.detailKey).font(.nino(.callout)).foregroundStyle(NinoColor.textSecondary)
            }
            Spacer(minLength: NinoSpacing.s)
            if let download = status.localDownload, LocalModelServer.sameModel(download.model, suggestion.id) {
                SettingsProgressBar(value: download.progress).frame(width: 120)
                Text(verbatim: "\(Int(download.progress * 100))%").font(.nino(.callout).monospacedDigit())
            } else if installed {
                Label { SText("settings.local.downloaded") } icon: { Image(systemName: NinoSymbol.okFill) }
                    .font(.nino(.callout).weight(.semibold)).foregroundStyle(NinoColor.success)
            } else {
                Button {
                    state.downloadLocalModel(suggestion.id)
                } label: {
                    Text(SettingsText.string("settings.local.downloadSize %@", locale,
                                             suggestion.sizeGB.formatted(.number.precision(.fractionLength(1)).locale(locale))))
                }
                .buttonStyle(.nino(.secondary))
                .disabled(status.ollama != .running || downloading)
            }
        }
        .padding(NinoSpacing.m)
        .background(shape.fill(selected ? NinoColor.accent.opacity(0.08) : NinoColor.accent.opacity(0)))
        .overlay(shape.strokeBorder(selected ? AnyShapeStyle(NinoColor.accent) : AnyShapeStyle(NinoColor.glassEdge),
                                    lineWidth: selected ? 1.5 : 1))
        .contentShape(shape)
        .onTapGesture { select(suggestion.id) }
    }

    // MARK: Sunucu ayarları

    @ViewBuilder private var advanced: some View {
        Grid(alignment: .leading, horizontalSpacing: NinoSpacing.m, verticalSpacing: NinoSpacing.s) {
            GridRow {
                SText("settings.local.address")
                SettingsField(placeholder: LocalModelServer.defaultAddress, text: $address, monospaced: true,
                              onSubmit: commitFields)
            }
            GridRow {
                SText("settings.local.modelName")
                SettingsField(placeholder: LocalModelServer.defaultModel, text: $model, monospaced: true,
                              onSubmit: commitFields)
            }
        }
        HStack(spacing: NinoSpacing.s) {
            Button { useServer(.ollama) } label: { SText("settings.local.useOllama") }
                .buttonStyle(.nino(.secondary))
            Button { useServer(.lmStudio) } label: { SText("settings.local.useLMStudio") }
                .buttonStyle(.nino(.secondary))
        }
        if !addressValid {
            NinoErrorLabel(SettingsText.string("settings.local.badAddress %@", locale, LocalModelServer.defaultAddress))
        }
        SHint("settings.local.nameHint")
        if status.savedKeys.contains(.local) {
            HStack {
                NinoOKLabel(SettingsText.string("settings.key.saved", locale))
                Spacer()
                Button { state.removeTranslationKey(for: .local) } label: { SText("settings.key.remove") }
                    .buttonStyle(.nino(.secondary))
            }
        } else {
            SettingsField(placeholder: SettingsText.string("settings.local.keyPlaceholder", locale), text: $key,
                          secure: true)
        }
    }

    // MARK: Eylemler

    private func select(_ id: String) {
        model = id
        commitFields()
    }

    private func useServer(_ server: MacSettings.LocalServer) {
        address = server.baseURL
        commitFields()
        if SettingsRules.localServerKind(address) == .ollama, !isStatic { state.checkOllama() }
    }

    /// Alanları ayara yazar; değiştiyse eski deneme sonucu silinir.
    private func commitFields() {
        var settings = state.settings
        if !address.isEmpty { settings.localAIBaseURL = address.trimmingCharacters(in: .whitespacesAndNewlines) }
        if !model.isEmpty { settings.localAIModel = model.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard settings != state.settings else { return }
        state.settings = settings
        status.engineTests[.local] = nil
    }

    private func test() {
        commitFields()
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            state.testTranslationEngine(.local)
        } else {
            state.saveTranslationKey(trimmed, for: .local)
            key = ""
        }
    }
}

/// "Önerilen" hapı: beyaz kalın 11 pt, mavi geçişli kapsül.
struct RecommendedPill: View {
    var body: some View {
        SText("settings.translation.recommended")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(LinearGradient(colors: [NinoRGB(0.18, 0.55, 1.0).color, NinoRGB(0.0, 0.36, 0.85).color],
                                                      startPoint: .leading, endPoint: .trailing)))
    }
}
