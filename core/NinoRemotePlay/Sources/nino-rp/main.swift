// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import NinoCore
import NinoRemotePlay

// Nino Remote Play deneme aracı.
//   nino-rp bul                         ağdaki PS5'leri listeler
//   nino-rp kaydet <8 haneli kod> <PSN hesap kimliği (base64)>
//   nino-rp izle [--tv <adres>]         altyazıyı okur, çevirir, ekrana (ve TV'ye) yazar
//   --ip <PS5 adresi>                    aramayı tek adrese yapar (yayın geçmeyen ağlar)

let secrets = KeychainSecretStore()
let args = Array(CommandLine.arguments.dropFirst())

func fail(_ s: String) -> Never {
    FileHandle.standardError.write(Data((s + "\n").utf8))
    exit(1)
}

func findConsole(timeout: TimeInterval = 8) async throws -> ConsoleInfo {
    let discovery = ConsoleDiscovery()
    // --ip <adres>: yayın yerine yalnız bu adrese sorulur.
    var host: String?
    if let i = args.firstIndex(of: "--ip"), i + 1 < args.count { host = args[i + 1] }
    let stream = try discovery.consoles(host: host)
    let found: ConsoleInfo? = await withTaskGroup(of: ConsoleInfo?.self) { group in
        group.addTask {
            for await list in stream { if let c = list.first(where: \.isPS5) ?? list.first { return c } }
            return nil
        }
        group.addTask { try? await Task.sleep(for: .seconds(timeout)); return nil }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
    discovery.stop()
    guard let found else { fail("Ağda PS5 bulunamadı. PS5 açık ve aynı ağda mı?") }
    return found
}

switch args.first {
case "bul":
    let c = try await findConsole()
    print("\(c.name)  \(c.address)  durum: \(c.state.rawValue)  kimlik: \(c.hostID)")
    let reg = try RegisteredConsole.load(hostID: c.hostID, from: secrets)
    print(reg == nil ? "Bu Mac'e henüz bağlı değil: nino-rp kaydet <kod> <hesap kimliği>" : "Bu Mac'e bağlı.")

case "kaydet":
    guard args.count >= 3 else { fail("Kullanım: nino-rp kaydet <8 haneli kod> <PSN hesap kimliği (base64)>") }
    let pin = try ConsoleRegistration.parsePIN(args[1])
    let account = try ConsoleRegistration.decodeAccountID(args[2])
    let c = try await findConsole()
    print("\(c.name) (\(c.address)) ile eşleşiliyor…")
    do {
        let reg = try await ConsoleRegistration.register(console: c, accountID: account, pin: pin)
        try reg.save(to: secrets)
        print("Tamam. \(reg.nickname) bu Mac'e bağlandı.")
    } catch {
        fail("Eşleşme olmadı: \(error)")
    }

case "izle":
    let c = try await findConsole()
    guard let reg = try RegisteredConsole.load(hostID: c.hostID, from: secrets) else {
        fail("Önce eşleştir: nino-rp kaydet <kod> <hesap kimliği>")
    }
    if c.state == .standby {
        print("PS5 uykuda, uyandırılıyor…")
        try RemotePlaySession.wake(address: c.address, console: reg)
        try await Task.sleep(for: .seconds(15))
    }
    var settings = NinoSettings()
    var output: SubtitleOutput?
    if let i = args.firstIndex(of: "--tv"), i + 1 < args.count {
        settings.display.host = args[i + 1]
        output = try await NinoSetup.connectDisplay(settings: settings, device: "Mac")
        print("TV'ye bağlandı.")
    }
    let engine = try NinoSetup.makeEngine(settings: settings, directories: try NinoDirectories.standard(),
                                          secrets: secrets, output: output)
    let session = RemotePlaySession(address: c.address, console: reg, options: .twentyPerSecond)
    let sessionEvents = session.events()
    Task {
        for await e in sessionEvents {
            switch e {
            case .connected: print("PS5'e bağlandı. Altyazı bekleniyor… (çıkmak için Ctrl+C)")
            case let .loginPINRequested(incorrect):
                print(incorrect ? "Giriş şifresi yanlış. 4 haneli şifreyi yeniden yaz:" : "PS5 giriş şifresi istiyor. 4 haneli şifreyi yaz:")
                if let line = readLine() {
                    do { try session.sendLoginPIN(line) } catch { print("\(error)") }
                }
            case let .quit(reason): print("Oturum kapandı: \(reason)")
            case .log: break
            }
        }
    }
    let engineEvents = await engine.events()
    Task {
        for await e in engineEvents {
            switch e {
            case let .subtitleStarted(s): print("EN  \(s.text)")
            case let .translated(_, text, _): print("TR  \(text)\n")
            case .translationFailed: print("TR  (çevrilemedi)\n")
            default: break
            }
        }
    }
    signal(SIGINT) { _ in exit(0) }
    await engine.run(session)
    if session.recentLog.contains(where: { $0.lowercased().contains("error") }) {
        print(session.recentLog.suffix(10).joined(separator: "\n"))
    }

default:
    print("""
    Nino Remote Play aracı
      nino-rp bul
      nino-rp kaydet <8 haneli kod> <PSN hesap kimliği (base64)>
      nino-rp izle [--tv <TV adresi>]
    """)
}
