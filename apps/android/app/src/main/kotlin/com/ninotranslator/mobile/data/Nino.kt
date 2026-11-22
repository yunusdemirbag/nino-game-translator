// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.data

import android.content.Context
import android.content.res.Resources
import java.io.File

/** Basit servis bulucu: arayüz ve hizmet veri katmanına buradan ulaşır. [init] uygulama açılışında çağrılır. */
object Nino {
    lateinit var appContext: Context
        private set
    lateinit var settings: Settings
        private set
    lateinit var secrets: Secrets
        private set
    lateinit var installIdentity: InstallIdentity
        private set
    lateinit var appUpdate: AppUpdateStore
        private set
    lateinit var history: HistoryStore
        private set
    lateinit var health: HealthLog
        private set
    lateinit var autoReport: AutoReportCounter
        private set
    lateinit var subtitleLayout: SubtitleLayoutStore
        private set
    lateinit var tvInstallLog: TvInstallLog
        private set

    /** Önceki süreç çeviri sırasında öldü mü (açılışta `translating` true kalmıştı). */
    @Volatile var previousRunDiedWhileTranslating = false
        internal set

    val filesDir: File get() = appContext.filesDir
    val noBackupDir: File get() = appContext.noBackupFilesDir
    val cacheDir: File get() = appContext.cacheDir

    /** Tek kurulum kimliği (havuz, satır kuyruğu, sorun bildirimi, Nino'ya Sor, ölçüm, TV bağlantısı). */
    val installId: String get() = installIdentity.id

    @Synchronized
    fun init(context: Context) {
        if (::settings.isInitialized) return
        val app = context.applicationContext ?: context
        appContext = app
        fun prefs(name: String) = app.getSharedPreferences(name, Context.MODE_PRIVATE)
        val files = app.filesDir
        settings = Settings(prefs(Settings.FILE)) { systemLanguage() }
        secrets = Secrets(prefs(Secrets.FILE), AndroidKeyAliasStore.cipher())
        installIdentity = InstallIdentity(files, prefs(InstallIdentity.FILE))
        appUpdate = AppUpdateStore(prefs(AppUpdateStore.FILE))
        history = HistoryStore(File(files, HistoryStore.FILE))
        health = HealthLog(File(files, HealthLog.PATH))
        autoReport = AutoReportCounter(File(files, AutoReportCounter.PATH))
        subtitleLayout = SubtitleLayoutStore(File(files, SubtitleLayoutStore.FILE))
        tvInstallLog = TvInstallLog(File(files, TvInstallLog.FILE))
    }

    fun settingsOrNull(): Settings? = if (::settings.isInitialized) settings else null

    /** Uygulama başına dil ayarından etkilenmeyen sistem dili. */
    private fun systemLanguage(): String =
        runCatching { Resources.getSystem().configuration.locales[0].language }.getOrNull() ?: java.util.Locale.getDefault().language
}
