// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import NinoCore

/// Oynanan oyun: beş kaynak, öncelik sırasıyla konsol → kullanıcı → paket → ekran → son oynanan (ninoya-sor.md §6).
/// "Hangi oyunu oynuyorsun?" sorusu artık sorulmaz: çeviri başlarken son oynanan oyun hemen etkin olur, ekran ve
/// paket isabetleri arka planda doğrular ya da sessizce başka oyuna geçer.
public struct GameTracker: Equatable, Sendable {
    /// Aday oyun: asıl kimlik (`GameIDs`: `pool-gta-6`, `Grand Theft Auto VI` → `gta-6`), görünen ad, varsa konsol kimliği.
    public struct Guess: Sendable, Equatable {
        public var id: String
        public var name: String
        /// PS5'in bildirdiği uygulama kimliği (`PPSA01234`); yalnız konsoldan gelende.
        public var titleID: String?
        public init(id: String, name: String, titleID: String? = nil) {
            self.id = id
            self.name = name
            self.titleID = titleID
        }
    }

    /// Paket çoğunluğu: son 20 oyun 5'i aynı paketten gelince.
    public static let voteWindow = 20
    public static let voteThreshold = 5
    /// Hızlı yol: penceredeki oyların hepsi aynı paketse 3 oy yeter; o paket zaten tahmin edilen oyunsa 1 oy doğrular.
    public static let unanimousThreshold = 3

    public private(set) var console: Guess?
    public private(set) var user: Guess?
    public private(set) var pack: Guess?
    public private(set) var screen: Guess?
    /// Son oynanan (PS5 adına göre; yoksa GTA 6): oturum başında hemen etkin, doğrulanmamış tahmin.
    public private(set) var seed: Guess?
    private var votes: [String] = []
    /// Oy veren paketlerin başlıkları (kimlik → başlık).
    private var voteTitles: [String: String] = [:]
    /// Bu oturumda soruldu mu (ya da "Sorma" dendi).
    public private(set) var asked = false
    public private(set) var sessionStarted: Date?

    public init() {}

    // MARK: Oturum

    /// Yeni çeviri oturumu: paket penceresi, konsol bilgisi ve "soruldu" işareti sıfırlanır; kullanıcının seçimi kalır.
    public mutating func startSession(at date: Date) {
        sessionStarted = date
        votes = []
        voteTitles = [:]
        pack = nil
        console = nil
        screen = nil
        seed = nil
        asked = false
    }

    public mutating func endSession() { sessionStarted = nil }

    /// Oturum başında son oynanan oyun (en düşük öncelik).
    public mutating func seed(_ name: String?) {
        guard let n = name.map(GameTracker.cleanName), !n.isEmpty else { seed = nil; return }
        seed = Guess(id: GameIDs.id(n) ?? n, name: n)
    }

    /// Tahmin uzun süre doğrulanmadı: bırakılır (oyun bilinmiyor sayılır).
    public mutating func dropSeed() { seed = nil }

    // MARK: Kaynaklar

    /// Oyun kimliği biçimi: dört büyük harf + beş rakam, isteğe bağlı `_00` (ninoya-sor.md §6 madde 1).
    public static func isGameTitleID(_ id: String) -> Bool {
        id.range(of: #"^[A-Z]{4}[0-9]{5}(_00)?$"#, options: .regularExpression) != nil
    }

    /// PS5'in bildirdiği uygulama (keşif cevabı). Boş ad yok sayılır; kimlik verildiyse ve oyun biçiminde değilse (ana
    /// ekran, sistem uygulaması) oyun yok sayılır. Elle seçimden başka oyunsa elle seçim silinir.
    @discardableResult
    public mutating func consoleReported(name: String?, titleID: String? = nil) -> Bool {
        let before = current
        let id = titleID?.trimmingCharacters(in: .whitespaces).uppercased()
        guard let raw = name.map(GameTracker.cleanName), !raw.isEmpty, id.map(GameTracker.isGameTitleID) ?? true else {
            console = nil
            return before != current
        }
        let c = Guess(id: GameIDs.id(raw) ?? raw, name: raw, titleID: id)
        if let u = user, !GameTracker.same(u.name, c.name) { user = nil }
        console = c
        return before != current
    }

    public mutating func consoleLost() { console = nil }

    /// Kullanıcının seçtiği oyun.
    public mutating func choose(_ name: String) {
        let n = GameTracker.cleanName(name)
        guard !n.isEmpty else { return }
        user = Guess(id: GameIDs.id(n) ?? n, name: n)
        asked = true
    }

    public mutating func clearUserChoice() { user = nil }

    /// Bir satır yalnız bu pakette bulundu. Genel paket oy sayılmaz.
    @discardableResult
    public mutating func vote(packID: String, title: String?) -> Bool {
        guard packID != LegacyLibrary.generalPackID else { return false }
        votes.append(packID)
        if let t = title.map(GameTracker.cleanName), !t.isEmpty { voteTitles[packID] = t }
        if votes.count > Self.voteWindow { votes.removeFirst(votes.count - Self.voteWindow) }
        let counts = Dictionary(grouping: votes, by: { $0 }).mapValues(\.count)
        guard let (winner, n) = counts.max(by: { $0.value < $1.value }) else { return false }
        let winnerTitle = voteTitles[winner]
        let guessed = [screen, seed].compactMap { $0 }.contains {
            GameIDs.sameGame($0.id, winner) || GameTracker.same($0.name, winnerTitle ?? winner)
        }
        let need = guessed && pack == nil ? 1 : (counts.count == 1 ? Self.unanimousThreshold : Self.voteThreshold)
        guard n >= need else { return false }
        let before = current
        let beforeEvidence = evidence
        let name = winnerTitle ?? GameIDs.displayName(winner)
        pack = Guess(id: GameIDs.id(winner) ?? winner, name: name)
        return before != current || beforeEvidence != evidence
    }

    /// Ekrandan tanınan oyun (yerel işaretler ya da sunucu).
    public mutating func screenRecognized(_ name: String) {
        let n = GameTracker.cleanName(name)
        guard !n.isEmpty else { return }
        screen = Guess(id: GameIDs.id(n) ?? n, name: n)
    }

    // MARK: Sonuç

    public var current: Guess? { console ?? user ?? pack ?? screen ?? seed }

    public var evidence: RecognizedGame.Evidence? {
        if console != nil { return .console }
        if user != nil { return .user }
        if pack != nil { return .pack }
        if screen != nil { return .screen }
        if seed != nil { return .lastPlayed }
        return nil
    }

    /// Oyun bu oturumda bir kaynakla doğrulandı mı (son oynanan tahmini değil).
    public var isConfirmed: Bool { console != nil || user != nil || pack != nil || screen != nil }

    /// "Kesin" sayılan: konsol, kullanıcı ya da ekran (paket tahmini değil).
    public var isCertain: Bool { console != nil || user != nil || (pack == nil && screen != nil) }

    public mutating func markAsked() { asked = true }

    // MARK: Adlar

    /// Denetim karakterleri boşluğa, fazla boşluk teke, en çok 120 karakter.
    public static func cleanName(_ raw: String) -> String {
        let spaced = String(raw.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : Character($0) })
        let collapsed = spaced.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String(collapsed.prefix(120))
    }

    /// Aynı oyun mu: asıl kimlik ya da ad anahtarı aynı (`pool-gta-6` = `GTA 6` = `Grand Theft Auto VI`).
    public static func same(_ a: String, _ b: String) -> Bool { GameIDs.sameGame(a, b) }
}
