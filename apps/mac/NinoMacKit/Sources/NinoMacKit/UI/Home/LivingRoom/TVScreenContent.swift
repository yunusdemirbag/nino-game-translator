// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AppKit
import SwiftUI

// TV ekranının içi (ana-ekran.md §4.5, §4.10, §4.11) ve canlı TV'de de kullanılan parçalar.

// MARK: - CANLI rozeti

/// Bayrak kırmızısı canlı nokta + "CANLI"; siyah %40 kapsül.
struct LiveBadge: View {
    var body: some View {
        HStack(spacing: 6) {
            NinoLiveDot(color: NinoFixedColor.flagRed.color)
            HText("home.tv.live")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(Capsule().fill(Color.black.opacity(0.4)))
    }
}

// MARK: - Satır alanı (canlı ekran ve canlı TV)

/// Son satır ya da bekleme yazısı; yeni satır belirerek ve 6 pt aşağıdan kayarak gelir.
struct LiveLineArea: View {
    let line: LiveLine?
    let style: SubtitleStyle
    let size: CGFloat
    /// Görüntü akmıyorsa satır yerine gösterilen durum metni (salonda).
    var statusText: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            if let statusText {
                Text(statusText)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            } else if let line, !line.translated.isEmpty {
                ThemedSubtitleLine(line.translated, style: style, size: size, lineLimit: 2)
                    .id(line.translated)
                    .transition(.opacity.combined(with: .offset(y: 6)))
            } else {
                HText("home.tv.waiting")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.3), value: line?.translated)
    }
}

// MARK: - İndirme sayacı (§4.10)

struct DownloadCounter: View {
    /// Latin yazıda hafif sağa yatık (shear −0.12, 3 pt kaydırma); Arapçada düz.
    static let slant = CGAffineTransform(a: 1, b: 0, c: -0.12, d: 1, tx: 3, ty: 0)

    let total: Int
    /// Sayma gösterisi oynasın mı (canlı ekran ilk göründüğünde).
    let animate: Bool
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ninoStaticRendering) private var isStatic
    @State private var shown: Int?
    @State private var punched = false

    var body: some View {
        let title = HomeText.string("home.tv.totalDownloads", locale).uppercased(with: locale)
        let value = shown ?? total
        let number = value.formatted(.number.grouping(.automatic).locale(locale))
        let arabic = title.containsArabicScript || number.containsArabicScript
        VStack(alignment: .trailing, spacing: 1) {
            outlined(Text(title).font(.ninoImpact(11)).tracking(arabic ? 0 : 0.8).foregroundStyle(.white), width: 1)
            outlined(Text(number).font(.ninoImpact(27).monospacedDigit())
                        .foregroundStyle(NinoFixedColor.downloadGreen.color), width: 1.5)
                .shadow(color: NinoFixedColor.downloadGreen.color(opacity: punched ? 0.95 : 0), radius: 14)
                .scaleEffect(punched ? 1.32 : 1, anchor: .trailing)
        }
        .fixedSize()
        .transformEffect(arabic ? .identity : Self.slant)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(title) \(total.formatted(.number.locale(locale)))"))
        .task(id: animate) { await countUp() }
    }

    /// Yazının dört yanına keskin siyah gölge + w + 1 aşağıda derinlik.
    private func outlined(_ text: some View, width w: CGFloat) -> some View {
        text
            .shadow(color: .black, radius: 0, x: w, y: 0)
            .shadow(color: .black, radius: 0, x: -w, y: 0)
            .shadow(color: .black, radius: 0, x: 0, y: w)
            .shadow(color: .black, radius: 0, x: 0, y: -w)
            .shadow(color: .black.opacity(0.9), radius: 0, x: 0, y: w + 1)
    }

    private func countUp() async {
        guard animate, !isStatic, !reduceMotion, total > 3 else {
            shown = nil
            return
        }
        for step in 1...3 {
            shown = step
            try? await Task.sleep(for: .milliseconds(280))
        }
        // Yazı hızlanarak dolar: ilerleme üssü 2.6 olan eğri, 1.55 sn, ~60 kare/sn.
        let began = Date()
        var progress = 0.0
        repeat {
            progress = min(1, Date().timeIntervalSince(began) / 1.55)
            let eased = pow(progress, 2.6)
            shown = max(3, Int((eased * Double(total)).rounded()))
            if progress < 1 { try? await Task.sleep(for: .milliseconds(16)) }
        } while progress < 1
        shown = total
        withAnimation(NinoMotion.spring(0.22, 0.45)) { punched = true }
        try? await Task.sleep(for: .milliseconds(260))
        withAnimation(NinoMotion.spring(0.45, 0.6)) { punched = false }
    }
}

// MARK: - Oyun fonu (§4.11)

struct GameBackdrop: View {
    let game: RecognizedGame?
    let coversFolder: URL?

