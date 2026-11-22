// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI

// Karo, kart, karo simgesi, etiket, durum noktası, canlı nokta, durum satırı/karosu, degrade simge kutusu,
// numaralı satır ve küçük metinler (tasarim-dili.md §8.5–§8.14). Metinler çağıran tarafça çevrilmiş gelir.

// MARK: - Karo ve kart (§8.5)

public struct NinoTileModifier: ViewModifier {
    public var active: Bool
    public var padding: CGFloat
    @Environment(\.colorScheme) private var scheme

    public init(active: Bool = false, padding: CGFloat = NinoSpacing.l) {
        self.active = active
        self.padding = padding
    }

    public func body(content: Content) -> some View {
        let shape = NinoRadius.shape(NinoRadius.card)
        content
            .padding(padding)
            .ninoGlass(in: shape, edge: !active)
            .overlay { if active { shape.strokeBorder(NinoColor.accent, lineWidth: 1.5) } }
            .shadow(color: NinoColor.pro.color(scheme).opacity(0.08), radius: 18, y: 8)
    }
}

public extension View {
    /// Karo zemini: 16 iç boşluk, cam, köşe 22, 1 pt cam kenarı (etkinse 1,5 pt accent), hafif gölge.
    func ninoTile(active: Bool = false, padding: CGFloat = NinoSpacing.l) -> some View {
        modifier(NinoTileModifier(active: active, padding: padding))
    }
}

/// Kart: sola yaslı dikey yığın (aralık 12), tam genişlik, karo zemininde; isteğe bağlı başlık (headline).
public struct NinoCard<Content: View>: View {
    private let title: String?
    private let content: Content

    public init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: NinoSpacing.m) {
            if let title {
                Text(title).font(.nino(.headline))
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninoTile()
    }
}

// MARK: - Karo simgesi (§8.6)

/// 24'lük accentSoft daire içinde 12 pt simge; paket türünde pro rengi.
public struct NinoTileIcon: View {
    private let systemName: String
    private let pack: Bool

    public init(systemName: String, pack: Bool = false) {
        self.systemName = systemName
        self.pack = pack
    }

    public var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(pack ? NinoColor.pro : NinoColor.accentText)
            .frame(width: 24, height: 24)
            .background(Circle().fill(NinoColor.accentSoft))
            .accessibilityHidden(true)
    }
}

// MARK: - Etiket (§8.7)

public struct NinoTag: View {
    public enum Kind: Sendable { case normal, pack, live }
    private let text: String
    private let kind: Kind

    public init(_ text: String, kind: Kind = .normal) {
        self.text = text
        self.kind = kind
    }

    public var body: some View {
        switch kind {
        case .live:
            HStack(spacing: NinoSpacing.s) {
                NinoLiveDot()
                Text(text).font(.nino(.caption)).foregroundStyle(NinoColor.textPrimary).lineLimit(1)
            }
        case .normal, .pack:
            Text(text)
                .font(.nino(.caption).monospacedDigit())
                .lineLimit(1)
                .foregroundStyle(kind == .pack ? NinoColor.pro : NinoColor.textSecondary)
                .padding(.horizontal, NinoSpacing.s)
                .frame(height: 24)
                .background(NinoRadius.shape(NinoRadius.tag).fill(kind == .pack ? NinoColor.proSoft : NinoColor.surface2))
        }
    }
}

// MARK: - Durum noktası ve tonu (§8.8)

public enum NinoStatusTone: Sendable, Equatable {
    case good, warning, idle

    public var color: NinoColor {
        switch self {
        case .good: return .success
        case .warning: return .warning
        case .idle: return .textSecondary
        }
    }

    /// PS5 / görüntü kaynağı kuralı: akıyorsa iyi; akmıyor ve çeviri açıksa uyarı; çeviri kapalıysa boşta.
    public static func source(streaming: Bool, translating: Bool) -> NinoStatusTone {
        streaming ? .good : (translating ? .warning : .idle)
    }

    /// TV kuralı: en az bir TV bağlıysa iyi; bağlı yok ve çeviri açıksa uyarı; çeviri kapalıysa boşta.
    public static func tv(connected: Int, translating: Bool) -> NinoStatusTone {
        connected > 0 ? .good : (translating ? .warning : .idle)
    }
}

/// 8×8 durum noktası (ekran okuyucudan gizli).
public struct NinoStatusDot: View {
    private let tone: NinoStatusTone
    private let size: CGFloat

    public init(_ tone: NinoStatusTone, size: CGFloat = NinoSize.statusDot) {
        self.tone = tone
        self.size = size
    }

    public var body: some View {
        Circle().fill(tone.color).frame(width: size, height: size).accessibilityHidden(true)
    }
}

// MARK: - Canlı nokta (§8.9)

/// 8×8 dolu daire ve arkasında 2 sn'de bir büyüyüp kaybolan 16'lık halka.
public struct NinoLiveDot: View {
    private let color: Color?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ninoStaticRendering) private var isStatic
    @State private var ringExpanded = false

    /// - Parameter color: Varsayılan success; TV içinde bayrak kırmızısı.
    public init(color: Color? = nil) { self.color = color }

    public var body: some View {
        ZStack {
            if !reduceMotion && !isStatic {
                Circle()
                    .stroke(fill, lineWidth: 2)
                    .frame(width: 16, height: 16)
                    .scaleEffect(ringExpanded ? 1.2 : 0.5)
                    .opacity(ringExpanded ? 0 : 0.7)
            }
            Circle().fill(fill).frame(width: 8, height: 8)
        }
        .frame(width: 8, height: 8)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion, !isStatic else { return }
            withAnimation(.easeOut(duration: 2).repeatForever(autoreverses: false)) { ringExpanded = true }
        }
    }

    private var fill: AnyShapeStyle { color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(NinoColor.success) }
}

