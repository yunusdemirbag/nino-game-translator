// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Darwin
import Foundation

/// Kaydın CPU ve bellek bütçesi (saf kural; saat dışarıdan verilir).
///
/// Kayıtçı kendi işinin iş parçacığı CPU süresini `add(work:)` ile bildirir. Her pencerede (varsayılan 5 sn)
/// oran hesaplanır: bütçe (ortalama %5 CPU ya da 150 MB) aşıldıysa kare aralıkları iki katına çıkar (en çok 8×);
/// üç pencere art arda bütçenin yarısının altında kalınırsa yarıya iner (en az 1×).
public struct DebugBudget: Sendable, Equatable {
    public struct Limits: Sendable, Equatable {
        public var maxCPU: Double = 0.05
        public var maxMemoryBytes: Int64 = 150 * 1024 * 1024
        public var window: TimeInterval = 5
        public var maxScale: Double = 8
        public var calmWindows = 3
        public init() {}
    }

    public let limits: Limits
    /// Kare aralıklarının çarpanı (1: hedef oran; 2: yarı oran…).
    public private(set) var scale: Double = 1
    public private(set) var lastFraction: Double = 0
    public private(set) var peakFraction: Double = 0
    public private(set) var totalWork: TimeInterval = 0
    public private(set) var totalTime: TimeInterval = 0
    public private(set) var slowDowns = 0

    private var windowStart: TimeInterval?
    private var windowWork: TimeInterval = 0
    private var calm = 0

    public init(limits: Limits = Limits()) { self.limits = limits }

    /// Kayıt açık kaldığı sürece ortalama CPU oranı.
    public var averageFraction: Double { totalTime > 0 ? totalWork / totalTime : 0 }

    public mutating func add(work: TimeInterval) { windowWork += max(0, work) }

    /// Pencere dolduysa kararı verir; çarpan değiştiyse `true`.
    @discardableResult
    public mutating func tick(now: TimeInterval, memoryBytes: Int64) -> Bool {
        guard let start = windowStart else {
            windowStart = now
            return false
        }
        let span = now - start
        guard span >= limits.window else { return false }
        let fraction = windowWork / span
        lastFraction = fraction
        peakFraction = max(peakFraction, fraction)
        totalWork += windowWork
        totalTime += span
        windowStart = now
        windowWork = 0
        let old = scale
        if fraction > limits.maxCPU || memoryBytes > limits.maxMemoryBytes {
            calm = 0
            scale = min(limits.maxScale, scale * 2)
            if scale != old { slowDowns += 1 }
        } else if fraction < limits.maxCPU / 2, Double(memoryBytes) < Double(limits.maxMemoryBytes) * 0.7 {
            calm += 1
            if calm >= limits.calmWindows {
                calm = 0
                scale = max(1, scale / 2)
            }
        } else {
            calm = 0
        }
        return scale != old
    }
}

/// Ölçüm yardımcıları.
public enum DebugMeasure {
    /// Çağıran iş parçacığının CPU süresi (sn).
    public static func threadCPU() -> TimeInterval {
        TimeInterval(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)) / 1e9
    }

    /// Sürecin toplam CPU süresi (kullanıcı + sistem, sn).
    public static func processCPU() -> TimeInterval {
        var u = rusage()
        getrusage(RUSAGE_SELF, &u)
        func s(_ t: timeval) -> TimeInterval { TimeInterval(t.tv_sec) + TimeInterval(t.tv_usec) / 1e6 }
        return s(u.ru_utime) + s(u.ru_stime)
    }

    /// Sürecin bellek ayak izi (phys_footprint, bayt).
    public static func footprint() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return r == KERN_SUCCESS ? Int64(info.phys_footprint) : 0
    }

    /// İşi yapar, iş parçacığı CPU süresini döner.
    @discardableResult
    public static func cpu(_ work: () -> Void) -> TimeInterval {
        let a = threadCPU()
        work()
        return threadCPU() - a
    }
}

