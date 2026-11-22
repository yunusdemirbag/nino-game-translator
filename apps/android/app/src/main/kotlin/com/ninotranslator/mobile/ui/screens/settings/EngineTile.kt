// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui.screens.settings

import android.content.Context
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import com.ninotranslator.core.http.UrlConnectionTransport
import com.ninotranslator.core.translation.AiModels
import com.ninotranslator.core.translation.KeyStatus
import com.ninotranslator.core.translation.OnlineEngines
import com.ninotranslator.core.translation.OnlineService
import com.ninotranslator.mobile.R
import com.ninotranslator.mobile.data.Engine
import com.ninotranslator.mobile.data.Nino
import com.ninotranslator.mobile.ui.components.GhostButton
import com.ninotranslator.mobile.ui.components.NinoTag
import com.ninotranslator.mobile.ui.components.NinoTextField
import com.ninotranslator.mobile.ui.components.NinoTile
import com.ninotranslator.mobile.ui.components.NoteTile
import com.ninotranslator.mobile.ui.components.SecondaryButton
import com.ninotranslator.mobile.ui.components.SegmentedPicker
import com.ninotranslator.mobile.ui.components.TileLabel
import com.ninotranslator.mobile.ui.screens.SmallNote
import com.ninotranslator.mobile.ui.theme.NinoType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Motorun ekrandaki adı. */
fun engineName(context: Context, e: Engine): String = when (e) {
    Engine.FREE -> context.getString(R.string.engine_free_short)
    Engine.DEEPL -> "DeepL"
    Engine.GEMINI -> "Gemini"
    Engine.OPENAI -> "OpenAI"
    Engine.CLAUDE -> "Claude"
}

/** Anahtarı hizmete gerçekten dener (engelleyici). */
fun testApiKey(context: Context, engine: Engine, key: String): KeyStatus {
    val service = OnlineService.of(engine.name) ?: return KeyStatus.INVALID_KEY
    val models = runCatching {
        AiModels.parse(context.assets.open("ai-models.json").bufferedReader().use { it.readText() })
    }.getOrNull()
    val e = OnlineEngines.create(service, key, UrlConnectionTransport, models, Nino.settings.aiModel) ?: return KeyStatus.UNREACHABLE
    return runCatching { e.testKey() }.getOrDefault(KeyStatus.UNREACHABLE)
}

/**
 * Çeviri motoru karosu (ekranlar-2 Ayarlar §6): dört parçalı segment, "Diğer" altında OpenAI | Claude, motor
 * ücretsiz değilse anahtar satırı (kaydet ve dene / kaldır).
 */
@Composable
fun EngineTile(label: String) {
    val context = LocalContext.current
    val settings = Nino.settings
    val secrets = Nino.secrets
    val rev by settings.revision.collectAsState()
    val secretRev by secrets.revision.collectAsState()
    val engine = remember(rev) { settings.engine }
    val saved = remember(secretRev, engine) { engine != Engine.FREE && secrets.apiKey(engine) != null }
    val scope = rememberCoroutineScope()
    var keyText by remember(engine) { mutableStateOf("") }
    var checking by remember { mutableStateOf<Engine?>(null) }
    var rejected by remember(engine) { mutableStateOf(false) }

    val main = listOf(Engine.FREE, Engine.DEEPL, Engine.GEMINI)
    val other = engine == Engine.OPENAI || engine == Engine.CLAUDE
    NinoTile {
        TileLabel(label)
        SegmentedPicker(
            listOf(stringResource(R.string.engine_free_short), "DeepL", "Gemini", stringResource(R.string.engine_other)),
            if (other) 3 else main.indexOf(engine),
            { i -> settings.engine = if (i < 3) main[i] else if (engine == Engine.CLAUDE) Engine.CLAUDE else Engine.OPENAI },
        )
        if (other) {
            SegmentedPicker(listOf("OpenAI", "Claude"), if (engine == Engine.CLAUDE) 1 else 0,
                { settings.engine = if (it == 1) Engine.CLAUDE else Engine.OPENAI })
        }
        if (engine != Engine.FREE) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.settings_key_for, engineName(context, engine)), Modifier.weight(1f), style = NinoType.Headline)
                if (saved) NinoTag(stringResource(R.string.settings_key_saved))
            }
            if (saved) {
                GhostButton(stringResource(R.string.settings_key_remove), { secrets.setApiKey(engine, null) })
            } else {
                val busy = checking != null
                NinoTextField(keyText, { keyText = it.trim(); rejected = false }, stringResource(R.string.settings_key), secret = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password), enabled = !busy)
                SecondaryButton(stringResource(if (busy) R.string.settings_key_checking else R.string.settings_key_save), {
                    val tested = engine
                    val key = keyText
                    checking = tested
                    scope.launch {
                        val status = withContext(Dispatchers.IO) { testApiKey(context, tested, key) }
                        val ok = status.acceptable && withContext(Dispatchers.IO) { secrets.setApiKey(tested, key) }
                        checking = null
                        // Deneme sürerken motor değiştiyse sonuç yalnız kaydı etkiler.
                        if (settings.engine == tested) {
                            if (ok) keyText = "" else rejected = true
                        }
                    }
                }, enabled = keyText.isNotBlank() && !busy)
                if (rejected) NoteTile(stringResource(R.string.settings_key_rejected))
            }
        }
        SmallNote(stringResource(R.string.settings_engine_note))
    }
}
