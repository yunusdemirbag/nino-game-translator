// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui.screens.setup

import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import com.ninotranslator.mobile.R
import com.ninotranslator.mobile.data.Nino
import com.ninotranslator.mobile.data.Ps5Registration
import com.ninotranslator.mobile.remoteplay.FoundPs5
import com.ninotranslator.mobile.remoteplay.NetworkAddresses
import com.ninotranslator.mobile.remoteplay.PairResult
import com.ninotranslator.mobile.remoteplay.Ps5Finder
import com.ninotranslator.mobile.remoteplay.Ps5Pairing
import com.ninotranslator.mobile.ui.components.CodeBoxes
import com.ninotranslator.mobile.ui.components.GhostButton
import com.ninotranslator.mobile.ui.components.NinoScreen
import com.ninotranslator.mobile.ui.components.NinoTextField
import com.ninotranslator.mobile.ui.components.NinoTile
import com.ninotranslator.mobile.ui.components.NinoTopBar
import com.ninotranslator.mobile.ui.components.NoteTile
import com.ninotranslator.mobile.ui.components.PrimaryButton
import com.ninotranslator.mobile.ui.components.ScreenHeader
import com.ninotranslator.mobile.ui.components.TileIcon
import com.ninotranslator.mobile.ui.components.TileLabel
import com.ninotranslator.mobile.ui.navigation.NinoNavigator
import com.ninotranslator.mobile.ui.shell.rememberTranslationStarter
import com.ninotranslator.mobile.ui.theme.NinoColors
import com.ninotranslator.mobile.ui.theme.NinoDimens
import com.ninotranslator.mobile.ui.theme.NinoType
import kotlinx.coroutines.launch

