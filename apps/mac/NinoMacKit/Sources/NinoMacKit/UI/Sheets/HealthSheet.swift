// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AppKit
import SwiftUI

/// Sistem sağlığı içeriği (gecmis-hakkinda-saglik.md §3). Ayarlar › Sistem sağlığı da bunu gösterir.
/// İki saniyede bir ölçümlerin kopyasını alır; kartlar ondan çizilir.
public struct HealthContent: View {
    private let state: AppState
    @State private var metrics: HealthMetrics
    @State private var now = Date()
    @Environment(\.locale) private var locale
    @Environment(\.ninoStaticRendering) private var isStatic

    public init(state: AppState) {
        self.state = state
        _metrics = State(initialValue: state.sheetsStatus.healthMetrics)
    }

    public var body: some View {
        let rowsNeedAction = HealthChecks.rows(metrics, state: state, locale: locale, now: now).contains { $0.level.needsAction }
        VStack(alignment: .leading, spacing: NinoSpacing.l) {
            HealthCauseCard(metrics: metrics, otherProblem: rowsNeedAction)
            HealthChecksCard(state: state, metrics: metrics, now: now)
            HealthProblemsCard(state: state)
            DeviceInfoCard(state: state)
            HealthDetailsCard(state: state, metrics: metrics)
        }
        // Ayarlar içinde de dar sütuna sığsın; geniş bir satır bütün sayfayı yana kaydırmasın.
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            guard !isStatic else { return }
            while !Task.isCancelled {
                metrics = state.sheetsStatus.healthMetrics
                now = Date()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}

/// Ayrı sayfa olarak (ana pencerenin üstünde): başlık, kaydırılan kartlar, Bitti.
public struct HealthSheet: View {
    private let state: AppState

    public init(state: AppState) { self.state = state }

    public var body: some View {
        VStack(alignment: .leading, spacing: NinoSpacing.l) {
            ShText("sheets.health.title").font(.nino(.display))
            SheetScroll {
                HealthContent(state: state).padding(.bottom, NinoSpacing.s)
            }
            HStack {
                Spacer()
                Button {
                    state.activeSheet = nil
                } label: {
                    ShText("sheets.common.done")
                }
                .buttonStyle(.nino(.primary, size: .large))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(NinoSpacing.xl)
        .frame(width: 640, height: NinoSize.windowHeight - 2 * NinoSpacing.xl)
        .ninoScreen()
    }
}

// MARK: - Muhtemel sebep

struct HealthCauseCard: View {
    let metrics: HealthMetrics
    /// Denetim satırlarından biri (ör. TV) işlem istiyorsa "her şey yolunda" yazılmaz.
    var otherProblem: Bool = false
    @Environment(\.locale) private var locale

    var body: some View {
        let causes = HealthRules.causes(metrics)
        if let first = causes.first {
            NinoCard {
                HStack(alignment: .top, spacing: NinoSpacing.m) {
                    Image(systemName: NinoSymbol.errorFill)
                        .font(.system(size: 22))
                        .foregroundStyle(NinoColor.warning)
                    VStack(alignment: .leading, spacing: NinoSpacing.s) {
                        Text(HealthText.causeTitle(first, locale)).font(.nino(.headline))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(HealthText.causeAction(first, locale)).fixedSize(horizontal: false, vertical: true)
                        let others = Array(causes.dropFirst())
                        ForEach(others.indices, id: \.self) { index in
                            let cause = others[index]
                            Text(verbatim: "• " + HealthText.causeTitle(cause, locale))
                                .font(.nino(.callout))
                                .foregroundStyle(NinoColor.textSecondary)
                        }
                    }
                }
            }
        } else if HealthRules.allGood(metrics), !otherProblem {
            NinoCard {
                Label { ShText("sheets.health.allGood") } icon: { Image(systemName: NinoSymbol.okFill) }
                    .font(.nino(.headline))
                    .foregroundStyle(NinoColor.success)
            }
        }
    }
}

// MARK: - Denetimler

struct HealthChecksCard: View {
    let state: AppState
    let metrics: HealthMetrics
    let now: Date
    @Environment(\.locale) private var locale

    var body: some View {
        let rows = HealthChecks.rows(metrics, state: state, locale: locale, now: now)
        NinoCard {
            if !metrics.hasMeasurements {
                NinoHint(SheetsText.string("sheets.health.checks.noData", locale))
            } else if !metrics.translating {
                NinoHint(SheetsText.string("sheets.health.checks.lastSession", locale))
            }
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider().overlay(NinoColor.tileBorder) }
                    HealthCheckRowView(row: row)
                    if row.id == "console", metrics.localNetworkSuspect, metrics.translating {
                        LocalNetworkWarning()
                    }
                }
            }
        }
    }
}

struct HealthCheckRowView: View {
    let row: HealthCheckRow
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(alignment: .top, spacing: NinoSpacing.m) {
            NinoTileIcon(systemName: row.symbol)
            VStack(alignment: .leading, spacing: NinoSpacing.xs) {
                HStack(spacing: NinoSpacing.s) {
                    Text(row.title).font(.nino(.body).weight(.semibold))
                    Spacer(minLength: NinoSpacing.s)
                    Circle().fill(HealthText.levelColor(row.level)).frame(width: 8, height: 8)
                    Text(HealthText.level(row.level, locale))
                        .font(.nino(.callout).weight(.semibold))
                        .foregroundStyle(HealthText.levelColor(row.level))
                }
                Text(row.value)
                    .font(.nino(.callout))
                    .foregroundStyle(NinoColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if row.level.needsAction, let advice = row.advice {
                    Text(advice).font(.nino(.callout)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, NinoSpacing.m)
        .accessibilityElement(children: .combine)
    }
}

struct LocalNetworkWarning: View {
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: NinoSpacing.s) {
            Label { ShText("sheets.health.localNetwork").fixedSize(horizontal: false, vertical: true) } icon: {
                Image(systemName: NinoSymbol.errorFill)
            }
            .font(.nino(.callout).weight(.semibold))
            .foregroundStyle(NinoColor.warning)
            Button {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                ShText("sheets.health.openSystemSettings")
            }
            .buttonStyle(.nino(.secondary))
        }
        .padding(.bottom, NinoSpacing.m)
        .padding(.leading, 24 + NinoSpacing.m)
    }
}

// MARK: - Son sorunlar

struct HealthProblemsCard: View {
    let state: AppState
    @Environment(\.locale) private var locale

