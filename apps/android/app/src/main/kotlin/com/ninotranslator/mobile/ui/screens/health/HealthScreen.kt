// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui.screens.health

import android.content.Context
import android.os.Build
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ninotranslator.mobile.BuildConfig
import com.ninotranslator.mobile.R
import com.ninotranslator.mobile.data.HealthIssueKind
import com.ninotranslator.mobile.data.Nino
import com.ninotranslator.mobile.data.SubtitleTarget
import com.ninotranslator.mobile.service.LiveStatus
import com.ninotranslator.mobile.support.DeviceSummary
import com.ninotranslator.mobile.support.HealthCause
import com.ninotranslator.mobile.support.HealthEval
import com.ninotranslator.mobile.support.HealthInput
import com.ninotranslator.mobile.support.HealthLevel
import com.ninotranslator.mobile.support.HealthFeed
import com.ninotranslator.mobile.support.NetKind
import com.ninotranslator.mobile.ui.components.NinoScreen
import com.ninotranslator.mobile.ui.components.NinoTile
import com.ninotranslator.mobile.ui.components.NinoTopBar
import com.ninotranslator.mobile.ui.components.RowList
import com.ninotranslator.mobile.ui.components.SecondaryButton
import com.ninotranslator.mobile.ui.components.TileLabel
import com.ninotranslator.mobile.ui.screens.Dot
import com.ninotranslator.mobile.ui.screens.Screens
import com.ninotranslator.mobile.ui.screens.SmallNote
import com.ninotranslator.mobile.ui.theme.NinoColors
import com.ninotranslator.mobile.ui.theme.NinoType
import java.text.DecimalFormat
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import kotlinx.coroutines.delay

/** Sebebin başlığı ve öğüdü (ekranlar-2 "Sistem sağlığı" §1). */
fun causeTexts(context: Context, c: HealthCause, i: HealthInput): Pair<String, String> {
    fun s(id: Int, vararg a: Any) = context.getString(id, *a)
    return when (c) {
        HealthCause.OFFLINE -> s(R.string.health_cause_offline) to s(R.string.health_advice_offline)
        HealthCause.PS5_AFTER_NETWORK -> s(R.string.health_cause_ps5_after_network) to s(R.string.health_advice_ps5_after_network)
        HealthCause.PS5_ASLEEP -> s(R.string.health_cause_ps5_asleep) to s(R.string.health_advice_ps5_asleep)
        HealthCause.PS5_IN_USE -> s(R.string.health_cause_ps5_in_use) to s(R.string.health_advice_ps5_in_use)
        HealthCause.PS5_LOST -> s(R.string.health_cause_ps5_lost) to s(R.string.health_advice_ps5_lost)
        HealthCause.PS5_NEVER -> s(R.string.health_cause_ps5_never) to s(R.string.health_advice_ps5_never)
        HealthCause.NETWORK_DROPPED -> s(R.string.health_cause_network_dropped) to s(R.string.health_advice_network_dropped, i.networkLosses)
        HealthCause.PICTURE_WIFI -> s(R.string.health_cause_picture_wifi) to s(R.string.health_advice_picture_wifi)
        HealthCause.PICTURE -> s(R.string.health_cause_picture) to s(R.string.health_advice_picture)
        HealthCause.DROPS -> s(R.string.health_cause_drops) to s(R.string.health_advice_drops, i.drops)
        HealthCause.SLOW -> s(R.string.health_cause_slow) to s(R.string.health_advice_slow, oneDecimal((i.medianTranslateMs ?: 0) / 1000.0))
        HealthCause.TV -> s(R.string.health_cause_tv) to s(R.string.health_advice_tv, i.tvDrops)
    }
}

/** Sorun kaydının adı. */
fun incidentName(context: Context, k: HealthIssueKind): String = context.getString(when (k) {
    HealthIssueKind.PS5_DROPPED -> R.string.health_incident_ps5_dropped
    HealthIssueKind.PS5_UNREACHABLE -> R.string.health_incident_ps5_unreachable
    HealthIssueKind.NETWORK_LOST -> R.string.health_incident_network
    HealthIssueKind.TV_DROPPED -> R.string.health_incident_tv
})

/** Yerel biçimli bir ondalık. */
fun oneDecimal(v: Double): String = DecimalFormat("0.0").format(v)

