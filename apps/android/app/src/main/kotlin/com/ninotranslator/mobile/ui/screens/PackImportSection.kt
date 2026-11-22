// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui.screens

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.ninotranslator.core.packs.PackImporter
import com.ninotranslator.mobile.R
import com.ninotranslator.mobile.data.Nino
import com.ninotranslator.mobile.service.TranslationControl
import com.ninotranslator.mobile.packs.PackInfo
import com.ninotranslator.mobile.packs.Packs
import com.ninotranslator.mobile.packs.StorePackCatalog
import com.ninotranslator.mobile.ui.components.GhostButton
import com.ninotranslator.mobile.ui.components.NinoRow
import com.ninotranslator.mobile.ui.components.NinoTextField
import com.ninotranslator.mobile.ui.components.NoteTile
import com.ninotranslator.mobile.ui.components.RowList
import com.ninotranslator.mobile.ui.components.SecondaryButton
import com.ninotranslator.mobile.ui.theme.NinoColors
import com.ninotranslator.mobile.ui.theme.NinoType
import java.io.File
import java.text.NumberFormat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Seçilebilen dosya türleri (depolama izni istenmez). */
private val IMPORT_TYPES = arrayOf(
    "application/json", "text/plain", "application/x-subrip", "text/srt", "application/srt", "text/*", "application/octet-stream",
)

private class ImportFailed(val read: Boolean) : Exception()

/** Dosyayı okur ve önizler (engelleyici). 64 MB'tan büyükse belleğe alınmadan reddedilir. */
private fun readPreview(context: Context, uri: Uri): Pair<String, PackImporter.Preview> {
    val cr = context.contentResolver
    var name = "pack.json"
    var size = -1L
    runCatching {
        cr.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { c ->
            if (c.moveToFirst()) {
                c.getColumnIndex(OpenableColumns.DISPLAY_NAME).takeIf { it >= 0 }?.let { i -> c.getString(i)?.let { name = it } }
                c.getColumnIndex(OpenableColumns.SIZE).takeIf { it >= 0 && !c.isNull(it) }?.let { i -> size = c.getLong(i) }
            }
        }
    }
    if (size > PackImporter.MAX_BYTES) throw ImportFailed(read = false)
    val bytes = try {
        cr.openInputStream(uri)?.use { input ->
            val out = java.io.ByteArrayOutputStream()
            val buf = ByteArray(64 * 1024)
            var total = 0L
            while (true) {
                val n = input.read(buf)
                if (n < 0) break
                total += n
                if (total > PackImporter.MAX_BYTES) throw ImportFailed(read = false)
                out.write(buf, 0, n)
            }
            out.toByteArray()
        } ?: throw ImportFailed(read = true)
    } catch (e: ImportFailed) { throw e } catch (e: Exception) { throw ImportFailed(read = true) }
    // Uzantısız ad: JSON say.
    val effective = if (PackImporter.kindOf(name) == null && '.' !in name) "$name.json" else name
    return try { name to PackImporter.preview(effective, bytes) } catch (e: Exception) { throw ImportFailed(read = false) }
}

/** İçe aktarılan paketler bölümü (ekranlar-2 "Paketi içe aktar"). */
@Composable
fun PackImportSection(imported: List<PackInfo>) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var reading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var preview by remember { mutableStateOf<Pair<String, PackImporter.Preview>?>(null) }
    var toDelete by remember { mutableStateOf<PackInfo?>(null) }
    val formatError = stringResource(R.string.packs_import_format_error)
    val readError = stringResource(R.string.packs_import_read_error)

    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        reading = true; error = null
        scope.launch {
            try {
                preview = withContext(Dispatchers.IO) { readPreview(context, uri) }
            } catch (e: ImportFailed) {
                error = if (e.read) readError else formatError
            }
            reading = false
        }
    }

    Text(stringResource(R.string.packs_imported_title), style = NinoType.Headline)
    SmallNote(stringResource(R.string.packs_import_note))
    if (imported.isNotEmpty()) {
        RowList(rows = imported.map { p ->
            @Composable {
                NinoRow(p.title, value = lineCountText(p.lineCount)) {
                    GhostButton(stringResource(R.string.packs_delete), { toDelete = p }, color = NinoColors.Danger)
                }
            }
        })
    }
    error?.let { NoteTile(it) }
    SecondaryButton(stringResource(R.string.packs_import), { launcher.launch(IMPORT_TYPES) }, enabled = !reading)

    preview?.let { (fileName, pv) -> ImportDialog(fileName, pv) { preview = null } }
    toDelete?.let { p ->
        ConfirmDialog(stringResource(R.string.packs_delete_title), stringResource(R.string.packs_delete_body, p.title),
            stringResource(R.string.packs_delete), {
                (Packs.catalog as? StorePackCatalog)?.deleteImported(p.id)
                    ?: File(File(Nino.filesDir, "packs-imported"), "${p.id}.json").delete().also { TranslationControl.reloadPacks(context) }
                toDelete = null
            }, { toDelete = null })
    }
}

