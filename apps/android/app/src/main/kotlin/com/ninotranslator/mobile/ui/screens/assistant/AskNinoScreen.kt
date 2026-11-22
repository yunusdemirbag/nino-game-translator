// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui.screens.assistant

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.ClickableText
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.NoteAdd
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.AddPhotoAlternate
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ninotranslator.mobile.R
import com.ninotranslator.mobile.support.AssistantChat
import com.ninotranslator.mobile.support.AssistantWarning
import com.ninotranslator.mobile.support.ChatItem
import com.ninotranslator.mobile.support.ImageShrink
import com.ninotranslator.mobile.support.ReplyBlock
import com.ninotranslator.mobile.support.ReplyParser
import com.ninotranslator.mobile.ui.components.NinoIconButton
import com.ninotranslator.mobile.ui.navigation.NinoNavigator
import com.ninotranslator.mobile.ui.navigation.Routes
import com.ninotranslator.mobile.ui.screens.Screens
import com.ninotranslator.mobile.ui.screens.report.PhotoThumb
import com.ninotranslator.mobile.ui.screens.report.rememberPhotoPicker
import com.ninotranslator.mobile.ui.theme.LocalAnimationsEnabled
import com.ninotranslator.mobile.ui.theme.NinoColors
import com.ninotranslator.mobile.ui.theme.NinoDimens
import com.ninotranslator.mobile.ui.theme.NinoType
import com.ninotranslator.mobile.ui.theme.ninoScreenBackground
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private val NinoBubble = RoundedCornerShape(18.dp, 18.dp, 18.dp, 6.dp)
private val UserBubble = RoundedCornerShape(18.dp, 18.dp, 6.dp, 18.dp)