    var body: some View {
        if let image = GameCovers.image(for: game, in: coversFolder) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .blur(radius: 14, opaque: true)
                .overlay(Color.black.opacity(0.36))
                .clipped()
        } else if game?.poolFirst == true {
            LinearGradient(stops: [
                .init(color: NinoRGB(0.10, 0.08, 0.34).color, location: 0),
                .init(color: NinoRGB(0.46, 0.16, 0.62).color, location: 0.40),
                .init(color: NinoRGB(0.93, 0.29, 0.60).color, location: 0.74),
                .init(color: NinoRGB(1.00, 0.55, 0.48).color, location: 1),
            ], startPoint: .top, endPoint: .bottom)
            .overlay(Color.black.opacity(0.28))
        } else {
            LinearGradient(colors: [NinoRGB(0.09, 0.12, 0.24).color, NinoRGB(0.15, 0.09, 0.18).color],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

/// Kullanıcının oyun görselleri: "Covers/<oyun-kimliği>.png" (jpg, jpeg, heic, webp de). GTA 6 için "gta-6".
@MainActor
enum GameCovers {
    private static var cache: [URL: (date: Date, image: NSImage)] = [:]

    static func image(for game: RecognizedGame?, in folder: URL?) -> NSImage? {
        guard let game, let folder else { return nil }
        var names = [game.id]
        if game.poolFirst || game.id.lowercased().contains("gta") { names.append("gta-6") }
        let fm = FileManager.default
        for name in names {
            for ext in ["png", "jpg", "jpeg", "heic", "webp"] {
                let url = folder.appendingPathComponent(name).appendingPathExtension(ext)
                guard let attributes = try? fm.attributesOfItem(atPath: url.path) else { continue }
                let date = attributes[.modificationDate] as? Date ?? .distantPast
                if let cached = cache[url], cached.date == date { return cached.image }
                guard let image = NSImage(contentsOf: url) else { continue }
                cache[url] = (date, image)
                return image
            }
        }
        return nil
    }
}

// MARK: - TV ekranı (§4.5)

/// Salondaki TV'nin içi; mantıksal 588 genişlikte çizilir.
struct LivingRoomTVContent: View {
    enum Phase: Equatable { case standby, splash, live }

    let phase: Phase
    let state: AppState
    let showCounter: Bool
    let animateCounter: Bool
    let size: CGSize
    var onSplashFinished: () -> Void = {}
    @Environment(\.locale) private var locale

    var body: some View {
        ZStack {
            Color.black
            switch phase {
            case .standby: standby
            case .splash:
                NinoSplashView(onFinished: onSplashFinished)
                    .frame(width: 1040, height: 586)
                    .environment(\.colorScheme, .dark)
                    .scaleEffect(LivingRoomGeometry.logicalTVWidth / 1040)
                    .frame(width: size.width, height: size.height)
                    .transition(.opacity)
            case .live: live.transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .environment(\.layoutDirection, .leftToRight)
        .animation(.easeOut(duration: 0.4), value: phase)
    }

    private var standby: some View {
        let text = HomeText.string("home.tv.dragPlug", locale).uppercased(with: locale)
        return ZStack(alignment: .topTrailing) {
            Text(text)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .tracking(text.containsArabicScript ? 0 : 2)
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if showCounter, let total = state.downloadTotal {
                DownloadCounter(total: total, animate: false).padding(18)
            }
        }
    }

    @ViewBuilder private var live: some View {
        if state.adminMode, let preview = state.adminTVPreview {
            // Admin: TV'nin gerçekten gösterdiğinin bileşik karesi (PS5 + TV katmanı).
            AdminTVPreviewImage(preview: preview, badge: state.adminBadges)
                .frame(width: size.width, height: size.height)
        } else {
            normalLive
        }
    }

    private var normalLive: some View {
        let streaming = HomeStatus.isStreaming(state)
        return ZStack {
            GameBackdrop(game: state.game, coversFolder: state.coversFolder)
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    LiveBadge()
                    Spacer()
                    if let total = state.downloadTotal {
                        DownloadCounter(total: total, animate: animateCounter)
                    }
                }
                Spacer(minLength: 0)
                LiveLineArea(line: state.lastLine, style: state.settings.style, size: 26,
                             statusText: streaming ? nil : HomeStatus.sourceText(state, locale))
                    .padding(.bottom, 8)
            }
            .padding(18)
        }
    }
}

/// Admin önizlemesinin resmi (TV ekranına sığar). "TV (admin)" etiketi yalnız geliştirici kimliğinde.
struct AdminTVPreviewImage: View {
    let preview: AdminTVPreview
    var badge: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black
            Image(decorative: preview.image, scale: 1)
                .resizable()
                .interpolation(.medium)
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if badge {
                Text(verbatim: "TV (admin)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.85)))
                    .padding(6)
            }
        }
    }
}
