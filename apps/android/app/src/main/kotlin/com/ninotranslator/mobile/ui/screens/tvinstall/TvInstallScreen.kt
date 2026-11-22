// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui.screens.tvinstall

import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Home
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ninotranslator.mobile.R
import com.ninotranslator.mobile.data.Nino
import com.ninotranslator.mobile.data.TvBrand
import com.ninotranslator.mobile.remoteplay.NetworkAddresses
import com.ninotranslator.mobile.tv.TvAppVersions
import com.ninotranslator.mobile.tv.TvFinders
import com.ninotranslator.mobile.tv.install.TvCandidate
import com.ninotranslator.mobile.tv.install.TvCandidateStatus
import com.ninotranslator.mobile.tv.install.TvInstallError
import com.ninotranslator.mobile.tv.install.TvInstallException
import com.ninotranslator.mobile.tv.install.TvInstallRequest
import com.ninotranslator.mobile.tv.install.TvInstallStep
import com.ninotranslator.mobile.tv.install.TvInstallers
import com.ninotranslator.mobile.ui.components.DangerButton
import com.ninotranslator.mobile.ui.components.GhostButton
import com.ninotranslator.mobile.ui.components.NinoScreen
import com.ninotranslator.mobile.ui.components.NinoTextField
import com.ninotranslator.mobile.ui.components.NinoTile
import com.ninotranslator.mobile.ui.components.NinoTopBar
import com.ninotranslator.mobile.ui.components.NoteTile
import com.ninotranslator.mobile.ui.components.PrimaryButton
import com.ninotranslator.mobile.ui.components.ScreenHeader
import com.ninotranslator.mobile.ui.components.SegmentedPicker
import com.ninotranslator.mobile.ui.components.SelectedMark
import com.ninotranslator.mobile.ui.components.StatusText
import com.ninotranslator.mobile.ui.components.TileLabel
import com.ninotranslator.mobile.ui.navigation.NinoNavigator
import com.ninotranslator.mobile.ui.screens.Screens
import com.ninotranslator.mobile.ui.screens.SmallNote
import com.ninotranslator.mobile.ui.theme.NinoColors
import com.ninotranslator.mobile.ui.theme.NinoType

private val BRANDS = listOf(TvBrand.SAMSUNG, TvBrand.LG, TvBrand.ANDROID_TV)

/** Adım metni. */
fun stepText(context: Context, s: TvInstallStep): String = context.getString(when (s) {
    TvInstallStep.PAIRING -> R.string.tvinstall_step_pairing
    TvInstallStep.APPROVE -> R.string.tvinstall_step_approve
    TvInstallStep.KEY -> R.string.tvinstall_step_key
    TvInstallStep.PLAY -> R.string.tvinstall_step_play
    TvInstallStep.CONNECTING -> R.string.tvinstall_step_connecting
    TvInstallStep.READING -> R.string.tvinstall_step_reading
    TvInstallStep.SIGNIN -> R.string.tvinstall_step_signin
    TvInstallStep.CERTIFICATE -> R.string.tvinstall_step_certificate
    TvInstallStep.SIGNING -> R.string.tvinstall_step_signing
    TvInstallStep.INSTALLING -> R.string.tvinstall_step_installing
    TvInstallStep.UNINSTALLING -> R.string.tvinstall_step_uninstalling
    TvInstallStep.LAUNCHING -> R.string.tvinstall_step_launching
})