/** Nino'ya Sor (ekranlar-2 "Nino'ya Sor"): kurulum yardımcısı sohbeti. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun AskNinoScreen(nav: NinoNavigator) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val chat by AssistantChat.state.collectAsState()
    var input by rememberSaveable { mutableStateOf("") }
    val photos = remember { mutableStateListOf<ByteArray>() }
    var loading by remember { mutableStateOf(0) }
    var photoFailed by remember { mutableStateOf(false) }
    val list = rememberLazyListState()

    val picker = rememberPhotoPicker({ AssistantChat.MAX_IMAGES - photos.size }) { uris ->
        loading += uris.size
        uris.forEach { uri ->
            scope.launch {
                val b = withContext(Dispatchers.IO) { ImageShrink.jpeg(context, uri, ImageShrink.CHAT_BYTES) }
                if (b != null && photos.size < AssistantChat.MAX_IMAGES) photos += b else if (b == null) photoFailed = true
                loading--
            }
        }
    }
    val count = chat.items.size + (if (chat.waiting) 1 else 0) + 1
    LaunchedEffect(count) { list.animateScrollToItem((count - 1).coerceAtLeast(0)) }

    fun send(text: String) {
        AssistantChat.send(text, photos.toList())
        input = ""; photos.clear(); photoFailed = false
    }
    val canSend = !chat.waiting && loading == 0 && (input.isNotBlank() || photos.isNotEmpty())

    Box(Modifier.fillMaxSize().ninoScreenBackground(), contentAlignment = Alignment.TopCenter) {
        Column(Modifier.widthIn(max = NinoDimens.MaxContentWidth + 40.dp).fillMaxSize().safeDrawingPadding().imePadding()) {
            // Üst satır
            Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                NinoIconButton(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.back), nav::back)
                Robot(44.dp, float = false, blink = true)
                Column(Modifier.weight(1f)) {
                    Text(stringResource(R.string.assistant_name), style = NinoType.Headline)
                    Text(stringResource(R.string.assistant_subtitle), fontSize = 13.sp, color = NinoColors.InkSecondary)
                }
                if (chat.items.isNotEmpty()) {
                    NinoIconButton(Icons.AutoMirrored.Filled.NoteAdd, stringResource(R.string.assistant_new_chat), {
                        if (!chat.waiting) AssistantChat.newChat()
                    })
                }
            }
            LazyColumn(Modifier.weight(1f).fillMaxWidth(), state = list,
                contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 20.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)) {
                item { NinoMessage(stringResource(R.string.assistant_greeting), false) }
                if (chat.items.isEmpty()) item {
                    FlowRow(Modifier.padding(start = 36.dp), horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        listOf(R.string.assistant_chip_1, R.string.assistant_chip_2, R.string.assistant_chip_3, R.string.assistant_chip_4).forEach { id ->
                            val t = stringResource(id)
                            Box(Modifier.clip(RoundedCornerShape(50)).background(Color.White).border(1.dp, NinoColors.BorderStrong, RoundedCornerShape(50))
                                .clickable { send(t) }.padding(horizontal = 14.dp, vertical = 9.dp)) {
                                Text(t, fontSize = 13.sp, color = NinoColors.Accent)
                            }
                        }
                    }
                }
                items(chat.items, key = { it.id }) { item ->
                    when (item) {
                        is ChatItem.Nino -> NinoMessage(item.text, item.reportSent)
                        is ChatItem.User -> UserMessage(item)
                        is ChatItem.Warning -> WarningMessage(item.kind) { nav.open(Routes.REPORT) }
                    }
                }
                if (chat.waiting) item { TypingBubble() }
            }
            // Yazma alanı
            Column(Modifier.fillMaxWidth().background(Color.White.copy(alpha = 0.7f)).padding(horizontal = 12.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp)) {
                if (photos.isNotEmpty()) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        photos.forEachIndexed { i, p -> PhotoThumb(p, 64.dp, 12.dp, stringResource(R.string.report_remove_photo), 22.dp) { photos.removeAt(i) } }
                    }
                }
                if (photoFailed) Text(stringResource(R.string.report_photo_failed), fontSize = 13.sp, color = NinoColors.Warning)
                Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    val full = photos.size + loading >= AssistantChat.MAX_IMAGES
                    NinoIconButton(Icons.Filled.AddPhotoAlternate, stringResource(R.string.assistant_attach),
                        { if (!full) { photoFailed = false; picker.pick(AssistantChat.MAX_IMAGES - photos.size) } },
                        tint = if (full) NinoColors.InkSecondary else NinoColors.Accent, background = Color.Transparent, border = null)
                    var focused by remember { mutableStateOf(false) }
                    Box(Modifier.weight(1f).heightIn(min = 44.dp).clip(RoundedCornerShape(22.dp)).background(Color.White)
                        .border(1.dp, if (focused) NinoColors.Accent else NinoColors.BorderStrong, RoundedCornerShape(22.dp))
                        .padding(horizontal = 16.dp, vertical = 11.dp)) {
                        if (input.isEmpty()) Text(stringResource(R.string.assistant_hint), style = NinoType.Body, color = NinoColors.InkSecondary)
                        BasicTextField(input, { input = it.take(AssistantChat.MAX_TEXT) }, Modifier.fillMaxWidth().onFocusChanged { focused = it.isFocused },
                            textStyle = NinoType.Body, maxLines = 5)
                    }
                    val sendLabel = stringResource(R.string.assistant_send)
                    Box(Modifier.size(44.dp).clip(CircleShape).background(if (canSend) NinoColors.Accent else NinoColors.Surface2)
                        .semantics { contentDescription = sendLabel }
                        .clickable(enabled = canSend) { send(input) }, contentAlignment = Alignment.Center) {
                        Icon(Icons.AutoMirrored.Filled.Send, null, Modifier.size(20.dp), tint = if (canSend) Color.White else NinoColors.InkSecondary)
                    }
                }
            }
        }
    }
}

@Composable
private fun Robot(size: androidx.compose.ui.unit.Dp, float: Boolean, blink: Boolean) {
    val animations = LocalAnimationsEnabled.current
    val lift = if (animations && float) {
        val t = rememberInfiniteTransition(label = "bot")
        val v by t.animateFloat(0f, 1f, infiniteRepeatable(tween(800, easing = FastOutSlowInEasing), RepeatMode.Reverse), label = "lift")
        v
    } else 0f
    var closed by remember { mutableStateOf(false) }
    if (animations && blink) {
        LaunchedEffect(Unit) { while (true) { delay(4_500); closed = true; delay(150); closed = false } }
    }
    Image(painterResource(if (closed) R.drawable.nino_bot_blink else R.drawable.nino_bot), null,
        Modifier.size(size).offset(y = (-3).dp * lift))
}

@Composable
private fun NinoRowFrame(content: @Composable () -> Unit) {
    Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Robot(28.dp, float = false, blink = false)
        Box(Modifier.widthIn(max = 300.dp).clip(NinoBubble).background(Color.White).border(1.dp, NinoColors.BorderStrong, NinoBubble)
            .padding(horizontal = 14.dp, vertical = 10.dp)) { content() }
    }
}

@Composable
private fun NinoMessage(text: String, reportSent: Boolean) {
    val blocks = remember(text) { ReplyParser.parse(text) }
    NinoRowFrame {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            blocks.forEachIndexed { i, b ->
                val prev = blocks.getOrNull(i - 1)
                val tight = prev != null && prev !is ReplyBlock.Paragraph && b !is ReplyBlock.Paragraph
                Box(Modifier.offset(y = if (tight) (-2).dp else 0.dp)) {
                    when (b) {
                        is ReplyBlock.Paragraph -> LinkText(b.text)
                        is ReplyBlock.Bullet -> Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Box(Modifier.padding(top = 7.dp).size(6.dp).clip(CircleShape).background(NinoColors.Accent))
                            LinkText(b.text, Modifier.weight(1f))
                        }
                        is ReplyBlock.Step -> Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Box(Modifier.heightIn(min = 21.dp).widthIn(min = 21.dp).clip(RoundedCornerShape(50)).background(NinoColors.Accent)
                                .padding(horizontal = if (b.number >= 10) 4.dp else 0.dp), contentAlignment = Alignment.Center) {
                                Text(b.number.toString(), fontSize = 12.sp, fontWeight = FontWeight.Bold, color = Color.White)
                            }
                            LinkText(b.text, Modifier.weight(1f))
                        }
                    }
                }
            }
            if (reportSent) {
                Box(Modifier.clip(RoundedCornerShape(50)).background(NinoColors.Success.copy(alpha = 0.1f)).padding(horizontal = 10.dp, vertical = 4.dp)) {
                    Text(stringResource(R.string.assistant_report_sent), fontSize = 13.sp, color = NinoColors.Success)
                }
            }
        }
    }
}

@Suppress("DEPRECATION")
@Composable
private fun LinkText(text: String, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val ranges = remember(text) { ReplyParser.links(text) }
    val annotated: AnnotatedString = remember(text) {
        buildAnnotatedString {
            append(text)
            ranges.forEach { r ->
                addStyle(SpanStyle(color = NinoColors.Accent, textDecoration = TextDecoration.Underline), r.first, r.last + 1)
                addStringAnnotation("url", text.substring(r.first, r.last + 1), r.first, r.last + 1)
            }
        }
    }
    ClickableText(annotated, modifier, style = NinoType.Body) { off ->
        annotated.getStringAnnotations("url", off, off).firstOrNull()?.let { Screens.openUrl(context, it.item) }
    }
}

@Composable
private fun UserMessage(item: ChatItem.User) {
    val rtl = LocalLayoutDirection.current == LayoutDirection.Rtl
    Column(Modifier.fillMaxWidth(), horizontalAlignment = if (rtl) Alignment.Start else Alignment.End,
        verticalArrangement = Arrangement.spacedBy(4.dp)) {
        if (item.images.isNotEmpty()) {
            val label = stringResource(R.string.assistant_screenshot)
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                item.images.forEach { img ->
                    val bmp = remember(img) { ImageShrink.decodePreview(img) }
                    if (bmp != null) Image(bmp.asImageBitmap(), label,
                        Modifier.size(84.dp).clip(RoundedCornerShape(14.dp)), contentScale = androidx.compose.ui.layout.ContentScale.Crop)
                }
            }
        }
        if (item.text.isNotEmpty()) {
            Box(Modifier.widthIn(max = 300.dp).clip(UserBubble).background(NinoColors.Accent).padding(horizontal = 14.dp, vertical = 10.dp)) {
                Text(item.text, style = NinoType.Body, color = Color.White)
            }
        }
        when (item.status) {
            ChatItem.Status.FAILED_RETRY -> Row(Modifier.clickable { AssistantChat.retry(item.id) }, verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(stringResource(R.string.assistant_not_sent), fontSize = 13.sp, color = NinoColors.Danger)
                Icon(Icons.Filled.Refresh, null, Modifier.size(16.dp), tint = NinoColors.Accent)
                Text(stringResource(R.string.assistant_retry), fontSize = 13.sp, color = NinoColors.Accent)
            }
            ChatItem.Status.FAILED_FINAL -> Text(stringResource(R.string.assistant_not_sent), fontSize = 13.sp, color = NinoColors.InkSecondary)
            else -> {}
        }
    }
}

@Composable
private fun WarningMessage(kind: AssistantWarning, onReport: () -> Unit) {
    NinoRowFrame {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(stringResource(when (kind) {
                AssistantWarning.DISABLED -> R.string.assistant_disabled
                AssistantWarning.RATE_LIMITED -> R.string.assistant_rate_limited
                AssistantWarning.BUSY -> R.string.assistant_busy
                AssistantWarning.NETWORK -> R.string.assistant_network
                AssistantWarning.TOO_LARGE -> R.string.assistant_too_large
                AssistantWarning.INVALID -> R.string.assistant_invalid
            }), style = NinoType.Body)
            if (kind == AssistantWarning.DISABLED) {
                Box(Modifier.clip(RoundedCornerShape(50)).background(NinoColors.Accent).clickable(onClick = onReport)
                    .padding(horizontal = 14.dp, vertical = 8.dp)) {
                    Text(stringResource(R.string.report_title), fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
                }
            }
        }
    }
}

@Composable
private fun TypingBubble() {
    val animations = LocalAnimationsEnabled.current
    val label = stringResource(R.string.assistant_typing)
    val phase = if (animations) {
        val t = rememberInfiniteTransition(label = "typing")
        val v by t.animateFloat(0f, 3f, infiniteRepeatable(tween(1200)), label = "p")
        v
    } else -1f
    Row(Modifier.semantics { contentDescription = label }, verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Robot(28.dp, float = true, blink = false)
        Row(Modifier.clip(NinoBubble).background(Color.White).border(1.dp, NinoColors.BorderStrong, NinoBubble)
            .padding(horizontal = 14.dp, vertical = 14.dp), horizontalArrangement = Arrangement.spacedBy(5.dp)) {
            for (i in 0 until 3) {
                val up = phase.toInt() == i
                Box(Modifier.offset(y = if (up) (-4).dp else 0.dp).size(7.dp).clip(CircleShape)
                    .background(if (up) NinoColors.Ink else NinoColors.InkSecondary.copy(alpha = 0.5f)))
            }
        }
    }
}
