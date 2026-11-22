// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AVFoundation
import AppKit
import Observation
import SwiftUI

/// Kartın açık oturumu (önizleme ya da çeviri). Önizleme görünümleri buradan okur.
@MainActor
@Observable
public final class CardPreviewHub {
    public static let shared = CardPreviewHub()

    public internal(set) var session: AVCaptureSession?
    /// Oturum yeniden kurulunca artar (katman yeniden bağlanır, yoksa eski karede donabiliyor).
    public internal(set) var generation = 0

    init() {}

    func attach(_ session: AVCaptureSession?) {
        self.session = session
        generation += 1
    }

    func rebuilt() { generation += 1 }
}

/// Kart denetimindeki canlı görüntü (siyah zemin, oran korunur). Oturum yoksa siyah kalır.
public struct CardPreviewView: View {
    private let hub: CardPreviewHub?

    public init(hub: CardPreviewHub? = nil) { self.hub = hub }

    public var body: some View {
        let hub = self.hub ?? .shared
        return CardPreviewLayerView(session: hub.session, generation: hub.generation)
    }
}

struct CardPreviewLayerView: NSViewRepresentable {
    let session: AVCaptureSession?
    let generation: Int

    func makeNSView(context: Context) -> CardVideoView {
        let view = CardVideoView()
        view.attach(session)
        return view
    }

    func updateNSView(_ view: CardVideoView, context: Context) {
        if view.generation != generation {
            view.generation = generation
            view.attach(session)
        }
    }
}

/// Kart oturumunu doğrudan ekran kartıyla çizen görünüm (okuma hattından geçmez).
final class CardVideoView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()
    var generation = -1

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        previewLayer.videoGravity = .resizeAspect
        previewLayer.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(previewLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) kullanılmaz") }

    /// Katmanı oturuma (yeniden) bağlar.
    func attach(_ session: AVCaptureSession?) {
        previewLayer.session = nil
        previewLayer.session = session
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = bounds
        CATransaction.commit()
    }
}
