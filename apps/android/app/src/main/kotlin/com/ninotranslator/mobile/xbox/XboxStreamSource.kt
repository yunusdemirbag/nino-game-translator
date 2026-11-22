// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.xbox

import android.content.Context
import android.media.AudioAttributes
import android.os.SystemClock
import android.util.Log
import com.ninotranslator.core.http.UrlConnectionTransport
import com.ninotranslator.mobile.data.Nino
import com.ninotranslator.mobile.data.XboxConsole
import com.ninotranslator.mobile.service.ChromaPlanes
import com.ninotranslator.mobile.service.FrameSource
import com.ninotranslator.mobile.service.ServiceStrings
import com.ninotranslator.mobile.service.SourceKind
import com.ninotranslator.mobile.service.SourceState
import com.ninotranslator.mobile.service.TextRef
import com.ninotranslator.mobile.service.VideoFrame
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.webrtc.DataChannel
import org.webrtc.EncodedImage
import org.webrtc.HardwareVideoDecoderFactory
import org.webrtc.IceCandidate
import org.webrtc.MediaConstraints
import org.webrtc.MediaStream
import org.webrtc.MediaStreamTrack
import org.webrtc.PeerConnection
import org.webrtc.PeerConnectionFactory
import org.webrtc.RtpReceiver
import org.webrtc.RtpTransceiver
import org.webrtc.SdpObserver
import org.webrtc.SessionDescription
import org.webrtc.SoftwareVideoDecoderFactory
import org.webrtc.VideoCodecInfo
import org.webrtc.VideoCodecStatus
import org.webrtc.VideoDecoder
import org.webrtc.VideoDecoderFactory
import org.webrtc.VideoSink
import org.webrtc.VideoTrack
import org.webrtc.audio.JavaAudioDeviceModule
import java.nio.ByteBuffer
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

/**
 * Xbox ev yayını kaynağı (servis.md 10.4–10.5): görüntü WebRTC ile Wi-Fi'dan gelir, donanım çözücüyle çözülür,
 * kareler en çok 66 ms'de bir parlaklık + renk düzlemi olarak okuma hattına verilir. Mikrofon açılmaz, girdi
 * gönderilmez. Kurulum ve ağ işi [worker]'da, kare onayları [ticker]'da yürür; [stop] beklemez.
 */
