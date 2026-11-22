// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI

/// Simge tonu.
enum Tone {
    case neutral, ok, accent, pro, error

    var color: Color {
        switch self {
        case .neutral: DS.Palette.secondary
        case .ok, .accent: DS.Palette.accent
        case .pro: DS.Palette.pro
        case .error: DS.Palette.danger
        }
    }
}

/// Cam karo.
struct Tile<Content: View>: View {
    var selected = false
    var spacing: CGFloat = 8
    @ViewBuilder let content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
        VStack(alignment: .leading, spacing: spacing, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.Space.tile)
            .background(shape.fill(DS.Palette.surface))
            .overlay(shape.strokeBorder(selected ? DS.Palette.accent : DS.Palette.border, lineWidth: selected ? 1.5 : 1))
            .shadow(color: DS.Palette.pro.opacity(0.10), radius: 14, y: 6)
    }
}

/// Karo içindeki kutusuz simge.
struct TileSymbol: View {
    let symbol: String
    var tone: Tone = .neutral

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(tone.color)
            .frame(width: 18, height: 18)
            .accessibilityHidden(true)
    }
}

/// Bir değeri gösteren karo ("PS5 / Bağlı Değil").
struct ValueTile: View {
    let symbol: String
    var tone: Tone = .neutral
    let label: String
    let value: String
    var live = false
    var selected = false

    var body: some View {
        Tile(selected: selected) {
            HStack(spacing: DS.Space.inline) {
                TileSymbol(symbol: symbol, tone: tone)
                Text(label).font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
                Spacer(minLength: 0)
                if live { StatusDot() }
            }
            Text(value).font(DS.Font.title).lineLimit(1).minimumScaleFactor(0.6)
        }
    }
}

/// Başlık ve açıklamalı karo.
struct InfoTile: View {
    let symbol: String
    var tone: Tone = .neutral
    let title: String
    let detail: String
    var selected = false

    var body: some View {
        Tile(selected: selected) {
            HStack(spacing: DS.Space.inline) {
                TileSymbol(symbol: symbol, tone: tone)
                Text(title).font(DS.Font.headline).fixedSize(horizontal: false, vertical: true)
            }
            Text(detail).font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

/// Liste satırı (geniş karonun içinde).
struct ListRow<Trailing: View>: View {
    let symbol: String
    var tone: Tone = .neutral
    let title: String
    var detail: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: DS.Space.gap) {
            TileSymbol(symbol: symbol, tone: tone)
            Text(title).font(DS.Font.headline).foregroundStyle(DS.Palette.text)
            Spacer(minLength: 8)
            if let detail {
                Text(detail).font(DS.Font.caption).foregroundStyle(DS.Palette.secondary).lineLimit(1)
            }
            trailing()
        }
        .frame(minHeight: DS.Size.row)
        .contentShape(Rectangle())
    }
}

/// Gidilecek ekranı olan satırın oku.
struct RowChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(DS.Palette.tertiary)
    }
}

/// Satır ayracı.
struct RowDivider: View {
    var body: some View {
        Rectangle().fill(DS.Palette.borderStrong.opacity(0.7)).frame(height: 1)
    }
}

/// Oyunun kısaltması ("GTA").
struct GameBadge: View {
    let text: String
    var size: CGFloat = 44

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(DS.Palette.text)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: DS.Radius.inner).fill(DS.Palette.surface2))
    }
}

// MARK: Etiketler ve durum

/// Durum noktası; canlıyken etrafında halka atar.
struct StatusDot: View {
    var color: Color = DS.Palette.success
    var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay {
                if pulsing && !reduceMotion {
                    Circle()
                        .stroke(color, lineWidth: 2)
                        .frame(width: 16, height: 16)
                        .scaleEffect(pulse ? 1.2 : 0.5)
                        .opacity(pulse ? 0 : 0.7)
                        .onAppear {
                            withAnimation(.easeOut(duration: 2).repeatForever(autoreverses: false)) { pulse = true }
                        }
                }
            }
            .accessibilityHidden(true)
    }
}

/// Durum satırı ("● Bağlı Değil") ya da küçük etiket ("Beta").
struct StatusLabel: View {
    let text: String
    var dotColor: Color? = nil
    var pulsing = false
    var onDark = false

    var body: some View {
        HStack(spacing: DS.Space.inline) {
            if let dotColor { StatusDot(color: dotColor, pulsing: pulsing) }
            Text(text).font(DS.Font.caption.monospacedDigit()).lineLimit(1)
        }
        .foregroundStyle(onDark ? Color.white.opacity(0.75) : DS.Palette.text)
    }
}

struct TagLabel: View {
    let text: String
    var pro = false

    var body: some View {
        Text(text)
            .font(DS.Font.caption.monospacedDigit())
            .lineLimit(1)
            .foregroundStyle(pro ? DS.Palette.pro : DS.Palette.secondary)
            .padding(.horizontal, 8)
            .frame(height: DS.Size.tag)
            .background(RoundedRectangle(cornerRadius: DS.Radius.tag).fill(pro ? DS.Palette.proSoft : DS.Palette.surface2))
    }
}

/// Uyarı satırı.
struct NoteLine: View {
    let text: String
    var color: Color = DS.Palette.warning

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(DS.Font.caption)
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Karşılama ve tur sayfa noktaları.
struct PageIndicator: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(DS.Palette.text.opacity(i == current ? 1 : 0.18))
                    .frame(width: i == current ? 22 : 8, height: 8)
            }
        }
        .animation(.easeOut(duration: 0.2), value: current)
        .accessibilityHidden(true)
    }
}

/// Koyu sahne üstündeki "Ücretsiz" etiketi.
struct FreeBadge: View {
    var text = L("ob.free")

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(DS.Palette.freeGreen)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(DS.Palette.freeGreen.opacity(0.14)))
            .overlay(Capsule().strokeBorder(DS.Palette.freeGreen.opacity(0.35), lineWidth: 1))
    }
}

// MARK: Koyu sahne

/// Koyu, yuvarlak köşeli sahne kartı.
struct DarkStage<Content: View>: View {
    var height: CGFloat? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.stage, style: .continuous)
        ZStack(content: content)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(LinearGradient(colors: [DS.Palette.stageTop, DS.Palette.stageBottom], startPoint: .top, endPoint: .bottom))
            .clipShape(shape)
            .overlay(shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0.03)],
                                                       startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(color: DS.Palette.text.opacity(0.35), radius: 18, y: 10)
    }
}

/// Sahne içindeki cam satır.
struct GlassRow<Trailing: View>: View {
    let symbol: String
    let title: String
    var detail: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        HStack(spacing: DS.Space.gap) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.white.opacity(0.10)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.7)
                if let detail {
                    Text(detail).font(.system(size: 13)).foregroundStyle(.white.opacity(0.6)).lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(shape.fill(Color.white.opacity(0.07)))
        .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }
}

extension GlassRow where Trailing == EmptyView {
    init(symbol: String, title: String, detail: String? = nil) {
        self.init(symbol: symbol, title: title, detail: detail, trailing: { EmptyView() })
    }
}
