// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import CRemotePlay
import Foundation
import NinoCore

/// PS5 ile Remote Play oturumu. Görüntüyü çözer ve okuma hattına kare verir.
public final class RemotePlaySession: FrameSource, @unchecked Sendable {
    public struct Options: Sendable {
        /// 1: 360p, 2: 540p, 3: 720p, 4: 1080p.
        public var resolution: Int32 = 3
        /// PS5'ten istenen akış hızı (30 ya da 60).
        public var fps: Int32 = 30
        /// Her kaçıncı karenin okuma hattına verileceği (30 kare/sn'de 4 → 7.5 kare/sn).
        /// `maxFrameRate` verilirse kullanılmaz.
        public var frameStride: Int = 4
        /// Okuma hattına saniyede en çok kaç kare verileceği (ör. 20). Süreye göre seçer;
        /// akış hızından bağımsızdır. `nil`: `frameStride` kullanılır.
        public var maxFrameRate: Double?

        public init(resolution: Int32 = 3, fps: Int32 = 30, frameStride: Int = 4, maxFrameRate: Double? = nil) {
            self.resolution = resolution
            self.fps = fps
            self.frameStride = max(1, frameStride)
            self.maxFrameRate = maxFrameRate.flatMap { $0 > 0 ? $0 : nil }
        }

        /// Saniyede ~20 kare (altyazı okuma için önerilen).
        public static let twentyPerSecond = Options(maxFrameRate: 20)
    }

    public enum Event: Equatable, Sendable {
        case connected
        /// PS5 giriş şifresi (4 hane) istiyor. `incorrect`: önceki şifre yanlıştı.
        /// Cevap: `sendLoginPIN(_:)`.
        case loginPINRequested(incorrect: Bool)
        case quit(reason: String)
        case log(String)
    }

    public let address: String
    public let console: RegisteredConsole
    public let options: Options

    private let log = RemotePlayLog()
    private var session: UnsafeMutablePointer<ChiakiSession>?
    private let decoder = H264Decoder()
    private let lock = NSLock()
    /// Kütüphaneye dışarıdan yapılan çağrılar (şifre) ile kapanışı sıralar.
    /// Geri çağrılar bu kilidi hiç almaz; böylece kütüphane kilidiyle ters sıra oluşmaz.
    private let apiLock = NSLock()
    private var frameContinuation: AsyncStream<Frame>.Continuation?
    private var eventContinuation: AsyncStream<Event>.Continuation?
    private var picker: FramePicker
    private var frameIndex = 0
    private var startDate = Date()
    private var retained: Unmanaged<RemotePlaySession>?
    private static let teardownQueue = DispatchQueue(label: "nino.remoteplay.teardown")

    public init(address: String, console: RegisteredConsole, options: Options = Options()) {
        self.address = address
        self.console = console
        self.options = options
        picker = FramePicker(options: options)
        RemotePlayLib.initialize()
    }

    deinit { stop() }

    /// Olaylar: bağlandı, şifre istendi, kapandı.
    public func events() -> AsyncStream<Event> {
        let (s, c) = AsyncStream<Event>.makeStream()
        lock.withLock { eventContinuation = c }
        return s
    }