class XboxStreamSource(
    context: Context,
    private val console: XboxConsole,
    private val chain: XboxTokenChain,
) : FrameSource {
    override val kind = SourceKind.XBOX
    private val app = context.applicationContext
    private val texts = ServiceStrings(app)
    private val _state = MutableStateFlow<SourceState>(SourceState.Idle)
    override val state: StateFlow<SourceState> = _state
    override val runningGame: StateFlow<String?> = MutableStateFlow(null)

    private val worker = Executors.newSingleThreadScheduledExecutor { Thread(it, "nino-xbox").apply { isDaemon = true } }
    private val ticker = Executors.newSingleThreadScheduledExecutor { Thread(it, "nino-xbox-ack").apply { isDaemon = true } }
    private val policy = XboxRetryPolicy()
    /** Yayın kalitesi (Ayarlar › Yayın kalitesi); oturum başında bir kez okunur. */
    private val profile = XboxStreamProfile.of(Nino.settings.xboxQuality)
    private val totalFrames = AtomicLong()
    @Volatile private var sink: (VideoFrame) -> Unit = {}
    @Volatile private var stopped = false

    // Yalnız worker'da değişir.
    private var factory: PeerConnectionFactory? = null
    private var audio: JavaAudioDeviceModule? = null
    private var conn: Connection? = null
    @Volatile private var generation = 0

    override fun start(sink: (VideoFrame) -> Unit) {
        this.sink = sink
        _state.value = SourceState.Connecting
        post { attempt() }
    }

    override fun stop() {
        stopped = true
        sink = {}
        _state.value = SourceState.Idle
        post {
            end(conn, "kullanıcı durdurdu")
            runCatching { factory?.dispose() }
            runCatching { audio?.release() }
            factory = null; audio = null
            worker.shutdown()
        }
        ticker.shutdownNow()
    }

    override fun frameCount(): Long = totalFrames.get()

    private fun post(task: () -> Unit) {
        try { worker.execute(task) } catch (_: RejectedExecutionException) { }
    }

    // ---- bağlantı ----

    /** Tek bağlantının durumu; geç gelen geri çağrılar [gen] ile ayıklanır. */
    private inner class Connection(val gen: Int) {
        val startedAt = SystemClock.elapsedRealtime()
        var peer: PeerConnection? = null
        val channels = ConcurrentHashMap<String, DataChannel>()
        var sessionId: String? = null
        var api: XboxStreamApi? = null
        var keepalive: ScheduledFuture<*>? = null
        var firstFrameWatch: ScheduledFuture<*>? = null
        var ackTimer: ScheduledFuture<*>? = null
        val acks = FrameAckQueue()
        @Volatile var acking = false
        @Volatile var firstFrameAt = 0L
        @Volatile var lastHandedMs = 0L
        @Volatile var decoderTimes = false
        val frames = AtomicLong()
        val acksSent = AtomicLong()
        var sequence = 1L
        val arrivals = ConcurrentHashMap<Long, Long>()
        @Volatile var ended = false

        fun clockMs() = SystemClock.elapsedRealtime() - startedAt
        fun live() = !ended && !stopped && gen == generation
    }

    private fun attempt() {
        if (stopped) return
        val c = Connection(++generation)
        conn = c
        _state.value = SourceState.Connecting
        try {
            val f = factory()
            val handshake = XboxHandshake(XboxStreamApi(UrlConnectionTransport, profile) { chain.streamHost() }.also { c.api = it },
                chain::transferToken, sleep = { ms -> Thread.sleep(ms); if (!c.live()) throw InterruptedException() })
            val peer = PeerAdapter(c, f)
            val id = handshake.open(console.id)
            c.sessionId = id
            if (!c.live()) throw InterruptedException()
            handshake.awaitProvisioned(id)
            handshake.negotiate(id, peer)
            // İlk kare 20 sn içinde gelmezse konsola ulaşılamıyor sayılır.
            c.firstFrameWatch = worker.schedule({
                if (c.live() && c.firstFrameAt == 0L) fail(c, XboxStreamException(XboxProblem.UNREACHABLE, detail = "ilk kare gelmedi"))
            }, FIRST_FRAME_MS, TimeUnit.MILLISECONDS)
        } catch (_: InterruptedException) {
            if (!stopped && c.live()) fail(c, XboxStreamException(XboxProblem.NETWORK, detail = "kesildi"))
        } catch (e: Throwable) {
            Log.w(TAG, "bağlantı kurulamadı", e)
            fail(c, e)
        }
    }

    /** Bağlantıyı bitirir ve ilkeye göre yeniden dener ya da durur. Worker'da çağrılır. */
    private fun fail(c: Connection, e: Throwable) {
        if (c.ended || stopped) return
        val (problem, rejected) = if (e is UnsatisfiedLinkError || e is NoClassDefFoundError) XboxProblem.WEBRTC to false else XboxTexts.problemOf(e)
        end(c, "${problem.name}: ${e.message}")
        when (val next = policy.onEnded(problem, rejected, SystemClock.elapsedRealtime())) {
            is XboxNext.Retry -> {
                _state.value = SourceState.Reconnecting(XboxTexts.retryKey(next.problem))
                try { worker.schedule({ attempt() }, next.delayMs, TimeUnit.MILLISECONDS) } catch (_: RejectedExecutionException) { }
            }
            is XboxNext.GiveUp -> _state.value = XboxTexts.giveUp(next.problem) { texts.get(TextRef(it)) }
            is XboxNext.Stop -> _state.value = SourceState.Failed(XboxTexts.retryKey(next.problem))
        }
    }

    /** Kaynakları kapatır, uzak oturumu siler, özet yazar. */
    private fun end(c: Connection?, reason: String) {
        if (c == null || c.ended) return
        c.ended = true
        c.acking = false
        c.keepalive?.cancel(false); c.firstFrameWatch?.cancel(false); c.ackTimer?.cancel(false)
        c.channels.values.forEach { ch -> runCatching { ch.unregisterObserver(); ch.close(); ch.dispose() } }
        c.channels.clear()
        c.peer?.let { p -> runCatching { p.close(); p.dispose() } }
        c.peer = null
        val id = c.sessionId
        val api = c.api
        if (id != null && api != null) runCatching { api.delete(id) }.onFailure { Log.w(TAG, "oturum silinemedi", it) }
        val since = if (c.firstFrameAt > 0) (SystemClock.elapsedRealtime() - c.firstFrameAt) / 1000 else -1
        // Özet: neden, kare sayısı, gönderilen onay, ilk kareden sonra kaç sn.
        Log.i(TAG, "bağlantı bitti: $reason; kare=${c.frames.get()} onay=${c.acksSent.get()} ilkKaredenSonra=${since}sn")
        if (conn === c) conn = null
    }

    // ---- WebRTC ----

    private fun factory(): PeerConnectionFactory {
        factory?.let { return it }
        if (!initialized) {
            PeerConnectionFactory.initialize(PeerConnectionFactory.InitializationOptions.builder(app).createInitializationOptions())
            initialized = true
        }
        val adm = JavaAudioDeviceModule.builder(app)
            .setUseStereoOutput(true)
            .setUseStereoInput(false)
            .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_GAME)
                .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE).build())
            .createAudioDeviceModule()
        // Mikrofon hiç açılmaz: yerel ses parçası yok, kayıt izni yok; yine de susturulur.
        adm.setMicrophoneMute(true)
        audio = adm
        return PeerConnectionFactory.builder()
            .setAudioDeviceModule(adm)
            .setVideoDecoderFactory(TimedDecoderFactory())
            .createPeerConnectionFactory()
            .also { factory = it }
    }

    /** Donanım çözücüyü sarar: her karenin varış ve çözülme anını onay için kaydeder. Yoksa yazılım çözücü. */
    private inner class TimedDecoderFactory : VideoDecoderFactory {
        private val hardware = HardwareVideoDecoderFactory(null)
        private val software = SoftwareVideoDecoderFactory()

        override fun getSupportedCodecs(): Array<VideoCodecInfo> {
            val hw = hardware.supportedCodecs.toList()
            return (hw + software.supportedCodecs.filter { s -> hw.none { it.name.equals(s.name, true) } }).toTypedArray()
        }

        override fun createDecoder(info: VideoCodecInfo): VideoDecoder? =
            hardware.createDecoder(info)?.let { TimedDecoder(it) } ?: software.createDecoder(info)
    }

    private inner class TimedDecoder(private val inner: VideoDecoder) : VideoDecoder {
        override fun initDecode(settings: VideoDecoder.Settings, callback: VideoDecoder.Callback): VideoCodecStatus =
            inner.initDecode(settings) { frame, decodeMs, qp ->
                conn?.let { c ->
                    if (c.live() && c.acking) {
                        val capture = frame.timestampNs / 1_000_000
                        val arrival = c.arrivals.remove(capture) ?: c.clockMs()
                        c.acks.add(FrameTiming(XboxChannelMessages.rtpKey(capture), arrival, c.clockMs()))
                    }
                }
                callback.onDecodedFrame(frame, decodeMs, qp)
            }

        override fun decode(image: EncodedImage, info: VideoDecoder.DecodeInfo): VideoCodecStatus {
            conn?.let { c ->
                c.decoderTimes = true
                if (c.acking) {
                    if (c.arrivals.size > 256) c.arrivals.clear()
                    c.arrivals[image.captureTimeMs] = c.clockMs()
                }
            }
            return inner.decode(image, info)
        }

        override fun release(): VideoCodecStatus = inner.release()
        override fun getImplementationName(): String = inner.implementationName
    }

    /** [XboxHandshake]'in WebRTC tarafı; her adım en çok 10 sn beklenir. */
    private inner class PeerAdapter(private val c: Connection, f: PeerConnectionFactory) : XboxPeerSide {
        private val local = ArrayList<XboxIceCandidate>()
        private val gathered = CountDownLatch(1)
        private val pc: PeerConnection

        init {
            val config = PeerConnection.RTCConfiguration(STUN.map { PeerConnection.IceServer.builder(it).createIceServer() }).apply {
                sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN
            }
            pc = f.createPeerConnection(config, Observer(c, ::onCandidate) { gathered.countDown() })
                ?: throw XboxStreamException(XboxProblem.WEBRTC, detail = "bağlantı nesnesi kurulamadı")
            c.peer = pc
            // Önce sıralı veri kanalları, sonra ses (gönder-al, yerel parça yok) ve görüntü (yalnız al).
            for (spec in XboxChannelMessages.CHANNELS) {
                val ch = pc.createDataChannel(spec.label, DataChannel.Init().apply { ordered = true; protocol = spec.protocol }) ?: continue
                c.channels[spec.label] = ch
                ch.registerObserver(ChannelObserver(c, spec.label, ch))
            }
            pc.addTransceiver(MediaStreamTrack.MediaType.MEDIA_TYPE_AUDIO,
                RtpTransceiver.RtpTransceiverInit(RtpTransceiver.RtpTransceiverDirection.SEND_RECV))
            val video = pc.addTransceiver(MediaStreamTrack.MediaType.MEDIA_TYPE_VIDEO,
                RtpTransceiver.RtpTransceiverInit(RtpTransceiver.RtpTransceiverDirection.RECV_ONLY))
            runCatching {
                val codecs = f.getRtpReceiverCapabilities(MediaStreamTrack.MediaType.MEDIA_TYPE_VIDEO).codecs
                video.setCodecPreferences(codecs.sortedBy { if (it.name.equals("H264", true)) 0 else 1 })
            }
        }

        private fun onCandidate(ic: IceCandidate) {
            synchronized(local) { local += XboxIceCandidate("a=" + ic.sdp.removePrefix("a="), ic.sdpMid, ic.sdpMLineIndex) }
        }

        override fun makeOffer(): String = await<SessionDescription> { pc.createOffer(it, MediaConstraints()) }.description
        override fun applyLocal(sdp: String) { await<Unit> { pc.setLocalDescription(it, SessionDescription(SessionDescription.Type.OFFER, sdp)) } }
        override fun applyAnswer(sdp: String) { await<Unit> { pc.setRemoteDescription(it, SessionDescription(SessionDescription.Type.ANSWER, sdp)) } }

        override fun collectCandidates(maxWaitMs: Long): List<XboxIceCandidate> {
            gathered.await(maxWaitMs, TimeUnit.MILLISECONDS)
            return synchronized(local) { local.toList() }
        }

        override fun addRemote(candidate: XboxIceCandidate) {
            val line = candidate.candidate.removePrefix("a=").trim()
            if (!pc.addIceCandidate(IceCandidate(candidate.sdpMid ?: "0", candidate.sdpMLineIndex, line))) Log.w(TAG, "aday eklenemedi: $line")
        }
    }

    private inner class Observer(
        private val c: Connection,
        private val onCandidate: (IceCandidate) -> Unit,
        private val onGathered: () -> Unit,
    ) : PeerConnection.Observer {
        override fun onConnectionChange(newState: PeerConnection.PeerConnectionState) {
            Log.i(TAG, "bağlantı durumu: $newState")
            if (newState == PeerConnection.PeerConnectionState.FAILED || newState == PeerConnection.PeerConnectionState.CLOSED)
                post { if (c.live()) fail(c, XboxStreamException(XboxProblem.NETWORK, detail = newState.name)) }
        }
        override fun onIceGatheringChange(s: PeerConnection.IceGatheringState) { if (s == PeerConnection.IceGatheringState.COMPLETE) onGathered() }
        override fun onIceCandidate(candidate: IceCandidate) = onCandidate(candidate)
        override fun onTrack(transceiver: RtpTransceiver) {
            when (val track = transceiver.receiver.track()) {
                is VideoTrack -> track.addSink(FrameSink(c))
                null -> Unit
                else -> if (track.kind() == MediaStreamTrack.AUDIO_TRACK_KIND) {
                    // Ayar açıksa oyun sesi telefonda stereo çalar; kapalıysa susturulur.
                    val on = Nino.settings.xboxAudioOnDevice
                    track.setEnabled(on)
                    audio?.setSpeakerMute(!on)
                }
            }
        }
        override fun onSignalingChange(s: PeerConnection.SignalingState) {}
        override fun onIceConnectionChange(s: PeerConnection.IceConnectionState) {}
        override fun onIceConnectionReceivingChange(receiving: Boolean) {}
        override fun onIceCandidatesRemoved(candidates: Array<out IceCandidate>) {}
        override fun onAddStream(stream: MediaStream) {}
        override fun onRemoveStream(stream: MediaStream) {}
        override fun onDataChannel(channel: DataChannel) {}
        override fun onRenegotiationNeeded() {}
        override fun onAddTrack(receiver: RtpReceiver, streams: Array<out MediaStream>) {}
    }

    private inner class ChannelObserver(private val c: Connection, private val label: String, private val ch: DataChannel) : DataChannel.Observer {
        override fun onBufferedAmountChange(previous: Long) {}

        override fun onStateChange() {
            val s = ch.state()
            if (!c.live()) return
            if (s == DataChannel.State.OPEN) when (label) {
                XboxChannelMessages.MESSAGE -> sendText(c, XboxChannelMessages.MESSAGE, XboxChannelMessages.handshake())
                XboxChannelMessages.INPUT -> post {
                    if (c.live()) c.keepalive = worker.scheduleWithFixedDelay({
                        val id = c.sessionId
                        if (c.live() && id != null) runCatching { c.api?.keepalive(id) }.onFailure { Log.w(TAG, "keepalive", it) }
                    }, KEEPALIVE_MS, KEEPALIVE_MS, TimeUnit.MILLISECONDS)
                }
            }
            if (s == DataChannel.State.CLOSED && label == XboxChannelMessages.INPUT)
                post { if (c.live()) fail(c, XboxStreamException(XboxProblem.NETWORK, detail = "input kanalı kapandı")) }
        }

        override fun onMessage(buffer: DataChannel.Buffer) {
            val bytes = ByteArray(buffer.data.remaining()).also { buffer.data.get(it) }
            if (buffer.binary) {
                val type = XboxChannelMessages.reportType(bytes)
                if (type != XboxChannelMessages.REPORT_VIBRATION) Log.d(TAG, "$label: ${bytes.size} baytlık ikili veri geldi (tür $type)")
                return
            }
            val text = String(bytes, Charsets.UTF_8)
            Log.d(TAG, "$label: ${text.take(300)}")
            if (label == XboxChannelMessages.MESSAGE && XboxChannelMessages.isHandshakeAck(text) && c.live() && !c.acking) onHandshakeAck(c)
        }
    }

    private fun onHandshakeAck(c: Connection) {
        sendText(c, XboxChannelMessages.CONTROL, XboxChannelMessages.authorization())
        sendText(c, XboxChannelMessages.CONTROL, XboxChannelMessages.gamepadAdded(0))
        sendBinary(c, XboxChannelMessages.INPUT, XboxChannelMessages.clientInfo(c.clockMs().toDouble()))
        XboxChannelMessages.configuration(profile.width, profile.height).forEach { sendText(c, XboxChannelMessages.MESSAGE, it) }
        c.acks.clear()
        c.acking = true
        // 16 ms'de bir en çok 29 kare tek pakette.
        c.ackTimer = try {
            ticker.scheduleWithFixedDelay({
                if (!c.live()) return@scheduleWithFixedDelay
                val batch = c.acks.take()
                if (batch.isNotEmpty()) {
                    sendBinary(c, XboxChannelMessages.INPUT, XboxChannelMessages.frameAcks(c.sequence++, c.clockMs().toDouble(), batch))
                    c.acksSent.addAndGet(batch.size.toLong())
                }
            }, ACK_MS, ACK_MS, TimeUnit.MILLISECONDS)
        } catch (_: RejectedExecutionException) { null }
    }

    private fun sendText(c: Connection, label: String, text: String) {
        c.channels[label]?.send(DataChannel.Buffer(ByteBuffer.wrap(text.toByteArray(Charsets.UTF_8)), false))
    }

    private fun sendBinary(c: Connection, label: String, bytes: ByteArray) {
        c.channels[label]?.send(DataChannel.Buffer(ByteBuffer.wrap(bytes), true))
    }

    /** Görüntü karesi: ilk kare durumu "görüntü geliyor" yapar; hatta en çok 66 ms'de bir verilir. */
    private inner class FrameSink(private val c: Connection) : VideoSink {
        override fun onFrame(frame: org.webrtc.VideoFrame) {
            if (!c.live()) return
            c.frames.incrementAndGet()
            totalFrames.incrementAndGet()
            val nowMs = SystemClock.elapsedRealtime()
            if (c.firstFrameAt == 0L) {
                c.firstFrameAt = nowMs
                post { if (c.live()) { policy.onStreaming(SystemClock.elapsedRealtime()); _state.value = SourceState.Streaming } }
            }
            // Yazılım çözücüde çözücü anları yok: onay buradan.
            if (c.acking && !c.decoderTimes) {
                val capture = frame.timestampNs / 1_000_000
                c.acks.add(FrameTiming(XboxChannelMessages.rtpKey(capture), c.clockMs(), c.clockMs()))
            }
            if (nowMs - c.lastHandedMs < FRAME_INTERVAL_MS) return
            c.lastHandedMs = nowMs
            val i420 = runCatching { frame.buffer.toI420() }.getOrNull() ?: return
            try {
                sink(VideoFrame(i420.dataY, i420.width, i420.height, i420.strideY, nowMs,
                    ChromaPlanes(i420.dataU, i420.dataV, i420.strideU, 1)))
            } catch (e: Exception) {
                Log.w(TAG, "kare okunamadı", e)
            } finally {
                i420.release()
            }
        }
    }

    /** libwebrtc'nin geri çağrılı SDP işini en çok 10 sn bekleyen çağrıya çevirir. */
    private fun <T> await(start: (SdpObserver) -> Unit): T {
        val latch = CountDownLatch(1)
        var value: Any? = null
        var error: String? = null
        start(object : SdpObserver {
            override fun onCreateSuccess(d: SessionDescription?) { value = d; latch.countDown() }
            override fun onSetSuccess() { value = Unit; latch.countDown() }
            override fun onCreateFailure(e: String?) { error = e ?: "oluşturulamadı"; latch.countDown() }
            override fun onSetFailure(e: String?) { error = e ?: "konamadı"; latch.countDown() }
        })
        if (!latch.await(STEP_MS, TimeUnit.MILLISECONDS)) throw XboxStreamException(XboxProblem.TIMEOUT, detail = "WebRTC adımı yanıt vermedi")
        error?.let { throw XboxStreamException(XboxProblem.SERVICE, detail = it) }
        @Suppress("UNCHECKED_CAST")
        return value as T
    }

    companion object {
        private const val TAG = "NinoXbox"
        const val FRAME_INTERVAL_MS = 66L
        const val FIRST_FRAME_MS = 20_000L
        const val KEEPALIVE_MS = 30_000L
        const val ACK_MS = 16L
        const val STEP_MS = 10_000L
        val STUN = listOf("stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302")
        @Volatile private var initialized = false
    }
}
