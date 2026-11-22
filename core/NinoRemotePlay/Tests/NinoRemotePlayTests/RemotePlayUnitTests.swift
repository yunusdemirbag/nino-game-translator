// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import CoreMedia
import Foundation
import NinoCore
import VideoToolbox
import XCTest
@testable import NinoRemotePlay

final class AnnexBTests: XCTestCase {
    func testSplitBothStartCodes() {
        let d = Data([0, 0, 0, 1, 0x67, 1, 2, 0, 0, 1, 0x68, 3, 0, 0, 0, 1, 0x65, 9, 9])
        let units = AnnexB.split(d)
        XCTAssertEqual(units, [Data([0x67, 1, 2]), Data([0x68, 3]), Data([0x65, 9, 9])])
        XCTAssertEqual(units.map(AnnexB.h264Type), [7, 8, 5])
    }

    func testAVCC() {
        XCTAssertEqual(AnnexB.avcc([Data([1, 2]), Data([3])]), Data([0, 0, 0, 2, 1, 2, 0, 0, 0, 1, 3]))
        XCTAssertEqual(AnnexB.split(Data([1, 2, 3])), [])
    }
}

final class RegistrationInputTests: XCTestCase {
    func testPIN() throws {
        XCTAssertEqual(try ConsoleRegistration.parsePIN("1234 5678"), 12_345_678)
        XCTAssertThrowsError(try ConsoleRegistration.parsePIN("123"))
    }

    func testAccountID() throws {
        XCTAssertEqual(try ConsoleRegistration.decodeAccountID("AQIDBAUGBwg="), [1, 2, 3, 4, 5, 6, 7, 8])
        XCTAssertThrowsError(try ConsoleRegistration.decodeAccountID("AQID"))
    }

    func testRegisteredConsoleRoundTripInSecretStore() throws {
        let store = MemorySecretStore()
        let c = RegisteredConsole(hostID: "ABC", nickname: "PS5", isPS5: true, target: 1_000_100,
                                  registKey: Array(repeating: 0x31, count: 16), rpKey: Array(0..<16), serverMAC: [1, 2, 3, 4, 5, 6])
        try c.save(to: store)
        XCTAssertEqual(try RegisteredConsole.load(hostID: "ABC", from: store), c)
        XCTAssertNil(try RegisteredConsole.load(hostID: "YOK", from: store))
        XCTAssertNotNil(try store.get("remoteplay.ABC"))
    }
}

/// VideoToolbox ile bir kare kodlar, Annex-B'ye çevirir ve çözücüden geri alır.
final class H264DecoderTests: XCTestCase {
    private func encodeOneFrame(width: Int, height: Int) throws -> Data {
        var session: VTCompressionSession?
        XCTAssertEqual(VTCompressionSessionCreate(allocator: nil, width: Int32(width), height: Int32(height),
                                                  codecType: kCMVideoCodecType_H264, encoderSpecification: nil,
                                                  imageBufferAttributes: nil, compressedDataAllocator: nil,
                                                  outputCallback: nil, refcon: nil, compressionSessionOut: &session), noErr)
        let s = try XCTUnwrap(session)
        defer { VTCompressionSessionInvalidate(s) }
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)

        var pixel: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &pixel)
        let pb = try XCTUnwrap(pixel)
        CVPixelBufferLockBaseAddress(pb, [])
        memset(CVPixelBufferGetBaseAddress(pb), 0x80, CVPixelBufferGetDataSize(pb))
        CVPixelBufferUnlockBaseAddress(pb, [])

        var out = Data()
        let props = [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary
        let st = VTCompressionSessionEncodeFrame(s, imageBuffer: pb, presentationTimeStamp: .zero, duration: .invalid,
                                                 frameProperties: props, infoFlagsOut: nil) { status, _, sample in
            guard status == noErr, let sample, let fmt = CMSampleBufferGetFormatDescription(sample),
                  let block = CMSampleBufferGetDataBuffer(sample) else { return }
            let start = Data([0, 0, 0, 1])
            for i in 0..<2 {
                var ptr: UnsafePointer<UInt8>?
                var size = 0
                CMVideoFormatDescriptionGetH264ParameterSetAtIndex(fmt, parameterSetIndex: i, parameterSetPointerOut: &ptr,
                                                                   parameterSetSizeOut: &size, parameterSetCountOut: nil,
                                                                   nalUnitHeaderLengthOut: nil)
                if let ptr { out += start + Data(bytes: ptr, count: size) }
            }
            var length = 0
            var dataPtr: UnsafeMutablePointer<CChar>?
            CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPtr)
            let avcc = Data(bytes: dataPtr!, count: length)
            var i = 0
            while i + 4 <= avcc.count {
                let n = avcc[i..<i + 4].reduce(0) { $0 << 8 | Int($1) }
                out += start + avcc[(i + 4)..<(i + 4 + n)]
                i += 4 + n
            }
        }
        XCTAssertEqual(st, noErr)
        VTCompressionSessionCompleteFrames(s, untilPresentationTimeStamp: .invalid)
        return out
    }

    func testDecodesAnnexBKeyframe() throws {
        let sample = try encodeOneFrame(width: 320, height: 240)
        XCTAssertFalse(sample.isEmpty)
        let decoder = H264Decoder()
        let image = try XCTUnwrap(try decoder.decode(sample, wantImage: true))
        XCTAssertEqual(image.width, 320)
        XCTAssertEqual(image.height, 240)
        XCTAssertNil(try decoder.decode(sample, wantImage: false))
    }
}
