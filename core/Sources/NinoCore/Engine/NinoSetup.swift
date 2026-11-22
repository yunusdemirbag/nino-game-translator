// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Ayarlardan çalışır bir Nino kurar. Uygulamaların tek giriş noktası.
public enum NinoSetup {
    /// Ayarlara göre motoru kurar: veri klasörü, diskteki önbellek, seçili oyunun
    /// paketi, çevirmen zinciri (anahtarlar Keychain'den) ve okuma hattı.
    public static func makeEngine(settings: NinoSettings,
                                  directories: NinoDirectories,
                                  secrets: SecretStore,
                                  recognizer: TextRecognizer? = defaultRecognizer(),
                                  output: SubtitleOutput? = nil,
                                  session: URLSession = .shared,
                                  onDevice: TranslationProvider? = makeOnDeviceTranslationProvider()) throws -> NinoEngine {
        try directories.prepare()
        let cache = TranslationCache(fileURL: directories.translationCacheFile)
        let library = PackLibrary(directory: directories.packsDirectory)
        let pack = settings.translation.selectedGameID.flatMap { library.pack(for: $0) }
        let timeout = max(0.5, settings.translation.providerTimeoutSeconds)
        let chain = ProviderChain(providers: settings.makeProviders(secrets: secrets, session: session, onDevice: onDevice),
                                  timeout: .milliseconds(Int(timeout * 1000)))
        let translator = Translator(cache: cache, chain: chain, pack: pack,
                                    userTerms: settings.translation.userTerms,
                                    sourceLanguage: settings.translation.sourceLanguage,
                                    targetLanguage: settings.translation.targetLanguage)
        let pipeline = ReadingPipeline(recognizer: recognizer, configuration: settings.readingConfiguration)
        return NinoEngine(pipeline: pipeline, translator: translator, output: output,
                          options: .init(position: settings.display.position))
    }

    /// Bu platformun varsayılan OCR okuyucusu.
    public static func defaultRecognizer() -> TextRecognizer? {
        #if canImport(Vision)
        return VisionTextRecognizer()
        #else
        return nil
        #endif
    }

    /// Bulunanlar arasından seçer: son bağlanılan TV hemen seçilir; süre dolarsa
    /// görülen ilk uyumlu TV seçilir.
    static func pickDisplay(_ stream: AsyncStream<[DiscoveredDisplay]>, lastID: String?,
                            timeout: TimeInterval) async -> DiscoveredDisplay? {
        let seen = Recent<DiscoveredDisplay>()
        let search = Task { () -> DiscoveredDisplay? in
            for await list in stream {
                let usable = list.filter(\.isCompatible)
                if let match = usable.first(where: { $0.id != nil && $0.id == lastID }) { return match }
                if lastID == nil, let first = usable.first { return first }
                if let first = usable.first { seen.set(first) }
            }
            return nil
        }
        let timer = Task {
            try? await Task.sleep(for: .milliseconds(Int(timeout * 1000)))
            search.cancel()
        }
        defer { timer.cancel() }
        return await search.value ?? seen.get()
    }

    public enum DisplayError: Error, Equatable { case notFound }

    /// TV'ye bağlanır: ayarda adres varsa ona, yoksa ağda arar (önce son
    /// bağlanılan TV). Bağlanınca canlı tutmayı başlatır.
    public static func connectDisplay(settings: NinoSettings, device: String? = nil,
                                      searchTimeout: TimeInterval = 5) async throws -> NinoSender {
        var host = settings.display.host
        var port = settings.display.port
        if host == nil, settings.display.autoDiscover {
            let browser = NinoBrowser()
            defer { browser.stop() }
            let found = await pickDisplay(browser.displays(), lastID: settings.display.lastDisplayID, timeout: searchTimeout)
            if let found {
                let resolved = try await NinoBrowser.resolve(found.endpoint)
                host = resolved.host
                port = resolved.port
            }
        }
        guard let host else { throw DisplayError.notFound }
        let sender = NinoSender(host: host, port: port, device: device, client: "nino-core/\(NinoCore.version)")
        try await sender.connect()
        await sender.startKeepAlive()
        return sender
    }
}

final class Recent<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T?
    func set(_ v: T) { lock.withLock { if value == nil { value = v } } }
    func get() -> T? { lock.withLock { value } }
}
