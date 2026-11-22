// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI
import UIKit

/// Tam ekran altyazı: simsiyah zemin, alta yaslı büyük yazı. iPhone'da yatay açılır, parlaklık kısılır.
struct SubtitleScreen: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var savedBrightness: CGFloat?

    private var baseSize: CGFloat { DS.isPad ? 60 : 36 }
    private var font: SubtitleTypeface { model.settings.style.font }
    private var textColor: Color { model.settings.style.isYellow ? DS.Palette.subtitleYellow : .white }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 8) {
                Spacer(minLength: 0)
                if model.isDemo {
                    if let line = model.demoLine?.translation { subtitle(line, last: true, fading: false) }
                } else {
                    ForEach(Array(model.stack.lines.enumerated()), id: \.element.id) { i, line in
                        subtitle(BalancedWrap.wrap(line.text), last: i == model.stack.lines.count - 1, fading: line.fading)
                    }
                }
            }
            .padding(.horizontal, DS.isPad ? 60 : 20)
            .padding(.bottom, DS.isPad ? 80 : 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let problem = model.problemText {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text(problem)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: 520)
                .padding(20)
                .allowsHitTesting(false)
                .accessibilityElement(children: .combine)
            }

            VStack {
                HStack(alignment: .top) {
                    statusLabel
                    Spacer(minLength: 0)
                    SquareIconButton(symbol: "xmark", label: L("common.close.alt")) { dismiss() }
                }
                Spacer(minLength: 0)
                Text(L("phone.keepon.note"))
                    .font(DS.Font.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.bottom, 8)
            }
            .padding(20)
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .environment(\.layoutDirection, .leftToRight)
        .onAppear {
            Orientation.request(.landscape)
            savedBrightness = UIScreen.main.brightness
            UIScreen.main.brightness = min(UIScreen.main.brightness, 0.4)
        }
        .onDisappear {
            Orientation.request(.portrait)
            if let savedBrightness { UIScreen.main.brightness = savedBrightness }
        }
    }

    private func subtitle(_ text: String, last: Bool, fading: Bool) -> some View {
        let size = baseSize * model.settings.style.scale
        return Text(verbatim: TextDirection.prepared(text))
            .font(font.font(size: size))
            .tracking(font.tracking(size: size))
            .foregroundStyle(last ? textColor : Color(rgb: 0x7C7A76))
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.5)
            .opacity(fading ? 0.4 : 1)
            .subtitleDirection(for: text)
            .transition(.opacity)
    }

    @ViewBuilder private var statusLabel: some View {
        let streaming = model.link == .streaming || model.isDemo
        let text: String = {
            if model.isDemo { return L("demo.status") }
            if model.link != .streaming {
                return model.problemText == nil ? model.consoleStatusText : L("status.connecting")
            }
            return model.settings.packsActive ? L("status.ps5.packs") : L("status.ps5.connected")
        }()
        if streaming {
            StatusLabel(text: text, dotColor: DS.Palette.success, pulsing: true, onDark: true)
        } else {
            TagLabel(text: text)
        }
    }
}
