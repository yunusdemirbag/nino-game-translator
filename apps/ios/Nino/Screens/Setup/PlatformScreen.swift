// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI

/// Konsol seçimi: PlayStation 5 ya da Xbox (Beta).
struct PlatformScreen: View {
    @EnvironmentObject private var model: AppModel
    var onBack: (() -> Void)?
    let onDone: () -> Void
    @State private var choice: ConsoleKind = .playstation

    var body: some View {
        NinoScreen {
            HStack {
                if let onBack { SquareIconButton(symbol: "chevron.left", label: L("common.back"), action: onBack) }
                Spacer(minLength: 0)
            }
            .frame(height: DS.Size.icon)
        } content: {
            HeroTitle(title: L("console.title"),
                      lead: L("console.choose.body"),
                      spacing: 4)
            ChoiceTile(title: "PlayStation 5", detail: L("console.ps5.detail"),
                       selected: choice == .playstation) { choice = .playstation }
            ChoiceTile(title: "Xbox", tag: "Beta",
                       detail: L("console.xbox.detail"),
                       selected: choice == .xbox) { choice = .xbox }
            if choice == .xbox {
                NoteLine(text: L("xbox.beta.note"),
                         color: DS.Palette.secondary)
            }
        } footer: {
            Button(L("common.next")) {
                model.choosePlatform(choice)
                onDone()
            }
            .buttonStyle(.primary)
        }
        .onAppear { choice = model.platform }
    }
}
