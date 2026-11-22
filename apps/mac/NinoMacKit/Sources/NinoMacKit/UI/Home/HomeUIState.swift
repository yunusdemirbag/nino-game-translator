// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Observation
import SwiftUI

/// Ana pencerenin yalnız arayüze ait, uygulama açık kaldıkça süren durumu.
/// Motorla ilgisi yoktur; `AppState`'e konmaz.
@MainActor
@Observable
public final class HomeUIState {
    /// Açılış animasyonu bitti mi (bitmeden ana ekran kurulmaz, robot görünmez).
    public var splashFinished: Bool
    /// Salondaki fiş gösterisi bu açılışta oynadı mı (Ayarlar'dan dönünce yeniden oynamaz).
    public var livingRoomIntroPlayed: Bool
    /// "Başladı" balonu gösterilsin mi.
    public var startedBubbleVisible = false
    /// Hazırlanırken gelen tıklama: hazırlık bitince çeviri durdurulacak.
    private(set) var stopWhenReady = false

    /// - Parameter skipIntro: Testlerde ve ekran görüntülerinde açılış ve fiş gösterisi oynamaz.
    public init(skipIntro: Bool = false) {
        splashFinished = skipIntro
        livingRoomIntroPlayed = skipIntro
    }

    /// Takma/çıkarma kuralı (ana-ekran.md §4.8; cam anahtarda da aynısı).
    public func togglePlug(_ state: AppState) {
        switch state.translation {
        case .starting:
            // Hazırlık sürüyor: tıklama kaybolmasın, hazırlık bitince durdurulur.
            stopWhenReady = true
        case .on:
            state.stopTranslation()
        case .off:
            if state.canStart {
                state.startTranslation()
            } else {
                state.openSetup(at: .console)
            }
        }
    }

    /// Ana ekranda Enter: fişe tıklamakla aynı (aynı canlanma). Sayfa açıkken ya da kurulum sürerken işlenmez.
    /// - Returns: Tuş işlendi mi.
    @discardableResult
    public func handleReturnKey(_ state: AppState) -> Bool {
        guard state.activeSheet == nil, state.isSetupComplete, splashFinished else { return false }
        togglePlug(state)
        return true
    }

    /// Çeviri durumu değişince çağrılır (ana pencere bağlar).
    public func translationChanged(_ state: AppState, from old: TranslationPhase) {
        if old == .starting, state.translation != .starting, stopWhenReady {
            stopWhenReady = false
            if state.translation == .on { state.stopTranslation() }
        }
        if state.translation == .off { stopWhenReady = false }
    }
}
