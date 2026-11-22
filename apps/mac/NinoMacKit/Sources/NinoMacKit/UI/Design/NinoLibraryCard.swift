// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import NinoCore
import SwiftUI

/// Nino kütüphanesinin oyun listesi (kurulumun çeviri adımı ve Ayarlar › Çeviri aynı kaynağı kullanır).
enum NinoLibrary {
    /// GTA 6 her zaman (havuz öncelikli), ardından kurulu paketler; aynı oyun bir kez.
    static func gameNames(_ packs: [GamePackInfo]) -> [String] {
        var names = ["GTA 6"]
        for p in packs where !names.contains(where: { GameTracker.same($0, p.name) }) { names.append(p.name) }
        return names
    }
}

/// "Kütüphane aktif" kartı: solda maskot, sağda onaylı başlık, açıklama ve altında oyunlar.
/// Seçilecek bir şey değildir; metinler çağıranın tablosundan gelir.
struct NinoLibraryCard<Games: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let games: Games

    var body: some View {
        HStack(alignment: .center, spacing: NinoSpacing.l) {
            NinoAsset.mascot.image
                .aspectRatio(contentMode: .fit)
                .frame(width: 72, height: 84)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: NinoSymbol.okFill).foregroundStyle(NinoColor.success)
                    Text(title).fixedSize(horizontal: false, vertical: true)
                }
                .font(.nino(.headline))
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                Text(detail)
                    .font(.nino(.callout))
                    .foregroundStyle(NinoColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                games
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninoTile()
    }
}
