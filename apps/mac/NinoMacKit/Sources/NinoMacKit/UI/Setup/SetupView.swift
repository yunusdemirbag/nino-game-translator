// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI

/// Kurulum sihirbazının çerçevesi (kurulum.md §2): üst şerit, kaydırılan cam kart, alt düğme sırası.
/// Yakalama kartı rehberi açıkken kart ve alt sıra yerine rehber görünür.
public struct SetupView: View {
    private let state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 0) {
            topBar
            ZStack {
                if state.setup.captureGuideOpen {
                    CaptureCardGuide(state: state, context: .wizard) { state.setup.captureGuideOpen = false }
                        .transition(.opacity)
                } else {
                    wizard.transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: state.setup.captureGuideOpen)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var topBar: some View {
        HStack(spacing: NinoSpacing.s) {
            NinoLogo(size: 26)
            NinoWordmark(size: 16)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, NinoSpacing.xl)
        .padding(.top, 12)
    }

    private var wizard: some View {
        VStack(spacing: 0) {
            SetupCard {
                SetupStepContent(state: state)
            } overlay: {
                if state.setupStep == .welcome {
                    // Sağdan sola dillerde de sağda kalır.
                    HStack {
                        Spacer()
                        SetupLanguagePicker(state: state)
                    }
                    .padding(NinoSpacing.l)
                    .environment(\.layoutDirection, .leftToRight)
                }
            }
            .padding(.horizontal, NinoSpacing.xxl)
            .padding(.top, 12)
            SetupBottomRow(state: state)
                .frame(maxWidth: 700)
                .padding(.horizontal, NinoSpacing.xxl)
                .padding(.vertical, NinoSpacing.l)
        }
    }
}

/// Tek cam kart: en çok 700 genişlik, kalan yüksekliği doldurur, içi gizli çubukla dikey kaydırılır.
struct SetupCard<Content: View, Overlay: View>: View {
    let content: Content
    let overlay: Overlay
    var verticalInset: CGFloat = NinoSpacing.l
    @Environment(\.ninoStaticRendering) private var isStatic
    @Environment(\.colorScheme) private var scheme

    init(verticalInset: CGFloat = NinoSpacing.l, @ViewBuilder content: () -> Content,
         @ViewBuilder overlay: () -> Overlay) {
        self.verticalInset = verticalInset
        self.content = content()
        self.overlay = overlay()
    }

    var body: some View {
        let shape = NinoRadius.shape(NinoRadius.card)
        GeometryReader { proxy in
            Group {
                if isStatic {
                    // ImageRenderer kaydırma alanını çizemez: içerik üstten başlar, taşan kesilir.
                    inner(minHeight: proxy.size.height)
                        .frame(height: proxy.size.height, alignment: .top)
                        .clipped()
                } else {
                    ScrollView(.vertical) { inner(minHeight: proxy.size.height) }
                        .scrollIndicators(.hidden)
                }
            }
        }
        .overlay(alignment: .top) { overlay }
        .frame(maxWidth: 700)
        .ninoGlass(in: shape)
        .clipShape(shape)
        .shadow(color: NinoColor.pro.color(scheme).opacity(0.06), radius: 20, y: 8)
    }

    private func inner(minHeight: CGFloat) -> some View {
        content
            .padding(.horizontal, NinoSpacing.xxl)
            .padding(.vertical, verticalInset)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .top)
    }
}

extension SetupCard where Overlay == EmptyView {
    init(verticalInset: CGFloat = NinoSpacing.l, @ViewBuilder content: () -> Content) {
        self.init(verticalInset: verticalInset, content: content) { EmptyView() }
    }
}

/// Geçerli adımın ekranı; adım değişince yenisi sağdan kayarak gelir, eskisi sola gider.
struct SetupStepContent: View {
    let state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            step
                .id(stepID)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
        }
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.86), value: stepID)
    }

    /// Hoş geldin'in üç hâli kendi aralarında solarak değişir; adım kimliği yalnız adımdır.
    private var stepID: SetupStep { state.setupStep }

    @ViewBuilder private var step: some View {
        switch state.setupStep {
        case .welcome: WelcomeStep(state: state)
        case .secondAccount: SecondAccountStep(state: state)
        case .psnLogin: PSNLoginStep(state: state)
        case .console: ConsolePairStep(state: state)
        case .tv: TVStep(state: state)
        case .test: TestStep(state: state)
        case .betterTranslation, .done: BetterTranslationStep(state: state)
        }
    }
}

/// Alt düğme sırası: solda Geri, ortada sayfa noktaları, sağda Devam / Şimdilik Geç.
struct SetupBottomRow: View {
    let state: AppState
    @Environment(\.locale) private var locale

    var body: some View {
        ZStack {
            SetupPageDots(count: SetupFlow.stepCount, current: SetupFlow.dotIndex(state.setupStep))
            HStack {
                if SetupFlow.showsBack(state) {
                    Button { SetupFlow.goBack(state) } label: {
                        Label { KText("setup.back") } icon: {
                            Image(systemName: "chevron.left").flipsForRightToLeftLayoutDirection(true)
                        }
                    }
                    .buttonStyle(.nino(.ghost, size: .large))
                }
                Spacer()
                forward
            }
        }
        .frame(minHeight: NinoSize.buttonHeightLarge)
    }

    @ViewBuilder private var forward: some View {
        switch SetupFlow.forwardButton(state) {
        case .none:
            EmptyView()
        case .skip:
            Button { SetupFlow.goNext(state) } label: { KText("setup.skip") }
                .buttonStyle(.nino(.secondary, size: .large))
        case .proceed:
            Button { SetupFlow.goNext(state) } label: {
                KText("setup.continue").frame(minWidth: 120 - 2 * NinoSpacing.l)
            }
            .buttonStyle(.nino(.primary, size: .large))
            .keyboardShortcut(.defaultAction)
            .disabled(!SetupFlow.canContinue(state))
        }
    }
}