    /// Kareler. İlk çağrıda oturum açılır.
    public func frames() -> AsyncStream<Frame> {
        let (stream, continuation) = AsyncStream<Frame>.makeStream(bufferingPolicy: .bufferingNewest(1))
        lock.withLock { frameContinuation = continuation }
        // Akış iptal edilince stop() iptal edenin iş parçacığında çalışmasın: oturum iş parçacığı
        // o sırada akışı bitirmeye çalışıyor olabilir ve join karşılıklı kilitlenirdi.
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            DispatchQueue.global().async { self.stop() }
        }
        do { try start() } catch {
            emit(.quit(reason: "\(error)"))
            continuation.finish()
        }
        return stream
    }

    public func start() throws {
        guard lock.withLock({ session == nil }) else { return }
        guard console.registKey.count == 16, console.rpKey.count == 16 else {
            throw RemotePlayError.badInput("kayıt bilgisi eksik")
        }
        var info = ChiakiConnectInfo()
        info.ps5 = console.isPS5
        let host = strdup(address)
        defer { free(host) }
        info.host = UnsafePointer(host)
        writeFixed(&info.regist_key, console.registKey)
        writeFixed(&info.morning, console.rpKey)
        chiaki_connect_video_profile_preset(&info.video_profile,
                                            ChiakiVideoResolutionPreset(rawValue: UInt32(options.resolution)),
                                            ChiakiVideoFPSPreset(rawValue: UInt32(options.fps)))
        info.video_profile.codec = CHIAKI_CODEC_H264
        info.video_profile_auto_downgrade = true
        info.enable_keyboard = false
        info.enable_dualsense = false
        info.audio_video_disabled = CHIAKI_AUDIO_DISABLED
        info.auto_regist = false
        info.holepunch_session = nil
        info.rudp_sock = nil
        info.packet_loss_max = 0.05
        info.enable_idr_on_fec_failure = true

        let s = UnsafeMutablePointer<ChiakiSession>.allocate(capacity: 1)
        var err = chiaki_session_init(s, &info, log.pointer)
        guard err == CHIAKI_ERR_SUCCESS else {
            s.deallocate()
            throw RemotePlayError.library(RemotePlayLib.message(err))
        }
        let me = Unmanaged.passRetained(self)
        retained = me
        let user = me.toOpaque()
        chiaki_session_set_event_cb(s, { event, user in
            guard let event, let user else { return }
            let me = Unmanaged<RemotePlaySession>.fromOpaque(user).takeUnretainedValue()
            CallbackThread.run { me.handle(event.pointee) }
        }, user)
        chiaki_session_set_video_sample_cb(s, { buf, size, _, _, user in
            guard let buf, let user else { return true }
            let me = Unmanaged<RemotePlaySession>.fromOpaque(user).takeUnretainedValue()
            CallbackThread.run { me.video(Data(bytes: buf, count: size)) }
            return true
        }, user)
        startDate = Date()
        // Oturum iş parçacığı başlamadan işaretçi görünür olsun (geri çağrılar ona bakar).
        lock.withLock { session = s }
        err = chiaki_session_start(s)
        guard err == CHIAKI_ERR_SUCCESS else {
            lock.withLock { session = nil }
            chiaki_session_fini(s)
            s.deallocate()
            retained?.release()
            retained = nil
            throw RemotePlayError.library(RemotePlayLib.message(err))
        }
    }

    /// Oturumu kapatır. Her iş parçacığından, kütüphane geri çağrılarının içinden de
    /// güvenle çağrılabilir; geri çağrı içinden çağrılırsa kapanış arka kuyrukta biter.
    public func stop() {
        let (s, frames, r) = lock.withLock { () -> (UnsafeMutablePointer<ChiakiSession>?, AsyncStream<Frame>.Continuation?, Unmanaged<RemotePlaySession>?) in
            let x = session
            session = nil
            let f = x == nil ? nil : frameContinuation
            if x != nil { frameContinuation = nil }
            let r = x == nil ? nil : retained
            if x != nil { retained = nil }
            return (x, f, r)
        }
        guard let s else { return }
        // Kilit dışında: bitiş işleyicisi yeniden stop() çağırır.
        frames?.finish()
        let teardown = { [apiLock] in
            apiLock.withLock {
                chiaki_session_stop(s)
                chiaki_session_join(s)
                chiaki_session_fini(s)
                s.deallocate()
            }
            r?.release()
        }
        if CallbackThread.isCurrent {
            // Oturum iş parçacığı kendini bekleyemez.
            Self.teardownQueue.async(execute: teardown)
        } else {
            teardown()
        }
    }

    /// PS5'in istediği 4 haneli giriş şifresini gönderir (`Event.loginPINRequested` sonrası).
    public func sendLoginPIN(_ pin: String) throws {
        let digits = pin.filter { !$0.isWhitespace }
        guard digits.count == 4, digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber) else {
            throw RemotePlayError.badInput("Giriş şifresi 4 haneli olmalı")
        }
        let bytes = Array(digits.utf8)
        let send = { [self] () -> ChiakiErrorCode? in
            // apiLock tutulurken gönderilir: stop() oturumu bu sırada serbest bırakamaz.
            // `lock` tutulmaz: kütüphane olay gönderirken kendi kilidini tutar ve `lock`u ister.
            apiLock.withLock {
                guard let s = lock.withLock({ session }) else { return nil }
                return bytes.withUnsafeBufferPointer { chiaki_session_set_login_pin(s, $0.baseAddress, $0.count) }
            }
        }
        if CallbackThread.isCurrent {
            // Olay geri çağrısında oturum kilidi kütüphanede tutuluyor; ayrı iş parçacığında gönder.
            guard lock.withLock({ session != nil }) else { throw RemotePlayError.notConnected }
            DispatchQueue.global().async { _ = send() }
            return
        }
        guard let err = send() else { throw RemotePlayError.notConnected }
        guard err == CHIAKI_ERR_SUCCESS else { throw RemotePlayError.library(RemotePlayLib.message(err)) }
    }

    /// Son günlük satırları (hata ayıklama için).
    public var recentLog: [String] { log.recent }

    // MARK: Geri çağrılar (kütüphane iş parçacıklarından)

    private func emit(_ e: Event) {
        let c = lock.withLock { eventContinuation }
        c?.yield(e)
    }

    func handle(_ e: ChiakiEvent) {
        switch e.type {
        case CHIAKI_EVENT_CONNECTED:
            emit(.connected)
        case CHIAKI_EVENT_LOGIN_PIN_REQUEST:
            emit(.loginPINRequested(incorrect: e.login_pin_request.pin_incorrect))
        case CHIAKI_EVENT_QUIT:
            let reason = String(cString: chiaki_quit_reason_string(e.quit.reason))
            emit(.quit(reason: reason))
            let (frames, events) = lock.withLock { () -> (AsyncStream<Frame>.Continuation?, AsyncStream<Event>.Continuation?) in
                defer { frameContinuation = nil; eventContinuation = nil }
                return (frameContinuation, eventContinuation)
            }
            // Kilit dışında bitir: kare akışının bitiş işleyicisi stop() çağırır.
            frames?.finish()
            events?.finish()
        default:
            break
        }
    }

    private func video(_ sample: Data) {
        let want = picker.shouldDeliver(at: Date().timeIntervalSince(startDate))
        do {
            if let image = try decoder.decode(sample, wantImage: want) {
                frameIndex += 1
                let frame = Frame(image: image, index: frameIndex, time: Date().timeIntervalSince(startDate))
                let c = lock.withLock { frameContinuation }
                c?.yield(frame)
            }
        } catch {
            // Bu geri çağrı bitmeden kapanış (join) tamamlanamaz; işaretçi geçerli kalır.
            if let s = lock.withLock({ session }) { _ = chiaki_session_request_idr(s) }
        }
    }

    /// Test için: kare akışını bağlar, oturum açmaz.
    func attachFrameStreamForTesting() -> AsyncStream<Frame> {
        let (stream, continuation) = AsyncStream<Frame>.makeStream(bufferingPolicy: .bufferingNewest(1))
        lock.withLock { frameContinuation = continuation }
        // Akış iptal edilince stop() iptal edenin iş parçacığında çalışmasın: oturum iş parçacığı
        // o sırada akışı bitirmeye çalışıyor olabilir ve join karşılıklı kilitlenirdi.
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            DispatchQueue.global().async { self.stop() }
        }
        return stream
    }

    /// Uykudaki konsolu uyandırır (kayıt anahtarıyla).
    public static func wake(address: String, console: RegisteredConsole) throws {
        RemotePlayLib.initialize()
        let log = RemotePlayLog()
        let keyString = String(decoding: console.registKey.prefix { $0 != 0 }, as: UTF8.self)
        guard let credential = UInt64(keyString, radix: 16) else { throw RemotePlayError.badInput("kayıt anahtarı") }
        let err = chiaki_discovery_wakeup(log.pointer, nil, address, credential, console.isPS5)
        guard err == CHIAKI_ERR_SUCCESS else { throw RemotePlayError.library(RemotePlayLib.message(err)) }
    }
}

/// Hangi çözülen karenin okuma hattına verileceğini seçer.
/// Süre kipinde ilerleyen bir son tarih kullanır: 30 kare/sn akıştan 20 kare/sn seçilebilir
/// (yalnız "son kareden 50 ms geçti mi" bakılsa 15 kare/sn kalırdı).
struct FramePicker {
    private let stride: Int
    private let interval: TimeInterval?
    private var count = 0
    private var next: TimeInterval?
    /// Kare zamanlarındaki küçük oynamaya pay.
    static let tolerance: TimeInterval = 0.002

    init(options: RemotePlaySession.Options) {
        stride = max(1, options.frameStride)
        interval = options.maxFrameRate.map { 1 / $0 }
    }

    mutating func shouldDeliver(at t: TimeInterval) -> Bool {
        guard let interval else {
            count += 1
            return count % stride == 0
        }
        if let n = next, t + Self.tolerance < n { return false }
        var upcoming = (next ?? t) + interval
        if upcoming <= t { upcoming = t + interval } // uzun boşluktan sonra yeniden başla
        next = upcoming
        return true
    }
}
