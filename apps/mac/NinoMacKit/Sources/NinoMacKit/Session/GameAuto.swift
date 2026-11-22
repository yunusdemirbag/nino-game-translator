// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import NinoCore

/// Oyun kendiliğinden ve hemen: soru ve elle seçim yok. Çeviri başlarken bu PS5'te son oynanan
/// (hiç yoksa GTA 6) hemen etkin olur; ilk saniyelerde her karede hafif okuma, ekran işaretleri ve paket isabetleri
/// arka planda doğrular ya da sessizce başka oyuna geçer.
extension LiveEngine {
    /// Hiç oyun bilinmiyorsa başlangıç tahmini.
    static let defaultGame = GameReading.ScreenGame.gta6
    /// Son oynanan tahmini bu kadar süre doğrulanmazsa bırakılır (yanlış oyunun havuz önceliği sürmesin).
    static let seedTimeoutMs = 180_000

    /// Saklanmış oyun adı: tablodaki asıl oyunun adı, yoksa olduğu gibi.
    nonisolated static func storedGameName(_ name: String) -> String { GameIDs.knownName(name) ?? name }

    /// Son oynanan (PS5 adı → oyun), takma adlı eski değerler asıl ada çevrilmiş.
    var rememberedGames: [String: String] { lastGames.mapValues(Self.storedGameName) }

    /// Oyun hafızasının anahtarı: PS5 adı (yoksa adresi); başka kaynakta ortak anahtar.
    var gameMemoryKey: String {
        (state.settings.videoSource == .ps5 ? consoleKey : nil) ?? ""
    }

    /// Bu PS5'te son oynanan oyun (`sheetsStatus.lastPlayedGame`).
    func refreshGameMemory() {
        state.sheetsStatus.lastPlayedGame = rememberedGames[gameMemoryKey]
    }

    /// Oturum başı (`games.startSession` hemen ardından): son oynanan tahmini. Eski sürümlerin elle seçtiği oyun
    /// (`pinnedGames` kaydı) artık okunmaz; oyun hep kendiliğinden tanınır.
    func seedGameForSession() {
        games.clearUserChoice()
        let name = rememberedGames[gameMemoryKey] ?? Self.defaultGame
        games.seed(name)
        seedSinceMs = env.clock.nowMs
        refreshGameMemory()
        subtitleLog.write("Oyun: son oynanan \(name) hemen etkin (ekrandan doğrulanıyor)")
    }

    /// Oyun bir kaynakla doğrulandıysa: PS5 adına göre hatırlanır, hızlı okuma durur.
    func gameConfirmedIfNeeded() {
        guard games.isConfirmed, let c = games.current else { return }
        seedSinceMs = nil
        quickSense?.stop()
        let key = gameMemoryKey
        let name = Self.storedGameName(c.name)
        if lastGames[key] != name {
            var map = lastGames
            map[key] = name
            lastGames = map
        }
        state.sheetsStatus.lastPlayedGame = name
    }

    /// Tahmin süresi doldu mu (4 sn'lik zamanlayıcı).
    func checkSeed(nowMs: Int? = nil) {
        guard games.evidence == .lastPlayed, let since = seedSinceMs, let name = games.seed?.name else { return }
        let now = nowMs ?? env.clock.nowMs
        guard now - since >= Self.seedTimeoutMs else { return }
        seedSinceMs = nil
        games.dropSeed()
        subtitleLog.write("Oyun: \(name) ekrandan doğrulanmadı; oyun bilinmiyor sayılır")
        gameChanged()
    }

    /// Kareler okumaya giderken hızlı oyun tanımaya da bakılır (bir okuma sürerken gelen kare atlanır).
    func quickTap(_ stream: AsyncStream<Frame>, token: Int) -> AsyncStream<Frame> {
        guard let sense = quickSense else { return stream }
        return AsyncStream(bufferingPolicy: .bufferingNewest(2)) { continuation in
            let task = Task.detached { [weak self] in
                for await f in stream {
                    if sense.claim() {
                        let image = f.image
                        Task.detached { [weak self] in
                            guard let v = await sense.read(GameReading.ImageFrame(image)) else { return }
                            await self?.quickRecognized(v, token: token)
                        }
                    }
                    continuation.yield(f)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func quickRecognized(_ v: GameReading.GameMarkers.Verdict, token: Int) {
        guard token == sessionToken else { return }
        // Yalnız özel adlar (imza yok): tahmini doğrular ama başka oyuna geçirmez.
        if !v.strong {
            guard let c = games.current, GameIDs.sameGame(c.id, v.id) || GameTracker.same(c.name, v.name) else { return }
        }
        screenIdentified(v.name, how: "\(v.strong ? "ekran işaretleri" : "özel adlar"): \(v.hits.joined(separator: ", "))")
    }

    /// Ekranda gösterilen altyazı: satır anahtarı yalnız bir paketteyse o oyuna oy (havuz öncelikli tahminde çevirmen
    /// paketlere hiç bakmaz; paketten gelen satırın oyunu çevirmen zaten verdi), özel adlar tahmini doğrular.
    func noteShownLine(_ line: LiveLine) {
        if line.origin != .pack, let hit = library.exact(line.source), hit.packs.count == 1,
           hit.packIndex < library.packs.count {
            let pack = library.packs[hit.packIndex]
            if games.vote(packID: pack.id, title: pack.title) { gameChanged() }
        }
        if let v = quickSense?.observeLines([GameReading.Line(line.source)]) {
            quickRecognized(v, token: sessionToken)
        }
    }

    /// PS5 yeniden aktı: oyun doğrulanmadıysa hızlı okuma penceresi yeniden açılır.
    func quickSenseStreamResumed() {
        guard state.isTranslating, !games.isConfirmed else { return }
        quickSense?.start()
    }
}
