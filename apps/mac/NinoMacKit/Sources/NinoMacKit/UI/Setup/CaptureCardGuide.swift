// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI

/// Yakalama kartı rehberi (kurulum.md §10): bağlantı, HDCP, takma ve deneme. Sihirbazın kartının yerini alır;
/// Ayarlar'dan ayrı pencerede de açılır (o zaman yatay kenar 24, ilk sayfada Vazgeç).
public struct CaptureCardGuide: View {
    public enum Context: Sendable { case wizard, settingsWindow }

    private let state: AppState
    private let context: Context
    private let onClose: () -> Void
    @State private var page = 0
    @State private var toTV: Bool
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameter onClose: Rehber kapanınca (Geri ile ilk sayfadan, Vazgeç ya da Ayarlar'da Bitti).
    public init(state: AppState, context: Context, initialPage: Int = 0, onClose: @escaping () -> Void) {
        self.state = state
        self.context = context
        self.onClose = onClose
        _page = State(initialValue: min(max(initialPage, 0), 2))
        // Kaynak zaten kart ve çıktı TV ise "Akıllı TV" seçili gelir, değilse "Monitör".
        _toTV = State(initialValue: state.settings.videoSource == .card && state.settings.output == .tv)
    }

    private var edge: CGFloat { context == .wizard ? NinoSpacing.xxl : NinoSpacing.xl }

    public var body: some View {
        VStack(spacing: 0) {
            SetupCard(verticalInset: NinoSpacing.xl) {
                ZStack(alignment: .top) {
                    pageView
                        .id(page)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                removal: .move(edge: .leading).combined(with: .opacity)))
                }
                .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.86), value: page)
            }
            .padding(.horizontal, edge)
            .padding(.top, 12)
            bottomRow
                .frame(maxWidth: 700)
                .padding(.horizontal, edge)
                .padding(.vertical, NinoSpacing.l)
        }
    }

    @ViewBuilder private var pageView: some View {
        switch page {
        case 0: connectionPage
        case 1: hdcpPage
        default: plugPage
        }
    }

    // MARK: Alt sıra

    private var bottomRow: some View {
        ZStack {
            SetupPageDots(count: 3, current: page)
            HStack {
                if page == 0 && context == .settingsWindow {
                    Button(action: onClose) {
                        Label { KText("setup.card.cancel") } icon: { Image(systemName: "xmark") }
                    }
                    .buttonStyle(.nino(.ghost, size: .large))
                } else {
                    Button(action: back) {
                        Label { KText("setup.back") } icon: {
                            Image(systemName: "chevron.left").flipsForRightToLeftLayoutDirection(true)
                        }
                    }
                    .buttonStyle(.nino(.ghost, size: .large))
                }
                Spacer()
                Button(action: forward) {
                    KText(page == 2 ? "setup.card.done" : "setup.continue").frame(minWidth: 120 - 2 * NinoSpacing.l)
                }
                .buttonStyle(.nino(.primary, size: .large))
                .keyboardShortcut(.defaultAction)
            }
        }
        .frame(minHeight: NinoSize.buttonHeightLarge)
    }

    private func back() {
        if page == 0 { onClose() } else { page -= 1 }
    }

    private func forward() {
        guard page == 2 else { page += 1; return }
        switch context {
        case .wizard:
            SetupFlow.captureGuideDone(toTV: toTV, state)
        case .settingsWindow:
            state.settings.videoSource = .card
            state.settings.output = toTV ? .tv : .computer
            onClose()
        }
    }

    // MARK: 1. Bağlantı

    private var connectionPage: some View {
        NinoSetupStepLayout(icon: .symbol(NinoSymbol.captureCard), title: SetupText.string("setup.card.connect.title", locale),
                            message: SetupText.string("setup.card.connect.message", locale)) {
            VStack(spacing: NinoSpacing.m) {
                ConnectionOption(selected: !toTV, title: SetupText.string("setup.card.monitor", locale),
                                 detail: SetupText.string("setup.card.monitor.detail", locale),
                                 chain: [NinoSymbol.controllerFill, NinoSymbol.captureCard, "laptopcomputer", "display"]) {
                    toTV = false
                }
                ConnectionOption(selected: toTV, title: SetupText.string("setup.card.tv", locale),
                                 detail: SetupText.string("setup.card.tv.detail", locale),
                                 chain: [NinoSymbol.controllerFill, NinoSymbol.captureCard, "tv"]) {
                    toTV = true
                }
            }
        }
    }

    // MARK: 2. HDCP

    private var hdcpPage: some View {
        NinoSetupStepLayout(icon: .symbol("lock.open.fill"), title: SetupText.string("setup.card.hdcp.title", locale),
                            message: SetupText.string("setup.card.hdcp.message", locale)) {
            VStack(alignment: .leading, spacing: NinoSpacing.l) {
                ForEach(1...3, id: \.self) { n in
                    NinoNumberedRow(number: n, text: SetupText.string("setup.card.hdcp.step\(n)", locale))
                }
                VStack(alignment: .leading, spacing: NinoSpacing.s) {
                    noteRow("info.circle", "setup.card.hdcp.netflix")
                    noteRow("headphones", "setup.card.hdcp.headset")
                }
                .padding(.horizontal, NinoSpacing.xs)
            }
        }
    }

    private func noteRow(_ symbol: String, _ key: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: NinoSpacing.s) {
            Image(systemName: symbol)
            KText(key).fixedSize(horizontal: false, vertical: true)
        }
        .font(.nino(.callout))
        .foregroundStyle(NinoColor.textSecondary)
    }

    // MARK: 3. Takma ve deneme

    private var plugPage: some View {
        NinoSetupStepLayout(icon: .symbol("checkmark.seal.fill"), title: SetupText.string("setup.card.plug.title", locale),
                            message: SetupText.string(toTV ? "setup.card.plug.tv" : "setup.card.plug.monitor", locale)) {
            CaptureCardCheckView(state: state)
        }
    }
}

