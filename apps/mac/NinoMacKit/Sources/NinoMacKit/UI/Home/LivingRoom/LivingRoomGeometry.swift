// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import SwiftUI

/// Salon sahnesinin tuval koordinatları ve hesapları (ana-ekran.md §4.2–§4.8).
/// Tuval 1672×941, sol üst köşe başlangıç. Görünümden bağımsızdır; testlerle sınanır.
public struct LivingRoomGeometry: Equatable, Sendable {
    public static let canvas = CGSize(width: 1672, height: 941)
    /// TV içeriğinin çizildiği mantıksal genişlik.
    public static let logicalTVWidth: CGFloat = 588
    /// Kablonun serbest boyu.
    public static let cableLength: CGFloat = 330
    /// Prize bu kadar yaklaşan fiş tam prize döner.
    public static let facingDistance: CGFloat = 120
    /// Bırakılan fiş prize bundan yakınsa takılır.
    public static let snapDistance: CGFloat = 140

    public var asset: NinoAsset
    /// TV ekranı (içerik alanı).
    public var tvScreen: CGRect
    /// TV çerçevesi (ışıklar için).
    public var tvFrame: CGRect
    public var cabinet: CGRect
    public var socket: CGPoint
    /// Kablonun başı (Xbox'ta çizilen kablo buradan başlar).
    public var cableHead: CGPoint
    /// Görseldeki kablonun son parçası (PS5); çizilen kablo bunun üstünden geçer.
    public var cableTail: [CGPoint]
    /// Kablonun çıkış yönü (birim).
    public var exitDirection: CGVector
    /// Fişin sarktığı yer (çıkıkken).
    public var hangPoint: CGPoint
    /// Xbox'ta kablonun başında küçük fiş başı çizilir.
    public var drawsCableHeadPlug: Bool

    public static let ps5 = LivingRoomGeometry(
        asset: .livingRoom,
        tvScreen: CGRect(x: 149, y: 40, width: 1151, height: 595),
        tvFrame: CGRect(origin: CGPoint(x: 139, y: 27), size: CGSize(width: 1171, height: 621)),
        cabinet: CGRect(x: 49, y: 713, width: 1502, height: 160),
        socket: CGPoint(x: 1564, y: 378),
        cableHead: CGPoint(x: 1550, y: 734),
        cableTail: [(1490, 706), (1522, 706), (1535, 709), (1545, 716), (1552, 727)].map { CGPoint(x: $0.0, y: $0.1) },
        exitDirection: CGVector(dx: 0.5, dy: 0.87),
        hangPoint: CGPoint(x: 1600, y: 885),
        drawsCableHeadPlug: false)

    public static let xbox = LivingRoomGeometry(
        asset: .livingRoomXbox,
        tvScreen: CGRect(x: 136, y: 40, width: 1185, height: 596),
        tvFrame: CGRect(origin: CGPoint(x: 121, y: 26), size: CGSize(width: 1214, height: 630)),
        cabinet: CGRect(x: 43, y: 733, width: 1580, height: 167),
        socket: CGPoint(x: 1561, y: 381),
        cableHead: CGPoint(x: 1572, y: 722),
        cableTail: [],
        exitDirection: CGVector(dx: 1, dy: 0.1),
        hangPoint: CGPoint(x: 1646, y: 912),
        drawsCableHeadPlug: true)

    public static func forConsole(_ console: MacSettings.GameConsole) -> LivingRoomGeometry {
        console == .xbox ? .xbox : .ps5
    }

    // MARK: TV içi

    /// Mantıksal TV'nin yüksekliği: 588 × ekran yüksekliği / ekran genişliği.
    public var logicalTVHeight: CGFloat { Self.logicalTVWidth * tvScreen.height / tvScreen.width }
    /// Mantıksal TV'den ekran dikdörtgenine büyütme (PS5 ≈ 1,9575, Xbox ≈ 2,015).
    public var tvContentScale: CGFloat { tvScreen.width / Self.logicalTVWidth }

    // MARK: Ölçekleme (§4.2)

    /// Sahne küçülür ama hiç büyümez.
    public static func scale(for available: CGSize) -> CGFloat {
        guard available.width > 0, available.height > 0 else { return 0 }
        return min(1, available.width / canvas.width, available.height / canvas.height)
    }

    /// Sehpanın ortasını pencerenin ortasına getiren yatay kayma (tuval birimi; ölçekle çarpılır).
    public var centeringShift: CGFloat { Self.canvas.width / 2 - cabinet.midX }

    /// Ölçeklenmiş tuvalin ayrılan alandaki sol üst köşesi (ortalanmış + sehpa kayması).
    public func origin(in available: CGSize) -> CGPoint {
        let s = Self.scale(for: available)
        return CGPoint(x: (available.width - Self.canvas.width * s) / 2 + centeringShift * s,
                       y: (available.height - Self.canvas.height * s) / 2)
    }

    /// Tuval noktasının ayrılan alandaki yeri (ölçek ve ortalama kayması uygulanmış).
    public func viewPoint(_ canvasPoint: CGPoint, in available: CGSize) -> CGPoint {
        let s = Self.scale(for: available)
        let o = origin(in: available)
        return CGPoint(x: o.x + canvasPoint.x * s, y: o.y + canvasPoint.y * s)
    }

