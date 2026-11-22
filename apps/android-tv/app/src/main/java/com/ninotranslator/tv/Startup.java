// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.tv;

/**
 * Uygulama açılırken ne gösterileceği. Android'e bağlı değildir (bkz. StartupTest).
 *
 * Katmanlı derlemede (sideload) TV'nin girişine hiç dokunulmaz: izin varsa katman arka planda hazırlanır, kullanıcı
 * kumandayla PS5'in girişine geçer. Google Play derlemesinde katman yoktur, oyun her zaman Nino'nun içinde gösterilir.
 */
final class Startup {
    enum Plan {
        /** Katman hazır; Nino ana ekranı gösterilir. */
        HOME,
        /** Katman hazır; ekran gösterilmeden kapanılır (masaüstü ADB ile açtı). */
        QUIET,
        /** İzin yok; izin ekranı. */
        ASK_PERMISSION,
        /** HDMI Nino'nun içinde, altyazı üstte. */
        IN_APP
    }

    private Startup() {}

    /**
     * @param overlayBuild bu derlemede katman var mı
     * @param permitted "diğer uygulamaların üzerinde göster" izni
     * @param chosenInApp kullanıcı daha önce "izin vermeden devam et" dedi
     * @param wantsInApp bilgisayardaki ya da telefondaki Nino'da görüntü modu "uygulama içinde" seçili
     * @param fromLauncher kumandayla ana ekrandan açıldı
     */
    static Plan decide(boolean overlayBuild, boolean permitted, boolean chosenInApp, boolean wantsInApp, boolean fromLauncher) {
        if (!overlayBuild) return Plan.IN_APP;
        if (permitted && wantsInApp) return Plan.IN_APP;
        if (permitted) return fromLauncher ? Plan.HOME : Plan.QUIET;
        return chosenInApp ? Plan.IN_APP : Plan.ASK_PERMISSION;
    }
}