/** Sistem sağlığı (ekranlar-2 "Sistem sağlığı"): veriler her saniye yenilenir. */
@Composable
fun HealthScreen(nav: com.ninotranslator.mobile.ui.navigation.NinoNavigator) {
    val context = LocalContext.current
    LaunchedEffect(Unit) { HealthFeed.ensureStarted(context) }
    val i by HealthFeed.input.collectAsState()
    val issues by Nino.health.issues.collectAsState()
    var tick by remember { mutableStateOf(0) }
    LaunchedEffect(Unit) { while (true) { delay(1_000); tick++ } }

    NinoScreen(topBar = { NinoTopBar(onBack = nav::back, title = stringResource(R.string.nino_system_health)) }) {
        // 1. Sebep karosu
        val causes = HealthEval.causes(i)
        if (causes.isNotEmpty()) {
            val (title, advice) = causeTexts(context, causes.first(), i)
            NinoTile {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Dot(Screens.healthColor(HealthLevel.PROBLEM), 14.dp)
                    Text(title, Modifier.weight(1f), style = NinoType.Headline)
                }
                Text(advice, style = NinoType.Body)
                causes.drop(1).forEach { SmallNote("• " + causeTexts(context, it, i).first) }
            }
        } else if (i.running && i.streaming) {
            NinoTile {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Dot(Screens.healthColor(HealthLevel.GOOD), 14.dp)
                    Text(stringResource(R.string.health_all_fine), style = NinoType.Headline)
                }
            }
        }

        // 3'ün satırları (genel durumun rengi için önce hesaplanır)
        val net = HealthEval.networkLevel(i)
        val ps5 = HealthEval.ps5Level(i)
        val pic = HealthEval.pictureLevel(i)
        val tr = HealthEval.translationLevel(i)
        val tvShown = i.targetTv
        val tv = HealthEval.tvLevel(i)
        val overall = HealthEval.overall(listOfNotNull(net, ps5, pic, tr, if (tvShown) tv else null))

        // 2. Genel durum
        NinoTile {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Dot(Screens.healthColor(if (!i.measured) HealthLevel.UNKNOWN else overall), 14.dp)
                Text(stringResource(when {
                    !i.measured -> R.string.nino_health_measured_on_start
                    overall == HealthLevel.PROBLEM -> R.string.nino_health_problem
                    overall == HealthLevel.WARNING -> R.string.nino_health_warning
                    overall == HealthLevel.GOOD -> R.string.nino_health_good
                    else -> R.string.nino_health_measuring
                }), style = NinoType.Headline)
            }
            SmallNote(stringResource(R.string.nino_health_intro))
        }

        // 3. Ölçüm satırları
        val rows = ArrayList<@Composable () -> Unit>()
        rows += {
            MeasureRow(net, stringResource(R.string.nino_health_network), if (i.network == NetKind.WIFI) "Wi-Fi" else stringResource(when (i.network) {
                NetKind.WIFI, NetKind.WIRED -> R.string.nino_net_wired
                NetKind.CELLULAR -> R.string.nino_net_cellular
                NetKind.OFFLINE -> R.string.nino_net_offline
                NetKind.OTHER -> R.string.nino_net_other
            }), when {
                i.network == NetKind.OFFLINE -> stringResource(R.string.nino_net_offline_advice)
                i.network == NetKind.CELLULAR -> stringResource(R.string.nino_net_cellular_advice)
                net == HealthLevel.WARNING || net == HealthLevel.PROBLEM -> stringResource(R.string.nino_net_weak_advice)
                else -> null
            })
        }
        rows += {
            val since = i.disconnectedSinceMs
            MeasureRow(ps5, stringResource(R.string.nino_health_ps5), when {
                !i.measured -> "—"
                since != null && i.everStreamed -> stringResource(R.string.health_disconnected_for, ((i.nowMs - since) / 60_000).toInt().coerceAtLeast(1))
                i.everStreamed && i.drops == 0 -> stringResource(R.string.nino_connected)
                i.drops > 0 -> stringResource(R.string.nino_dropped_times, i.drops)
                i.failedConnects > 0 -> stringResource(R.string.nino_could_not_connect)
                else -> "—"
            }, when (ps5) {
                HealthLevel.PROBLEM -> stringResource(R.string.nino_ps5_problem_advice)
                HealthLevel.WARNING -> stringResource(R.string.nino_ps5_warning_advice)
                else -> null
            })
        }
        rows += {
            val fps = HealthEval.fpsShown(i)
            MeasureRow(pic, stringResource(R.string.nino_health_picture), when {
                fps != null -> stringResource(R.string.nino_fps, fps.toInt().toString())
                i.running && !i.streaming -> stringResource(R.string.health_no_picture)
                else -> "—"
            }, if (pic == HealthLevel.WARNING || pic == HealthLevel.PROBLEM) stringResource(R.string.nino_picture_advice) else null)
        }
        rows += {
            val m = i.medianTranslateMs
            MeasureRow(tr, stringResource(R.string.nino_health_translation), when {
                m != null -> stringResource(R.string.nino_seconds, oneDecimal(m / 1000.0))
                i.lines > 0 && i.lines == i.packLines -> stringResource(R.string.health_all_ready, i.lines)
                i.measured && i.lines == 0 -> stringResource(R.string.health_no_subtitle_yet)
                else -> "—"
            }, if (tr == HealthLevel.WARNING || tr == HealthLevel.PROBLEM) stringResource(R.string.nino_translation_advice) else null)
        }
        if (tvShown) rows += {
            MeasureRow(tv, "TV", when {
                i.tvConnected > 0 -> stringResource(R.string.nino_connected)
                i.running -> stringResource(R.string.nino_waiting)
                else -> "—"
            }, if (tv == HealthLevel.WARNING) stringResource(R.string.nino_tv_advice) else null)
        }
        RowList(rows = rows)

        // 4. Son sorunlar
        if (issues.isNotEmpty()) {
            val fmt = remember { DateTimeFormatter.ofLocalizedDateTime(FormatStyle.SHORT).withZone(ZoneId.systemDefault()) }
            val autoReport = remember(tick / 10) { Nino.settings.autoReport }
            NinoTile {
                TileLabel(stringResource(R.string.health_recent))
                issues.sortedByDescending { it.dateMs }.take(8).forEach { issue ->
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        SmallNote(fmt.format(Instant.ofEpochMilli(issue.dateMs)))
                        Text(incidentName(context, issue.kind), Modifier.weight(1f), style = NinoType.Body, textAlign = TextAlign.End)
                    }
                }
                SmallNote(stringResource(if (autoReport) R.string.health_recent_auto else R.string.health_recent_manual))
            }
        }

        // 5. Ayrıntılar
        var open by remember { mutableStateOf(false) }
        NinoTile(onClick = { open = !open }) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.nino_health_details), Modifier.weight(1f), style = NinoType.Headline)
                Text(stringResource(if (open) R.string.nino_hide else R.string.nino_show), fontSize = 13.sp, color = NinoColors.Accent)
            }
            SmallNote(stringResource(R.string.nino_health_send_note))
            if (open) {
                val text = detailsText(i)
                Text(text, fontFamily = FontFamily.Monospace, fontSize = 12.sp, color = NinoColors.Ink)
                SecondaryButton(stringResource(R.string.nino_health_share), { Screens.shareText(context, text) })
            }
        }

        // 6. Cihaz bilgileri
        DeviceInfoTile(tick)
    }
}

