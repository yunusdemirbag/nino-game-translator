// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI

// Henüz yazılmamış sayfalar için yer tutucular. Her sayfa kendi ajanınca yazılınca
// `SheetHost` (UI/Home/MainWindowView.swift) ve `SetupHost` içindeki ilgili satır değiştirilir.

/// Boş sayfa: başlık ve kapat düğmesi.
struct PlaceholderSheet: View {
    let title: String
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: NinoSpacing.l) {
            Text(verbatim: title).font(.nino(.display))
            Button("OK", action: onClose)
                .buttonStyle(.nino(.primary))
                .keyboardShortcut(.defaultAction)
        }
        .frame(minWidth: 640, minHeight: 480)
        .ninoScreen()
    }
}

/// Kurulum ekranının yer tutucusu (docs/yeni/mac/kurulum.md'yi yazacak ajan değiştirir).
struct SetupPlaceholder: View {
    let state: AppState

    var body: some View {
        VStack(spacing: NinoSpacing.l) {
            NinoSetupStepLayout(icon: .logo, title: "Setup", message: "\(state.setupStep.rawValue)") {
                Button("Done") {
                    state.setupStep = .done
                    state.setupOpenedFromHome = false
                }
                .buttonStyle(.nino(.primary, size: .hero))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
