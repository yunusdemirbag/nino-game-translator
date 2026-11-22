// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreMotion
import SwiftUI
import Translation
import UIKit

/// Ana ekran: durum, salon sahnesi (fiş prize takılınca çeviri başlar), kısa yollar.
struct HomeScreen: View {
    @EnvironmentObject private var model: AppModel
    @Binding var path: [Route]
    /// Kurulumdan açılan "PS5'siz önizleme": yalnız demo, kısa yol yok.
    var demoOnly = false
    var onClose: (() -> Void)?

    @State private var fullScreen = false
    @StateObject private var sideways = SidewaysWatcher()

    enum Phase { case notPaired, ready, connecting, live }

    private var phase: Phase {
        if model.isDemo { return .live }
        if model.isRunning { return model.link == .streaming ? .live : .connecting }
        if model.isStarting { return .connecting }
        return model.canStart ? .ready : .notPaired
    }

    private var onPhone: Bool { model.isDemo || model.settings.output.showsOnPhone }

    var body: some View {
        NinoScreen {
            if demoOnly {
                HStack {
                    NinoLogo(size: 36)
                    Spacer(minLength: 0)
                    Button(L("common.close")) { model.stopDemo(); onClose?() }.buttonStyle(.ghost)
                }
                .frame(height: DS.Size.icon)
            } else {
                HStack(spacing: DS.Space.gap) {
                    NinoLogo(size: 36)
                    Spacer(minLength: 0)
                    SquareIconButton(symbol: "clock.arrow.circlepath", label: L("settings.history")) { path.append(.history) }
                    SquareIconButton(symbol: "gearshape", label: L("settings.title")) { path.append(.settings) }
                    ProfileButton { path.append(.profile) }
                        .tourAnchor(.profile)
                }
                .frame(height: DS.Size.icon)
            }
        } content: {
            statusRow.padding(.top, 8)
            Text(title)
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.6)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
            LivingRoomScene(xbox: model.isXbox,
                            active: model.isDemo || model.isRunning || model.isStarting,
                            streaming: phase == .live,
                            line: model.currentLine,
                            source: model.isDemo ? model.demoLine?.source : nil,
                            problem: phase == .connecting ? model.problemText : nil,
                            badge: model.isDemo ? L("demo.badge") : L("home.live.badge"),
                            downloads: model.downloadTotal,
                            onToggle: toggle,
                            onOpenTV: { fullScreen = true })
                .padding(.top, 8)
                .tourAnchor(.start)
            underScene
            if phase == .notPaired && !model.isDemo {
                TryWithoutPS5Button { model.startDemo() }.frame(maxWidth: .infinity)
            }
            if phase == .live && onPhone {
                HStack(spacing: 8) {
                    Image(systemName: "rotate.right").font(.system(size: 15, weight: .medium))
                    Text(L("home.rotate.hint")).font(.system(size: 14))
                }
                .foregroundStyle(DS.Palette.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
                .transition(.opacity)
            }
            if !demoOnly {
                shortcuts.padding(.top, 16)
                if let offer = model.tvUpdateOffer {
                    ActionCard(symbol: "arrow.triangle.2.circlepath", tint: DS.Palette.accent, title: L("tv.update.title"),
                               detail: L("tv.update.versions", offer.installed, offer.available),
                               button: L("tv.update.button")) { path.append(.tvUpdate) }
                } else if model.tvAppMissing {
                    Button { path.append(.tvInstall) } label: {
                        InfoTile(symbol: "arrow.down.app", title: L("tv.install.fromphone"),
                                 detail: "Samsung · LG · Android TV")
                    }
                    .buttonStyle(.plain)
                }
            }
            if model.onDeviceStatus == .needsDownload && !demoOnly {
                LanguagePackCard()
            }
            if model.onDeviceStatus == .unavailable && !model.onlineEngineActive {
                OldIOSCard { path.append(.settings) }
            } else if model.onDeviceStatus == .unsupported && !model.onlineEngineActive {
                NoteLine(text: L("translate.error.unsupportedlang"))
            }
            if model.isRunning && !model.isDemo {
                if model.sessionLines == 0 && !model.isXbox {
                    NoteLine(text: L("psn.controller.warning"),
                             color: DS.Palette.secondary)
                }
                Text(L("home.foreground.note"))
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Palette.tertiary)
                    .padding(.top, 4)
            }
        }
        .animation(.easeOut(duration: 0.25), value: phase)
        .task(id: model.settings.targetLanguage) { await model.refreshTranslationStatus() }
        .fullScreenCover(isPresented: $fullScreen, onDismiss: { sideways.disarm() }) {
            SubtitleScreen()
        }
        .onChange(of: model.isRunning) { _, running in
            if running && onPhone { fullScreen = true }
        }
        .onChange(of: watchSideways, initial: true) { _, on in
            if on { sideways.start { if !fullScreen { fullScreen = true } } } else { sideways.stop() }
        }
        .onDisappear { sideways.stop() }
    }

    private var watchSideways: Bool { (model.isRunning || model.isDemo) && onPhone }

    private var title: String {
        switch phase {
        case .notPaired: L("home.title.pair")
        case .live: L("home.title.live")
        case .ready, .connecting: L("home.title.ready", languageName)
        }
    }

    private var languageName: String {
        let t = Languages.normalized(model.settings.targetLanguage)
        if t == "tr" { return L("lang.tr") }
        if t == "ar" { return L("lang.ar") }
        return Languages.nativeName(t)
    }

    private var statusRow: some View {
        let live = Color(rgb: 0x30C578)
        let (color, text, blinking): (Color, String, Bool) = {
            if model.isDemo { return (live, L("demo.status"), false) }
            let prefix = model.consoleName + "  ·  "
            switch phase {
            case .notPaired: return (DS.Palette.secondary, L("home.status.notpaired"), false)
            case .ready: return (DS.Palette.accent, prefix + L("home.status.ready"), false)
            case .connecting: return (model.problemText == nil ? DS.Palette.accent : DS.Palette.warning,
                                      prefix + L("home.status.connecting"), true)
            case .live: return (live, prefix + (onPhone ? L("home.status.live") : L("home.status.tv")), true)
            }
        }()
        return HStack(spacing: 8) {
            BlinkingDot(color: color, blinking: blinking)
            Text(text).font(.system(size: 14, weight: .medium)).foregroundStyle(DS.Palette.secondary).lineLimit(1)
        }
    }

    private var underScene: some View {
        HStack(spacing: 10) {
            Text(underSceneText)
                .font(.footnote.weight(.medium))
                .foregroundStyle(DS.Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if phase == .live {
                Button { fullScreen = true } label: {
                    Label(L("home.fullscreen"), systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(DS.Palette.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color.white.opacity(0.72)))
                        .overlay(Capsule().strokeBorder(Color.white, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
    }

    private var underSceneText: String {
        switch phase {
        case .notPaired: model.isDemo ? L("scene.unplug") : L("slide.pair")
        case .ready: L("scene.plug")
        case .connecting, .live: L("scene.unplug")
        }
    }

    private var shortcuts: some View {
        HStack(spacing: 10) {
            Shortcut(symbol: "gamecontroller.fill",
                     title: model.isXbox ? "Xbox · Beta" : "PS5",
                     value: model.isXbox ? (model.xboxConsole == nil ? L("xbox.choose.title") : model.consoleName)
                        : (model.console == nil ? L("home.status.notpaired") : model.consoleName)) { path.append(.ps5) }
            Shortcut(symbol: model.settings.output.showsOnPhone ? "iphone" : "tv",
                     title: L("home.output"),
                     value: model.settings.output.showsOnPhone ? L("home.output.phone") : (model.tv?.name ?? "TV")) { path.append(.target) }
                .tourAnchor(.target)
            Shortcut(symbol: "shippingbox.fill", title: L("home.packs"), value: L("home.packs.free")) { path.append(.packs) }
                .tourAnchor(.packs)
        }
    }

    /// Fiş/priz: başlat ya da durdur; kurulum eksikse PS5 sayfası.
    private func toggle() {
        if model.isDemo { model.stopDemo(); return }
        Task {
            while model.isStarting { try? await Task.sleep(for: .milliseconds(50)) }
            if model.isRunning {
                model.stop()
            } else if model.canStart {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                await model.start()
            } else if !demoOnly {
                path.append(.ps5)
            }
        }
    }
}

/// Kısa yol karosu.
private struct Shortcut: View {
    let symbol: String
    let title: String
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: symbol).font(.system(size: 20, weight: .semibold)).foregroundStyle(DS.Palette.accent)
                Spacer().frame(height: 12)
                Text(verbatim: title).font(.system(size: 12)).foregroundStyle(DS.Palette.secondary).lineLimit(1)
                Text(verbatim: value).font(.system(size: 14, weight: .semibold)).foregroundStyle(DS.Palette.text)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.72)))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Yanıp sönen durum noktası.
private struct BlinkingDot: View {
    let color: Color
    let blinking: Bool
    @State private var dim = false

    var body: some View {
        Circle().fill(color).frame(width: 8, height: 8)
            .opacity(blinking && dim ? 0.3 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim = true }
            }
    }
}

/// PS5'siz önizleme: ana ekranın demo hâli.
struct DemoPreview: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var path: [Route] = []

    var body: some View {
        HomeScreen(path: $path, demoOnly: true, onClose: { dismiss() })
            .onAppear { model.startDemo() }
            .onDisappear { model.stopDemo() }
    }
}

