// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AppKit
import Foundation
import NinoCore
import NinoDebugKit
import SwiftUI

/// Hata ayıklama kaydının uygulamaya bağlandığı yer (yalnız admin modu / Debug yapısı). Motorun içine dokunmaz:
/// kareler `NinoAppSupport.tap`'ten, TV mesajları hub'a eklenen dinleyici çıkıştan, günlük satırları
/// `RotatingLog.mirror`'dan, durumlar AppState'ten (saniyede bir bakılır), pencere ana iş parçacığında küçük boyda,
/// TV ekranı adb ile gelir.
@MainActor
public final class DebugRecording {
    public let recorder: DebugRecorder
    private weak var engine: LiveEngine?
    let tap: DebugHubTap
    private let shooter: DebugTVShooter
    private var timer: Timer?
    private var lastState: [String: String] = [:]
    private var windowSource: WindowSource?
    /// Ana pencerenin içeriği (uygulama açılışında bağlanır). Gerçek pencere yokken (kapatıldı ya da kapalıyken çıkılıp
    /// SwiftUI açılışta geri getirmedi) kayıt bunu ekran dışında çizer; yoksa pencere kareleri hiç oluşmuyordu.
    public var offscreenContent: (@MainActor () -> AnyView)?
    private var terminateObserver: NSObjectProtocol?

    /// Admin modu kapalıysa hiçbir şey kurulmaz (klasör de açılmaz).
    public static func makeIfEnabled(engine: LiveEngine, adminMode: Bool) -> DebugRecording? {
        guard adminMode else { return nil }
        return DebugRecording(engine: engine)
    }

