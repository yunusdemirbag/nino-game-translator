// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import Observation
import SwiftUI
import WebKit

/// PSN girişini yürüten denetleyici (kurulum.md §5). Kurulum ekranı `begin()` çağırır, `isPresented`
/// doğruyken `PSNLoginView`'u sayfa olarak gösterir; sonuç `onFinish` ile gelir.
@MainActor
@Observable
public final class PSNLoginController {
    public private(set) var isPresented = false
    public private(set) var isWorking = false
    public private(set) var lastError: PSNLoginError?

    /// Başarıda 8 baytlık hesap kimliği; kasaya yazılmış olarak gelir.
    public var onFinish: ((Result<Data, PSNLoginError>) -> Void)?

    @ObservationIgnored let fetcher: PSNAccountIDFetcher
    @ObservationIgnored let store: ConsoleRecordStore
    @ObservationIgnored let log: ConsoleLog
    @ObservationIgnored var flow = PSNLoginFlow()

    public init(store: ConsoleRecordStore, log: ConsoleLog, fetcher: PSNAccountIDFetcher = PSNAccountIDFetcher()) {
        self.store = store
        self.log = log
        self.fetcher = fetcher
    }

    /// Giriş penceresini açar.
    public func begin() {
        guard !isWorking else { return }
        flow = PSNLoginFlow()
        lastError = nil
        isWorking = true
        isPresented = true
    }

    /// Vazgeç ya da pencere kapandı.
    public func cancel() {
        guard isPresented else { return }
        isPresented = false
        if let error = flow.closedWithoutRedirect() { finish(.failure(error)) }
    }

    /// Gezinme kararı (tarayıcı her gezinmede sorar).
    func decide(url: URL?) -> PSNLoginFlow.Decision {
        let decision = flow.decide(url: url)
        if case let .cancel(capture?) = decision {
            isPresented = false
            Task { await complete(with: capture) }
        }
        return decision
    }

    func mainFrameResponse(status: Int) {
        flow.mainFrameResponse(status: status)
        if status >= 400 { log.write("PSN giriş sayfası: HTTP \(status)") }
    }

    func loadFailed(_ error: Error) {
        let e = error as NSError
        flow.loadFailed(domain: e.domain, code: e.code, description: e.localizedDescription)
    }

    /// Yakalanan yönlendirmeden hesap kimliğine.
    public func complete(with redirect: PSNAuth.Redirect) async {
        do {
            let id = try await fetcher.accountID(for: redirect)
            try store.saveAccountID(id)
            finish(.success(id))
        } catch let e as PSNLoginError {
            finish(.failure(e))
        } catch {
            finish(.failure(.unreadable(detail: "\(error)")))
        }
    }

    /// Elle yazılan kimlik. Geçerliyse web girişi gibi saklanır.
    @discardableResult
    public func enterManually(_ text: String) -> Bool {
        guard let id = PSNAuth.manualAccountID(text) else { return false }
        do { try store.saveAccountID(id) } catch { return false }
        log.write("PSN girişi yapıldı (elle)")
        lastError = nil
        onFinish?(.success(id))
        return true
    }

    /// Yalnız hesap kimliği silinir.
    public func signOut() {
        try? store.deleteAccountID()
        log.write("PSN hesabından çıkıldı")
    }

    public static var manualEntryErrorMessage: String { ConsoleText.string("console.psn.error.manualInvalid") }

    public func errorMessage() -> String? { lastError?.message(logPath: log.path) }

    private func finish(_ result: Result<Data, PSNLoginError>) {
        isWorking = false
        switch result {
        case .success:
            lastError = nil
            log.write("PSN girişi yapıldı")
        case let .failure(e):
            lastError = e
            log.write("PSN girişi başarısız: \(e.logName)" + (e.detail.map { " (\($0))" } ?? ""))
        }
        onFinish?(result)
    }
}

/// 520×680 giriş penceresi: üstte başlık ve Vazgeç, altında kalıcı olmayan veri depolu tarayıcı.
public struct PSNLoginView: View {
    let controller: PSNLoginController

    public init(controller: PSNLoginController) {
        self.controller = controller
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(verbatim: "PlayStation Network").font(.headline)
                Spacer()
                Button(ConsoleText.string("console.psn.cancel")) { controller.cancel() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
            Divider()
            PSNWebView(controller: controller)
        }
        .frame(width: 520, height: 680)
    }
}

struct PSNWebView: NSViewRepresentable {
    let controller: PSNLoginController

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.load(URLRequest(url: PSNAuth.signInURL()))
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.stopLoading()
        nsView.navigationDelegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        let controller: PSNLoginController
        init(controller: PSNLoginController) { self.controller = controller }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            switch controller.decide(url: navigationAction.request.url) {
            case .allow: decisionHandler(.allow)
            case .cancel: decisionHandler(.cancel)
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                     decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void) {
            if navigationResponse.isForMainFrame, let http = navigationResponse.response as? HTTPURLResponse {
                controller.mainFrameResponse(status: http.statusCode)
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            controller.loadFailed(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            controller.loadFailed(error)
        }
    }
}