/// Telefon yan çevrilince tam ekran altyazıyı açar (ana ekran dikey kilitli olduğu için ivmeölçerle anlaşılır).
@MainActor
final class SidewaysWatcher: ObservableObject {
    private let motion = CMMotionManager()
    private var armed = false
    private var sidewaysSince: Date?

    func start(onSideways: @escaping () -> Void) {
        guard motion.isAccelerometerAvailable, !motion.isAccelerometerActive else { return }
        motion.accelerometerUpdateInterval = 0.1
        motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let a = data?.acceleration else { return }
            if a.y < -0.75 && abs(a.x) < 0.45 {
                self.armed = true
                self.sidewaysSince = nil
            } else if abs(a.x) > 0.75 && abs(a.y) < 0.45 {
                let since = self.sidewaysSince ?? Date()
                self.sidewaysSince = since
                if self.armed, Date().timeIntervalSince(since) >= 0.7, UIApplication.shared.applicationState == .active {
                    self.armed = false
                    onSideways()
                }
            }
        }
    }

    func stop() { motion.stopAccelerometerUpdates() }
    func disarm() { armed = false; sidewaysSince = nil }
}

/// iOS 26 öncesi: Apple'ın ücretsiz çevirisi yok.
/// Simge + başlık + açıklama + tek düğmeli vurgulu kart (TV güncellemesi, dil paketi).
struct ActionCard: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    let button: String
    var busy = false
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        VStack(alignment: .leading, spacing: 10) {
            Label { Text(title).font(.headline).foregroundStyle(DS.Palette.text) } icon: {
                Image(systemName: symbol).foregroundStyle(tint)
            }
            Text(detail).font(.subheadline).foregroundStyle(DS.Palette.secondary)
            Button(action: action) {
                HStack(spacing: 8) {
                    if busy { ProgressView().tint(.white) }
                    Text(button).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                }
                .padding(.horizontal, 14).padding(.vertical, 9).background(Capsule().fill(tint))
            }
            .buttonStyle(.plain)
            .disabled(busy)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(shape.fill(tint.opacity(0.08)))
        .overlay(shape.strokeBorder(tint.opacity(0.35), lineWidth: 1))
    }
}