/// `olcum.json`: kayıtçının son ölçümü (nino-debug özeti okur).
public struct DebugMeasurement: Codable, Sendable, Equatable {
    public var at: Int64 = 0
    public var since: Int64 = 0
    /// Kayıtçının ortalama / son pencere / en yüksek CPU oranı (bir çekirdeğin oranı; 0.05 = %5).
    public var cpuAverage: Double = 0
    public var cpuLast: Double = 0
    public var cpuPeak: Double = 0
    /// Kare aralığı çarpanı ve kaç kez yavaşlatıldı.
    public var scale: Double = 1
    public var slowDowns = 0
    /// Kayıtçının tuttuğu tampon belleği (tahmin) ve sürecin toplam ayak izi.
    public var recorderBytes: Int64 = 0
    public var processFootprint: Int64 = 0
    /// Diske yazma hızı (bayt/dk, son dakika) ve toplam.
    public var bytesPerMinute: Int64 = 0
    public var bytesWritten: Int64 = 0
    public var ps5Frames = 0
    /// Kodlayıcının alamadığı kare (yazma hatası ya da kodlayıcı 100 ms'de hazır olmadı).
    public var ps5Dropped = 0
    /// Zamanı gelmiş ama önceki kare hâlâ işlendiği için alınmayan kare (kayıt yetişemedi; okuma hattını etkilemez).
    public var ps5Busy = 0
    public var macFrames = 0
    /// Pencere zamanı geldiğinde kaydedilecek pencere yoktu.
    public var macMissing = 0
    public var eventFrames = 0
    public var tvShots = 0
    public var tvMessages = 0
    public var logLines = 0
    public var ringTotal: Int64 = 0
    public var ringLimit: Int64 = DebugRing.defaultLimit

    public init() {}

    /// Eski sürümün yazdığı dosyada olmayan alanlar varsayılanla okunur.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        at = try c.decodeIfPresent(type(of: at), forKey: .at) ?? at
        since = try c.decodeIfPresent(type(of: since), forKey: .since) ?? since
        cpuAverage = try c.decodeIfPresent(type(of: cpuAverage), forKey: .cpuAverage) ?? cpuAverage
        cpuLast = try c.decodeIfPresent(type(of: cpuLast), forKey: .cpuLast) ?? cpuLast
        cpuPeak = try c.decodeIfPresent(type(of: cpuPeak), forKey: .cpuPeak) ?? cpuPeak
        scale = try c.decodeIfPresent(type(of: scale), forKey: .scale) ?? scale
        slowDowns = try c.decodeIfPresent(type(of: slowDowns), forKey: .slowDowns) ?? slowDowns
        recorderBytes = try c.decodeIfPresent(type(of: recorderBytes), forKey: .recorderBytes) ?? recorderBytes
        processFootprint = try c.decodeIfPresent(type(of: processFootprint), forKey: .processFootprint) ?? processFootprint
        bytesPerMinute = try c.decodeIfPresent(type(of: bytesPerMinute), forKey: .bytesPerMinute) ?? bytesPerMinute
        bytesWritten = try c.decodeIfPresent(type(of: bytesWritten), forKey: .bytesWritten) ?? bytesWritten
        ps5Frames = try c.decodeIfPresent(type(of: ps5Frames), forKey: .ps5Frames) ?? ps5Frames
        ps5Dropped = try c.decodeIfPresent(type(of: ps5Dropped), forKey: .ps5Dropped) ?? ps5Dropped
        ps5Busy = try c.decodeIfPresent(type(of: ps5Busy), forKey: .ps5Busy) ?? ps5Busy
        macFrames = try c.decodeIfPresent(type(of: macFrames), forKey: .macFrames) ?? macFrames
        macMissing = try c.decodeIfPresent(type(of: macMissing), forKey: .macMissing) ?? macMissing
        eventFrames = try c.decodeIfPresent(type(of: eventFrames), forKey: .eventFrames) ?? eventFrames
        tvShots = try c.decodeIfPresent(type(of: tvShots), forKey: .tvShots) ?? tvShots
        tvMessages = try c.decodeIfPresent(type(of: tvMessages), forKey: .tvMessages) ?? tvMessages
        logLines = try c.decodeIfPresent(type(of: logLines), forKey: .logLines) ?? logLines
        ringTotal = try c.decodeIfPresent(type(of: ringTotal), forKey: .ringTotal) ?? ringTotal
        ringLimit = try c.decodeIfPresent(type(of: ringLimit), forKey: .ringLimit) ?? ringLimit
    }
}