    /// Fiş ipucunun yeri (ayrılan alanın birimleriyle): ok ucu prizin hemen üstünde, balon okun üstünde.
    public struct HintPlacement: Equatable, Sendable {
        /// Okun ucu (prizi gösterir).
        public var arrowTip: CGPoint
        /// Balonun sığabileceği kutu; balon kutunun alt-sona yaslanır.
        public var box: CGRect
    }

    /// - Parameters:
    ///   - available: Sahneye ayrılan alan.
    ///   - arrowLength: Okun boyu (pt).
    ///   - maxWidth: Balonun en geniş hâli (pt).
    public func plugHintPlacement(in available: CGSize, arrowLength: CGFloat = 18,
                                  maxWidth: CGFloat = 260) -> HintPlacement {
        let s = Self.scale(for: available)
        let socketView = viewPoint(socket, in: available)
        // Priz kapağı yaklaşık 100'lük; ok ucu kapağın hemen üstünde (fiş takılıyken de kapak görünür).
        let tip = CGPoint(x: socketView.x, y: socketView.y - 54 * s)
        let bottom = tip.y - arrowLength - 2
        // Balon TV'nin sağ kenarını aşmaz, pencereden taşmaz.
        let leftBound = max(4, viewPoint(CGPoint(x: tvFrame.maxX, y: 0), in: available).x + 10)
        let right = min(available.width - 4, max(socketView.x + 70 * s + 24, leftBound + 60))
        let width = max(60, min(maxWidth, right - leftBound))
        let top = max(0, viewPoint(CGPoint(x: 0, y: tvFrame.minY), in: available).y)
        return HintPlacement(arrowTip: tip,
                             box: CGRect(x: right - width, y: top, width: width, height: max(0, bottom - top)))
    }

    // MARK: Fiş (§4.8)

    /// Kablo eğrisinin başladığı nokta: görseldeki son parçanın son noktası (Xbox'ta kablonun başı).
    public var cableStart: CGPoint { cableTail.last ?? cableHead }

    /// Fişin dinlenme yeri.
    public func restingPoint(plugged: Bool) -> CGPoint { plugged ? socket : hangPoint }

    /// Fişin açısı θ (radyan, saat yönü artı; 0'da uçlar aşağı bakar).
    public func plugAngle(at plug: CGPoint) -> Double {
        let d0 = distance(socket, hangPoint)
        let d = distance(socket, plug)
        guard d0 > Self.facingDistance, d > 1 else { return 0 }
        let t = min(1, max(0, (d0 - d) / (d0 - Self.facingDistance)))
        let eased = t * t * (3 - 2 * t)
        let alpha = atan2(-(socket.x - plug.x), socket.y - plug.y)
        return Double(eased) * Double(alpha)
    }

    /// Bırakılan fiş prize yakın mı.
    public func isNearSocket(_ point: CGPoint) -> Bool {
        distance(point, socket) < Self.snapDistance
    }

    /// Kablonun eğrisi: başlangıç, iki kontrol noktası ve bitiş.
    public struct CableCurve: Equatable, Sendable {
        public var start: CGPoint
        public var control1: CGPoint
        public var control2: CGPoint
        public var end: CGPoint
    }

    /// - Parameters:
    ///   - plug: Fişin o anki yeri (merkezi).
    ///   - seated: Fiş takılı ve sürüklenmiyor.
    public func cableCurve(plug: CGPoint, seated: Bool) -> CableCurve {
        let s = cableStart
        let exit = exitDirection
        if seated {
            let end = CGPoint(x: plug.x, y: plug.y + 30)
            return CableCurve(start: s,
                              control1: CGPoint(x: s.x + 90 * exit.dx, y: s.y + 90 * exit.dy),
                              control2: CGPoint(x: end.x + 10, y: end.y + 170),
                              end: end)
        }
        let theta = plugAngle(at: plug)
        let u = CGVector(dx: -sin(theta), dy: cos(theta))
        let throat = CGPoint(x: plug.x - 40 * u.dx, y: plug.y - 40 * u.dy)
        let sag = max(0, Self.cableLength - distance(throat, s)) * 0.45
        return CableCurve(start: s,
                          control1: CGPoint(x: s.x + 70 * exit.dx, y: s.y + 70 * exit.dy + sag),
                          control2: CGPoint(x: throat.x - 80 * u.dx, y: throat.y - 80 * u.dy + sag),
                          end: throat)
    }

    /// Bütün kablo: PS5'te görseldeki son parçanın noktalarından düz çizgiyle geçer, sonra eğri.
    public func cablePath(plug: CGPoint, seated: Bool) -> Path {
        let curve = cableCurve(plug: plug, seated: seated)
        var path = Path()
        if let first = cableTail.first {
            path.move(to: first)
            for point in cableTail.dropFirst() { path.addLine(to: point) }
        } else {
            path.move(to: curve.start)
        }
        path.addCurve(to: curve.end, control1: curve.control1, control2: curve.control2)
        return path
    }
}

private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    hypot(a.x - b.x, a.y - b.y)
}