// MARK: - Durum satırı (§8.10) ve durum karosu (§8.11)

public struct NinoStatusRow: View {
    private let title: String
    private let value: String
    private let tone: NinoStatusTone

    public init(title: String, value: String, tone: NinoStatusTone) {
        self.title = title
        self.value = value
        self.tone = tone
    }

    public var body: some View {
        HStack(spacing: NinoSpacing.m) {
            NinoStatusDot(tone)
            Text(title).font(.nino(.body).weight(.semibold))
            Spacer(minLength: 0)
            Text(value)
                .lineLimit(1)
                .foregroundStyle(tone == .good ? NinoColor.textPrimary : NinoColor.textSecondary)
        }
    }
}

/// Durum karosu. Aynı sıradaki karolar eşit boy alsın diye `frame(maxHeight: .infinity)` ile kullanın.
public struct NinoStatusTile<Accessory: View>: View {
    private let systemName: String
    private let title: String
    private let value: String
    private let tone: NinoStatusTone
    private let accessory: Accessory

    public init(systemName: String, title: String, value: String, tone: NinoStatusTone,
                @ViewBuilder accessory: () -> Accessory) {
        self.systemName = systemName
        self.title = title
        self.value = value
        self.tone = tone
        self.accessory = accessory()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: NinoSpacing.s) {
            HStack(spacing: NinoSpacing.s) {
                NinoTileIcon(systemName: systemName)
                Text(title).font(.nino(.caption)).foregroundStyle(NinoColor.textSecondary)
                Spacer(minLength: 0)
                if tone != .idle { NinoStatusDot(tone) }
            }
            Text(value).font(.nino(.headline)).fixedSize(horizontal: false, vertical: true)
            accessory
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ninoTile()
        .accessibilityElement(children: .combine)
    }
}

public extension NinoStatusTile where Accessory == EmptyView {
    init(systemName: String, title: String, value: String, tone: NinoStatusTone) {
        self.init(systemName: systemName, title: title, value: value, tone: tone) { EmptyView() }
    }
}

// MARK: - Degrade simge kutusu (§8.12)

public struct NinoGradientIconBox: View {
    private let systemName: String
    private let size: CGFloat
    @Environment(\.colorScheme) private var scheme

    public init(systemName: String, size: CGFloat = 44) {
        self.systemName = systemName
        self.size = size
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(shape.fill(NinoGradients.iconFill(scheme)))
            .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.05)],
                                                       startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(color: NinoColor.accent.color(scheme).opacity(0.45), radius: size * 0.25, y: size * 0.10)
            .accessibilityHidden(true)
    }
}

/// Ortak degradeler.
public enum NinoGradients {
    /// Simge kutusu ve numara dairesi: sol üstten sağ alta accentHi → derin lacivert.
    public static func iconFill(_ scheme: ColorScheme) -> LinearGradient {
        LinearGradient(colors: [NinoColor.accentHi.color(scheme), NinoFixedColor.deepNavy.color],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Birincil düğme ve seçili bölme: yukarıdan aşağı accent → derin lacivert.
    public static func primaryFill(_ scheme: ColorScheme) -> LinearGradient {
        LinearGradient(colors: [NinoColor.accent.color(scheme), NinoFixedColor.deepNavy.color],
                       startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - Numaralı satır (§8.13)

public struct NinoNumberedRow: View {
    private let number: Int
    private let text: String
    @Environment(\.colorScheme) private var scheme

    public init(number: Int, text: String) {
        self.number = number
        self.text = text
    }

    public var body: some View {
        HStack(alignment: .center, spacing: NinoSpacing.l) {
            Text("\(number)")
                .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(NinoGradients.iconFill(scheme)))
                .shadow(color: NinoColor.accent.color(scheme).opacity(0.35), radius: 6, y: 2)
            Text(text)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .ninoTile()
    }
}

// MARK: - Küçük metinler (§8.14)

/// İpucu: callout, textSecondary, satır arası +2, alt satıra kayar.
public struct NinoHint: View {
    private let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text)
            .font(.nino(.callout))
            .foregroundStyle(NinoColor.textSecondary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Hata: üçgen simge + metin, callout, warning.
public struct NinoErrorLabel: View {
    private let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Label { Text(text).fixedSize(horizontal: false, vertical: true) } icon: {
            Image(systemName: NinoSymbol.errorFill)
        }
        .font(.nino(.callout))
        .foregroundStyle(NinoColor.warning)
    }
}

/// Tamam: onay simgesi + metin, body yarı kalın, success.
public struct NinoOKLabel: View {
    private let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Label { Text(text) } icon: { Image(systemName: NinoSymbol.okFill) }
            .font(.nino(.body).weight(.semibold))
            .foregroundStyle(NinoColor.success)
    }
}
