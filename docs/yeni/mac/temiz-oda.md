# Temiz oda denetimi (Mac)

Denetim: eski `mac/`, `core/`, `remoteplay/`, `nino-ios/` Swift dosyalarıyla `apps/mac/` arasında birebir aynı olan
≥45 karakterlik satırlar (boşluklar teklenir; yorum ve `import` satırları sayılmaz). Eski dosyalar açılmadı; yalnız
betiğin yazdırdığı tek satırlara bakıldı.

Son çalıştırma: 22 Kasım 2026. İlk çalıştırmada 262 ortak satır vardı; projeye özgü ad ya da formül taşıyanlar davranış
değişmeden yeniden yazıldı. Kalan 171 satır.

## Kalanlar: yalnız Apple / Swift API kalıpları

Bunlar SwiftUI, AppKit, AVFoundation, ScreenCaptureKit, WebKit, CoreGraphics, POSIX soket, URLSession, Sparkle
temsilcisi ve XCTest çağrılarının olağan yazımıdır (ör. `.frame(maxWidth: .infinity, alignment: .leading)`,
`FileManager.default.urls(...)`, `Task.sleep(for:)`, `RoundedRectangle(cornerRadius:style:)`). Bilerek dokunulmadı.
Yer: ilk eşleşen yeni dosya ve satır (aynı satır başka yerde de geçiyorsa sayısı parantezde).

