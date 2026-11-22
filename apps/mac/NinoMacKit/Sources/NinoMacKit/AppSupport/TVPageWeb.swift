// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AppKit
import Foundation
import ObjectiveC
import WebKit

/// TV web sayfasının (`TVPage/`, apps/tv-web/src'nin kopyası; yalnız `platform.js` farklı) Mac'te çalışan hâli:
/// saydam zeminli WKWebView, ağ tamamen kapalı (içerik kuralı), veri kalıcı değil. TV'lere giden protokol mesajları
/// aynen `window.nino.receive` ile verilir; sayfa yeniden yüklenirse son durum yeniden kurulur.
///
/// Pencereyi bu sınıf kurmaz: admin bileşik karesi (`TVPageRenderer`) gizli bir pencerede, bilgisayardaki ekran
/// öğeleri katmanı (`ComputerScreenPanelController`) oyunun üstündeki panelde kullanır.
@MainActor
final class TVPageWeb: NSObject, WKNavigationDelegate {
    /// Sayfanın düzen boyu (TV'deki gibi 1920 × 1080 CSS pikseli).
    nonisolated static let layoutSize = CGSize(width: 1920, height: 1080)
    /// Sayfanın TV'ye ait olup Mac'te anlamsız parçaları: bekleme sahnesi, durum kutusu, ipuçları.
    nonisolated static let tvOnlyParts = "#lobby,#status,#demo-note,#source-note,#no-signal"

    let webView: WKWebView
    private(set) var ready = false
    private var pending: [String] = []
    /// Sayfa yeniden yüklenirse verilecek son durum (style, son show, screen, region'lar).
    private var replay: [String: String] = [:]
    private var regionOrder: [String] = []

    static func pageFolder() -> URL? { Bundle.module.url(forResource: "TVPage", withExtension: nil) }

    /// - Parameter hidden: Ayrıca gizlenecek parçalar (CSS seçicisi; boşsa yalnız TV'ye ait parçalar).
    init(frame: CGRect, hidden: String = "") {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.suppressesIncrementalRendering = false
        let parts = hidden.isEmpty ? Self.tvOnlyParts : Self.tvOnlyParts + "," + hidden
        let css = "\(parts){display:none!important}html,body{background:transparent!important}"
        let js = "var s=document.createElement('style');s.textContent=\(DebugTextJS.quote(css));document.documentElement.appendChild(s);"
        config.userContentController.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        webView = WKWebView(frame: frame, configuration: config)
        super.init()
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = self
        guard let folder = Self.pageFolder() else { return }
        let rules = """
        [{"trigger":{"url-filter":"^(https?|wss?|ftp)://"},"action":{"type":"block"}}]
        """
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "nino-tvpage-ag-yok", encodedContentRuleList: rules) {
            [weak self] list, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let list { self.webView.configuration.userContentController.add(list) }
                self.webView.loadFileURL(folder.appendingPathComponent("index.html"), allowingReadAccessTo: folder)
            }
        }
    }

    /// Ekran dışındaki pencere "örtülü" sayılıp çizim durmasın (yalnız gizli pencere: admin bileşik karesi ve testler;
    /// özel anahtar yoksa geçilir).
    func keepDrawingWhenOccluded() {
        let occlusion = NSSelectorFromString("_setWindowOcclusionDetectionEnabled:")
        guard let m = class_getInstanceMethod(WKWebView.self, occlusion) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
        unsafeBitCast(method_getImplementation(m), to: Setter.self)(webView, occlusion, false)
    }

    /// TV'ye giden bir protokol mesajı (JSON metni).
    func receive(_ json: String) {
        remember(json)
        guard ready else {
            pending.append(json)
            if pending.count > 200 { pending.removeFirst(pending.count - 200) }
            return
        }
        webView.evaluateJavaScript("window.nino&&window.nino.receive(\(json))")
    }

    /// Son durumu tutar: sayfa sonradan açılırsa ya da yeniden yüklenirse aynı katman kurulur.
    func remember(_ json: String) {
        guard let o = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any],
              let type = o["type"] as? String else { return }
        switch type {
        case "style": replay["style"] = json
        case "show": replay["show"] = json
        case "clear": replay["show"] = nil
        case "screen": replay["screen"] = json
        case "screen-clear": replay["screen"] = nil
        case "region":
            let id = "region:" + ((o["id"] as? String) ?? "")
            if !regionOrder.contains(id) { regionOrder.append(id) }
            replay[id] = json
        case "region-clear":
            for id in regionOrder { replay[id] = nil }
            regionOrder = []
        case "stopped":
            let style = replay["style"]
            replay = [:]
            regionOrder = []
            replay["style"] = style
        default: break
        }
    }

    var replayMessages: [String] {
        (["style", "screen", "show"].compactMap { replay[$0] }) + regionOrder.compactMap { replay[$0] }
    }

    /// Görüntünün tamamı (saydam zemin), `width` nokta genişliğinde; sayfa hazır değilse nil.
    func snapshot(width: CGFloat, _ done: @escaping @MainActor (CGImage?) -> Void) {
        guard ready else { return done(nil) }
        let config = WKSnapshotConfiguration()
        config.rect = CGRect(origin: .zero, size: webView.bounds.size)
        config.snapshotWidth = NSNumber(value: Double(width))
        config.afterScreenUpdates = true
        webView.takeSnapshot(with: config) { image, _ in
            var rect = CGRect(origin: .zero, size: image?.size ?? .zero)
            done(image?.cgImage(forProposedRect: &rect, context: nil, hints: nil))
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready = true
        let queued = replayMessages
        pending = []
        for m in queued { webView.evaluateJavaScript("window.nino&&window.nino.receive(\(m))") }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        ready = false
        if let folder = Self.pageFolder() { webView.loadFileURL(folder.appendingPathComponent("index.html"), allowingReadAccessTo: folder) }
    }

    /// Yalnız yerel dosyalar açılır.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.request.url?.isFileURL == true ? .allow : .cancel)
    }
}