/** Hata öğüdü + gerekirse "\n\n" + ayrıntı (ekranlar-2 "TV uygulaması kurulumu"). */
fun installErrorText(context: Context, e: TvInstallException, brand: TvBrand, phoneIp: String): String {
    fun s(id: Int, vararg a: Any) = context.getString(id, *a)
    val advice = when (e.error) {
        TvInstallError.SPACE -> s(R.string.tvinstall_err_space)
        TvInstallError.CONNECTION -> s(R.string.tvinstall_err_connection)
        TvInstallError.PACKAGE_MISSING -> s(R.string.tvinstall_err_package_missing)
        TvInstallError.FAILED -> s(R.string.tvinstall_err_failed)
        TvInstallError.NOT_READY -> s(R.string.not_ready_yet)
        TvInstallError.ADDRESS_INVALID -> s(R.string.address_invalid)
        TvInstallError.SAMSUNG_UNREACHABLE -> s(R.string.tvinstall_err_unreachable, phoneIp)
        TvInstallError.SAMSUNG_TOO_OLD -> s(R.string.tvinstall_err_too_old)
        TvInstallError.SAMSUNG_LOGIN -> s(R.string.tvinstall_err_login)
        TvInstallError.SAMSUNG_CERTIFICATE -> s(R.string.tvinstall_err_certificate)
        TvInstallError.SAMSUNG_MISMATCH -> s(R.string.tvinstall_err_mismatch)
        TvInstallError.SAMSUNG_REJECTED -> s(R.string.tvinstall_err_rejected)
        TvInstallError.SAMSUNG_CLOCK -> s(R.string.tvinstall_err_clock)
        TvInstallError.SAMSUNG_BLOCKED -> s(R.string.tvinstall_err_blocked)
        TvInstallError.LG_UNREACHABLE -> s(R.string.tvinstall_lg_err_unreachable)
        TvInstallError.LG_KEY_SERVER -> s(R.string.tvinstall_lg_err_key_server)
        TvInstallError.LG_PASSPHRASE -> s(R.string.tvinstall_lg_err_passphrase)
        TvInstallError.LG_KEY_REFUSED -> s(R.string.tvinstall_lg_err_key_refused)
        TvInstallError.ANDROID_UNREACHABLE -> s(R.string.tvinstall_android_err_unreachable)
        TvInstallError.ANDROID_NOT_APPROVED -> s(R.string.tvinstall_android_err_not_approved)
        TvInstallError.ANDROID_NOT_PAIRED -> s(R.string.tvinstall_android_err_not_paired)
        TvInstallError.ANDROID_PAIRING -> s(R.string.tvinstall_android_err_pairing)
        TvInstallError.ANDROID_PLAY_COPY -> s(R.string.tvinstall_android_err_play_copy)
        TvInstallError.ANDROID_OTHER_COPY -> s(R.string.tvinstall_android_err_other_copy)
        TvInstallError.ANDROID_REMOVE_MANUALLY -> s(R.string.tvinstall_android_err_remove_manually)
        TvInstallError.ANDROID_NEED_PORT -> s(R.string.tvinstall_android_need_port)
        TvInstallError.ANDROID_NEED_PAIR_PORT -> s(R.string.tvinstall_android_need_pair_port)
    }
    val noDetail = e.error in setOf(TvInstallError.LG_PASSPHRASE, TvInstallError.ANDROID_PLAY_COPY, TvInstallError.ANDROID_OTHER_COPY,
        TvInstallError.ANDROID_REMOVE_MANUALLY, TvInstallError.NOT_READY)
    val parts = mutableListOf(advice)
    if (brand == TvBrand.SAMSUNG && (e.error == TvInstallError.FAILED || e.error == TvInstallError.SAMSUNG_REJECTED || e.maintenanceHint)) {
        parts += s(R.string.tvinstall_maintenance)
    }
    if (!noDetail) {
        e.tvSays?.let { parts += s(R.string.tvinstall_lg_tv_says, it) }
        e.detail?.let { parts += s(R.string.tvinstall_details, it) }
    }
    return parts.joinToString("\n\n")
}

/**
 * TV uygulaması kurulumu (ekranlar-2): Samsung, LG, Android TV. Asıl kurulum [TvInstallers] arkasında; [host] verilirse
 * (güncelleme kartı) o TV seçili gelir ve kurulum kendiliğinden başlar.
 */
