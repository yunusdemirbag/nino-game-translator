// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.service

import com.ninotranslator.mobile.remoteplay.PairedPs5
import com.ninotranslator.mobile.remoteplay.RemotePlaySession
import com.ninotranslator.mobile.remoteplay.RemotePlayState
import com.ninotranslator.mobile.remoteplay.RemotePlayTarget
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach

/** PS5 Remote Play kaynağı: [RemotePlaySession]'ı okuma hattına bağlar. */
class RemotePlaySource(
    private val target: RemotePlayTarget,
    private val onHostChanged: (PairedPs5) -> Unit,
    private val scope: CoroutineScope,
) : FrameSource {
    override val kind = SourceKind.REMOTE_PLAY
    private val _state = MutableStateFlow<SourceState>(SourceState.Idle)
    override val state: StateFlow<SourceState> = _state
    private val _game = MutableStateFlow<String?>(null)
    override val runningGame: StateFlow<String?> = _game
    @Volatile private var sink: (VideoFrame) -> Unit = {}

    private val session = RemotePlaySession(
        onHostChanged = onHostChanged,
        frameListener = { f ->
            sink(VideoFrame(f.luma, f.width, f.height, f.stride, f.timestampMs, f.chroma?.let { ChromaPlanes.nv12(it, f.width) }))
        },
    )

    override fun start(sink: (VideoFrame) -> Unit) {
        this.sink = sink
        session.state.onEach { _state.value = map(it); if (it !is RemotePlayState.Streaming) _game.value = null }.launchIn(scope)
        session.runningApp.onEach { app ->
            if (_state.value == SourceState.Streaming) _game.value = app?.runningAppName?.takeIf { it.isNotBlank() }
        }.launchIn(scope)
        session.start(target)
    }

    override fun stop() {
        sink = {}
        session.release()
    }

    override fun frameCount(): Long = session.frameCount()

    private fun map(s: RemotePlayState): SourceState = when (s) {
        RemotePlayState.Idle -> SourceState.Idle
        RemotePlayState.Preparing -> SourceState.Preparing
        RemotePlayState.Connecting -> SourceState.Connecting
        RemotePlayState.Streaming -> SourceState.Streaming
        is RemotePlayState.Reconnecting -> SourceState.Reconnecting(s.reasonKey, s.detail)
        is RemotePlayState.Failed -> SourceState.Failed(s.reasonKey, s.detail)
    }
}

/** Debug yapısındaki deneme kaynağını sağlayan kayıt (debug kaynak kümesi doldurur; yayın yapısında boş). */
object DebugSources {
    interface Factory {
        /** Deneme kareleri klasöründe kare var mı (ya da örnek kaynak açık mı). */
        fun available(context: android.content.Context): Boolean
        fun create(context: android.content.Context, scope: CoroutineScope): FrameSource
    }

    @Volatile var factory: Factory? = null

    fun available(context: android.content.Context): Boolean =
        com.ninotranslator.mobile.BuildConfig.DEBUG && factory?.available(context) == true
}
