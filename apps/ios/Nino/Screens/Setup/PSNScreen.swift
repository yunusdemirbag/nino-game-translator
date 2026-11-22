// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI
import WebKit

/// Kurulum 1/3: ikinci PSN hesabıyla giriş.
struct PSNScreen: View {
    @EnvironmentObject private var model: AppModel
    var onBack: (() -> Void)?
    var onSkip: (() -> Void)?
    let onDone: () -> Void

    @State private var showLogin = false
    @State private var showWhy = false
    @State private var showDemo = false
    @State private var working = false
    @State private var error: String?
    @State private var gotRedirect = false

    var body: some View {
        NinoScreen {
            SetupHeader(step: 1, onBack: onBack, onSkip: onSkip)
        } content: {
            HeroTitle(step: L("setup.step", 1), title: L("psn.title"), lead: L("psn.body"))
            DarkStage {
                VStack(spacing: 10) {
                    GlassRow(symbol: "person.badge.plus", title: L("psn.free"), detail: L("psn.free.detail"))
                    GlassRow(symbol: "gamecontroller.fill", title: L("psn.play"), detail: L("psn.play.detail"))
                    GlassRow(symbol: "lock.shield.fill", title: L("psn.password"), detail: L("psn.password.detail"))
                }
                .padding(16)
            }
            .padding(.top, 6)
            NoteLine(text: L("psn.controller.warning"))
            if model.accountID != nil {
                StatusLabel(text: L("psn.signedin"), dotColor: DS.Palette.success)
            }
            if working { ProgressView().tint(DS.Palette.accent) }
            if let error { NoteLine(text: error) }
        } footer: {
            HStack {
                Button(L("psn.why")) { showWhy = true }
                    .buttonStyle(.ghost)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
                TryWithoutPS5Button { showDemo = true }
            }
            if model.accountID != nil {
                Button(L("psn.again")) { openLogin() }.buttonStyle(.secondary)
                Button(L("ob.continue"), action: onDone).buttonStyle(.primary)
            } else {
                Button(L("psn.signin")) { openLogin() }.buttonStyle(.primary).disabled(working)
            }
        }
        .sheet(isPresented: $showLogin, onDismiss: loginClosed) {
            PSNLoginSheet { url in
                gotRedirect = true
                showLogin = false
                Task { await finish(url) }
            } onCancel: { showLogin = false }
        }
        .sheet(isPresented: $showWhy) {
            SheetBody {
                HeroTitle(title: L("psn.why"), lead: L("psn.why.body"))
            }
            .fittedSheet()
        }
        .fullScreenCover(isPresented: $showDemo) {
            DemoPreview()
        }
    }

    private func openLogin() {
        gotRedirect = false
        error = nil
        showLogin = true
    }

    private func loginClosed() {
        if !gotRedirect {
            error = L("psn.error.windowclosed")
        }
    }

    private func finish(_ url: URL) async {
        working = true
        error = nil
        defer { working = false }
        do {
            try await model.completePSNLogin(redirect: url)
            onDone()
        } catch let failure as PSNLogin.Failure {
            error = failure.message
        } catch {
            self.error = L("signin.error.incomplete") + " (\(error.localizedDescription))"
        }
    }
}

/// Sony'nin giriş sayfası (çerezsiz, her açılışta temiz).
private struct PSNLoginSheet: View {
    let onRedirect: (URL) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            PSNWebView(onRedirect: onRedirect)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(Text(verbatim: "PlayStation Network"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(L("common.cancel"), action: onCancel) }
                }
        }
        .presentationDragIndicator(.visible)
    }
}

private struct PSNWebView: UIViewRepresentable {
    let onRedirect: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onRedirect: onRedirect) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.load(URLRequest(url: PSNLogin.authorizeURL))
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onRedirect: (URL) -> Void
        private var reported = false

        init(onRedirect: @escaping (URL) -> Void) { self.onRedirect = onRedirect }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = action.request.url, PSNLogin.isRedirect(url) {
                decisionHandler(.cancel)
                guard !reported else { return }
                reported = true
                onRedirect(url)
                return
            }
            decisionHandler(.allow)
        }
    }
}