| Yer | Satır |
|---|---|
| `App/SparkleAutoUpdater.swift:57` | `immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {` |
| `AppIdentity.swift:42` | `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]` |
| `AppIdentity.swift:47` | `FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]` |
| `AppSupport/DebugFrames.swift:125` | `Task.detached(priority: .utility) { [weak self] in` |
| `AppSupport/DebugFrames.swift:198` (×2) | `CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)` |
| `AppSupport/DebugFrames.swift:205` (×2) | `guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,` |
| `AppSupport/DebugFrames.swift:207` | `bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }` |
| `AppSupport/NinoAppSupport.swift:118` | `try? await Task.sleep(for: .milliseconds(500))` |
| `AppSupport/NinoAppSupport.swift:138` | `try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)` |
| `AppSupport/OCRHelper.swift:50` | `bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }` |
| `AppSupport/OCRHelper.swift:60` | `return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,` |
| `AppSupport/OCRHelper.swift:62` | `provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)` |
| `AppSupport/OCRHelper.swift:438` (×2) | `process.standardError = FileHandle.nullDevice` |
| `Capture/CaptureCoordinator.swift:34` | `let home = FileManager.default.homeDirectoryForCurrentUser` |
| `Capture/CaptureCoordinator.swift:223` | `for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {` |
| `Capture/CardCapture.swift:37` (×2) | `private var observers: [NSObjectProtocol] = []` |
| `Capture/CardCapture.swift:105` (×2) | `if session.isRunning { session.stopRunning() }` |
| `Capture/CardCapture.swift:130` | `switch AVCaptureDevice.authorizationStatus(for: type) {` |
| `Capture/CardCapture.swift:161` | `kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,` |
| `Capture/CardCapture.swift:181` (×3) | `let now = ProcessInfo.processInfo.systemUptime` |
| `Capture/CardGameWindow.swift:154` | `func windowWillClose(_ notification: Notification) {` |
| `Capture/CardGameWindow.swift:174` | `for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {` |
| `Capture/Greenlight.swift:72` | `guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],` |
| `Capture/Greenlight.swift:133` | `return hasher.finalize().map { String(format: "%02x", $0) }.joined()` |
| `Capture/Greenlight.swift:150` (×3) | `defer { try? FileManager.default.removeItem(at: file) }` |
| `Capture/Greenlight.swift:191` | `request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")` |
| `Capture/Greenlight.swift:193` | `let (data, response) = try await URLSession.shared.data(for: request)` |
| `Capture/Greenlight.swift:202` | `try await withCheckedThrowingContinuation { continuation in` |
| `Capture/Greenlight.swift:227` | `func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,` |
| `Capture/Greenlight.swift:228` | `totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {` |
| `Capture/Greenlight.swift:232` | `func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {` |
| `Capture/Greenlight.swift:246` (×2) | `func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {` |
| `Capture/Greenlight.swift:253` | `try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)` |
| `Capture/Greenlight.swift:267` | `process.executableURL = URL(fileURLWithPath: tool)` |
| `Capture/Greenlight.swift:269` | `process.standardOutput = FileHandle.nullDevice` |
| `Capture/Greenlight.swift:271` | `return try await withCheckedThrowingContinuation { continuation in` |
| `Capture/PixelCopy.swift:20` | `guard width > 0, height > 0 else { return nil }` |
| `Capture/PixelCopy.swift:24` | `guard let provider = CGDataProvider(data: data as CFData) else { return nil }` |
| `Capture/WindowCapture.swift:247` | `let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,` |
| `Console/PSNAuth.swift:51` | `let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,` |
| `Console/PSNAuth.swift:144` | `return withUnsafeBytes(of: value.littleEndian) { Data($0) }` |
| `Console/PSNLoginView.swift:149` | `view.navigationDelegate = context.coordinator` |
| `Console/PSNLoginView.swift:162` | `final class Coordinator: NSObject, WKNavigationDelegate {` |
| `Console/PSNLoginView.swift:182` | `func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {` |
| `Console/PSNLoginView.swift:186` | `func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {` |
| `NinoScenes.swift:72` | `.toolbarBackground(.hidden, for: .windowToolbar)` |
| `NinoScenes.swift:152` | `.keyboardShortcut("f", modifiers: [.control, .command])` |
| `Services/HistoryStore.swift:90` (×2) | `formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]` |
| `Services/NetworkClient.swift:30` (×2) | `let (data, response) = try await session.data(for: request)` |
| `Services/NetworkClient.swift:75` (×2) | `let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)` |
| `Services/PhotoAttachment.swift:38` | `let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0` |
| `Services/PhotoAttachment.swift:57` | `kCGImageSourceCreateThumbnailFromImageAlways: true,` |
| `Services/PhotoAttachment.swift:58` | `kCGImageSourceCreateThumbnailWithTransform: true,` |
| `Services/PhotoAttachment.swift:82` | `let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)` |
| `Services/PhotoAttachment.swift:95` | `guard CGImageDestinationFinalize(dest) else { return nil }` |
| `Services/ReportService.swift:120` (×3) | `request.setValue("application/json", forHTTPHeaderField: "Content-Type")` |
| `Services/ReportService.swift:207` (×2) | `try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)` |
| `Services/SupportInfo.swift:46` | `var buffer = [CChar](repeating: 0, count: size)` |
| `Services/SupportInfo.swift:47` | `guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }` |
| `Services/SupportInfo.swift:265` | `formatter.formatOptions = [.withInternetDateTime]` |
| `Session/LocalNetworkProbe.swift:70` | `setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))` |
| `Session/LocalNetworkProbe.swift:71` | `var buffer = [UInt8](repeating: 0, count: 2048)` |
| `Storage/RotatingLog.swift:28` | `formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"` |
| `Storage/RotatingLog.swift:89` | `.map { $0.trimmingCharacters(in: .whitespaces) }` |
| `TVSetup/TVBasics.swift:110` | `let stem = (name as NSString).deletingPathExtension` |
| `TVSetup/TVLiveTransports.swift:75` (×3) | `let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)` |
| `TVSetup/TVLiveTransports.swift:78` | `setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))` |
| `TVSetup/TVLiveTransports.swift:104` | `$0.withMemoryRebound(to: sockaddr.self, capacity: 1) {` |
| `TVSetup/TVLiveTransports.swift:126` | `var buffer = [UInt8](repeating: 0, count: 4096)` |
| `TVSetup/TVLiveTransports.swift:184` | `$0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }` |
| `TVSetup/TVPorts.swift:193` (×3) | `formatter.locale = Locale(identifier: "en_US_POSIX")` |
| `TVSetup/TVSetupController.swift:657` | `guard !Task.isCancelled, let self else { return }` |
| `Tests/AppSupportTests.swift:191` (×2) | `defer { try? FileManager.default.removeItem(at: dir) }` |
| `Tests/AppSupportTests.swift:332` (×4) | `space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!` |
| `Tests/HomeSnapshotTests.swift:256` (×40) | `.fixedSize(horizontal: false, vertical: true)` |
| `Tests/HomeSnapshotTests.swift:299` (×8) | `.frame(maxWidth: .infinity, maxHeight: .infinity)` |
| `Tests/LocalizationTests.swift:22` | `.sorted { $0.lastPathComponent < $1.lastPathComponent }` |
| `Tests/SessionOverlaysTests.swift:55` | `let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,` |
| `Tests/SheetsSnapshotTests.swift:187` (×11) | `.frame(width: size.width, height: size.height)` |
| `Tests/SheetsSnapshotTests.swift:195` (×4) | `let tiff = try XCTUnwrap(image.tiffRepresentation)` |
| `Tests/SheetsSnapshotTests.swift:196` (×4) | `let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))` |
| `Tests/SheetsSnapshotTests.swift:198` (×4) | `try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)` |
| `Tests/TVHelperADBTests.swift:664` | `try await Task.sleep(nanoseconds: 300_000_000)` |
| `UI/Design/NinoButtons.swift:78` | `.animation(.easeOut(duration: 0.12), value: pressed)` |
| `UI/Design/NinoL10n.swift:19` | `let code = locale.language.languageCode?.identifier ?? "en"` |
| `UI/Design/NinoTiles.swift:240` | `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)` |
| `UI/Design/NinoTiles.swift:272` | `startPoint: .top, endPoint: .bottom), lineWidth: 1))` |
| `UI/Design/NinoTiles.swift:308` | `.font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())` |
| `UI/Home/AskNinoButton.swift:30` | `.background(Circle().fill(Color.white.opacity(0.92)))` |
| `UI/Home/AskNinoButton.swift:48` | `.background(Capsule().fill(Color.black.opacity(0.55)))` |
| `UI/Home/AskNinoButton.swift:50` | `.transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity),` |
| `UI/Home/HomeView.swift:46` | `.transition(.move(edge: .trailing).combined(with: .opacity))` |
| `UI/Home/LivingRoom/LivingRoomParts.swift:78` (×2) | `RoundedRectangle(cornerRadius: 16, style: .continuous)` |
| `UI/Home/LivingRoom/LivingRoomParts.swift:83` | `RoundedRectangle(cornerRadius: 12, style: .continuous)` |
| `UI/Home/LivingRoom/LivingRoomParts.swift:144` | `.shadow(color: .black.opacity(0.25), radius: 3, y: 2)` |
| `UI/Home/LivingRoom/LivingRoomParts.swift:146` | `RoundedRectangle(cornerRadius: 3, style: .continuous)` |
| `UI/Home/LivingRoom/LivingRoomParts.swift:173` | `.shadow(color: .black.opacity(0.45), radius: 6, y: 4)` |
| `UI/Home/LivingRoom/LivingRoomParts.swift:188` | `RoundedRectangle(cornerRadius: 5, style: .continuous)` |
| `UI/Home/LivingRoom/LivingRoomParts.swift:191` | `RoundedRectangle(cornerRadius: 9, style: .continuous)` |
| `UI/Home/LivingRoom/LivingRoomParts.swift:203` | `.shadow(color: .black.opacity(0.3), radius: 4, y: 3)` |
| `UI/Home/LivingRoom/TVScreenContent.swift:23` | `.background(Capsule().fill(Color.black.opacity(0.4)))` |
| `UI/Home/LivingRoom/TVScreenContent.swift:49` | `.transition(.opacity.combined(with: .offset(y: 6)))` |
| `UI/Home/LivingRoom/TVScreenContent.swift:113` | `try? await Task.sleep(for: .milliseconds(280))` |
| `UI/Home/LivingRoom/TVScreenContent.swift:126` | `try? await Task.sleep(for: .milliseconds(260))` |
| `UI/Home/LivingRoom/TVScreenContent.swift:176` | `guard let image = NSImage(contentsOf: url) else { continue }` |
| `UI/Home/LivingRoom/TVScreenContent.swift:224` | `.font(.system(size: 13, weight: .semibold, design: .monospaced))` |
| `UI/Home/SplashView.swift:75` | `RoundedRectangle(cornerRadius: 8, style: .continuous)` |
| `UI/Home/SplashView.swift:81` | `RoundedRectangle(cornerRadius: 6, style: .continuous)` |
| `UI/Home/SplashView.swift:89` | `.clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))` |
| `UI/Home/SplashView.swift:99` | `try? await Task.sleep(for: .milliseconds(900))` |
| `UI/Home/SplashView.swift:105` | `try? await Task.sleep(for: .milliseconds(650))` |
| `UI/Home/SplashView.swift:118` | `try? await Task.sleep(for: .milliseconds(1700))` |
| `UI/Home/SplashView.swift:120` | `try? await Task.sleep(for: .milliseconds(450))` |
| `UI/Home/Subtitles/StreamWindow.swift:69` | `func makeNSView(context: Context) -> NSView {` |
| `UI/Home/Subtitles/StreamWindow.swift:73` | `window.contentAspectRatio = NSSize(width: 16, height: 9)` |
| `UI/Home/Subtitles/StreamWindow.swift:74` | `window.contentMinSize = NSSize(width: 480, height: 270)` |
| `UI/Home/Subtitles/SubtitleOverlayWindow.swift:20` | `override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }` |
| `UI/Home/Subtitles/SubtitleOverlayWindow.swift:90` | `panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]` |
| `UI/Home/Subtitles/SubtitleOverlayWindow.swift:112` | `NSScreen.screens.contains { $0.frame.intersects(frame) }` |
| `UI/Home/Subtitles/SubtitleOverlayWindow.swift:229` | `DragGesture(minimumDistance: 0, coordinateSpace: .global)` |
| `UI/Home/Subtitles/SubtitleOverlayWindow.swift:282` | `if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }` |
| `UI/Home/Toggle/GlassSwitch.swift:80` | `.frame(maxWidth: .infinity, alignment: .trailing)` |
| `UI/Home/Toggle/GlassSwitch.swift:161` | `startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2)` |
| `UI/Home/Toggle/ToggleHome.swift:50` | `.transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.94)))` |
| `UI/Home/Toggle/ToggleHome.swift:99` (×11) | `.environment(\.layoutDirection, .leftToRight)` |
| `UI/Settings/AppearanceSettings.swift:81` | `.font(.system(size: fontSize, weight: .medium))` |
| `UI/Settings/AppearanceSettings.swift:107` (×2) | `.background(Capsule().fill(Color.black.opacity(0.45)))` |
| `UI/Settings/AppearanceSettings.swift:142` (×5) | `startPoint: .topLeading, endPoint: .bottomTrailing)` |
| `UI/Settings/ConnectionSettings.swift:205` (×2) | `.background(Capsule().fill(Color.black.opacity(0.5)))` |
| `UI/Settings/ConnectionSettings.swift:218` | `if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {` |
| `UI/Settings/HiddenSettings.swift:104` | `.background(RoundedRectangle(cornerRadius: 12, style: .continuous)` |
| `UI/Settings/HiddenSettings.swift:106` | `startPoint: .topLeading, endPoint: .bottomTrailing)))` |
| `UI/Settings/HiddenSettings.swift:289` (×2) | `.frame(width: rect.width, height: rect.height)` |
| `UI/Settings/OBSSettings.swift:91` | `Image(systemName: selected ? "checkmark.circle.fill" : "circle")` |
| `UI/Settings/SettingsControls.swift:58` | `func makeBody(configuration: Configuration) -> some View {` |
| `UI/Settings/SettingsControls.swift:65` (×3) | `@Environment(\.isEnabled) private var isEnabled` |
| `UI/Settings/SettingsControls.swift:66` (×18) | `@Environment(\.colorScheme) private var scheme` |
| `UI/Settings/SettingsControls.swift:90` | `.shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)` |
| `UI/Settings/SettingsControls.swift:171` | `.accessibilityValue(Text(verbatim: "\(Int(value * 100))%"))` |
| `UI/Settings/SettingsControls.swift:387` (×5) | `.accessibilityAddTraits(selected ? .isSelected : [])` |
| `UI/Settings/SettingsControls.swift:409` | `NSPasteboard.general.setString(address, forType: .string)` |
| `UI/Settings/SettingsView.swift:127` (×22) | `@Environment(\.accessibilityReduceMotion) private var reduceMotion` |
| `UI/Settings/SettingsView.swift:433` (×24) | `.frame(maxWidth: .infinity, alignment: .leading)` |
| `UI/Setup/CaptureCardGuide.swift:193` | `.background(RoundedRectangle(cornerRadius: 8, style: .continuous)` |
| `UI/Setup/ConsolePairStep.swift:249` | `.font(.system(size: 22, weight: .bold, design: .rounded))` |
| `UI/Setup/ConsolePairStep.swift:272` | `.font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())` |
| `UI/Setup/SetupParts.swift:155` | `.background(Capsule().fill(Color.white.opacity(0.06)))` |
| `UI/Setup/SetupParts.swift:233` | `.background(Capsule().fill(Color.white.opacity(0.08)))` |
| `UI/Setup/SetupView.swift:127` (×2) | `.transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),` |
| `UI/Setup/SetupView.swift:128` (×2) | `removal: .move(edge: .leading).combined(with: .opacity)))` |
| `UI/Setup/TestAndTranslationSteps.swift:43` | `.animation(.easeOut(duration: 0.3), value: line)` |
| `UI/Setup/XboxConnectList.swift:96` | `Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)` |
| `UI/Setup/XboxConnectList.swift:99` | `.font(.system(size: 13, weight: .bold, design: .rounded))` |
| `UI/Sheets/AskNinoSheet.swift:386` | `.font(.system(size: 12, weight: .bold, design: .rounded))` |
| `UI/Sheets/HealthSheet.swift:280` | `.font(.system(size: 11, design: .monospaced))` |
| `UI/Sheets/NinoBotViews.swift:94` | `func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {` |
| `UI/Sheets/NinoBotViews.swift:101` | `func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {` |
| `UI/Sheets/SheetParts.swift:167` | `NSPasteboard.general.setString(text, forType: .string)` |
| `UI/Sheets/SheetParts.swift:217` (×2) | `await Task.detached(priority: .userInitiated) {` |
| `UI/Sheets/SheetParts.swift:258` (×2) | `await withCheckedContinuation { continuation in` |