    var body: some View {
        let problems = Array(state.sheetsStatus.problems.sorted { $0.date > $1.date }.prefix(8))
        if !problems.isEmpty {
            NinoCard(title: SheetsText.string("sheets.health.recentProblems", locale)) {
                VStack(alignment: .leading, spacing: NinoSpacing.s) {
                    ForEach(problems) { problem in
                        HStack(alignment: .firstTextBaseline, spacing: NinoSpacing.m) {
                            Text(problem.date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened)
                                .locale(locale)))
                                .font(.nino(.callout))
                                .foregroundStyle(NinoColor.textSecondary)
                                .frame(width: 150, alignment: .leading)
                            Text(HealthText.problem(problem.kind, locale)).font(.nino(.callout))
                        }
                    }
                }
                NinoHint(SheetsText.string(state.settings.autoReport ? "sheets.health.autoOn" : "sheets.health.autoOff",
                                           locale))
            }
        }
    }
}

// MARK: - Cihaz bilgileri

struct DeviceInfoCard: View {
    let state: AppState
    @Environment(\.locale) private var locale

    var body: some View {
        let info = DeviceInfo.make(state: state, facts: state.sheetsStatus.deviceFacts, tvApp: state.sheetsStatus.tvApp)
        NinoCard(title: SheetsText.string("sheets.device.title", locale)) {
            VStack(alignment: .leading, spacing: NinoSpacing.s) {
                ForEach(info.rows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: NinoSpacing.m) {
                        ShText(row.labelKey)
                            .font(.nino(.callout))
                            .foregroundStyle(NinoColor.textSecondary)
                            .frame(width: 150, alignment: .leading)
                        Text(verbatim: row.value)
                            .font(.nino(.callout))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            CopyFeedbackButton(titleKey: "sheets.device.copy", copiedKey: "sheets.common.copied") { info.summary }
            NinoHint(SheetsText.string("sheets.device.hint", locale))
        }
    }
}

// MARK: - Ayrıntılar

struct HealthDetailsCard: View {
    let state: AppState
    let metrics: HealthMetrics
    @State private var expanded = false
    @State private var copyID = 0
    @State private var saveError: String?
    @Environment(\.locale) private var locale

    var body: some View {
        NinoCard {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { expanded.toggle() }
                copyID += 1
                saveError = nil
            } label: {
                HStack {
                    ShText("sheets.health.details").font(.nino(.headline))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .foregroundStyle(NinoColor.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                let text = details
                SheetScroll {
                    Text(verbatim: text)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(NinoSpacing.s)
                }
                .frame(height: 260)
                .background(NinoRadius.shape(NinoRadius.inner).fill(NinoColor.surface2))
                HStack(spacing: NinoSpacing.m) {
                    CopyFeedbackButton(titleKey: "sheets.health.copyDetails", copiedKey: "sheets.common.copied") { text }
                        .id(copyID)
                    Button {
                        Task { await saveZip(text) }
                    } label: {
                        ShText("sheets.health.saveZip")
                    }
                    .buttonStyle(.nino(.secondary))
                }
                if let saveError { NinoErrorLabel(saveError) }
                NinoHint(SheetsText.string("sheets.health.zipHint", locale))
            }
        }
    }

    private var details: String {
        let s = state.sheetsStatus
        if let folder = s.dataFolder {
            return DetailsText.make(state: state, facts: s.deviceFacts, metrics: metrics, tvApp: s.tvApp, folder: folder)
        }
        let none = DataFolder(support: URL(fileURLWithPath: "/nonexistent"), logs: URL(fileURLWithPath: "/nonexistent"))
        return DetailsText.make(state: state, facts: s.deviceFacts, metrics: metrics, tvApp: s.tvApp, folder: none)
    }

    private func saveZip(_ text: String) async {
        saveError = nil
        guard let engine = state.engine else { return }
        do {
            let url = try await engine.saveLogsZip(details: text)
            if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        } catch {
            saveError = SheetsText.string("sheets.health.zipError", locale) + " (\(error.localizedDescription))"
        }
    }
}
