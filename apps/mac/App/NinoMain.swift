// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI
import NinoMacKit

@main
struct NinoMain: App {
    // Açılışta / Dock'ta ana pencereyi geri getirir; son pencere kapanınca uygulama kapanmaz.
    @NSApplicationDelegateAdaptor(NinoAppDelegate.self) private var appDelegate

    init() {
        // `--ocr-helper` ile açıldıysa pencere açmadan yedek OCR süreci olur ve buradan hiç dönmez.
        // Aksi hâlde gerçek motor kurulur ve yardımcılar (Sparkle, kısayollar, admin modu) bağlanır.
        NinoAppSupport.launch(makeAutoUpdater: { SparkleAutoUpdater() })
    }

    var body: some Scene {
        NinoScenes()
    }
}