    init(engine: LiveEngine, limit: Int64 = DebugRing.defaultLimit) {
        // `~/Library/Logs/Nino` (yayın) ya da `~/Library/Logs/Nino Dev` (deneme yapısı): DataFolder.logs.
        self.engine = engine
        let layout = DebugRecordLayout(logsFolder: engine.env.folder.logs)
        let ref = WeakEngineRef(engine)
        let tap = DebugHubTap()
        self.tap = tap
        recorder = DebugRecorder(layout: layout, limit: limit) {
            let snapshot = await MainActor.run { () -> (SubtitleSession?, LiveLine?) in
                (ref.engine?.session, ref.engine?.state.lastLine)
            }
            let area = await snapshot.0?.reader.readingArea
            let box = await snapshot.0?.reader.currentSubtitle?.box
            return DebugAnnotation(readingArea: area, subtitleBox: box, tvBoxes: tap.boxes,
                                   read: snapshot.1?.source ?? "", translation: snapshot.1?.translated ?? "")
        }
        shooter = DebugTVShooter(keyFile: engine.env.folder.adbKeyFile)
        let rec = recorder
        tap.recorder = rec
        let links = engine.links
        tap.tvCount = { links.connectedCount }
        engine.subtitleLog.mirror = { date, m in rec.logLine(m, kind: "altyazi", at: date) }
        engine.remotePlayLog.mirror = { date, m in rec.logLine(m, kind: "remoteplay", at: date) }
        Task { await links.hub.add(tap, key: "debug-kayit") }
        recorder.start()
        rec.logLine("hata ayıklama kaydı başladı (\(engine.env.identity.flavor.rawValue), sınır \(limit / 1_048_576) MB)",
                    kind: "durum", at: Date())
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
        terminateObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                                                   object: nil, queue: .main) { _ in rec.stop() }
    }

    /// Saniyede bir: durum değişiklikleri, pencere görüntüsü, TV ekran görüntüsü zamanı.
    func tick() {
        guard let engine else { return }
        let s = engine.state
        let now = Date()
        var current: [String: String] = [
            "PS5": "\(s.source)",
            "çeviri": "\(s.translation)",
            "TV sayısı": "\(s.connectedDisplays)",
            "oyun": s.game?.name ?? "yok",
        ]
        if let tv = s.pairedTV { current["eşli TV"] = "\(tv.brand.rawValue) \(tv.host)" }
        for key in current.keys.sorted() where lastState[key] != current[key] {
            recorder.logLine("durum: \(key) \(current[key] ?? "")", kind: "durum", at: now)
        }
        lastState = current

        if recorder.wantsWindowFrame() {
            var image: CGImage?
            var source = WindowSource.none
            let cpu = DebugMeasure.cpu {
                if let real = Self.windowImage() {
                    image = real
                    source = .window
                } else if let content = offscreenContent, let drawn = Self.offscreenImage(content()) {
                    image = drawn
                    source = .offscreen
                }
            }
            if let image { recorder.offerWindow(image, captureCPU: cpu) } else { recorder.windowMissing() }
            if windowSource != source {
                windowSource = source
                recorder.logLine("pencere: \(source.text) \(Self.windowList())", kind: "durum", at: now)
            }
        }

        let isAndroid = s.pairedTV?.brand == .androidTV
        if let host = s.pairedTV?.host,
           shooter.isDue(now: now.timeIntervalSince1970, isAndroidTV: isAndroid, translating: s.translation != .off,
                         scale: recorder.scale) {
            let rec = recorder
            let shooter = self.shooter
            Task.detached(priority: .background) {
                if let png = await shooter.shoot(host: host) { rec.tvShot(png, at: Date()) }
            }
        }
    }

    /// Ana penceremizin görüntüsü (en çok 1280×800 nokta, 1×). Görünümümüz kendimize çizdirilir (`cacheDisplay`):
    /// ekran kaydı izni gerekmez; pencere başka pencerelerin arkasında, ekran kilitli ya da uykudayken de çalışır.
    /// (İlk sürümde "örtülü değil" koşulu vardı; oyun oynanırken pencere hep arkada kaldığı için hiç kare çıkmıyordu.)
    static func windowImage() -> CGImage? {
        guard let app = NSApp else { return nil }  // testlerde uygulama nesnesi yok
        let list = app.windows.map {
            WindowCandidate(visible: $0.isVisible, miniaturized: $0.isMiniaturized, panel: $0 is NSPanel,
                            hasContent: $0.contentView != nil, offscreen: $0.frame.minX < -10_000,
                            normalLevel: $0.level == .normal, main: $0 === app.mainWindow,
                            area: $0.frame.width * $0.frame.height)
        }
        guard let i = WindowCandidate.pick(list), let view = app.windows[i].contentView else { return nil }
        let bounds = view.bounds
        guard bounds.width >= 2, bounds.height >= 2 else { return nil }
        let k = min(1, 1280 / bounds.width, 800 / bounds.height)
        let w = Int(bounds.width * k), h = Int(bounds.height * k)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = bounds.size
        view.cacheDisplay(in: bounds, to: rep)
        return rep.cgImage
    }

    /// Ana pencerenin içeriği pencere olmadan (ekran görüntüsü kipinde, `ninoStaticRendering`), 1× çizilir.
    static func offscreenImage(_ content: AnyView,
                               size: CGSize = CGSize(width: NinoSize.windowWidth, height: NinoSize.windowHeight)) -> CGImage? {
        let renderer = ImageRenderer(content: content
            .frame(width: size.width, height: size.height)
            .environment(\.ninoStaticRendering, true))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(size)
        return renderer.cgImage
    }

    enum WindowSource {
        case window, offscreen, none
        var text: String {
            switch self {
            case .window: "gerçek pencere çiziliyor"
            case .offscreen: "ana pencere kapalı, içeriği ekran dışında çiziliyor"
            case .none: "kaydedilecek pencere yok"
            }
        }
    }

    /// Tanı satırı: uygulamanın bütün pencereleri (sınıf, kimlik, görünürlük, çerçeve, katman).
    static func windowList() -> String {
        guard let app = NSApp else { return "[]" }
        let items = app.windows.map { w in
            let f = w.frame
            return "\(type(of: w)) id=\(w.identifier?.rawValue ?? "-") görünür=\(w.isVisible) küçük=\(w.isMiniaturized) "
                + "çerçeve=\(Int(f.minX)),\(Int(f.minY)),\(Int(f.width))x\(Int(f.height)) katman=\(w.level.rawValue)"
        }
        return "[" + items.joined(separator: "; ") + "]"
    }

    private final class WeakEngineRef: @unchecked Sendable {
        weak var engine: LiveEngine?
        init(_ e: LiveEngine) { engine = e }
    }
}

/// Hub'a eklenen dinleyici çıkış: hub'ın TV'lere dağıttığı her mesajı (protokol JSON'u, sığdırılmış hâliyle) kayda yazar ve
/// TV'de o an görünen kutuları (altyazı, ekran öğeleri, ek alanlar) kare çizimi için tutar. "Altyazı yalnız
/// bilgisayarda" iken hub ona da altyazı göndermez. Görmediği: yeni bağlanan TV'ye o TV'nin kendi yolundan yeniden
/// gönderilenler (style, started, son altyazı; "TV bağlandı" satırından hemen sonra) ve 8787'deki eski biçime çeviri.
final class DebugHubTap: DisplayOutput, @unchecked Sendable {
    private let lock = NSLock()
    private var showBox: NinoBox?
    private var screenBoxes: [NinoBox] = []
    private var regionBoxes: [String: NinoBox] = [:]
    var recorder: DebugRecorder?
    var tvCount: @Sendable () -> Int = { 0 }
    /// Her mesajın JSON'u (admin bileşik karesi: gizli TV sayfası).
    var onMessage: (@Sendable (String) -> Void)? {
        get { lock.withLock { messageHandler } }
        set { lock.withLock { messageHandler = newValue } }
    }
    private var messageHandler: (@Sendable (String) -> Void)?

