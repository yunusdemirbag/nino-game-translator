// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.tv;

import android.app.Application;

/** Süreç açılışı: ölçüm (önceki çökme, açılış) ve protokol sunucusu. */
public class NinoTvApp extends Application {
    @Override
    public void onCreate() {
        super.onCreate();
        Metrics.get(this).start();
        LinkHub.get(this).ensureRunning();
    }

    /** Uygulama öndeyken sistem belleğin azaldığını bildirdi (otomatik teşhis: app.resources). */
    @Override
    public void onTrimMemory(int level) {
        super.onTrimMemory(level);
        if (level == TRIM_MEMORY_RUNNING_LOW || level == TRIM_MEMORY_RUNNING_CRITICAL) Metrics.get(this).memoryWarning();
    }
}
