// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import NinoCore

/// Kurulum ekranı ile uygulama modeli arasındaki bağ (AppModel'e dokunmadan, uzantı olarak).
extension AppModel {
    var tvInstallFiles: TVInstallFiles { TVInstallFiles(support: folders.support) }
    var tvInstallLog: TVInstallLog { TVInstallLog(file: tvInstallFiles.logFile) }
    var tvPackages: TVPackageStore { TVPackageStore(cache: tvInstallFiles.packages) }

    /// Telefonun TV uygulamasını en son kurduğu ya da sürümünü okuduğu TV (UserDefaults `tvAppInstalled`).
    var installedTVApp: InstalledTVApp? {
        defaults.data(forKey: Keys.tvAppInstalled).flatMap { try? JSONDecoder().decode(InstalledTVApp.self, from: $0) }
    }

    // MARK: TV uygulaması sürüm denetimi (davranis.md §2.6)

    /// TV'deki uygulama telefonun kurabileceği paketten eskiyse güncelleme önerisi.
    var tvUpdateOffer: TVUpdateOffer? {
        guard let brand = installedTVApp?.brand ?? tv?.brand else { return nil }
        let recorded = installedTVApp.flatMap { $0.brand == brand && !$0.version.isEmpty ? $0.version : nil }
        guard let installed = tvAppSeenVersion ?? recorded, let available = tvPackageVersions[brand],
              VersionOrder.isNewer(available, than: installed) else { return nil }
        return TVUpdateOffer(brand: brand, installed: installed, available: available)
    }

    /// Paket sürümlerini arka planda okur (açılışta ve kurulumdan sonra).
    func loadTVPackageVersions() async {
        let store = tvPackages
        let versions = await Task.detached(priority: .utility) { () -> [PairedTV.Brand: String] in
            var out: [PairedTV.Brand: String] = [:]
            for brand in [PairedTV.Brand.androidTV, .lg, .samsung] {
                if let v = store.localVersion(TVPackageKind(brand)) { out[brand] = v }
            }
            return out
        }.value
        tvPackageVersions = versions
    }

    /// Bağlanan TV uygulaması sürümünü bildirdi: hatırlanır; eşli TV'nin adresiyse kayda da yazılır.
    func tvAppReported(version: String, host: String) {
        tvAppSeenVersion = version
        guard !ephemeral, !host.isEmpty else { return }
        let record: InstalledTVApp?
        if var known = installedTVApp, known.host == host {
            known.version = version
            record = known
        } else if let tv, tv.host == host {
            record = InstalledTVApp(brand: tv.brand, host: host, port: nil, version: version)
        } else {
            record = nil
        }
        if let record, let data = try? JSONEncoder().encode(record) { defaults.set(data, forKey: Keys.tvAppInstalled) }
    }

    /// Kurulum bitti: TV hatırlanır ve altyazı hedefi olarak eşlenir. TV uygulaması yeni açıldığı için dinlemeye
    /// başlaması birkaç saniye sürebilir; eşlemeden önce kısa süre beklenir.
    func tvAppInstalled(brand: PairedTV.Brand, host: String, port: UInt16?, version: String) async {
        tvAppSeenVersion = version
        if !ephemeral, let data = try? JSONEncoder().encode(InstalledTVApp(brand: brand, host: host, port: port, version: version)) {
            defaults.set(data, forKey: Keys.tvAppInstalled)
        }
        guard !ephemeral else { return }
        for _ in 0..<12 {
            if await Displays.probe(host: host) { break }
            try? await Task.sleep(for: .seconds(1))
        }
        let name: String
        if let tv, tv.host == host, tv.brand == brand {
            name = tv.name
        } else {
            name = switch brand {
            case .androidTV: "Android TV"
            case .lg: "LG TV"
            case .samsung: "Samsung TV"
            }
        }
        await pairTV(PairedTV(name: name, host: host, brand: brand))
    }

    /// Uygulama öne gelince: eşlenen ya da kurulan LG TV varsa geliştirici modu süresi (günde en çok bir kez) uzatılır.
    func renewLGSessionIfDue() async {
        let hosts = [tv.flatMap { $0.brand == .lg ? $0.host : nil },
                     installedTVApp.flatMap { $0.brand == .lg ? $0.host : nil }].compactMap { $0 }
        for host in Set(hosts) where !host.isEmpty { await renewLGSessionIfDue(host: host) }
    }

    /// LG geliştirici modunun süresini günde bir uzatır (kayıtlı anahtar ve açık geliştirici modu gerekir).
    func renewLGSessionIfDue(host: String) async {
        guard !ephemeral, let key = LGKeyStore(files: tvInstallFiles).load(host) else { return }
        let defaults = self.defaults
        let log = tvInstallLog
        await Task.detached(priority: .utility) {
            guard TCPChannel.isOpen(host: host, port: LGInstaller.sshPort, timeout: 1.5),
                  let rsa = try? RSAPrivateKey(pem: key) else { return }
            let installer = LGInstaller(shell: LGSSHShell(host: host, key: rsa), log: log)
            if let hours = LGSessionRenewal.renewIfDue(host: host, defaults: defaults, renew: { (try? installer.renewSession()) ?? nil }) {
                log.write("LG developer mode extended: \(hours) h left")
            }
        }.value
    }
}

/// Ana ekrandaki "TV uygulamasını güncelle" kartının bilgisi.
struct TVUpdateOffer: Equatable {
    var brand: PairedTV.Brand
    var installed: String
    var available: String
}

extension TVPackageKind {
    init(_ brand: PairedTV.Brand) {
        switch brand {
        case .androidTV: self = .android
        case .lg: self = .lg
        case .samsung: self = .samsung
        }
    }
}
