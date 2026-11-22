// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Eski sürümlerin adları (yalnız veri taşıma için). Değerler kodlu durur; başka hiçbir
/// dosyada açık yazılmaz.
enum LegacyNames {
    private static func decode(_ base64: String) -> String {
        guard let data = Data(base64Encoded: base64), let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    /// Eski veri ve günlük klasörünün adı.
    static var folderName: String { decode("Q291Y2hTdWJz") }
    /// Eski uygulamanın paket kimliği.
    static var bundleID: String { decode("Y29tLmNvdWNoc3Vicy5tYWM=") }
    /// Eski uygulamanın olağan kurulum yeri (mutlak).
    static var systemInstallPath: String { decode("L0FwcGxpY2F0aW9ucy9Db3VjaFN1YnMuYXBw") }
    /// Eski uygulamanın ev klasörüne göre kurulum yeri.
    static var userInstallPath: String { decode("QXBwbGljYXRpb25zL0NvdWNoU3Vicy5hcHA=") }

    // MARK: Sahadaki eski TV uygulaması (tv-kurulumu.md, "Eski TV uygulaması")

    /// Eski LG ve Android TV uygulamasının kimliği (paket adı).
    static var tvPackage: String { decode("Y29tLmNvdWNoc3Vicy50dg==") }
    /// Eski Samsung TV uygulamasının uygulama kimliği.
    static var samsungTVAppID: String { decode("Q291Y2hTdWJzVC5Db3VjaFN1YnM=") }
    /// Eski Samsung TV uygulamasının paket kimliği (uygulama kimliğinin nokta öncesi).
    static var samsungTVPackageID: String {
        String(samsungTVAppID.split(separator: ".", maxSplits: 1).first ?? "")
    }
}
