// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import NinoDebugKit

// nino-debug: hata ayıklama kaydından bir zaman aralığını tek klasöre çıkarır.
//   nino-debug son 5dk
//   nino-debug 16:05-16:10
//   nino-debug son 30sn --cikti ~/Desktop/inceleme
//   nino-debug durum              (kayıt klasörü, boyut, son ölçüm)
//   nino-debug kacan 23:00-23:45  (kaçırma ölçer: kayıttaki diyalog satırları ↔ günlükteki okumalar)
// Seçenekler: --cikti <klasör>, --kok <debug-kayit klasörü>.

let usage = """
Kullanım:
  nino-debug son 5dk | son 30sn | son 2sa
  nino-debug 16:05-16:10 | 16:05:30-16:06
  nino-debug durum
  nino-debug kacan 23:00-23:45   kaçan altyazı satırları (kayıt okunur, kacan.md yazılır)
Seçenekler:
  --cikti <klasör>   çıktı klasörü (varsayılan <kök>/cikti/<zaman>/)
  --adim <ms>        kacan: kurallar açık okuyucunun kare arası adımı (varsayılan 250)
  --kok <klasör>     kayıt kökü (varsayılan ~/Library/Logs/Nino/debug-kayit ya da "Nino Dev")

"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

var rangeArgs: [String] = []
var outPath: String?
var rootPath: String?
var stepMs = 250
var args = Array(CommandLine.arguments.dropFirst())
while !args.isEmpty {
    let a = args.removeFirst()
    switch a {
    case "--cikti", "-o":
        guard !args.isEmpty else { fail("--cikti için klasör gerekli") }
        outPath = args.removeFirst()
    case "--kok":
        guard !args.isEmpty else { fail("--kok için klasör gerekli") }
        rootPath = args.removeFirst()
    case "--adim":
        guard let v = args.first.flatMap(Int.init) else { fail("--adim için ms gerekli") }
        args.removeFirst()
        stepMs = v
    case "-h", "--help", "yardim":
        print(usage, terminator: "")
        exit(0)
    default:
        rangeArgs.append(a)
    }
}

func expand(_ p: String) -> URL { URL(fileURLWithPath: (p as NSString).expandingTildeInPath) }

let layout: DebugRecordLayout = {
    if let rootPath { return DebugRecordLayout(root: expand(rootPath)) }
    let list = DebugRootFinder.candidates()
    return DebugRootFinder.newest(list) ?? list[0]
}()

if rangeArgs == ["durum"] {
    let files = DebugRecordIndex.scan(layout)
    let total = files.reduce(Int64(0)) { $0 + $1.bytes }
    print("Kök: \(layout.root.path)")
    print("Dosya: \(files.count), toplam \(total / 1_048_576) MB")
    if let first = files.map(\.startMs).min(), let last = files.map(\.endMs).max() {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        print("Kapsam: \(f.string(from: Date(timeIntervalSince1970: TimeInterval(first) / 1000))) – \(f.string(from: Date(timeIntervalSince1970: TimeInterval(last) / 1000)))")
    }
    if let d = try? Data(contentsOf: layout.measureFile), let s = String(data: d, encoding: .utf8) { print("Son ölçüm: \(s)") }
    exit(0)
}

let missMeter = rangeArgs.first == "kacan"
if missMeter { rangeArgs.removeFirst() }

guard !rangeArgs.isEmpty, let range = DebugRange.parse(rangeArgs, now: Date()) else {
    FileHandle.standardError.write(Data(usage.utf8))
    exit(2)
}
guard FileManager.default.fileExists(atPath: layout.root.path) else {
    fail("Kayıt klasörü yok: \(layout.root.path)\nKayıt yalnız admin modunda (ninoAdminMode) ya da Debug yapısında çalışır.")
}

let out: URL = {
    if let outPath { return expand(outPath) }
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
    return layout.outputFolder.appendingPathComponent(f.string(from: Date()), isDirectory: true)
}()

if missMeter {
    do {
        try await MissMeterCommand.run(layout: layout, from: range.from, to: range.to, out: out, stepMs: stepMs)
    } catch {
        fail("Ölçülemedi: \(error)")
    }
    exit(0)
}

do {
    let r = try DebugExport(layout: layout).run(from: range.from, to: range.to, into: out)
    let c = r.counts
    print("Çıktı: \(r.folder.path)")
    print("PS5 kare \(c.ps5Frames), pencere \(c.macFrames), olay \(c.eventFrames), TV ekranı \(c.tvShots), TV mesajı \(c.tvMessages), günlük \(c.logLines)")
    print("Okunan satır \(r.summary.readLines), gösterilen \(r.summary.shown); özet: \(r.folder.appendingPathComponent("ozet.md").path)")
} catch {
    fail("Çıkarılamadı: \(error)")
}
