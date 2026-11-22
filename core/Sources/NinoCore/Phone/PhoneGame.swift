// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

// MARK: - Telefon oyunu kararı (tarif §1.1)

extension GameReading {
    public enum PhoneGame {
        /// Oyunun nereden bilindiği.
        public enum Knowledge: Equatable, Sendable {
            /// PS5, kullanıcı ya da ekran söyledi.
            case certain(String)
            /// Yalnız altyazı paketinden tahmin.
            case packGuess(String)
            case unknown
        }

        public struct Decision: Equatable, Sendable {
            /// Telefon araması (ve GTA 6 kuralları) açık mı?
            public var on: Bool
            /// Oyun kesin biliniyorsa "son oyun havuz öncelikliydi" olarak saklanacak değer.
            public var rememberPoolPriority: Bool?
        }

        /// Havuz öncelikli oyun mu (`GTA 6` = `Grand Theft Auto VI` = `gta-6`)?
        public static func isPoolPriority(_ game: String?, games: [String] = PoolRemoteConfig().poolFirstGames) -> Bool {
            guard let game, !game.isEmpty else { return false }
            return games.contains { GameIDs.sameGame($0, game) }
        }

        public static func isPoolPriorityLanguage(_ language: String, languages: [String] = PoolRemoteConfig().poolFirstLanguages) -> Bool {
            languages.contains { $0.lowercased() == language.lowercased() }
        }

        /// Telefon araması yapılır mı?
        public static func decide(cornersEnabled: Bool, sourceLanguage: String, targetLanguage: String,
                                  game: Knowledge, lastGameWasPoolPriority: Bool,
                                  games: [String] = PoolRemoteConfig().poolFirstGames,
                                  languages: [String] = PoolRemoteConfig().poolFirstLanguages) -> Decision {
            let languageFirst = isPoolPriorityLanguage(targetLanguage, languages: languages)
            var remember: Bool?
            let gameOn: Bool
            switch game {
            case .certain(let name):
                gameOn = isPoolPriority(name, games: games)
                remember = gameOn
            case .packGuess(let name):
                gameOn = isPoolPriority(name, games: games) || languageFirst
            case .unknown:
                // Oyun bilinmezken telefon ve harita okuması açık kalır (tanınınca karar yeniden verilir).
                gameOn = true
            }
            let on = cornersEnabled && sourceLanguage.lowercased().hasPrefix("en") && gameOn
            return Decision(on: on, rememberPoolPriority: remember)
        }
    }
}

// MARK: - Oyunu ekrandan tanıma (tarif §2)

extension GameReading {
    public enum ScreenGame {
        public static let gta6 = "GTA 6"

        /// Menü aramasının satırlarından oyun. Yoksa `nil`.
        public static func detect(_ lines: [String]) -> String? {
            if MapScreen.isMapScreen(lines) { return gta6 }
            let cleaned = lines.map { Corners.cleanMenuLine($0).lowercased() }
            let words = cleaned.map { Set(Text.keyWords($0)) }
            if words.contains(where: { $0.contains("jason") && $0.contains("lucia") }) { return gta6 }
            let brief = words.contains { $0.contains("brief") }
            let progress = words.contains { $0.contains("progress") }
            let person = words.contains { $0.contains("jason") || $0.contains("lucia") } || cleaned.contains("map")
            if brief, progress, person { return gta6 }
            if cleaned.contains(where: { Text.key($0) == "whatup" }) { return gta6 }
            return nil
        }
    }

    /// Oturumun oyun bilgisi: PS5/kullanıcı söyledi mi, ekrandan mı tanındı.
    public struct GameSense: Equatable, Sendable {
        /// PS5'in ya da kullanıcının söylediği oyun. Ekrandan tanıma bunu ezmez.
        public var reported: String?
        public private(set) var fromScreen: String?

        public init(reported: String? = nil) { self.reported = reported }

        public var current: String? { reported ?? fromScreen }

        /// Menü araması satırları. Oyun yeni tanındıysa `true` (görev çizgisi yeniden hesaplanmalı).
        public mutating func observeScreen(_ lines: [String]) -> Bool {
            guard let game = ScreenGame.detect(lines) else { return false }
            return note(game)
        }

        /// Telefonda sohbet ya da uygulama okundu.
        public mutating func notePhoneRead() -> Bool { note(ScreenGame.gta6) }

        mutating func note(_ game: String) -> Bool {
            if let r = reported, !r.isEmpty { return false }
            if let f = fromScreen, GameName.key(f) == GameName.key(game) { return false }
            fromScreen = game
            return true
        }
    }
}

// MARK: - GTA 6'ya özel kurallar (tarif §10)

extension GameReading {
    /// Yalnız telefon oyununda açık olan kurallar ve nerede oldukları.
    public enum GTA6Rules {
        public struct Rule: Equatable, Sendable {
            public var number: Int
            public var summary: String
            /// Kodun yeri; `nil` ise henüz yok.
            public var location: String?
        }

        public static let all: [Rule] = [
            Rule(number: 1, summary: "Telefon paneli ve uygulama balonları", location: "Phone/PhoneWatcher, PhoneLayout"),
            Rule(number: 2, summary: "Altyazıda telefon maskesi, açık zeminde koyu yazı, telefon yazıları", location: "FilterChain 5–10 + PhoneWatcher.context"),
            Rule(number: 3, summary: "Mesaj köşesi (sol ≥ 0,66, üst ≥ 0,74) kart sayılır", location: "FilterChain 6"),
            Rule(number: 4, summary: "Ortadan 0,12'den uzak blok altyazı değil", location: "FilterChain 14"),
            Rule(number: 5, summary: "Küçük harfle başlayan blok altyazı değil", location: "FilterChain 18"),
            Rule(number: 6, summary: "Mesaj listesi ve arama kartı altyazı değil", location: "FilterChain 19–20"),
            Rule(number: 7, summary: "Yer anahtarı gta-6, görev çizgisi ≤ 0,935, taban çizgisi", location: "Placement + Reader.Configuration.poolPriority"),
            Rule(number: 8, summary: "Görev şeridinde pembe vurgu", location: nil),
            Rule(number: 9, summary: "`A e DRINKS` ve balık ipuçları", location: "Filters.isHint"),
            Rule(number: 10, summary: "Menü sekmesi, harita ekranı ve harita kartı", location: "Phone/MapCard"),
            Rule(number: 11, summary: "Oyunu ekrandan tanıma", location: "Phone/PhoneGame (ScreenGame, GameSense)"),
            Rule(number: 12, summary: "Telefon uygulamaları: WhatUp, Ryde/Rydeme, BuckMe, Vice City Horn, Leonida Journal, fitness",
                 location: "Phone/PhoneDictionary"),
        ]

        /// Okuyucu ayarını telefon oyununa göre kurar.
        public static func apply(_ phoneGame: Bool, packGame: String?, to cfg: inout Reader.Configuration) {
            cfg.poolPriority = phoneGame
            cfg.cardsEnabled = cfg.cardsEnabled || phoneGame
            cfg.gameKey = Placement.gameKey(poolPriority: phoneGame, packGame: packGame)
            cfg.mapScreenCountsAsMenu = phoneGame
        }
    }
}