## Başka ajanın dosyaları (dokunulmadı)

`TVSetup/Helper/Samsung/` ve Samsung testleri o sırada başka bir ajanın işindeydi; bu satırlar ona bırakıldı
(satırın bir kopyası orada). Çoğu API kalıbı; `SamsungLogin` `Failure` bildirimi ve `SamsungOutputs` "TV yanıt vermedi"
satırı projeye özgü görünüyor: Samsung işini yapan ajanın yeniden yazması önerilir.

| Yer | Satır |
|---|---|
| `Capture/Greenlight.swift:201` (×6) | `return try await withTaskCancellationHandler {` |
| `TVSetup/Helper/AndroidTVInstaller.swift:104` (×3) | `.trimmingCharacters(in: .whitespacesAndNewlines)` |
| `TVSetup/Helper/Samsung/SamsungDER.swift:51` | `let parts = dotted.split(separator: ".").compactMap { UInt64($0) }` |
| `TVSetup/Helper/Samsung/SamsungLogin.swift:35` | `public enum Failure: Error, Equatable, Sendable {` |
| `TVSetup/Helper/Samsung/SamsungLogin.swift:54` | `let lines = head.components(separatedBy: "\r\n")` |
| `TVSetup/Helper/Samsung/SamsungOutputs.swift:143` | `if lines.isEmpty { return "TV yanıt vermedi" }` |
| `Tests/SamsungInstallTests.swift:199` | `try await Task.sleep(nanoseconds: 100_000_000)` |
| `Tests/SamsungTestSupport.swift:194` (×3) | `$0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }` |
| `Tests/SamsungTestSupport.swift:406` | `try await Task.sleep(nanoseconds: 20_000_000)` |
| `Tests/TVHelperADBTests.swift:53` (×3) | `let deadline = Date().addingTimeInterval(timeout)` |
| `Tests/TVSetupPartsTests.swift:33` (×5) | `try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)` |