/** PS5 eşleme (ekranlar-1 §6.2): sürekli arama, elle adres, 8 haneli kod, hata nedenleri. */
@Composable
fun Ps5PairScreen(nav: NinoNavigator) {
    val context = LocalContext.current
    val secrets = Nino.secrets
    val firstSetup = !nav.canGoBack()
    val starter = rememberTranslationStarter()
    val scope = rememberCoroutineScope()

    var found by remember { mutableStateOf<List<FoundPs5>?>(null) }
    var scanKey by remember { mutableIntStateOf(0) }
    var address by rememberSaveable { mutableStateOf(secrets.console?.host.orEmpty()) }
    var userChose by rememberSaveable { mutableStateOf(false) }
    var manual by rememberSaveable { mutableStateOf(false) }
    var code by rememberSaveable { mutableStateOf("") }
    var invalidAddress by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var working by remember { mutableStateOf(false) }

    // Ekran açık kaldıkça arama (2,5 sn; bulunamazsa 1,5 sn, bulunursa 6 sn sonra yeniden).
    LaunchedEffect(scanKey) {
        Ps5Finder().pairingScan().collect { list ->
            found = list
            if (list.isNotEmpty() && !userChose) {
                address = list.first().address
                manual = false
            } else if (list.isEmpty() && !userChose) {
                manual = true
            }
        }
    }

    fun connect() {
        invalidAddress = false
        error = null
        val clean = NetworkAddresses.cleanManualAddress(address)
        if (clean == null) { invalidAddress = true; return }
        address = clean
        val account = secrets.accountId
        if (account == null) { error = context.getString(R.string.pair_failed, reasonText(context, "error_not_paired", null)); return }
        working = true
        scope.launch {
            val r = try {
                Ps5Pairing().pair(clean, account, code)
            } catch (e: Exception) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                working = false
                error = context.getString(R.string.pair_failed, e.message ?: context.getString(R.string.regist_failed))
                return@launch
            }
            when (r) {
                is PairResult.Success -> {
                    val c = r.console
                    val saved = secrets.setConsole(Ps5Registration(c.host, c.name, c.registKey, c.morning))
                    working = false
                    if (saved) nav.finishStep() else error = context.getString(R.string.pair_failed, context.getString(R.string.regist_failed))
                }
                is PairResult.Failure -> {
                    working = false
                    if (r.reasonKey == "address_invalid") invalidAddress = true
                    else error = context.getString(R.string.pair_failed, reasonText(context, r.reasonKey, r.detail))
                }
            }
        }
    }

    NinoScreen(
        topBar = {
            NinoTopBar(onBack = if (firstSetup) null else nav::back, actions = {
                if (firstSetup) GhostButton(stringResource(R.string.skip_for_now), nav::skipSetup)
            })
        },
        bottom = {
            if (!manual) GhostButton(stringResource(R.string.pair_not_found), { manual = true; userChose = true })
            if (firstSetup) GhostButton(stringResource(R.string.demo_try), {
                starter.startDemo()
                nav.skipSetup()
            })
            PrimaryButton(stringResource(R.string.pair_button), ::connect,
                enabled = !working && code.length == 8 && address.isNotBlank())
        },
    ) {
        ScreenHeader(stringResource(R.string.pair_title), step = stringResource(R.string.setup_step, 2),
            body = stringResource(R.string.pair_body))

        val list = found
        when {
            list == null -> NinoTile {
                Text(stringResource(R.string.pair_searching), style = NinoType.Body, color = NinoColors.InkSecondary)
            }
            list.isEmpty() -> NinoTile {
                Text(stringResource(R.string.pair_searching), style = NinoType.Headline)
                Text(stringResource(R.string.pair_still_searching), style = NinoType.Caption.copy(fontWeight = null),
                    color = NinoColors.InkSecondary)
                GhostButton(stringResource(R.string.pair_search_again), { found = null; scanKey++ })
            }
            else -> list.forEach { ps5 ->
                NinoTile(selected = ps5.address == address, onClick = {
                    address = ps5.address; userChose = true; invalidAddress = false
                }) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(NinoDimens.InnerGap)) {
                        TileIcon(Icons.Filled.CheckCircle, tint = NinoColors.Success)
                        Column(Modifier.weight(1f)) {
                            Text(stringResource(R.string.pair_found, ps5.name), style = NinoType.Headline)
                            Text(stringResource(R.string.pair_same_wifi, ps5.address), style = NinoType.Caption.copy(fontWeight = null),
                                color = NinoColors.InkSecondary)
                        }
                    }
                }
            }
        }

        if (manual) {
            NinoTextField(address, { address = it; userChose = true; invalidAddress = false }, stringResource(R.string.pair_address),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri))
        }
        if (invalidAddress) NoteTile(stringResource(R.string.address_invalid))

        NinoTile {
            TileLabel(stringResource(R.string.pair_code))
            CodeBoxes(code, { code = it }, contentDescription = stringResource(R.string.pair_code), enabled = !working)
            Text(stringResource(R.string.pair_code_note), style = NinoType.Caption.copy(fontWeight = null), color = NinoColors.InkSecondary)
        }
        error?.let { NoteTile(it) }
        if (working) Text(stringResource(R.string.pair_working), style = NinoType.Body, color = NinoColors.InkSecondary)
    }
}

/** Eşleme hata anahtarından metin; bilinmeyen anahtar "PS5'e bağlanılamadı." olur. Ayrıntı parantez içinde. */
internal fun reasonText(context: Context, key: String, detail: String?): String {
    val res = when (key) {
        "regist_wrong_account" -> R.string.regist_wrong_account
        "regist_wrong_code" -> R.string.regist_wrong_code
        "regist_in_use" -> R.string.regist_in_use
        "regist_version" -> R.string.regist_version
        "regist_crashed" -> R.string.regist_crashed
        "regist_bad_address" -> R.string.regist_bad_address
        "regist_no_answer" -> R.string.regist_no_answer
        "regist_no_reply" -> R.string.regist_no_reply
        "address_invalid" -> R.string.address_invalid
        "error_native" -> R.string.error_native
        "error_not_paired" -> R.string.error_not_paired
        else -> R.string.regist_failed
    }
    val text = context.getString(res)
    return if (detail.isNullOrBlank()) text else "$text ($detail)"
}