/// Apple çevirisinin dil paketi indirilmemiş (iOS 26+): "İndir" sistemin indirme penceresini açar (Translation
/// `prepareTranslation`); bitince durum yeniden okunur ve kart kaybolur. Tarif: ana-ekran.md §2.2.
private struct LanguagePackCard: View {
    @EnvironmentObject private var model: AppModel
    @State private var request = LanguagePackRequest()

    var body: some View {
        let target = Languages.normalized(model.settings.targetLanguage)
        let source = Locale.current.localizedString(forLanguageCode: model.settings.sourceLanguage) ?? model.settings.sourceLanguage
        ActionCard(symbol: "arrow.down.circle", tint: DS.Palette.accent,
                   title: L("langpack.title", source, Languages.nativeName(target)),
                   detail: L("langpack.detail"), button: L("langpack.download"), busy: request.busy) {
            request.start(source: model.settings.sourceLanguage, target: target)
        }
        .modifier(LanguagePackDownload(request: $request) { await model.refreshTranslationStatus() })
    }
}

/// İndirme isteğinin durumu (test edilebilir): düğmeye basınca yapılandırma kurulur, iş bitince sıfırlanır.
struct LanguagePackRequest: Equatable {
    private(set) var source: String?
    private(set) var target: String?
    private(set) var attempt = 0
    var busy: Bool { source != nil }

