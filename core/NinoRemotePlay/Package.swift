// swift-tools-version:5.9
// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import PackageDescription

// Remote Play bağlantısı. C çekirdeği önce derlenmelidir:
//   ./scripts/fetch-deps.sh && ./scripts/build-deps.sh && ./scripts/build-c.sh
let package = Package(
    name: "NinoRemotePlay",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "NinoRemotePlay", targets: ["NinoRemotePlay"]),
        .executable(name: "nino-rp", targets: ["nino-rp"]),
    ],
    dependencies: [
        .package(name: "NinoCore", path: ".."),
    ],
    targets: [
        // NINO_CREMOTEPLAY_PATH: yeni üretilen çerçeveyi yerine koymadan denemek için
        // (ör. .build-c/out/CRemotePlay.xcframework).
        .binaryTarget(name: "CRemotePlay",
                      path: Context.environment["NINO_CREMOTEPLAY_PATH"] ?? "Frameworks/CRemotePlay.xcframework"),
        .target(
            name: "NinoRemotePlay",
            dependencies: [.product(name: "NinoCore", package: "NinoCore"), "CRemotePlay"],
            linkerSettings: [
                .linkedFramework("VideoToolbox"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("CoreServices"),
                .linkedFramework("SystemConfiguration"),
                .linkedFramework("Security"),
            ]
        ),
        .executableTarget(name: "nino-rp", dependencies: ["NinoRemotePlay", .product(name: "NinoCore", package: "NinoCore")]),
        .testTarget(name: "NinoRemotePlayTests", dependencies: ["NinoRemotePlay"]),
    ]
)
