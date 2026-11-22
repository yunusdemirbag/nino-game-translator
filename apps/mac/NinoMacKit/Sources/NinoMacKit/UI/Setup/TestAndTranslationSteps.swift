// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI

/// Küçük TV önizlemesi: koyu oyun sahnesi, altta altyazı stiliyle satır, isteğe bağlı sol üst hap.
struct SetupTVPreview<Badge: View>: View {
    let line: String
    let style: SubtitleStyle
    let size: CGSize
    let badge: Badge

    init(line: String, style: SubtitleStyle, size: CGSize, @ViewBuilder badge: () -> Badge) {
        self.line = line
        self.style = style
        self.size = size
        self.badge = badge()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [NinoRGB(0.10, 0.16, 0.30).color, NinoRGB(0.20, 0.13, 0.20).color,
                                    NinoRGB(0.05, 0.06, 0.10).color],
                           startPoint: .top, endPoint: .bottom)
            Circle()
                .fill(NinoRGB(0.95, 0.55, 0.25).color(opacity: 0.35))
                .frame(width: size.width * 0.35)
                .blur(radius: 30)
                .offset(x: size.width * 0.2, y: -size.height * 0.35)
            ThemedSubtitleLine(line, style: style, size: max(11, size.height * 0.075), lineLimit: 2)
                .padding(.horizontal, size.width * 0.06)
                .padding(.bottom, size.height * 0.07)
                .id(line)
                .transition(.opacity)
        }
        .frame(width: size.width, height: size.height)
        .overlay(alignment: .topLeading) { badge.padding(10) }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.black.opacity(0.6), lineWidth: 3))
        .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
        .environment(\.layoutDirection, .leftToRight)
        .animation(.easeOut(duration: 0.3), value: line)
    }
}

extension SetupTVPreview where Badge == EmptyView {
    init(line: String, style: SubtitleStyle, size: CGSize) {
        self.init(line: line, style: style, size: size) { EmptyView() }
    }
}

// MARK: - Adım 6: Deneyelim (kurulum.md §8)

struct TestStep: View {
    let state: AppState
    @Environment(\.locale) private var locale

    private var onComputer: Bool { state.settings.output == .computer }
    private var phase: TestPhase { state.setup.test }
    private var sending: Bool { phase == .sending || phase == .resending }

