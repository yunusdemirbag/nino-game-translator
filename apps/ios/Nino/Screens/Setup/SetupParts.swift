// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI

/// Kurulum ekranlarının üst satırı: geri, üç parçalı ilerleme, "Şimdilik Geç".
struct SetupHeader: View {
    let step: Int
    var onBack: (() -> Void)?
    var onSkip: (() -> Void)?

    var body: some View {
        HStack(spacing: DS.Space.gap) {
            if let onBack {
                SquareIconButton(symbol: "chevron.left", label: L("common.back"), action: onBack)
            }
            HStack(spacing: 4) {
                ForEach(1...3, id: \.self) { i in
                    Capsule()
                        .fill(i <= step ? DS.Palette.accent : DS.Palette.borderStrong)
                        .frame(height: 4)
                }
            }
            .frame(maxWidth: .infinity)
            if let onSkip {
                Button(L("common.skipfornow"), action: onSkip)
                    .buttonStyle(.ghost)
                    .fixedSize()
            }
        }
        .frame(height: DS.Size.icon)
    }
}

/// "Yeniden Ara": aranırken dönen gösterge, değilse yenile düğmesi.
struct SearchAgainButton: View {
    let searching: Bool
    let action: () -> Void

    var body: some View {
        if searching {
            ProgressView().tint(DS.Palette.accent).frame(width: DS.Size.icon, height: DS.Size.icon)
        } else {
            SquareIconButton(symbol: "arrow.clockwise", label: L("common.searchagain"), tint: DS.Palette.accent, action: action)
        }
    }
}

/// İçeriği kadar açılan alt sayfa.
struct FittedSheet: ViewModifier {
    @State private var height: CGFloat = 320

    func body(content: Content) -> some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                height = h.rounded(.up)
            }
            .presentationDetents([.height(height)])
            .presentationDragIndicator(.visible)
            .presentationBackground(DS.Palette.surface)
    }
}

extension View {
    func fittedSheet() -> some View { modifier(FittedSheet()) }
}

/// Küçük bilgi sayfasının içi: 20 boşluk, aralık 12, sola yaslı.
struct SheetBody<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.gap, content: content)
            .padding(DS.Space.screen)
            .foregroundStyle(DS.Palette.text)
            .readableColumn()
    }
}

/// Seçilebilir seçenek karosu (konsol seçimi).
struct ChoiceTile: View {
    let title: String
    var tag: String? = nil
    let detail: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Tile(selected: selected) {
                HStack(spacing: DS.Space.gap) {
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(selected ? DS.Palette.accent : DS.Palette.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(verbatim: title).font(DS.Font.headline)
                            if let tag { TagLabel(text: tag) }
                        }
                        Text(detail).font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(DS.Palette.text)
    }
}