## Eski veri ve test dizgeleri taraması

Karar: eski yazarın `glossary-en-tr.json`, `golden-vectors.json`, `fuzzy-vectors.json`, `pack-matches.json` dosyaları
yeni kodda yok. Betik `scripts/temiz-oda-tarama.py` bu dört dosyanın değerleriyle ve eski testlerin (`core/Tests`,
`mac/NinoTests`) ≥20 karakterlik dizgeleriyle NinoCore (`Sources`, `Tests`, `docs/tarif`), NinoMacKit ve
`docs/yeni/mac` arasındaki ≥12 karakterlik ortak değerleri sayar. Sözlük girişleri kısa da olsa sayılır; çok sözcüklü ya
da uzun girişler büyük/küçük harf duyarsız, sözcük sınırıyla aranır. Eski dosyalar yalnız karşılaştırma için okunur; bu
bölüm değer değil, yalnız sayı verir.

Son çalıştırma: 22 Kasım 2026. İlk çalıştırmada yaklaşık 990 eşleşme vardı (sözlük 152, altın vektör 55, bulanık 27,
paket 8, eski test cümlesi ~520, gerisi genel). Yapılanlar:

- Gömülü sözlük (`BuiltinGlossary`) baştan yazıldı: kendi seçtiğimiz 10 terim, `keep` 2, `keepExact` 1, 9 argo kuralı,
  15 hazır satır. Eski sözlükle hiçbir giriş ortak değil (her giriş ayrıca eski dosyaya karşı tek tek denetlendi).