@Composable
private fun ImportDialog(fileName: String, pv: PackImporter.Preview, onClose: () -> Unit) {
    val scope = rememberCoroutineScope()
    var title by remember { mutableStateOf(pv.suggestedTitle?.takeIf { it.isNotBlank() } ?: fileName.substringBeforeLast('.')) }
    var installing by remember { mutableStateOf(false) }
    var failed by remember { mutableStateOf(false) }
    var replaceAsk by remember { mutableStateOf(false) }
    val nf = remember { NumberFormat.getIntegerInstance() }

    fun install(replace: Boolean) {
        installing = true; failed = false
        scope.launch {
            val r = withContext(Dispatchers.IO) {
                runCatching {
                    val cat = Packs.catalog as? StorePackCatalog
                    cat?.saveImported(title, pv, replace)
                        ?: PackImporter.save(File(Nino.filesDir, "packs-imported"), title, pv, replace).also { TranslationControl.reloadPacks(Nino.appContext) }
                }
            }
            installing = false
            r.onSuccess { onClose() }.onFailure { e ->
                if (e is PackImporter.Failure.Exists) replaceAsk = true else failed = true
            }
        }
    }

    val canInstall = pv.entries.isNotEmpty() && title.isNotBlank() && !installing
    AlertDialog(
        onDismissRequest = { if (!installing) onClose() },
        containerColor = NinoColors.Surface2,
        title = { Text(stringResource(R.string.packs_import_heading), style = NinoType.Headline) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                NinoTextField(title, { title = it }, stringResource(R.string.packs_import_game_title), enabled = !installing)
                CountRow(stringResource(R.string.packs_import_usable), nf.format(pv.entries.size))
                CountRow(stringResource(R.string.packs_import_invalid), nf.format(pv.invalid))
                CountRow(stringResource(R.string.packs_import_duplicate), nf.format(pv.duplicates))
                CountRow(stringResource(R.string.packs_import_conflict), nf.format(pv.conflicts))
                if (pv.entries.isEmpty()) Text(stringResource(R.string.packs_import_empty), style = NinoType.Body, color = NinoColors.Warning)
                if (failed) Text(stringResource(R.string.packs_import_install_error), style = NinoType.Body, color = NinoColors.Danger)
                if (installing) Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(Modifier.size(24.dp), color = NinoColors.Accent, strokeWidth = 2.dp)
                }
            }
        },
        confirmButton = {
            TextButton(onClick = { install(false) }, enabled = canInstall) {
                Text(stringResource(R.string.packs_import_install), style = NinoType.Headline,
                    color = if (canInstall) NinoColors.Accent else NinoColors.InkSecondary)
            }
        },
        dismissButton = {
            TextButton(onClick = onClose, enabled = !installing) {
                Text(stringResource(R.string.cancel), style = NinoType.Headline, color = NinoColors.AccentText)
            }
        },
    )
    if (replaceAsk) {
        ConfirmDialog(stringResource(R.string.packs_import_replace_title), stringResource(R.string.packs_import_replace_body),
            stringResource(R.string.packs_import_replace), { replaceAsk = false; install(true) }, { replaceAsk = false })
    }
}

@Composable
private fun CountRow(name: String, value: String) {
    Row(Modifier.fillMaxWidth()) {
        Text(name, Modifier.weight(1f), style = NinoType.Body, color = NinoColors.InkSecondary)
        Text(value, style = NinoType.Body)
    }
}