/** Ayrıntılar metni (dilden bağımsız). */
fun detailsText(i: HealthInput): String {
    val s = Nino.settings
    val engine = s.engine.name.lowercase()
    return buildString {
        append("Nino Android ").append(BuildConfig.VERSION_NAME).append('\n')
        append("cihaz: ").append(Build.MANUFACTURER).append(' ').append(Build.MODEL).append(", Android ").append(Build.VERSION.RELEASE).append('\n')
        append("çıkış: ").append(if (s.target == SubtitleTarget.TV) "tv" else "phone").append(", bağlı TV: ").append(LiveStatus.state.value.connectedTvs)
            .append(", motor: ").append(engine).append('\n')
        append("oturum: ").append(if (i.running) "sürüyor" else "bitti").append('\n')
        append(HealthEval.summaryLine(i))
    }
}

@Composable
private fun MeasureRow(level: HealthLevel, title: String, value: String, advice: String?) {
    Column(Modifier.padding(vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Dot(Screens.healthColor(level), 10.dp)
            Text(title, Modifier.weight(1f), style = NinoType.Headline)
            Text(value, style = NinoType.Body, color = NinoColors.InkSecondary, textAlign = TextAlign.End)
        }
        if (advice != null) SmallNote(advice, Modifier.padding(start = 20.dp))
    }
}

/** Cihaz bilgileri karosu; durum, TV, oyun değiştikçe yenilenir. */
@Composable
private fun DeviceInfoTile(tick: Int) {
    val context = LocalContext.current
    val fields = remember(tick / 2) { DeviceSummary.fields() }
    var copied by remember { mutableStateOf(false) }
    LaunchedEffect(copied) { if (copied) { delay(2_000); copied = false } }
    val names = mapOf(
        "app" to R.string.device_info_app, "device" to R.string.device_info_device, "system" to R.string.device_info_system,
        "tv" to R.string.device_info_tv, "console" to R.string.device_info_console, "status" to R.string.device_info_status,
    )
    NinoTile {
        TileLabel(stringResource(R.string.device_info_title))
        SmallNote(stringResource(R.string.device_info_note))
        fields.forEach { (k, v) ->
            val label = names[k] ?: return@forEach
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                SmallNote(stringResource(label))
                Text(v, Modifier.weight(1f), style = NinoType.Body, textAlign = TextAlign.End)
            }
        }
        SecondaryButton(stringResource(if (copied) R.string.history_copied else R.string.device_info_copy), {
            Screens.copy(context, DeviceSummary.join(fields)); copied = true
        })
    }
}
