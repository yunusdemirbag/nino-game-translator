// swift-tools-version:5.9
// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import PackageDescription

// Mac uygulamasının bütün mantığı ve ekranları. Xcode hedefi (apps/mac/App) yalnız
// bu paketi açar; böylece her şey `swift test` ile uygulama açılmadan sınanır.
//
// NinoCore deponun core/ klasöründedir. Yeri NINOCORE_DIR ile değiştirilebilir; core/ yoksa
// ~/Desktop/NinoCore (çekirdeğin ayrı geliştirme deposu) kullanılır.
let coreDirectory: String = {
    if let custom = ProcessInfo.processInfo.environment["NINOCORE_DIR"], !custom.isEmpty { return custom }
    let inRepo = Context.packageDirectory + "/../../../core"
    if FileManager.default.fileExists(atPath: inRepo + "/Package.swift") { return inRepo }
    return NSHomeDirectory() + "/Desktop/NinoCore"
}()

let package = Package(
    name: "NinoMacKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NinoMacKit", targets: ["NinoMacKit"]),
        // Hata ayıklama kaydının çekirdeği (halka tampon, indeks, bütçe, çıkarma, özet) ve komut satırı aracı.
        .library(name: "NinoDebugKit", targets: ["NinoDebugKit"]),
        .executable(name: "nino-debug", targets: ["nino-debug"]),
    ],
    dependencies: [
        .package(name: "NinoCore", path: coreDirectory),
        .package(name: "NinoRemotePlay", path: coreDirectory + "/NinoRemotePlay"),
    ],
    targets: [
        .target(
            name: "NinoMacKit",
            dependencies: [
                "NinoDebugKit",
                .product(name: "NinoCore", package: "NinoCore"),
                .product(name: "NinoRemotePlay", package: "NinoRemotePlay"),
            ],
            // TVPage: TV web sayfasının kopyası (apps/tv-web/src; yalnız platform.js farklı), admin bileşik karesi.
            resources: [.process("Resources"), .copy("TVPage")]
        ),
        .target(name: "NinoDebugKit"),
        // `kacan` alt komutu (kaçırma ölçer) NinoCore'un okuyucusunu kullanır.
        .executableTarget(name: "nino-debug", dependencies: ["NinoDebugKit", .product(name: "NinoCore", package: "NinoCore")]),
        .testTarget(name: "NinoMacKitTests", dependencies: ["NinoMacKit", "NinoDebugKit"], resources: [.copy("Fixtures")]),
    ]
)