- Oyun deyimleri (`GameIdioms`), uydurma ad listesi (`NameShield`) ve yapay zekâ isteğindeki örnek etiket de kendi
  seçimimiz (bunlar eski kaynaktan tarifle gelmişti).
- Satır anahtarı vektörleri kendi cümlelerimiz; beklenen anahtarlar havuz sunucusunun `nino-pool/src/key.js` koduyla
  node'da hesaplandı, Swift `LineKey` hepsinde aynı.
- Bulanık eşleme ve paket eşleme testleri kendi cümlelerimiz ve kendi ürettiğimiz OCR bozulmalarıyla (I→l, rn→m,
  5→s, 1→i, boşluk kaybı); beklenenler tarif kurallarından bağımsız hesaplandı. Gerçek eski paket satırını sınayan iki
  isteğe bağlı test cümleyi artık `NINO_LEGACY_PACK_LINE` ortam değişkeninden alır (verilmezse o denetim atlanır).
- Okuma hattı, telefon, çevirmen ve havuz testlerindeki, tariflerdeki örnek cümleler kendi cümlelerimizle değişti.
  Tariflerdeki eski arayüz metinleri çıkarıldı: yerlerinde yeni uygulamanın metin anahtarı ve yeni EN/TR metni,
  karşılığı olmayanlarda kısa bir açıklama var; eski kod yollarına göndermeler de kalktı. Belgelerin önceki hâli
  depo dışında arşivde. Eski `Localizable.xcstrings`'in ≥20 karakterlik EN/TR değerleriyle (boşluk birleştirilerek)
  `docs/yeni/mac` arasında ortak değer kalmadı.

Kalan (farklı değer / yer):

| Kategori | Sayı | Durum |
|---|---|---|
| Dört eski veri dosyası (sözlük, vektörler) | 0 / 0 | temiz |
| Eski test örnek cümleleri | 0 / 0 | temiz |
| GTA 6 oyun metni (telefon mesajları, harita kartları; oyunun kendi metni) | 19 / 46 | karar gereği kalır. 7'si `.lines.txt`'te, bir kısmı ekran karelerinde gözle doğrulandı; doğrulanamayan okuma örnekleri değiştirildi |
| Genel: oyun adları ve kimlikleri, paket kimlikleri, adresler, model adları, HTTP başlıkları, kod kalıpları, `checkpoint`/`cooldown` gibi sıradan sözcükler | 78 / 297 | bilerek dokunulmadı |
| Arayüz metinleri (`.xcstrings` ve tariflerdeki arayüz tabloları) | 0 / 0 | temiz |
| Yeni `.xcstrings` değerlerinden eski `Localizable.xcstrings` (anahtar + EN + TR) ile birebir aynı kalanlar (≥12 karakter, boşluk birleştirilerek; ayrı karşılaştırma) | 4 anahtar / 8 değer (önce 419 / 619) | temiz: 610 EN/TR değeri aynı anlamla yeniden yazıldı, yer tutucular aynı. Kalan 8 değer yalnız ad ya da cihazdaki menü yolu: `Capture card`/`Capture Card` (2 anahtar) ve PS5 menü yolları `setup.ps5.step1.path`, `setup.ps5.step2.path` (EN/TR). Diğer 10 dilin anlamı değişmedi |

Not: tarama birebir kopyayı bulur. İkinci geçişte eklenen satırlarda eski dizgelerle ortak 4 sözcüklük diziler
arandı; kalanlar düğme ipuçları ve oyun adları gibi genel kalıplar.

## Swift dizge değişmezleri taraması (≥12 karakter)

Yeni Swift kodundaki (NinoMacKit ve NinoCore) ≥12 karakterlik dizge değişmezlerinden 200'ü eski kod dizgeleriyle ya da
eski `Localizable.xcstrings` metinleriyle birebir aynı çıktı. 72'si Nino'nun kendi yazdığı metindi ve aynı anlamla
yeniden yazıldı: Görünüm ayarlarındaki örnek altyazılar (EN/TR), admin şeridi, günlük ve durum satırları, Sorun Bildir
bulguları ve cihaz özeti etiketleri (`SupportInfo`), telefon sözlüğünün, menü satırlarının ve harita kartı terim
düzeltmelerinin Türkçe karşılıkları. Testler yeni metinlere uyarlandı.

### Olgu olarak kalanlar (128)

| Tür | Sayı |
|---|---|
| Oyun adları ve oyun adı eşleme kalıpları (`GameSuggestions`, `GameName`) | 39 |
| PS5 sistem bildirimleri (EN ve Türkçe PS5 arayüzü, `PoolFilter`) | 25 |
| GTA 6 oyun arayüzü metni: telefon uygulama yazıları ve kökleri, yayın adları, harita tuşları, menü sözcükleri, gelen arama | 35 |
| Çeviri motorunun yanlış çıktısını tanıyan terim kalıpları (harita kartı düzeltmesinin sol tarafı) | 8 |
| Marka ve platform adları (Nino Game Translator, Android TV / Google TV, Samsung Tizen, PlayStation Network) | 7 |
| Hakkında ekranındaki kişi adları, telif ve üçüncü taraf atıf satırları | 4 |
| Dil adları (kendi dillerinde) | 2 |
| Sistemden ve sunuculardan gelen, eşleşmesi gereken hata metinleri (TV, sağlayıcılar) | 6 |
| Dosya yolu ve tarih biçimi | 2 |