    private func emit(_ json: String) {
        recorder?.tvMessage(json, tvCount: tvCount())
        onMessage?(json)
    }

    var boxes: [NinoBox] {
        lock.withLock { (showBox.map { [$0] } ?? []) + screenBoxes + regionBoxes.keys.sorted().compactMap { regionBoxes[$0] } }
    }

    func show(_ payload: ShowPayload) async throws {
        lock.withLock { showBox = payload.box }
        emit(NinoMessage.show(payload).jsonString)
    }

    func clear(id: Int?) async throws {
        lock.withLock { showBox = nil }
        emit(NinoMessage.clear(id: id).jsonString)
    }

    func send(_ event: NinoEvent) async throws {
        lock.withLock {
            switch event {
            case let .screen(p): screenBoxes = p.items.map(\.box)
            case .screenClear: screenBoxes = []
            case let .region(r): regionBoxes[r.id] = r.text.isEmpty ? nil : r.box
            case .regionClear: regionBoxes = [:]
            case .stopped:
                showBox = nil
                screenBoxes = []
                regionBoxes = [:]
            default: break
            }
        }
        emit(event.jsonString)
    }
}

/// Android TV ekran görüntüsü (adb, 5555). Yalnız saklı ve TV'nin zaten onayladığı anahtarla: anahtar yoksa ya da TV
/// tanımıyorsa TV'de onay kutusu ÇIKMAZ, bu oturumda bir daha denenmez. Erişilemezse 5 dk bekler. Aynı anda tek iş.
final class DebugTVShooter: @unchecked Sendable {
    let keyFile: URL
    let connector: ADBConnecting
    private let lock = NSLock()
    private var last: TimeInterval?
    private var blockedUntil: TimeInterval?
    private var disabled = false
    private var busy = false

    init(keyFile: URL, connector: ADBConnecting = NWADBConnector()) {
        self.keyFile = keyFile
        self.connector = connector
    }

    /// Zamanı geldiyse işi üstlenir (`true` dönerse `shoot` çağrılmalı).
    func isDue(now: TimeInterval, isAndroidTV: Bool, translating: Bool, scale: Double) -> Bool {
        lock.withLock {
            guard !busy, DebugRecordingRules.shouldShootTV(now: now, last: last, blockedUntil: blockedUntil, disabled: disabled,
                                                          isAndroidTV: isAndroidTV, translating: translating, scale: scale)
            else { return false }
            busy = true
            last = now
            return true
        }
    }

    func shoot(host: String) async -> Data? {
        defer { lock.withLock { busy = false } }
        guard let keyData = FileManager.default.contents(atPath: keyFile.path), let key = try? ADBKey(fileData: keyData) else {
            lock.withLock { disabled = true }
            return nil
        }
        do {
            let stream = try await connector.connect(host: host, port: AndroidTVInstaller.port, timeout: 3)
            defer { stream.close() }
            var timing = ADBConnection.Timing()
            timing.frame = 10
            let adb = ADBConnection(stream: stream, timing: timing)
            try await adb.handshake(key: key, offerKey: false)
            let png = try await adb.run("exec:screencap -p", timeout: 20)
            guard DebugImageIO.isPNG(png) else { throw ADBError.protocolError("screencap") }
            return png
        } catch ADBError.notApproved {
            lock.withLock { disabled = true }
        } catch ADBError.tlsRequired {
            lock.withLock { disabled = true }
        } catch {
            lock.withLock { blockedUntil = Date().timeIntervalSince1970 + DebugRecordingRules.tvShotBackoff }
        }
        return nil
    }
}

/// Kaydedilecek pencerenin seçimi (saf kural): görünür (sıraya alınmış) ya da küçültülmüş normal pencereler; panel,
/// gizli TV sayfası (ekran dışı) ve içeriksiz pencere hariç. Ana pencere önce, yoksa en büyüğü.
struct WindowCandidate: Equatable {
    var visible: Bool
    var miniaturized: Bool
    var panel: Bool
    var hasContent: Bool
    var offscreen: Bool
    var normalLevel: Bool
    var main: Bool
    var area: CGFloat

    static func pick(_ list: [WindowCandidate]) -> Int? {
        let ok = list.indices.filter {
            let c = list[$0]
            return (c.visible || c.miniaturized) && !c.panel && c.hasContent && !c.offscreen && c.normalLevel
        }
        if let m = ok.first(where: { list[$0].main }) { return m }
        return ok.max { list[$0].area < list[$1].area }
    }
}