@Composable
fun TvInstallScreen(nav: NinoNavigator, host: String?) {
    val settings = Nino.settings
    // Önceki ziyaretten kalan sonuç ya da hata girişte silinir (süren kurulum etkilenmez). Güncelleme kartından aynı TV
    // için gelindiyse (ek bilgi gerekti) hata kalır ki kullanıcı hangi adımın eksik olduğunu görsün.
    remember { if (!TvInstallSession.isFor(host)) TvInstallSession.clearFinished(); true }
    val notice by TvAppVersions.state.collectAsState()
    val initialBrand = remember {
        notice?.takeIf { host != null && it.host == host }?.brand
            ?: TvInstallSession.state.value.card?.takeIf { host != null && it.host == host }?.brand
            ?: settings.installedTv?.takeIf { host != null && it.host == host }?.brand
            ?: settings.installedTv?.brand ?: settings.tvInstallBrand
    }
    var brand by rememberSaveable { mutableStateOf(initialBrand) }

    val b = brand
    if (b == null) {
        // Ara ekran: ağdaki TV'ye göre marka seçilir.
        LaunchedEffect(Unit) {
            val found = runCatching { TvFinders.current.search() }.getOrDefault(emptyList())
            val pick = found.firstOrNull { it.brand != null && it.brand != TvBrand.ANDROID_TV }?.brand
                ?: found.firstNotNullOfOrNull { it.brand } ?: TvBrand.SAMSUNG
            settings.tvInstallBrand = pick
            brand = pick
        }
        NinoScreen(topBar = { NinoTopBar(onBack = nav::back) }) {
            ScreenHeader(stringResource(R.string.tvinstall_title), body = stringResource(R.string.tvinstall_any_body))
            NinoTile { StatusText(stringResource(R.string.tvinstall_searching), good = false, live = true) }
        }
        return
    }
    BrandInstall(nav, b, host, onBrand = { nb -> settings.tvInstallBrand = nb; TvInstallSession.clearFinished(); brand = nb })
}