## Dört sözcüklük örtüşme taraması (EN/TR metinler ve Swift dizgeleri)

Yeni `.xcstrings` dosyalarındaki EN ve TR değerleriyle NinoMacKit ve NinoCore Swift dizge değişmezleri, eski
`Localizable.xcstrings` (anahtar + bütün diller) ile ardışık dört sözcük (küçük harf, `\w+`) ve birebir (≥12 karakter)
olarak karşılaştırıldı. Örtüşen 409 anahtardaki 692 EN/TR değeri (sonra ağ ve ikinci hesap terimleri tek karşılıkta birleştirildi) ve 10 Swift dizgesi (günlük satırları, sahte cevap,
güç uyarısı adı) aynı anlamla yeniden yazıldı; yer tutucular aynı, diğer 10 dile dokunulmadı. İki test yeni metne uyarlandı.

Bir dörtlü yalnız bütün sözcükleri aşağıdaki olgulardan geliyorsa sayılmadı. Kalan istisna: **94** (86 metin değeri,
8 Swift dizgesi). Hepsi şu türlerden:

| Tür | Örnekler |
|---|---|
| macOS menü yolları (EN/TR) | System Settings › Privacy & Security › Local Network / Camera / Screen Recording; General › Language & Region › Translation Languages |
| PS5 menü yolları ve ayar adları | Settings › System › Remote Play › Pair Device, Enable Remote Play, Settings › Network › Connection Status, Stay connected to the internet, PS button › profile picture › Switch User (EN/TR) |
| TV menüleri ve TV'nin kendi yazıları | Samsung Host PC IP, Developer Mode, External Device Manager, System Manager › Time, Reset Smart Hub; Android TV Device Preferences › About, "Always allow from this computer"; LG webostv.developer.lge.com; Xbox Devices & connections › Remote features, xbox.com/play › My consoles |
| Sabit kod ve adresler | Samsung geliştirici kodu 1 2 3 4 5, 127.0.0.1, remoteplay.dl.playstation.net adresleri |
| Marka ve ürün adları | PS Remote Play / chiaki-ng, Android TV / Google TV, PlayStation Network, Xbox Series X\|S, 5 GHz Wi-Fi, Sony Interactive Entertainment Inc., GNU AGPL-3.0, Gemini / ChatGPT / Claude / DeepL, TikTok LIVE Studio / Streamlabs |
| PS5 sistem bildirimi kalıbı | `PoolFilter` içindeki "press the ps button" (eşleşmesi gereken PS5 metni) |

Not: PS5'in Türkçe menü adı metinlerde önce iki yazımla geçiyordu ("Uzaktan Oynama" / "Uzaktan Oynatma"). Terim
eşitleme turunda çoğunluktaki "Uzaktan Oynatma"ya birleştirildi. Bu seçim sayıya göre yapıldı, cihazda doğrulanmadı.

## On dilde yeniden yazım ve terim eşitleme (ar, bn, fil, hi, id, ms, nl, th, ur, vi)

Eski katalogla örtüşen değerler bu on dilde güncel EN/TR anlamıyla yeniden yazıldı: Sheets/Home/AppSupport **1757**,
Settings/Capture/Console **1910**, Setup/TVSetup **2184** değer. Tablolar paralel yazıldığı için ardından bir terim
eşitleme turu yapıldı (449 değer, 12 dil):

