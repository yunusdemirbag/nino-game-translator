// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI

/// Kullanım turunun hedefleri.
enum TourTarget: Int, CaseIterable {
    case start, target, packs, profile

    var title: String {
        switch self {
        case .start: L("home.start.here")
        case .target: L("target.title.alt")
        case .packs: L("packs.ready")
        case .profile: L("settings.profile.title")
        }
    }

    var text: String {
        switch self {
        case .start: L("home.start.hint")
        case .target: L("settings.target.detail")
        case .packs: L("settings.packs.detail")
        case .profile: L("settings.profile.detail")
        }
    }
}

struct TourAnchorKey: PreferenceKey {
    static let defaultValue: [TourTarget: Anchor<CGRect>] = [:]
    static func reduce(value: inout [TourTarget: Anchor<CGRect>], nextValue: () -> [TourTarget: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Öğenin çerçevesini kullanım turuna bildirir.
    func tourAnchor(_ target: TourTarget) -> some View {
        anchorPreference(key: TourAnchorKey.self, value: .bounds) { [target: $0] }
    }
}

/// Ana ekranın üstünde dört adımlık tur: karartma, hedefte delik ve mavi halka, açıklama kartı.
struct CoachTour: View {
    let anchors: [TourTarget: Anchor<CGRect>]
    let onFinish: () -> Void
    @State private var index = 0

    var body: some View {
        GeometryReader { geo in
            let target = TourTarget.allCases[index]
            let rect = anchors[target].map { geo[$0].insetBy(dx: -6, dy: -6) }
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.72)
                    .mask {
                        Rectangle()
                            .overlay {
                                if let rect {
                                    RoundedRectangle(cornerRadius: 16)
                                        .frame(width: rect.width, height: rect.height)
                                        .position(x: rect.midX, y: rect.midY)
                                        .blendMode(.destinationOut)
                                }
                            }
                            .compositingGroup()
                    }
                if let rect {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(DS.Palette.accent, lineWidth: 2)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
                card(target)
                    .frame(width: min(geo.size.width - 40, DS.isPad ? DS.Size.readable : .infinity))
                    .position(x: geo.size.width / 2, y: cardY(rect, height: geo.size.height))
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .transition(.opacity)
        .animation(.easeOut(duration: 0.25), value: index)
    }

    private func cardY(_ rect: CGRect?, height: CGFloat) -> CGFloat {
        guard let rect else { return height / 2 }
        if rect.midY > height / 2 { return max(140, rect.minY - 120) }
        return min(height - 140, rect.maxY + 120)
    }

    private func card(_ target: TourTarget) -> some View {
        let count = TourTarget.allCases.count
        let last = index == count - 1
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(verbatim: "\(index + 1) / \(count)").font(DS.Font.caption.monospacedDigit()).foregroundStyle(DS.Palette.secondary)
                Spacer(minLength: 0)
                Button(L("common.skip"), action: onFinish).buttonStyle(.ghost)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(target.title).font(DS.Font.title)
                Text(target.text).font(DS.Font.body).foregroundStyle(DS.Palette.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                PageIndicator(count: count, current: index)
                Spacer(minLength: 0)
                Button(last ? L("common.done.alt") : L("common.next")) {
                    if last { onFinish() } else { withAnimation { index += 1 } }
                }
                .buttonStyle(.primary)
                .frame(width: 120)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(DS.Palette.surface2))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(DS.Palette.border, lineWidth: 1))
        .foregroundStyle(DS.Palette.text)
    }
}

/// Sağ altta yüzen "Nino'ya Sor" robotu.
struct AskNinoButton: View {
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            BotFace(size: 46, floating: true)
                .frame(width: 62, height: 62)
                .background(Circle().fill(Color.white.opacity(0.95)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.75), lineWidth: 1))
                .shadow(color: DS.Palette.pro.opacity(0.22), radius: 14, y: 6)
        }
        .buttonStyle(BotButtonStyle())
        .accessibilityLabel(Text(L("ask.title")))
        .sheet(isPresented: $open) { AskNinoSheet() }
    }
}

private struct BotButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
