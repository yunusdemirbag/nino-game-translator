// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import Foundation
import NinoCore

/// Bilgisayardaki ekran öğeleri katmanının (telefon paneli, harita kartı, köşeler, tuş ipuçları, mesaj/arama kartı,
/// "Ekranı çevir" sonucu) kuralları. Katman TV sayfasının kendisidir (`TVPage/`), oyunun ekrandaki alanının tam üstünde
/// durur; böylece öğeler TV'dekiyle aynı yerde ve aynı görünümde çıkar.
///
/// Hangi kipte ne görünür (`AppState.subtitlesOnTV` / `subtitlesOnComputer`):
/// - TV'de: TV her şeyi çizer (altyazı, ek alanlar, ekran öğeleri); bilgisayarda hiçbir şey yok.
/// - Bilgisayarda (PS Remote Play penceresi her zaman bu kiptir): alt altyazı ve ek alanlar altyazı penceresinde
///   (`SubtitleOverlayController`, değişmedi); ekran öğeleri bu katmanda, yalnız oyunun alanı biliniyorsa (oyun
///   penceresinden ya da kart penceresinden okunurken). Alan bilinmiyorsa (Nino'nun kendi PS5 bağlantısı) katman çıkmaz.
/// - İkisinde: TV her şeyi çizer; bilgisayarda yukarıdaki gibi.
///
/// Katman `show` / `clear` / `region` almaz ve sayfanın altyazı ile ek alan parçaları gizlidir: alt satır ve ek alanlar
/// iki kez çizilmez.
public enum ComputerScreenRules {
    /// Katmana giden mesaj türleri.
    public static let forwardedTypes: Set<String> = ["screen", "screen-clear", "stopped"]

    /// Sayfada ayrıca gizlenen parçalar: altyazı ve gölgesi, ek alanlar, Nino rozeti, "çeviri başladı" balonu.
    static let hiddenParts = "#caption,#shade,#areas,#watermark,#hello"

    public static func forwards(_ event: NinoEvent) -> Bool { forwardedTypes.contains(event.type) }

    /// Katman ekranda mı.
    public static func isVisible(subtitlesOnComputer: Bool, translating: Bool, gameArea: CGRect?, hasItems: Bool) -> Bool {
        guard subtitlesOnComputer, translating, hasItems, let area = gameArea else { return false }
        return area.width >= 64 && area.height >= 36
    }

    /// Sayfa 1920 CSS pikseli genişlikte düzenlensin diye yakınlaştırma (alanın genişliği / 1920).
    public static func pageZoom(for area: CGRect) -> CGFloat {
        max(0.05, area.width / TVPageWeb.layoutSize.width)
    }

    /// Mesajdan sonra katmanda öğe var mı (`nil`: bu mesaj durumu değiştirmez).
    static func hasItems(after json: String) -> (has: Bool, durationMs: Int)? {
        guard let o = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any],
              let type = o["type"] as? String else { return nil }
        switch type {
        case "screen":
            let items = (o["items"] as? [Any]) ?? []
            return (!items.isEmpty, (o["durationMs"] as? Int) ?? 0)
        case "screen-clear", "stopped": return (false, 0)
        default: return nil
        }
    }
}

/// Hub'a "bilgisayar" anahtarıyla eklenen çıkış: ekran öğesi mesajlarını bilgisayardaki katmana verir.
///
/// "Altyazı yalnız bilgisayarda" iken hub altyazı olaylarını (bunlara `screen` de dahil) TV çıkışlarına göndermez,
/// yalnız yönlendiren çıkışlara gönderir; bu çıkış yönlendiren sayılır ki o kipte de alsın. Kendisi TV'ye bir şey
/// iletmez; görünürlüğe katman karar verir (`ComputerScreenRules.isVisible`). Hiç hata atmaz.
public final class ComputerScreenFeed: SubtitleRoutingOutput, @unchecked Sendable {
    public static let hubKey = "bilgisayar"

    private let lock = NSLock()
    private var handler: (@Sendable (String) -> Void)?

    public init() {}

    /// Katmana gidecek her mesajın JSON'u (her kuyruktan çağrılabilir).
    public var onMessage: (@Sendable (String) -> Void)? {
        get { lock.withLock { handler } }
        set { lock.withLock { handler = newValue } }
    }

    public func setSubtitlesOnTV(_ on: Bool) async {}

    /// Alt altyazı bilgisayarda altyazı penceresinde çizilir.
    public func show(_ payload: ShowPayload) async throws {}
    public func clear(id: Int?) async throws {}

    public func send(_ event: NinoEvent) async throws {
        guard ComputerScreenRules.forwards(event) else { return }
        onMessage?(event.jsonString)
    }
}
