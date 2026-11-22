// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Sahadaki eski TV uygulamaları ağı tararken `/hello` cevabında eski sürümün adını arar; bulamazsa o adresi
/// Nino'nun sunucusu saymaz. Ad yalnız burada, kodlu durur (veri uyumu); hiçbir yerde gösterilmez.
enum LegacyCompatName {
    /// Eski sürümün küçük harfli adı.
    static let lowercased = String(decoding: Data(base64Encoded: "Y291Y2hzdWJz") ?? Data(), as: UTF8.self)

    /// `/hello` gövdesi: yeni istemciler `app` alanına, eski TV uygulamaları eski adın geçmesine bakar.
    static var helloBody: Data {
        Data(#"{"app":"nino","compat":""#.utf8) + Data(lowercased.utf8) + Data(#""}"#.utf8)
    }
}
