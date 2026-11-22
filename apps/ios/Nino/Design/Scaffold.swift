// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI

extension View {
    /// iPad'de içeriği en çok 680 pt genişlikte bir sütuna alıp ortalar; iPhone'da bir şey yapmaz.
    @ViewBuilder func readableColumn() -> some View {
        if DS.isPad {
            frame(maxWidth: DS.Size.readable).frame(maxWidth: .infinity)
        } else {
            self
        }
    }
}

/// Uygulama ekranlarının üç bölmeli iskeleti: üst satır, kayan içerik, altta sabit düğmeler.
struct NinoScreen<Header: View, Content: View, Footer: View>: View {
    private let header: Header
    private let content: Content
    private let footer: Footer

    init(@ViewBuilder header: () -> Header,
         @ViewBuilder content: () -> Content,
         @ViewBuilder footer: () -> Footer) {
        self.header = header()
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .readableColumn()
                .padding(.horizontal, DS.Space.screen)
                .padding(.top, DS.isPad ? 20 : 8)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: DS.Space.gap) { content }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .readableColumn()
                    .padding(.horizontal, DS.Space.screen)
                    .padding(.top, DS.Space.gap)
                    .padding(.bottom, DS.Space.screen)
            }
            VStack(spacing: DS.Space.gap) { footer }
                .readableColumn()
                .padding(.horizontal, DS.Space.screen)
                .padding(.bottom, DS.isPad ? 40 : 20)
        }
        .foregroundStyle(DS.Palette.text)
        .background(ScreenBackground())
        .toolbar(.hidden, for: .navigationBar)
    }
}

extension NinoScreen where Footer == EmptyView {
    init(@ViewBuilder header: () -> Header, @ViewBuilder content: () -> Content) {
        self.init(header: header, content: content, footer: { EmptyView() })
    }
}

/// İki sütunlu karo ızgarası. "Geniş" işaretli karo tam satır kaplar; bir satırdaki karolar eşit boydadır.
struct BentoGrid: Layout {
    var spacing: CGFloat = DS.Space.gap

    private func rows(_ subviews: Subviews) -> [[Int]] {
        var result: [[Int]] = []
        var current: [Int] = []
        for i in subviews.indices {
            if subviews[i][BentoWide.self] {
                if !current.isEmpty { result.append(current); current = [] }
                result.append([i])
            } else {
                current.append(i)
                if current.count == 2 { result.append(current); current = [] }
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private func layout(width: CGFloat, subviews: Subviews) -> [(row: [Int], height: CGFloat)] {
        let column = (width - spacing) / 2
        return rows(subviews).map { row in
            let w = row.count == 1 && subviews[row[0]][BentoWide.self] ? width : column
            let h = row.map { subviews[$0].sizeThatFits(ProposedViewSize(width: w, height: nil)).height }.max() ?? 0
            return (row, h)
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 350
        let rows = layout(width: width, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let column = (bounds.width - spacing) / 2
        var y = bounds.minY
        for (row, height) in layout(width: bounds.width, subviews: subviews) {
            for (n, index) in row.enumerated() {
                let wide = subviews[index][BentoWide.self]
                let w = wide ? bounds.width : column
                let x = bounds.minX + (wide ? 0 : CGFloat(n) * (column + spacing))
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: w, height: height))
            }
            y += height + spacing
        }
    }
}

struct BentoWide: LayoutValueKey {
    static let defaultValue = false
}

extension View {
    /// Bento ızgarasında tam satır kaplar.
    func bentoWide(_ wide: Bool = true) -> some View { layoutValue(key: BentoWide.self, value: wide) }
}
