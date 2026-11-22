// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import NinoCore

/// Ekranda gösterilen paket bilgisi.
struct GamePack: Identifiable, Equatable {
    let id: String
    let title: String
    let lineCount: Int

    /// Oyun rozeti: tek sözcükse ilk 3 harf, değilse ilk üç sözcüğün baş harfleri.
    var monogram: String {
        let words = title.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if words.count == 1 { return String(words[0].prefix(3)).uppercased() }
        return words.prefix(3).compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    /// Satırın paket anahtarı (NinoCore `LineKey`; 16 küçük onaltılık hane).
    static func key(_ text: String) -> String? {
        LineKey.key(text).map { String(format: "%016llx", $0) }
    }
}

/// Paketler: sunucudan inenler ve içe aktarılanlar (aynı kimlik sonra okunanla değişir). Uygulamaya paket gömülmez;
/// hepsi Nino sunucusundan (`/v1/packs`) iner. Okuma ve arama NinoCore'un eski biçim kütüphanesiyle yapılır.
struct GamePackLibrary {
    private(set) var library = LegacyLibrary()

    static func downloadDirectory(folders: AppFolders) -> URL {
        folders.support.appendingPathComponent("Packs/files", isDirectory: true)
    }

    static func directories(folders: AppFolders) -> [URL] {
        [downloadDirectory(folders: folders),
         folders.support.appendingPathComponent("Packs/imported", isDirectory: true)]
    }

    /// Sunucudaki paketleri indirir (açılışta ve 24 saatte bir). Dönüş: kütüphane yeniden okunmalı mı.
    static func update(folders: AppFolders, force: Bool = false) async -> Bool {
        guard let base = NinoServer.base else { return false }
        let dir = downloadDirectory(folders: folders)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let updater = PackUpdater(packsDirectory: dir,
                                  statusFile: folders.support.appendingPathComponent("Packs/packs-remote.json"),
                                  configuration: PoolConfiguration(baseURL: base, platform: "ios", appVersion: AppInfo.version),
                                  transport: URLSessionPoolTransport(session: .shared))
        let result = force ? await updater.check() : await updater.checkIfDue(.launch)
        for id in result?.failed ?? [] { AppDiagnosis.shared.packResult(id, ok: false) }
        for id in result?.downloaded ?? [] { AppDiagnosis.shared.packResult(id, ok: true) }
        return result?.changed ?? false
    }

    static func load(folders: AppFolders) -> GamePackLibrary {
        var lib = GamePackLibrary()
        lib.library = LegacyLibrary(directories: directories(folders: folders))
        return lib
    }

    var packs: [GamePack] {
        library.infos.filter { $0.id != LegacyLibrary.generalPackID }
            .map { GamePack(id: $0.id, title: $0.title, lineCount: $0.lineCount) }
    }

    var totalLines: Int { packs.reduce(0) { $0 + $1.lineCount } }

    /// Kapatılan paketler çıkarılmış kütüphane.
    func enabled(excluding disabled: [String]) -> LegacyLibrary {
        guard !disabled.isEmpty else { return library }
        return LegacyLibrary(packs: library.packs.filter { !disabled.contains($0.id) })
    }
}

/// Çekirdeğin çevirmenine paket araması: oyunun paketi kapsam olarak tutulur (son tam eşleşme), bulanık arama yalnız
/// kapsamda yapılır; satırı veren paketin adı bildirilir.
final class PackLookup: PhraseLookup, @unchecked Sendable {
    private var library: LegacyLibrary
    private let lock = NSLock()
    private var scope = PackScope()
    private let onHit: @Sendable (String) -> Void

    init(library: LegacyLibrary, onHit: @escaping @Sendable (String) -> Void) {
        self.library = library
        self.onHit = onHit
    }

    /// Paketler sonradan yüklenince (açılışta arka planda okunur) çeviri durmadan devreye girer.
    func setLibrary(_ new: LegacyLibrary) {
        lock.withLock {
            library = new
            scope = PackScope()
        }
    }

    func lookup(_ sentence: String) -> String? {
        let (match, library) = lock.withLock { (scope.lookup(sentence, in: library), library) }
        guard let match else { return nil }
        let title = library.infos.first { $0.id == match.packID }?.title ?? match.packID
        onHit(title)
        return match.text
    }

    var terms: [Term] { [] }
}