/// Rehberin bağlantı seçeneği: işaret, başlık, açıklama ve kablo şeması.
private struct ConnectionOption: View {
    let selected: Bool
    let title: String
    let detail: String
    let chain: [String]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: NinoSpacing.m) {
                Image(systemName: selected ? NinoSymbol.okFill : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(selected ? NinoColor.accent : NinoColor.textSecondary)
                VStack(alignment: .leading, spacing: NinoSpacing.s) {
                    Text(title).font(.nino(.headline)).foregroundStyle(NinoColor.textPrimary)
                    Text(detail)
                        .font(.nino(.callout))
                        .foregroundStyle(NinoColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        ForEach(Array(chain.enumerated()), id: \.offset) { index, symbol in
                            if index > 0 {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(NinoColor.textSecondary)
                            }
                            Image(systemName: symbol)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(NinoColor.accentText)
                                .frame(width: 36, height: 30)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(NinoColor.accentSoft))
                        }
                    }
                    .environment(\.layoutDirection, .leftToRight)
                    .padding(.top, NinoSpacing.xs)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .ninoTile(active: selected)
            .contentShape(NinoRadius.shape(NinoRadius.card))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Kart denetimi (rehberin son sayfası ve Ayarlar): önizleme, durum satırı, aygıt seçici.
/// Canlı görüntüyü motor `preview` görünümüyle verir; verilmezse yalnız durum çizilir.
public struct CaptureCardCheckView<Preview: View>: View {
    private let state: AppState
    private let preview: Preview
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL

    public init(state: AppState, @ViewBuilder preview: () -> Preview) {
        self.state = state
        self.preview = preview()
    }

    private var check: CaptureCardCheck { state.setup.captureCard }

    public var body: some View {
        VStack(alignment: .leading, spacing: NinoSpacing.m) {
            previewBox
            statusRow
            if check.devices.count > 1 { devicePicker }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { state.setCaptureCardPreview(true) }
        .onDisappear { state.setCaptureCardPreview(false) }
    }

    private var showsPicture: Bool {
        switch check.status {
        case .working, .black, .stopped: return true
        default: return false
        }
    }

    private var previewBox: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return ZStack {
            Color.black
            if showsPicture {
                preview
            } else {
                VStack(spacing: NinoSpacing.s) {
                    Image(systemName: check.status == .noPermission ? "lock.fill" : NinoSymbol.captureCard)
                        .font(.system(size: 30))
                    KText(check.status == .noPermission ? "setup.card.check.cameraNeeded" : "setup.card.check.looking")
                        .font(.nino(.headline))
                }
                .foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(height: 220)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topLeading) { pill.padding(10) }
        .clipShape(shape)
    }

    private var pill: some View {
        let (color, text): (Color, String) = {
            switch check.status {
            case .working(let name): return (.green, name)
            case .stopped(let name): return (.gray, name)
            case .black: return (.orange, check.devices.first?.name ?? SetupText.string("setup.card.check.noCard", locale))
            case .noCard: return (.orange, SetupText.string("setup.card.check.noCard", locale))
            case .searching: return (.orange, SetupText.string("setup.card.check.searching", locale))
            case .noPermission: return (.orange, SetupText.string("setup.card.check.noPermission", locale))
            }
        }()
        return HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(Capsule().fill(Color.black.opacity(0.5)))
    }

    @ViewBuilder private var statusRow: some View {
        switch check.status {
        case .working:
            Label { KText("setup.card.check.working") } icon: { Image(systemName: NinoSymbol.okFill) }
                .font(.nino(.callout))
                .foregroundStyle(NinoColor.success)
        case .black, .stopped:
            SetupErrorText(text: SetupText.string("setup.card.check.black", locale))
        case .noPermission:
            SetupErrorText(text: SetupText.string("setup.card.check.permission", locale))
            Button { openURL(SetupLinks.cameraSettings) } label: { KText("setup.card.check.openSettings") }
                .buttonStyle(.nino(.secondary))
        case .noCard, .searching:
            SetupErrorText(text: SetupText.string("setup.card.check.plugIn", locale))
        }
    }

    private var devicePicker: some View {
        HStack(spacing: NinoSpacing.m) {
            KText("setup.card.check.device").font(.nino(.callout).weight(.semibold))
            Picker(selection: Binding(get: { check.selectedDeviceID ?? "" },
                                      set: { state.selectCaptureDevice($0.isEmpty ? nil : $0) })) {
                KText("setup.card.check.automatic").tag("")
                ForEach(check.devices) { device in Text(verbatim: device.name).tag(device.id) }
            } label: { EmptyView() }
            .labelsHidden()
            .fixedSize()
        }
    }
}

public extension CaptureCardCheckView where Preview == CardPreviewView {
    /// Kartın gerçek görüntüsüyle (Capture/CardPreviewView).
    init(state: AppState) {
        self.init(state: state) { CardPreviewView() }
    }
}
