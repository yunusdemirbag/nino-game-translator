// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI

// Altyazı görünümü (ayarlar.md §6): canlı önizleme ve üç seçenekli kart (yazı boyu, arka plan, konuşanın adı).
// Canlı önizleme kurulumda da kullanılır (§14a). Yazı tipi, renk, tema gibi görünüş seçimleri kalktı;
// altyazı hep varsayılan görünümle çizilir (MacSettings+Coding.swift).

struct AppearanceSettings: View {
    let state: AppState

    var body: some View {
        HStack(alignment: .top, spacing: NinoSpacing.m) {
            SubtitlePreview(style: state.settings.style, size: CGSize(width: 470, height: 264))
            SubtitleStyleCard(state: state)
        }
    }
}

// MARK: - Canlı önizleme (§6.2)

/// Koyu oyun sahnesi üstünde seçili temayla dönen demo satırları. `line` verilirse döngü durur ve
/// yalnız o satırın çevirisi görünür (kurulumda çeviri sürerken).
public struct SubtitlePreview: View {
    public struct Line: Equatable, Sendable {
        public var source: String
        public var translated: String
        public init(source: String, translated: String) {
            self.source = source
            self.translated = translated
        }
    }

    /// Demo satırları (çevrilmez).
    public static let demoLines: [Line] = [
        Line(source: "Someone has to keep an eye on this town.", translated: "Bu kasabaya birinin göz kulak olması lazım."),
        Line(source: "Here they come. Keep your head down.", translated: "Geliyorlar. Başını eğ, görünme."),
        Line(source: "Is anyone there?", translated: "Orada biri mi var?"),
        Line(source: "The fog swallows every sound.", translated: "Sis bütün sesleri yutuyor."),
        Line(source: "Up to the roof. Move!", translated: "Çatıya çıkın. Çabuk!"),
        Line(source: "We're not done here.", translated: "Burada işimiz bitmedi."),
    ]

    private enum Phase { case english, turkish, gap }

    private let style: SubtitleStyle
    private let size: CGSize
    private let line: Line?
    @State private var index = 0
    @State private var phase: Phase = .turkish
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ninoStaticRendering) private var isStatic

    public init(style: SubtitleStyle, size: CGSize = CGSize(width: 452, height: 254), line: Line? = nil) {
        self.style = style
        self.size = size
        self.line = line
    }

    private var looping: Bool { line == nil && !reduceMotion && !isStatic }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let fontSize = SettingsRules.previewFontSize(style, width: size.width)
        let bottom = style.placement == .fixed ? max(10, size.height * CGFloat(style.bottomPercent) / 100)
                                               : size.height * 0.08
        let shown = line ?? Self.demoLines[index % Self.demoLines.count]
        ZStack(alignment: .bottom) {
            GameSceneBackground()
            Group {
                switch phase {
                case .english where line == nil:
                    Text(shown.source)
                        .font(.system(size: fontSize, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                case .gap where line == nil:
                    Color.clear.frame(height: fontSize)
                default:
                    ThemedSubtitleLine(shown.translated, style: style, size: fontSize)
                        .transition(.scale(scale: 0.94).combined(with: .opacity))
                }
            }
            .frame(maxWidth: style.backgroundShape == .band ? .infinity : nil)
            .padding(.horizontal, 12)
            .padding(.bottom, bottom)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(NinoColor.glassEdge, lineWidth: 1))
        .animation(reduceMotion || isStatic ? nil : NinoMotion.spring(0.4, 0.8), value: style)
        .accessibilityHidden(true)
        .task(id: looping) { await loop() }
    }

    private func loop() async {
        guard looping else {
            phase = .turkish
            return
        }
        while !Task.isCancelled {
            withAnimation(.easeOut(duration: 0.25)) { phase = .english }
            try? await Task.sleep(for: .seconds(0.9))
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { phase = .turkish }
            try? await Task.sleep(for: .seconds(2.6))
            withAnimation(.easeOut(duration: 0.2)) { phase = .gap }
            try? await Task.sleep(for: .seconds(0.5))
            guard !Task.isCancelled else { return }
            index += 1
        }
    }
}

/// Oyun sahnesi gibi koyu zemin: üç renkli geçiş, turuncu ve mavi bulanık daireler.
struct GameSceneBackground: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            ZStack {
                LinearGradient(colors: [NinoRGB(0.10, 0.14, 0.28).color, NinoRGB(0.24, 0.14, 0.22).color,
                                        NinoRGB(0.06, 0.08, 0.14).color],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle()
                    .fill(Color.orange.opacity(0.45))
                    .frame(width: w * 0.40, height: w * 0.40)
                    .blur(radius: w * 0.08)
                    .position(x: w * 0.78, y: proxy.size.height * 0.22)
                Circle()
                    .fill(Color.blue.opacity(0.40))
                    .frame(width: w * 0.45, height: w * 0.45)
                    .blur(radius: w * 0.09)
                    .position(x: w * 0.12, y: proxy.size.height * 0.55)
            }
        }
    }
}

// MARK: - Ayarlar kartı (§6.3)

/// Üç seçenek: yazı boyu (otomatik + kaydırıcı), arka planın koyuluğu, konuşanın adı.
struct SubtitleStyleCard: View {
    let state: AppState
    @Environment(\.locale) private var locale

    private func text(_ key: String) -> String { SettingsText.string(key, locale) }

    private var style: SubtitleStyle { state.settings.style }

    private func binding<V>(_ path: WritableKeyPath<SubtitleStyle, V>) -> Binding<V> {
        Binding(get: { state.settings.style[keyPath: path] }, set: { state.settings.style[keyPath: path] = $0 })
    }

    /// İngilizce satırın üstüne binerken arka plan en az %60 koyu kalır (normalize() de bunu ister), yoksa
    /// İngilizce yazı çevirinin arkasından görünür.
    private var backgroundRange: ClosedRange<Int> { style.placement == .cover ? 60...100 : 0...100 }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(text(state.settings.output == .tv ? "settings.style.onTV" : "settings.style.title"))
                .font(.nino(.headline))
            SettingsSwitch(title: text("settings.style.autoSize"), isOn: binding(\.autoSize))
            SettingsSliderRow(title: text("settings.style.size"), value: binding(\.fontSize), range: 20...80,
                              minLabel: text("settings.style.size.small"), maxLabel: text("settings.style.size.large"),
                              onDragStart: state.sendTestSubtitle)
            if style.autoSize { small("settings.style.autoSizeHint") }
            Divider().padding(.vertical, 4)
            SettingsSliderRow(title: text("settings.style.background"), value: binding(\.background),
                              range: backgroundRange,
                              minLabel: text(style.placement == .cover ? "settings.style.background.light"
                                                                       : "settings.style.background.none"),
                              maxLabel: text("settings.style.background.solid"), onDragStart: state.sendTestSubtitle)
            Divider().padding(.vertical, 4)
            SettingsSwitch(title: text("settings.style.speaker"),
                           isOn: Binding(get: { state.settings.showSpeakerNames },
                                         set: { state.settings.showSpeakerNames = $0 }))
            small("settings.style.speakerHint")
        }
        .font(.nino(.callout))
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninoTile(padding: NinoSpacing.m)
    }

    private func small(_ key: String) -> some View {
        Text(text(key))
            .font(.system(size: 11))
            .foregroundStyle(NinoColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
