// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

/// Annex-B (00 00 01 başlangıç kodlu) H.264 akışını NAL birimlerine ayırır.
public enum AnnexB {
    public static func split(_ data: Data) -> [Data] {
        let b = [UInt8](data)
        var units: [Data] = []
        var i = 0
        var start: Int?
        while i + 2 < b.count {
            if b[i] == 0, b[i + 1] == 0, b[i + 2] == 1 {
                if let s = start {
                    var end = i
                    if end > s, b[end - 1] == 0 { end -= 1 } // 4 baytlık başlangıç kodu
                    if end > s { units.append(Data(b[s..<end])) }
                }
                i += 3
                start = i
            } else {
                i += 1
            }
        }
        if let s = start, s < b.count { units.append(Data(b[s...])) }
        return units
    }

    /// H.264 NAL türü (5: IDR, 7: SPS, 8: PPS).
    public static func h264Type(_ nal: Data) -> UInt8 { (nal.first ?? 0) & 0x1F }

    /// NAL birimlerini 4 bayt uzunluk önekli (AVCC) biçime çevirir.
    public static func avcc(_ nals: [Data]) -> Data {
        var out = Data()
        for n in nals {
            var len = UInt32(n.count).bigEndian
            withUnsafeBytes(of: &len) { out.append(contentsOf: $0) }
            out.append(n)
        }
        return out
    }
}

/// VideoToolbox ile H.264 çözücü. Tek iş parçacığından sırayla çağrılır.
final class H264Decoder {
    private var format: CMVideoFormatDescription?
    private var session: VTDecompressionSession?
    private var sps: Data?
    private var pps: Data?

    enum DecodeError: Error { case noFormat, blockBuffer(OSStatus), sampleBuffer(OSStatus), decode(OSStatus) }

    deinit { reset() }

    func reset() {
        if let s = session { VTDecompressionSessionInvalidate(s) }
        session = nil
        format = nil
    }

    /// Bir video örneğini çözer. `wantImage` doğruysa kareyi `CGImage` olarak döner.
    func decode(_ sample: Data, wantImage: Bool) throws -> CGImage? {
        var slices: [Data] = []
        var newSPS: Data?, newPPS: Data?
        for nal in AnnexB.split(sample) {
            switch AnnexB.h264Type(nal) {
            case 7: newSPS = nal
            case 8: newPPS = nal
            case 9, 6: continue // ayraç, SEI
            default: slices.append(nal)
            }
        }
        if let s = newSPS, let p = newPPS, s != sps || p != pps || format == nil {
            sps = s
            pps = p
            try makeSession()
        }
        guard !slices.isEmpty else { return nil }
        guard let format, let session else { throw DecodeError.noFormat }

        let payload = AnnexB.avcc(slices)
        var block: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
                                                        blockLength: payload.count, blockAllocator: kCFAllocatorDefault,
                                                        customBlockSource: nil, offsetToData: 0, dataLength: payload.count,
                                                        flags: 0, blockBufferOut: &block)
        guard status == noErr, let block else { throw DecodeError.blockBuffer(status) }
        status = payload.withUnsafeBytes { CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: payload.count) }
        guard status == noErr else { throw DecodeError.blockBuffer(status) }

        var sampleBuffer: CMSampleBuffer?
        var size = payload.count
        status = CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
                                           sampleCount: 1, sampleTimingEntryCount: 0, sampleTimingArray: nil,
                                           sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sampleBuffer)
        guard status == noErr, let sampleBuffer else { throw DecodeError.sampleBuffer(status) }

        var image: CGImage?
        var decodeStatus: OSStatus = noErr
        status = VTDecompressionSessionDecodeFrame(session, sampleBuffer: sampleBuffer, flags: [], infoFlagsOut: nil) { st, _, buffer, _, _ in
            decodeStatus = st
            guard wantImage, st == noErr, let buffer else { return }
            var cg: CGImage?
            VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &cg)
            image = cg
        }
        guard status == noErr else {
            // Oturum bozulduysa bir sonraki SPS/PPS ile yeniden kurulur.
            if status == kVTInvalidSessionErr { reset() }
            throw DecodeError.decode(status)
        }
        if decodeStatus != noErr { throw DecodeError.decode(decodeStatus) }
        return image
    }

    private func makeSession() throws {
        reset()
        guard let sps, let pps else { throw DecodeError.noFormat }
        var fmt: CMFormatDescription?
        let status = sps.withUnsafeBytes { s in
            pps.withUnsafeBytes { p in
                let ptrs = [s.bindMemory(to: UInt8.self).baseAddress!, p.bindMemory(to: UInt8.self).baseAddress!]
                let sizes = [sps.count, pps.count]
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(allocator: kCFAllocatorDefault, parameterSetCount: 2,
                                                                           parameterSetPointers: ptrs, parameterSetSizes: sizes,
                                                                           nalUnitHeaderLength: 4, formatDescriptionOut: &fmt)
            }
        }
        guard status == noErr, let fmt else { throw DecodeError.decode(status) }
        let attrs: [CFString: Any] = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA]
        var s: VTDecompressionSession?
        let st = VTDecompressionSessionCreate(allocator: kCFAllocatorDefault, formatDescription: fmt, decoderSpecification: nil,
                                              imageBufferAttributes: attrs as CFDictionary, outputCallback: nil,
                                              decompressionSessionOut: &s)
        guard st == noErr, let s else { throw DecodeError.decode(st) }
        format = fmt
        session = s
    }
}