@Composable
private fun BrandInstall(nav: NinoNavigator, brand: TvBrand, host: String?, onBrand: (TvBrand) -> Unit) {
    val context = LocalContext.current
    val installer = TvInstallers.current
    val session by TvInstallSession.state.collectAsState()
    val signInUrl by installer.samsungSignInUrl.collectAsState()
    val running = session.running
    val phoneIp = remember { NetworkAddresses.pickLocalAddress(NetworkAddresses.systemInterfaces()) }

    var searching by remember(brand) { mutableStateOf(true) }
    var candidates by remember(brand) { mutableStateOf<List<TvCandidate>>(emptyList()) }
    var selected by rememberSaveable(brand) { mutableStateOf(host) }
    var manualOpen by rememberSaveable(brand) { mutableStateOf(brand == TvBrand.ANDROID_TV || host != null) }
    var manual by rememberSaveable(brand) { mutableStateOf(host.orEmpty()) }
    var passphrase by rememberSaveable(brand) { mutableStateOf("") }
    var wireless by rememberSaveable(brand) { mutableStateOf(false) }
    var pairAddress by rememberSaveable(brand) { mutableStateOf("") }
    var pairCode by rememberSaveable(brand) { mutableStateOf("") }
    var localError by remember(brand) { mutableStateOf<TvInstallException?>(null) }
    var autoStarted by rememberSaveable { mutableStateOf(false) }

    LaunchedEffect(brand) {
        searching = true
        candidates = runCatching { installer.discover(brand) }.getOrDefault(emptyList())
            .let { l -> if (brand == TvBrand.ANDROID_TV) l.sortedBy { if (it.status == TvCandidateStatus.DebugOn) 0 else 1 } else l }
        searching = false
        if (selected == null) {
            selected = when (brand) {
                TvBrand.LG -> (candidates.firstOrNull { it.status == TvCandidateStatus.DevOn } ?: candidates.firstOrNull())?.address
                TvBrand.ANDROID_TV -> candidates.firstOrNull { it.status == TvCandidateStatus.DebugOn }?.address
                else -> candidates.firstOrNull()?.address
            }
        }
        if (brand == TvBrand.ANDROID_TV && manual.isEmpty()) manual = selected.orEmpty()
        if (candidates.isEmpty()) manualOpen = true
    }

    // Seçilen ya da elle yazılan adres.
    val address: String? = when {
        brand == TvBrand.ANDROID_TV -> manual.trim().takeIf { it.isNotEmpty() }
        manualOpen && manual.isNotBlank() -> manual.trim()
        else -> selected
    }
    val lgKey = remember(address, brand) { brand == TvBrand.LG && address != null && installer.hasLgKey(address) }

    fun request(replace: Boolean = false): TvInstallRequest? {
        localError = null
        val addr = address ?: return null
        val cleaned: String = when (brand) {
            TvBrand.ANDROID_TV -> {
                val ip = NetworkAddresses.cleanManualAddress(addr)
                    ?: run { localError = TvInstallException(TvInstallError.ADDRESS_INVALID); return null }
                val port = addr.substringAfterLast(':', "").takeIf { ':' in addr }?.filter { it.isDigit() }?.takeIf { it.isNotEmpty() }
                if (wireless && port == null) { localError = TvInstallException(TvInstallError.ANDROID_NEED_PORT); return null }
                if (wireless && pairCode.isNotEmpty() && !pairAddress.contains(':')) {
                    localError = TvInstallException(TvInstallError.ANDROID_NEED_PAIR_PORT); return null
                }
                "$ip:${port ?: "5555"}"
            }
            else -> NetworkAddresses.cleanManualAddress(addr)
                ?: run { localError = TvInstallException(TvInstallError.ADDRESS_INVALID); return null }
        }
        return TvInstallRequest(
            brand = brand, address = cleaned, tvName = candidates.firstOrNull { it.address == selected }?.name,
            passphrase = passphrase.takeIf { brand == TvBrand.LG && it.isNotEmpty() },
            wireless = brand == TvBrand.ANDROID_TV && wireless,
            pairAddress = pairAddress.trim().takeIf { wireless && it.isNotEmpty() },
            pairCode = pairCode.takeIf { wireless && it.isNotEmpty() },
            replaceExisting = replace,
        )
    }

    val canInstall = !running && address != null && (brand != TvBrand.LG || passphrase.isNotEmpty() || lgKey)
    fun startInstall(replace: Boolean = false) { request(replace)?.let { TvInstallSession.start(it) } }

    // Güncelleme kartından gelindiyse kurulum kendiliğinden başlar.
    LaunchedEffect(searching) {
        if (!searching && host != null && !autoStarted && !running && session.result == null && session.error == null) {
            val ok = when (brand) { TvBrand.LG -> lgKey; TvBrand.ANDROID_TV -> address != null; else -> true }
            autoStarted = true
            if (ok) startInstall()
        }
    }

    val url = signInUrl
    if (url != null && brand == TvBrand.SAMSUNG) {
        SamsungSignIn(url, onClose = { installer.cancelSamsungSignIn() })
        return
    }

    val result = session.result
    val error = localError ?: session.error
    NinoScreen(
        topBar = { NinoTopBar(onBack = nav::back) },
        bottom = {
            val listShown = brand != TvBrand.ANDROID_TV && !manualOpen && candidates.isNotEmpty()
            if (result == null && listShown && !running) GhostButton(stringResource(R.string.tvinstall_not_found), { manualOpen = true })
            if (result != null) {
                PrimaryButton(stringResource(R.string.tvinstall_go_home), { TvInstallSession.clearFinished(); nav.tvInstallDone() })
            } else {
                PrimaryButton(stringResource(if (session.error != null) R.string.tvinstall_retry else R.string.tvinstall_button),
                    { startInstall() }, enabled = canInstall)
            }
        },
    ) {
        ScreenHeader(stringResource(R.string.tvinstall_title), body = stringResource(when (brand) {
            TvBrand.SAMSUNG -> R.string.tvinstall_body
            TvBrand.LG -> R.string.tvinstall_lg_body
            TvBrand.ANDROID_TV -> R.string.tvinstall_android_body
        }))
        if (!running) {
            SegmentedPicker(listOf(stringResource(R.string.tvinstall_brand_samsung), stringResource(R.string.tvinstall_brand_lg),
                stringResource(R.string.tvinstall_brand_android)), BRANDS.indexOf(brand), { onBrand(BRANDS[it]) })
        }
        SmallNote(stringResource(when (brand) {
            TvBrand.SAMSUNG -> R.string.tvinstall_supported
            TvBrand.LG -> R.string.tvinstall_lg_supported
            TvBrand.ANDROID_TV -> R.string.tvinstall_android_supported
        }))
        TileLabel(stringResource(when (brand) {
            TvBrand.SAMSUNG -> R.string.tvinstall_tvs
            TvBrand.LG -> R.string.tvinstall_lg_tvs
            TvBrand.ANDROID_TV -> R.string.tvinstall_android_tvs
        }))
        when {
            searching -> NinoTile { StatusText(stringResource(R.string.tvinstall_searching), good = false, live = true) }
            candidates.isEmpty() -> NinoTile {
                Text(stringResource(when (brand) {
                    TvBrand.SAMSUNG -> R.string.tvinstall_none
                    TvBrand.LG -> R.string.tvinstall_lg_none
                    TvBrand.ANDROID_TV -> R.string.tvinstall_android_none
                }), style = NinoType.Body, color = NinoColors.InkSecondary)
            }
        }
        candidates.forEach { tv -> CandidateTile(tv, tv.address == address?.substringBefore(':')) {
            if (!running) { selected = tv.address; if (brand == TvBrand.ANDROID_TV || manualOpen) manual = tv.address }
        } }

        // Markaya özel alanlar
        when (brand) {
            TvBrand.SAMSUNG -> if (manualOpen) {
                NinoTextField(manual, { manual = it }, stringResource(R.string.tvinstall_address), enabled = !running,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri))
            }
            TvBrand.LG -> {
                if (manualOpen) NinoTextField(manual, { manual = it }, stringResource(R.string.tvinstall_address), enabled = !running,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri))
                NinoTextField(passphrase, { passphrase = it.uppercase().filterNot { c -> c.isWhitespace() }.take(6) },
                    stringResource(if (lgKey) R.string.tvinstall_lg_passphrase_saved else R.string.tvinstall_lg_passphrase), enabled = !running)
            }
            TvBrand.ANDROID_TV -> {
                TileLabel(stringResource(R.string.tvinstall_android_mode))
                if (!running) {
                    SegmentedPicker(listOf(stringResource(R.string.tvinstall_android_mode_network), stringResource(R.string.tvinstall_android_mode_wireless)),
                        if (wireless) 1 else 0, { wireless = it == 1 })
                }
                NinoTextField(manual, { manual = it },
                    stringResource(if (wireless) R.string.tvinstall_android_address_wireless else R.string.tvinstall_android_address),
                    enabled = !running, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri))
                if (wireless) {
                    NinoTextField(pairAddress, { pairAddress = it }, stringResource(R.string.tvinstall_android_pair_address), enabled = !running,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri))
                    NinoTextField(pairCode, { pairCode = it.filter { c -> c.isDigit() }.take(6) }, stringResource(R.string.tvinstall_android_pair_code),
                        secret = true, enabled = !running, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword))
                }
            }
        }

        // Adımlar
        NinoTile {
            when (brand) {
                TvBrand.SAMSUNG -> {
                    Text(stringResource(R.string.tvinstall_steps_title), style = NinoType.Headline)
                    Text(stringResource(R.string.tvinstall_step1), style = NinoType.Body)
                    Text(stringResource(R.string.tvinstall_step2), style = NinoType.Body)
                    Text(stringResource(R.string.tvinstall_step3), style = NinoType.Body)
                    Text(phoneIp ?: stringResource(R.string.tvinstall_phone_ip_unknown),
                        fontSize = if (phoneIp != null) 28.sp else 15.sp, color = NinoColors.Accent, style = NinoType.Title)
                    Text(stringResource(R.string.tvinstall_step4), style = NinoType.Body)
                }
                TvBrand.LG -> {
                    Text(stringResource(R.string.tvinstall_lg_steps_title), style = NinoType.Headline)
                    listOf(R.string.tvinstall_lg_step1, R.string.tvinstall_lg_step2, R.string.tvinstall_lg_step3, R.string.tvinstall_lg_step4)
                        .forEach { Text(stringResource(it), style = NinoType.Body) }
                }
                TvBrand.ANDROID_TV -> {
                    Text(stringResource(R.string.tvinstall_android_steps_title), style = NinoType.Headline)
                    Text(stringResource(R.string.tvinstall_android_step1), style = NinoType.Body)
                    Text(stringResource(if (wireless) R.string.tvinstall_android_wireless_step2 else R.string.tvinstall_android_step2), style = NinoType.Body)
                    Text(stringResource(if (wireless) R.string.tvinstall_android_wireless_step3 else R.string.tvinstall_android_step3), style = NinoType.Body)
                }
            }
        }
        when (brand) {
            TvBrand.SAMSUNG -> SmallNote(stringResource(R.string.tvinstall_signin_note))
            TvBrand.LG -> SmallNote(stringResource(R.string.tvinstall_lg_session_note))
            else -> {}
        }

        // Durum
        val step = session.step
        when {
            running -> NinoTile(selected = true) {
                StatusText(step?.let { stepText(context, it) } ?: stringResource(R.string.tvinstall_step_connecting), good = false, live = true)
            }
            result != null -> NinoTile(selected = true) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Icon(Icons.Filled.CheckCircle, null, Modifier.size(24.dp), tint = NinoColors.Success)
                    Text(stringResource(if (result.alreadyInstalled) R.string.tvinstall_up_to_date else R.string.tvinstall_done, result.version),
                        Modifier.weight(1f), style = NinoType.Headline)
                }
                SmallNote(stringResource(R.string.tvinstall_next))
            }
            error != null -> {
                NoteTile(installErrorText(context, error, brand, phoneIp ?: "?"))
                if (error.replacePossible && session.error === error) {
                    DangerButton(stringResource(R.string.tvinstall_android_replace), { startInstall(replace = true) })
                }
                if (session.error === error) {
                    GhostButton(stringResource(R.string.tvinstall_share_log), {
                        Screens.shareText(context, Nino.tvInstallLog.read().takeLast(60_000), "Nino tvinstall.log")
                    })
                }
            }
        }
    }
}

