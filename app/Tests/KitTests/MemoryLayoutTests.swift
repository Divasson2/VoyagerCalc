// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// The three 16C memory layouts (standard 203 B at 0x6F0, extended B7B7 = E8E8 at 0x168, early E3E3 at 0x170):
// the converter and the structural pre-check. (core/tests/test_mem16.c checks the C side in depth.)

import Foundation
import XCTest
#if canImport(VoyagerKit)
@testable import VoyagerKit
#endif

final class MemoryLayoutTests: XCTestCase {
    func testConvertE3E3MovesThePoolDownByEightBytes() throws {
        var img = Data(count: VoyagerCalculator.memorySize)
        img[0x170] = 0xAB; img[0x6E4] = 0x12; img[0x6E8] = 0x34         // R0, a register, the program's top register
        let out = try XCTUnwrap(VoyagerCalculator.convertE3E3Memory(img))
        XCTAssertEqual(out[0x168], 0xAB)
        XCTAssertEqual(out[0x6DC], 0x12)
        XCTAssertEqual(out[0x6E0], 0x34)
        XCTAssertEqual(out[0x6E8], 0)
        XCTAssertNil(VoyagerCalculator.convertE3E3Memory(out), "a converted image is not converted again")
        var b7 = Data(count: VoyagerCalculator.memorySize); b7[0x168] = 1
        XCTAssertNil(VoyagerCalculator.convertE3E3Memory(b7), "a B7B7-layout image is left alone")
    }

    func testPrecheckOnTheExtendedMulti() throws {
        guard let fw = Fixtures.find(["HP12c-multi-152-ext16-feat-E8E8.bin"]) else { throw XCTSkip("no E8E8 firmware file found") }
        var std = Data(count: VoyagerCalculator.memorySize); std[0x6F8] = 1          // standard-layout data
        XCTAssertEqual(CalculatorMachine.layoutCheck(std, firmware: fw, variant: 160)?.verdict, .warn)
        var old = Data(count: VoyagerCalculator.memorySize); old[0x170] = 1; old[0x6E8] = 1      // E3E3-layout data
        XCTAssertEqual(CalculatorMachine.layoutCheck(old, firmware: fw, variant: 160)?.verdict, .convert)
        var ext = Data(count: VoyagerCalculator.memorySize); ext[0x168] = 1          // B7B7 layout
        XCTAssertEqual(CalculatorMachine.layoutCheck(ext, firmware: fw, variant: 160)?.verdict, .ok)
    }
}
