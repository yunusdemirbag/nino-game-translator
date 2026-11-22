// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import NinoCore

/// Çevrilen altyazının gittiği yer: telefon ekranı (model) ve varsa TV. TV'ye gönderilemezse telefon yine gösterir;
/// hata modele bildirilir.
final class LiveOutput: SubtitleOutput, @unchecked Sendable {
    enum Event: Sendable {
        case show(ShowPayload)
        case clear(id: Int?)
        case tvFailed(String)
    }

    private let lock = NSLock()
    private var tv: SubtitleOutput?
    private let sink: @Sendable (Event) -> Void

    init(tv: SubtitleOutput? = nil, sink: @escaping @Sendable (Event) -> Void) {
        self.tv = tv
        self.sink = sink
    }

    func setTV(_ output: SubtitleOutput?) { lock.withLock { tv = output } }
    var hasTV: Bool { lock.withLock { tv != nil } }

    func show(_ payload: ShowPayload) async throws {
        sink(.show(payload))
        guard let tv = lock.withLock({ tv }) else { return }
        do { try await tv.show(payload) } catch { sink(.tvFailed("\(error)")) }
    }

    func clear(id: Int?) async throws {
        sink(.clear(id: id))
        guard let tv = lock.withLock({ tv }) else { return }
        do { try await tv.clear(id: id) } catch { sink(.tvFailed("\(error)")) }
    }
}

/// Kare kaynağını sarar: her karede haber verir (son kare önizlemesi ve görüntü bekçisi için).
struct FrameTap: FrameSource {
    let base: FrameSource
    let onFrame: @Sendable (Frame) -> Void

    init(_ base: FrameSource, onFrame: @escaping @Sendable (Frame) -> Void) {
        self.base = base
        self.onFrame = onFrame
    }

    func frames() -> AsyncStream<Frame> {
        let upstream = base.frames()
        let (stream, continuation) = AsyncStream<Frame>.makeStream(bufferingPolicy: .bufferingNewest(1))
        // Pompa iptal edilmez: iptal, kaynağın kapanmasını (Remote Play'de iş parçacığı beklemesi) iptal edenin
        // iş parçacığında çalıştırır ve kilitlenmeye yol açar. Kaynak durdurulunca pompa kendiliğinden biter.
        Task {
            for await frame in upstream {
                onFrame(frame)
                continuation.yield(frame)
            }
            continuation.finish()
        }
        return stream
    }
}
