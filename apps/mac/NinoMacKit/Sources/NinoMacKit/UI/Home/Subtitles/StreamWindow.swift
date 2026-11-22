// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AppKit
import SwiftUI

// Yayın penceresi (ana-ekran.md §13): saydamlık tanımayan yayın programları için düz zeminli pencere.

public extension StreamBackground {
    /// Yeşil #00FF00, siyah #000000, mor #FF00FF.
    var color: Color {
        switch self {
        case .green: return NinoRGB(hex: 0x00FF00).color
        case .black: return NinoRGB(hex: 0x000000).color
        case .magenta: return NinoRGB(hex: 0xFF00FF).color
        }
    }
}

/// Yayın penceresinin içi. Satırlar her zaman klasik biçimde; Arapça için yön işareti eklenmez.
public struct StreamWindowContent: View {
    private let state: AppState
    @State private var stack = SubtitleStack()

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        GeometryReader { proxy in
            let scale = Swift.max(proxy.size.height / 1080, 0.2)  // 1080p kalıbına göre
            let style = state.settings.style
            ZStack {
                state.streamBackground.color
                VStack(spacing: 14 * scale) {
                    VStack(spacing: 10 * scale) {
                        ForEach(state.extraAreaTexts) { extra in
                            ExtraAreaBox(extra.text, style: style, scale: scale, solid: true)
                                .frame(maxWidth: .infinity, alignment: extra.alignment.frameAlignment)
                        }
                    }
                    .padding(.top, 16 * scale)
                    Spacer(minLength: 0)
                    ForEach(stack.visibleLines.sorted { $0.rank > $1.rank }) { entry in
                        ClassicSubtitleLine(entry.text, style: style, scale: scale, isCurrent: entry.rank == 0,
                                            box: .solid, fade: SubtitleStack.opacity(for: entry))
                            .opacity(entry.fading ? 0 : 1)
                    }
                }
                .padding(.horizontal, 24 * scale)
                .padding(.bottom, proxy.size.height * 0.07)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .background(StreamWindowConfigurator())
        .onChange(of: state.lastLine?.translated, initial: true) { _, text in
            if let text, !text.isEmpty {
                stack.push(text, stackPrevious: state.settings.style.stackPrevious)
            } else {
                stack.clear()
            }
        }
        .onDisappear { state.streamWindowOpen = false }
    }
}

/// Pencereye 16:9 oranı, en küçük boy ve kalıcı yer kaydını verir.
private struct StreamWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.contentAspectRatio = NSSize(width: 16, height: 9)
            window.contentMinSize = NSSize(width: 480, height: 270)
            if window.frameAutosaveName != "NinoStreamWindow" {
                if !window.setFrameUsingName("NinoStreamWindow") { window.center() }
                window.setFrameAutosaveName("NinoStreamWindow")
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