@Composable
private fun CandidateTile(tv: TvCandidate, selected: Boolean, onClick: () -> Unit) {
    NinoTile(selected = selected, onClick = onClick) {
        Box(Modifier.fillMaxWidth()) {
            Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Icon(Icons.Filled.Home, null, Modifier.size(24.dp), tint = NinoColors.AccentText)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(tv.name, style = NinoType.Headline)
                    SmallNote(if (tv.brand == TvBrand.SAMSUNG && tv.model != null) "${tv.model} · ${tv.address}" else tv.address)
                    when (val st = tv.status) {
                        TvCandidateStatus.DevOn -> StatusText(stringResource(R.string.tvinstall_dev_on), good = true)
                        TvCandidateStatus.DevOff -> StatusText(stringResource(R.string.tvinstall_dev_off), good = false)
                        is TvCandidateStatus.DevOtherIp -> StatusText(stringResource(R.string.tvinstall_dev_other_ip, st.ip), good = false)
                        TvCandidateStatus.DebugOn -> StatusText(stringResource(R.string.tvinstall_android_debug_on), good = true)
                        TvCandidateStatus.DebugOff -> StatusText(stringResource(R.string.tvinstall_android_debug_off), good = false)
                        null -> {}
                    }
                }
            }
            if (selected) SelectedMark(Modifier.align(Alignment.TopEnd))
        }
    }
}