    var body: some View {
        NinoSetupStepLayout(icon: .symbol("captions.bubble.fill"), title: SetupText.string("setup.test.title", locale),
                            message: SetupText.string(onComputer ? "setup.test.message.computer"
                                                                 : "setup.test.message.tv", locale)) {
            VStack(spacing: NinoSpacing.l) {
                SetupTVPreview(line: SetupText.string("setup.test.line", locale), style: state.settings.style,
                               size: CGSize(width: 400, height: 225)) {
                    if !onComputer { tvPill }
                }
                if phase == .ready || phase == .sending {
                    sendButton
                } else {
                    question
                    if phase == .notSeen || phase == .resending { notSeenRow }
                    resendLink
                }
                if onComputer {
                    SetupLink(systemImage: nil, title: SetupText.string("setup.test.adjust", locale)) {
                        state.overlayAdjusting = true
                    }
                    .disabled(state.overlayAdjusting)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var tvPill: some View {
        let connected = state.connectedDisplays > 0
        return HStack(spacing: 6) {
            Circle().fill(connected ? Color.green : Color.orange).frame(width: 7, height: 7)
            KText(connected ? "setup.test.tvConnected" : "setup.test.tvWaiting")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(Capsule().fill(Color.black.opacity(0.45)))
    }

    private var sendingText: String {
        SetupText.string(onComputer ? "setup.test.showing" : "setup.test.openingTV", locale)
    }

    private var sendButton: some View {
        Button {
            state.setup.test = .sending
            state.sendTestSubtitle()
        } label: {
            HStack(spacing: NinoSpacing.s) {
                if sending {
                    SetupSpinner(tint: .white)
                    Text(sendingText)
                } else {
                    KText(onComputer ? "setup.test.show" : "setup.test.send")
                }
            }
            .frame(minWidth: 280 - 2 * NinoSpacing.l)
        }
        .buttonStyle(.nino(.primary, size: .large))
        .disabled(sending)
    }

    private var question: some View {
        HStack(spacing: NinoSpacing.m) {
            KText(onComputer ? "setup.test.question.computer" : "setup.test.question.tv").font(.nino(.headline))
            Button {
                state.setup.test = .notSeen
            } label: { KText("setup.test.no") }
                .buttonStyle(.nino(.secondary, size: .large))
            Button { SetupFlow.testSeen(state) } label: { KText("setup.test.yes") }
                .buttonStyle(.nino(.primary, size: .large))
                .keyboardShortcut(.defaultAction)
        }
    }

    private var notSeenRow: some View {
        HStack(spacing: NinoSpacing.m) {
            Label {
                KText(onComputer ? "setup.test.tip.computer" : "setup.test.tip.tv")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "lightbulb.fill")
            }
            .font(.nino(.callout))
            .foregroundStyle(NinoColor.warning)
            if !onComputer {
                Button { state.setupStep = .tv } label: { KText("setup.test.reconnect") }
                    .buttonStyle(.nino(.ghost))
            }
        }
        .frame(maxWidth: 560)
    }

    @ViewBuilder private var resendLink: some View {
        if sending {
            SetupWorkingRow(text: sendingText)
        } else {
            SetupLink(systemImage: NinoSymbol.recheck, title: SetupText.string("setup.test.sendAgain", locale)) {
                state.setup.test = phase == .notSeen ? .resending : .sending
                state.sendTestSubtitle()
            }
        }
    }
}

// MARK: - Adım 7: Çeviri yolu ve API anahtarı (§9)

/// Üstte Nino kütüphanesi kartı (paketli oyunlar ücretsiz), altında "diğer oyunlar" için iki seçenek
/// (Ücretsiz seçili gelir; kendi API anahtarı) ve her zaman açık anahtar alanı.
struct BetterTranslationStep: View {
    let state: AppState
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL
    @State private var key = ""

    private var testing: Bool { state.setup.geminiTest == .testing }
    private var readyEngine: MacSettings.OnlineEngine? { state.readyOnlineEngine }

    var body: some View {
        NinoSetupStepLayout(icon: .symbol("wand.and.stars"), title: SetupText.string("setup.key.title", locale),
                            message: SetupText.string("setup.key.message", locale)) {
            VStack(alignment: .leading, spacing: NinoSpacing.l) {
                SetupLibraryCard(state: state)
                KText("setup.key.otherGames")
                    .font(.nino(.headline))
                    .padding(.horizontal, NinoSpacing.xs)
                VStack(spacing: NinoSpacing.s) {
                    SetupChoiceRow(title: SetupText.string("setup.key.free", locale),
                                   detail: SetupText.string("setup.key.freeDetail", locale),
                                   selected: !state.settings.onlineTranslation) {
                        state.settings.onlineTranslation = false
                    }
                    SetupChoiceRow(title: SetupText.string("setup.key.own", locale),
                                   detail: SetupText.string("setup.key.ownDetail", locale),
                                   selected: state.settings.onlineTranslation) {
                        chooseOwnKey()
                    }
                }
                if let readyEngine { ready(readyEngine) } else { form }
                VStack(alignment: .leading, spacing: 6) {
                    SetupNote(systemImage: "lock.fill", text: SetupText.string("setup.key.note.private", locale))
                    SetupNote(systemImage: "gauge.with.dots.needle.33percent",
                              text: SetupText.string("setup.gemini.note.limit", locale))
                    if readyEngine == nil {
                        SetupNote(systemImage: "info.circle", text: SetupText.string("setup.key.skipInfo", locale))
                    }
                }
                .padding(.horizontal, NinoSpacing.xs)
            }
        }
        .onChange(of: state.geminiReady) { _, ready in if ready { key = "" } }
    }

    private func chooseOwnKey() {
        var s = state.settings
        s.onlineTranslation = true
        // Anahtarı kayıtlı bir motor seçiliyse o kalır; yoksa bu adımın anahtar alanı Gemini içindir.
        if TranslationNudgeRules.readyEngine(s, savedKeys: state.settingsStatus.savedKeys,
                                             geminiKeySaved: state.setup.geminiKeySaved) == nil {
            s.onlineEngine = .gemini
        }
        state.settings = s
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: NinoSpacing.m) {
            Label {
                Text(SetupText.string("setup.key.prompt", locale)).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "key.fill").foregroundStyle(NinoColor.accent)
            }
            .font(.nino(.body).weight(.semibold))
            ForEach(1...3, id: \.self) { n in
                SetupCompactStep(number: n, text: SetupText.string("setup.gemini.step\(n)", locale))
            }
            HStack(spacing: NinoSpacing.m) {
                Button { openURL(SetupLinks.geminiKey) } label: { KText("setup.gemini.getKey") }
                    .buttonStyle(.nino(.primary, size: .large))
                SecureField(text: $key) { KText("setup.gemini.keyField") }
                    .ninoTextField()
                    .onSubmit(save)
                Button(action: save) {
                    if testing {
                        HStack(spacing: 6) { SetupSpinner(); KText("setup.gemini.testing") }
                    } else {
                        KText("setup.gemini.save")
                    }
                }
                .buttonStyle(.nino(.secondary, size: .large))
                .disabled(testing || key.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, NinoSpacing.xs)
            if case .failed(let message) = state.setup.geminiTest {
                SetupErrorText(text: message)
            }
            SetupLink(systemImage: "slider.horizontal.3", title: SetupText.string("setup.key.otherEngines", locale)) {
                state.open(.settingsTranslation)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninoTile()
    }

    private func save() {
        let text = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !testing else { return }
        state.setup.geminiTest = .testing
        state.saveGeminiKey(text)
    }

    private func ready(_ engine: MacSettings.OnlineEngine) -> some View {
        HStack(spacing: NinoSpacing.l) {
            VStack(alignment: .leading, spacing: NinoSpacing.s) {
                HStack(spacing: NinoSpacing.m) {
                    NinoGradientIconBox(systemName: "checkmark", size: 40)
                    if engine == .gemini {
                        KText("setup.gemini.ready").font(.ninoRounded(20, weight: .bold))
                    } else {
                        Text(SetupText.string("setup.key.ready %@", locale, HomeStatus.engineName(engine)))
                            .font(.ninoRounded(20, weight: .bold))
                    }
                }
                NinoHint(engine == .gemini ? SetupText.string("setup.gemini.ready.detail", locale)
                         : SetupText.string("setup.key.ready.detail %@", locale, HomeStatus.engineName(engine)))
            }
            Spacer(minLength: 0)
            GeminiSamplePreview(state: state)
        }
        .frame(maxWidth: .infinity)
        .ninoTile()
    }
}

/// "Nino Kütüphanesi Aktif": ortak kütüphane kartı, altında paketli oyunların kısa listesi (en çok 6 ad).
struct SetupLibraryCard: View {
    let state: AppState
    @Environment(\.locale) private var locale

    static func gameNames(_ packs: [GamePackInfo]) -> (shown: [String], more: Int) {
        let names = NinoLibrary.gameNames(packs)
        let shown = Array(names.prefix(6))
        return (shown, names.count - shown.count)
    }

    var body: some View {
        let list = Self.gameNames(state.settingsStatus.gamePacks)
        NinoLibraryCard(title: SetupText.string("setup.key.library.title", locale),
                        detail: SetupText.string("setup.key.library.detail", locale)) {
            Text(verbatim: list.shown.joined(separator: " · ")
                 + (list.more > 0 ? " · " + SetupText.string("setup.key.library.more %d", locale, list.more) : ""))
                .font(.nino(.caption).weight(.semibold))
                .foregroundStyle(NinoColor.accentText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Seçenek satırı: solda 18'lik daire (seçiliyse dolu iç daire), ad ve küçük açıklama; seçili olan vurgulu.
struct SetupChoiceRow: View {
    let title: String
    let detail: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: NinoSpacing.m) {
                ZStack {
                    Circle().strokeBorder(selected ? AnyShapeStyle(NinoColor.accent) : AnyShapeStyle(NinoColor.textSecondary),
                                          lineWidth: 1.5)
                    if selected { Circle().fill(NinoColor.accent).padding(4) }
                }
                .frame(width: 18, height: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.nino(.body).weight(.semibold)).foregroundStyle(NinoColor.textPrimary)
                    Text(detail).font(.nino(.caption)).foregroundStyle(NinoColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .ninoTile(active: selected, padding: NinoSpacing.m)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Gemini hazırken sağdaki önizleme: denemenin örnek çevirisi, yoksa akan örnek cümleler.
private struct GeminiSamplePreview: View {
    let state: AppState
    @Environment(\.locale) private var locale
    @Environment(\.ninoStaticRendering) private var isStatic
    @State private var index = 0

    var body: some View {
        let samples = (1...3).map { SetupText.string("setup.gemini.sample\($0)", locale) }
        let line = state.setup.geminiSample ?? samples[index % samples.count]
        SetupTVPreview(line: line, style: state.settings.style, size: CGSize(width: 300, height: 169))
            .task(id: state.setup.geminiSample == nil) {
                guard state.setup.geminiSample == nil, !isStatic else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(3))
                    index += 1
                }
            }
    }
}
