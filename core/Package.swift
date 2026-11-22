// swift-tools-version:5.9
// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import PackageDescription

let package = Package(
    name: "NinoCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "NinoCore", targets: ["NinoCore"]),
    ],
    targets: [
        .target(name: "NinoCore"),
        .testTarget(name: "NinoCoreTests", dependencies: ["NinoCore"], resources: [.copy("Resources")]),
    ]
)