    mutating func start(source: String, target: String) {
        guard !busy else { return }
        self.source = source
        self.target = target
        attempt += 1
    }

    mutating func finish() {
        source = nil
        target = nil
    }
}

private struct LanguagePackDownload: ViewModifier {
    @Binding var request: LanguagePackRequest
    let refresh: () async -> Void

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.modifier(LanguagePackTask(request: $request, refresh: refresh))
        } else {
            content
        }
    }
}

@available(iOS 26.0, *)
private struct LanguagePackTask: ViewModifier {
    @Binding var request: LanguagePackRequest
    let refresh: () async -> Void
    @State private var configuration: TranslationSession.Configuration?

    func body(content: Content) -> some View {
        content
            .translationTask(configuration) { session in
                // Sistem indirme penceresini gösterir; kullanıcı vazgeçerse hata atar.
                try? await session.prepareTranslation()
                await refresh()
                request.finish()
            }
            .onChange(of: request.attempt) { _, _ in
                guard let source = request.source, let target = request.target else { return }
                let wanted = TranslationSession.Configuration(source: Locale.Language(identifier: source),
                                                               target: Locale.Language(identifier: target))
                if configuration?.source == wanted.source, configuration?.target == wanted.target {
                    configuration?.invalidate()
                } else {
                    configuration = wanted
                }
            }
    }
}

private struct OldIOSCard: View {
    @Environment(\.openURL) private var openURL
    let onAddKey: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        VStack(alignment: .leading, spacing: 10) {
            Label { Text(L("oldios.title")).font(.headline).foregroundStyle(DS.Palette.text) } icon: {
                Image(systemName: "info.circle.fill").foregroundStyle(DS.Palette.warning)
            }
            Text(L("oldios.body", UIDevice.current.systemVersion)).font(.subheadline).foregroundStyle(DS.Palette.secondary)
            ViewThatFits {
                HStack(spacing: 10) { buttons }
                VStack(alignment: .leading, spacing: 8) { buttons }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(shape.fill(DS.Palette.warning.opacity(0.08)))
        .overlay(shape.strokeBorder(DS.Palette.warning.opacity(0.35), lineWidth: 1))
    }

    @ViewBuilder private var buttons: some View {
        Button(action: onAddKey) {
            Label(L("oldios.add"), systemImage: "key.fill").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 9).background(Capsule().fill(DS.Palette.accent))
        }
        .buttonStyle(.plain)
        Button { openURL(URL(string: "https://aistudio.google.com/apikey")!) } label: {
            Label(L("oldios.get"), systemImage: "arrow.up.right.square").font(.subheadline.weight(.semibold))
                .foregroundStyle(DS.Palette.accent).padding(.vertical, 9)
        }
        .buttonStyle(.plain)
    }
}
