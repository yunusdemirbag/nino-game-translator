// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI
import UIKit

/// "Nino'ya Sor" robotunun yüzü: göz kırpar, isteğe bağlı süzülür ya da düşünürken sallanır.
struct BotFace: View {
    var size: CGFloat
    var blinking = true
    var floating = false
    var thinking = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var eyesClosed = false
    @State private var up = false
    @State private var tilt = false

    private static let open = Bundle.main.path(forResource: "nino-bot-256", ofType: "png").flatMap(UIImage.init(contentsOfFile:))
    private static let closed = Bundle.main.path(forResource: "nino-bot-blink-256", ofType: "png").flatMap(UIImage.init(contentsOfFile:))

    var body: some View {
        Group {
            if let image = (eyesClosed ? Self.closed : nil) ?? Self.open {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "face.smiling").resizable().scaledToFit().foregroundStyle(.tint)
            }
        }
        .frame(width: size, height: size)
        .offset(y: floating && !reduceMotion ? (up ? -size * 0.05 : size * 0.05) : 0)
        .rotationEffect(.degrees(thinking && !reduceMotion ? (tilt ? 6 : -6) : 0))
        .accessibilityHidden(true)
        .task(id: blinking && !reduceMotion) {
            guard blinking, !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(Int.random(in: 4000...5000)))
                eyesClosed = true
                try? await Task.sleep(for: .milliseconds(150))
                eyesClosed = false
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            if floating { withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { up = true } }
        }
        .onChange(of: thinking, initial: true) { _, now in
            guard !reduceMotion else { return }
            if now {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { tilt = true }
            } else {
                withAnimation(.easeOut(duration: 0.2)) { tilt = false }
            }
        }
    }
}

/// "Yazıyor" üç noktası.
struct TypingDots: View {
    var color: Color = DS.Palette.secondary
    var diameter: CGFloat = 7
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: diameter * 0.6) {
                ForEach(0..<3, id: \.self) { i in
                    let phase = reduceMotion ? 0.5 : (sin(2 * .pi * t / 1.2 - Double(i) * 0.9) + 1) / 2
                    Circle()
                        .fill(color)
                        .frame(width: diameter, height: diameter)
                        .opacity(0.35 + 0.65 * phase)
                        .scaleEffect(0.75 + 0.35 * phase)
                }
            }
            .frame(height: diameter * 1.6)
        }
        .accessibilityHidden(true)
    }
}

/// Soldan sağa dizilen, sığmayanı alt satıra geçiren düzen (öneri çipleri).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(width, maxX), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