- Aynı kavramın etiketi her tabloda tek metin: Sistem durumu, Hata Bildir (EN'de de "Report an Issue"), Nino'ya Sor,
  Nino hakkında, Ayarlar (nl "Instellingen", ms "Tetapan"), Çeviri, TV için Nino uygulaması, altyazı penceresi,
  kamera izni ve capture card satırları.
- Atıflar etiketin güncel metnine bağlandı: "Ayarlar › Çeviri / Sıfırla / Bağlantı", Ücretsiz motor, Hata Bildir,
  Altyazı Penceresini Düzenle, Xbox'ı bağla, Ücretsiz Anahtar Oluştur, Kaydet ve Sına, Sayfayı Tekrar Aç, Devam.
- EN'deki "Get it from Settings › Picture source" olmayan bir indirme yerini gösteriyordu; Ayarlar'da Remote Play
  indirme düğmesi yok. Metin 12 dilde "Önce PS Remote Play'i kurun ya da Ayarlar › Bağlantı'dan başka bir görüntü
  kaynağı seçin" anlamına çevrildi.
- Terimler tek yazım: capture card (bn/hi Latin, id "kartu capture", ms "kad tangkap", nl "opnamekaart",
  vi "card ghi hình", tr "Capture Card"); TV bn'de "TV", hi ve ur'da yerel yazı (ur "Nino ٹی وی ایپ" dahil);
  bn'de "Mac"; bn/th "API key"; vi "app TV"; TR PS5 menüsü "Uzaktan Oynatma".
- Dış menü yolları her dilde tek biçim. macOS yolu ar, id, ms, nl, th ve vi'de yerel adla, bn, fil, hi ve ur'da
  İngilizce. PS5 yolları ve seçenek adları ar, id, nl ve vi'de yerel adla, öteki dillerde İngilizce.

Tarama notu: hi ve bn'de `\w+` bölmesi harf işaretlerinde (matra, virama) sözcüğü kesiyor, dörtlüler anlamsızlaşıyor.
Bu iki dilde sözcüğü bütün alan bölme (Devanagari ve Bengal harf işaretleri sözcüğe dahil) esas alındı. Tur sonunda
8 tablo × 12 dilin birleşik taramasında istisna dışı örtüşme **0** çıktı. Bu taramada olgu listesi şunlardan oluşuyor:
temel olgular, alanların `facts-<dil>` dosyaları ve bu turda eklenen **10 menü yolu olgusu** (14 değeri kapsıyor).
Alanların kendi betikleri (`\w+`, kendi olgu dosyaları) değiştirilen değerlerde iki tür bulgu veriyor: hi/bn bölme
yanlışları ve başka alanın olgu dosyasında duran yerel menü yolları. `setup.ps5.step2.path` (id, nl, vi) ve vi
`setup.ps5.step1.path` resmi PS5 yolu olduğu için eski katalogla birebir aynı; bunlar olgu olarak sayıldı.

Kalan olgu istisnaları yalnız menü yolları ve ürün adları. Bunlar macOS ve PS5 yolları ile seçenek adları
(ör. id "Pengaturan › Sistem › Remote Play › Pasangkan Perangkat", vi "Ghép nối thiết bị", ar "إقران الجهاز",
ms "Rakaman Skrin" yolu) ve Nino'nun kendi "Cài đặt › Kết nối" yolu. Yerel PS5 menü adları cihazda doğrulanmadı:
id PS5 ağ menüsü ("Pengaturan › Jaringan › Status Koneksi"), ar/id/vi "Hide Connection Status" ve "Switch User"
karşılıkları, ms macOS "Tetapan Sistem" adları ve tr "Uzaktan Oynatma".

Öneri: bu on dilin metinlerine, yayından önce o dili ana dili olarak konuşan biri baksın. Özellikle bn/hi'deki
Latin-yerel yazı karışımına (subtitle, translation sözcükleri) ve yerel PS5/macOS menü adlarına bakılmalı.

## Son tarama (Mac + NinoCore, 108 satır)

Tarayıcı: eski ağaç (`git archive cbc149d2`) ile `apps/mac` ve NinoCore arasında dört tür bulgu: 4GRAM (≥6 sözcüklük
metnin dörtlülerinin ≥%60'ı eski metinde), METIN (≥4 sözcüklük dizge birebir eski), YORUM, LISTE (eski koddan aynı
sözcük listesi satırı). NinoCore'un `.build-deps` klasörü (indirilen üçüncü taraf kaynak) taramaya girmez.
Son çalıştırma: 22 Kasım 2026. Düzeltmeden sonra yeniden çalıştırıldı: **59** satır kaldı, hepsi aşağıdaki DOKUNMA
tablosunda (olgu kümeleri satır düzeni değiştiği için artık bulgu vermiyor; TV kimliği düzeltmesinden sonra `appops` ve
yardımcı kullanım satırları da bulgu dışı kaldı, LG `appinfo.json` yolu yeni bulgu).

Bu bölüm, yukarıdaki bölümlerde `PoolFilter` için "olgu olarak kalan" diye sayılan PS5 bildirim öbeklerinin
yerine geçer: o liste artık kendi seçimimizdir.

### Yeniden yazılanlar (42 satır)

- **Arayüz metinleri:** `sheets.health.autoOn`, `sheets.health.cause.asleep.title`,
  `sheets.health.cause.elsewhere.action/.title`, `sheets.health.cause.pictureLossWired.title`,
  `sheets.report.nothingNoticed` (ar); `home.drop.network`, `home.splash.tagline` (nl);
  `settings.card.permissionTitle` ve `setup.card.check.cameraNeeded` (ur, ikisi aynı metin);
  `tv.install.error.notApproved` (bn). Anlam EN/TR ile aynı; EN/TR değişmedi.
- **Samsung kurulum günlüğü ve hata ayrıntıları** (`SamsungTVInstaller`): başlangıç satırı, LocalEndPoint satırı,
  DUID, giriş portu, 10 dakika zaman aşımı, hesapsız dönüş ve "sürüm hâlâ eski" iletileri; `SamsungLogin` giriş bitti
  sayfası. Testler (`SamsungInstallTests`) ve `tv-kurulumu.md` yeni metne uyarlandı.
- **Günlük:** `WindowCapture` Ekran Kaydı izni satırı (`kaynaklar.md` de).
- **Test cümleleri:** `DebugRecordTests`, `SheetsSnapshotTests`, `SetupSnapshotTests` (Mac); `ProvidersTextTests`
  hitap tablosu ve `LegacyPackTests` yarım okuma cümlesi (NinoCore). Hepsi kendi cümlelerimiz.
- **Belge:** `olcum.md` Google Play tablosunun başlık satırı.
- **Kendi seçimimizle yeniden derlenen listeler:**
  - `PoolFilter.turkishUIWords` ve `systemPhrases`: kuralın amacına göre (PS5 bildirimi ve Türkçe sistem arayüzü)
    kendi seçtiğimiz, konulara göre gruplanmış sözcükler. Eski listedeki bazı oyun içi ekran ve konsol kapatma
    öbekleri çıktı, yenileri girdi ("yukleniyor", "baglanti", "kupa kazandiniz" vb.). PS tuşu uyarısı için daha genel
    "ps button" öbeği var. Bilerek davranış farkı: bu süzgeç yalnız uygulamadaki ön süzgeçtir:
    havuz sunucusu satırı kendi süzgecinden yeniden geçirir, iki liste birebir aynı olmak zorunda değil.
  - `GameReading.Speaker.titleWords`: `AD:` biçiminde görünüp konuşan adı olmayan başlıklar; kendi gruplamamız ve
    eklerimiz (`bonus`, `score`, `unlocked`, `completed`, `failed`, `use`).

### Kalanlar (66 satır), hepsi bilerek

Olgu kümeleri: içerik dilin ya da donanımın kendisi, yazım türetildi (6 satır).

- `GameSimilarity.negations` (3 satır): İngilizce olumsuzluk sözcükleri ve `n't` kısaltmaları. Kısaltmalar artık
  yardımcı fiil + "n" + "t" diye türetilir; küme kapalıdır, başka üyesi yoktur.
- `GameReading.Speaker.abbreviations` (1): cümle bölücünün kısaltmaları (`SentenceSplitter.defaultAbbreviations`)
  ile rütbe kısaltmaları; İngilizcenin sabit kısaltmaları.
- `GameFilters.buttons` (1): DualSense tuş yazıları (L1–L3, R1–R3 türetilir, OPTIONS, TOUCHPAD).
- `LegacyPack.clauses` kapanış karakterleri (1): tırnak ve parantez kapanışları.

DOKUNMA türü (60 satır):

| Tür | Dosya | Neden zorunlu |
|---|---|---|
| Oyun adları (13) | `GameSuggestions.swift` (11), `SettingsSnapshotTests.swift`, NinoCore `LineKeyTests.swift` | oyunların resmi adı; tanıma ve öneri adla eşleşir |
| Cihaz ve üçüncü taraf program çıktıları (12) | `TVHelperADBTests.swift` (adb `INSTALL_FAILED_…`, `Unable to find package`), `SamsungOutputs.swift` (`connection reset by peer`, `same id and different certificate`), `SamsungInstallTests.swift` ve `SamsungTestSupport.swift` (sdb `capability` çıktısı, `sdk_toolpath`), NinoRemotePlay `ConsoleRegistration.swift` ve `RemotePlaySessionTests.swift` (Remote Play kayıt günlüğü `Reported Application Reason: …`, `timed out waiting for search response`), NinoCore `ProvidersNetworkTests.swift` (Google API `API key not valid`) | kodun eşleştirdiği dış programın kendi çıktısı; değişirse tanıma bozulur |
| Komutlar ve cihazdaki yollar (7) | `TVSetupControllerTests.swift`, `TVSetupPartsTests.swift` (`cat /media/developer/apps`, LG `rm -f /media/developer/temp/…`), `AndroidTVInstaller.swift` ve `TVHelperADBTests.swift` (`/data/local/tmp/nino-tv.apk`, `appops set … SYSTEM_ALERT_WINDOW allow`), `InProcessTVHelper.swift` (yardımcının komut satırı kullanımı: alt komut ve seçenek adları), `LGDeveloperMode.swift` (TV'deki `/media/developer/apps/usr/palm/applications/<kimlik>/appinfo.json` yolu) | TV'nin kabuğunda çalışan komut ya da yardımcının komut arayüzü |
| Protokol ve sistem dizgeleri (20) | `Info.plist` (uygulama kategorisi), `Nino.entitlements` (ses girişi yetkisi), `TVHelperADBTests.swift` (PEM başlığı), `SamsungCertificates.swift` (multipart başlığı), `PSNAuth.swift` ve `ConsolePSNTests.swift` (PSN bildirim kapsamları), `HomeView.swift`, `HealthSheet.swift`, `ConnectionSettings.swift`, `SetupParts.swift` (macOS `x-apple.systempreferences:` adresleri), `SettingsView.swift`, `HealthText.swift` (SF Symbols adları), `Greenlight.swift` (Greenlight ayar dosyası yolu), `TVDiscovery.swift` (LG SSDP URN), `LGDeveloperMode.swift` (LG kurulum isteği JSON'u), NinoCore `LinkIngressTests.swift` (CORS başlığı), `LegacyOBSPage.swift` (HTML viewport), `LegacyEventServer.swift` (`text/html; charset=utf-8`), `kutuphane.md` (havuz paket API'sinin JSON biçimi) | Apple, Sony, Samsung, LG, HTTP/HTML ya da sunucu sözleşmesinin sabit adı |
| Cihaz menü yolu (1) | `Setup.xcstrings` (`PS button › profile picture › Switch User`) | PS5'in kendi menü adları |
| Kod kalıbı, düz yazı değil (7) | NinoCore `AIProvider.swift` (2), `ProvidersNetworkTests.swift`, Mac `SheetsServicesTests.swift` (sağlayıcı JSON yanıt yolu `…?.first?[…]`), `LegacyLibraryTests.swift` (dosya yazma çağrısı), `TVStep.swift` (`\(tv.name) — \(tv.host)`), `ReportProblemSheet.swift` (tarih biçimi çağrısı) | tarayıcı iki dizge arasındaki kodu dizge sandı; içerik Gemini/OpenAI yanıt biçimi ve Swift API çağrısı |
