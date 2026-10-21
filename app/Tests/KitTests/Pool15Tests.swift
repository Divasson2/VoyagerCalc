// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// 0.6.0: the HP-15C memory pool through the Swift snapshot (complex stack, matrices, g MEM),
// and the inspector fixes (storage ends at matrix A; flag 8 from the memory, so loaded files show it).
// Values: docs/pool15c/pool15.py on the same dumps (Fixtures/pool15). Needs the C8C8 firmware.

import Foundation
import XCTest
#if canImport(VoyagerKit)
@testable import VoyagerKit
#endif

final class Pool15Tests: XCTestCase {
    static var machines: [Int: CalculatorMachine] = [:]
    static func machine(_ variant: Int) throws -> CalculatorMachine {
        if let m = machines[variant] { return m }
        guard let fw = Fixtures.hp15c3ROM else { throw XCTSkip("no C8C8 15C firmware") }
        let m = CalculatorMachine(); try m.loadFirmware(fw); try m.boot(restoring: nil)
        if m.variant != variant { try m.switchModel(to: variant) }
        machines[variant] = m
        return m
    }
    static func snapshot(_ dump: String, _ variant: Int) throws -> InspectorSnapshot {
        let m = try machine(variant)
        try m.putMemory(try Data(contentsOf: Fixtures.fixturesDir.appendingPathComponent("pool15/\(dump).bin")))
        return try XCTUnwrap(m.calc.inspect())
    }

    func testMatricesAndStorageEnd() throws {
        let s = try Self.snapshot("v150_24_fillA", 150)
        let p = try XCTUnwrap(s.pool)
        XCTAssertEqual(s.registerCount, 20, "R0..R19, matrix A's elements are not registers")
        XCTAssertEqual(s.registers.last?.name, "R.9")
        XCTAssertEqual(p.gmem, "19 70 00-0")
        XCTAssertEqual(p.rows[0], 2); XCTAssertEqual(p.cols[0], 3); XCTAssertEqual(p.dimension(1), "1×2")
        let a = s.matrices[0]
        XCTAssertEqual(a.values.map(\.text), ["11", "12", "13", "21", "22", "23"])
        XCTAssertEqual(a.tsv, "11\t12\t13\n21\t22\t23")
        XCTAssertTrue(a.isResult)
        XCTAssertFalse(s.isComplex)
        XCTAssertEqual(p.segments.map(\.kind), [.storage, .matrix(0), .matrix(1), .free])
        XCTAssertEqual(p.segments.map(\.count).reduce(0, +), 96)
    }

    func testComplexStackOrderAndFlag8FromMemory() throws {
        let s = try Self.snapshot("v150_18_cx_order", 150)
        XCTAssertTrue(s.isComplex, "flag 8 read from the memory image (0x4C bit 3), not the C annunciator")
        XCTAssertTrue(s.setFlags.contains(8))
        XCTAssertEqual(["X", "Y", "Z", "T", "LAST X"].map { s.imaginary(of: $0)?.text ?? "?" }, ["180", "8", "6", "6", "10"])
        let p = try XCTUnwrap(s.pool)
        XCTAssertEqual(p.gmem, "19 73 00-0")
        XCTAssertEqual(p.segments.first?.kind, .complex)
        XCTAssertEqual(p.segments.first?.count, 5)
    }

    func testComplexWithMatricesAndResult() throws {
        let s = try Self.snapshot("v150_34_sf8_with_matrices", 150)
        let p = try XCTUnwrap(s.pool)
        XCTAssertEqual(p.resultLetter, "C")
        XCTAssertEqual(s.matrices[2].values.map(\.text), ["181", "192", "203"])
        XCTAssertEqual(s.matrices[0].values.map(\.text), ["11", "12", "13", "21"])
        XCTAssertEqual(p.gmem, "19 64 00-0")
        XCTAssertEqual(s.registerCount, 20)
    }

    func testDoubleMemory152() throws {
        let s = try Self.snapshot("v152_81_prog_dimA_cx_dim25", 152)
        let p = try XCTUnwrap(s.pool)
        XCTAssertEqual(p.size, 192)
        XCTAssertEqual(p.gmem, "25 149 02-3")
        XCTAssertEqual(s.registerCount, 26)
        XCTAssertEqual(p.dimension(0), "3×4")
        XCTAssertEqual(p.segments.map(\.kind), [.complex, .storage, .matrix(0), .free, .program])
        let e = try Self.snapshot("v152_40_dims_ABCDE", 152).pool
        XCTAssertEqual(e?.gmem, "19 145 00-0")
        XCTAssertEqual(e?.matrixRegisters, 29)
    }

    func testFinancePacGMem() throws {
        guard let fw = Fixtures.hp15c3ROM else { throw XCTSkip("no C8C8 15C firmware") }
        let m = CalculatorMachine(); try m.loadFirmware(fw); try m.boot(restoring: nil)
        if m.variant != 152 { try m.switchModel(to: 152) }
        try m.putMemory(try ProgramDocTests.fixture("FinancePac.15c"))
        XCTAssertEqual(m.calc.inspect()?.pool?.gmem, "96 33 64-5")
    }

    func testDescriptor() {
        let v = RegisterValue(name: "X", text: "", decimal: "", isInteger: false, isNegative: false, number: 0, word: 0, raw: 0x1A_0000_0000_0000)
        XCTAssertEqual(v.matrixDescriptor, 0)
        let w = RegisterValue(name: "X", text: "", decimal: "", isInteger: false, isNegative: false, number: 0, word: 0, raw: 0x01_2300_0000_0001)
        XCTAssertNil(w.matrixDescriptor)
    }

    // MARK: 0.6.4, flag 8 and the 5 registers below R2 (docs/BUG-0.6.3-FLAG8-WRITE.md)

    static func bcd(_ n: Int) -> [UInt8] { var v = UInt64(n) << 48; return (0..<8).map { _ in defer { v >>= 8 }; return UInt8(v & 0xFF) } }
    static func off(_ p: Int) -> Int { 0x70 + 8 * (p - 0x10) }

    /// A real calculator image (Jose's E3E3 15.2, read over USB) put into complex mode by the
    /// firmware's rules (docs/HP15C-POOL-COMPLEX-MATRICES.md 3.1): R2.. and the map move up by 5,
    /// the imaginary stack LASTx, T, Z, Y, X sits at the old R2, flag 8 = CPU status bit 0x4C bit 3
    /// (and its S0A copy 0xC4 bit 0).
    static func synthComplex(_ img: Data, flag8: Bool = true) -> [UInt8] {
        var d = [UInt8](img)
        let data = Int(d[0x11E]), pool = d[0x118] == 0 ? 0x100 : Int(d[0x118])
        for p in stride(from: pool - 1, through: data, by: -1) { d.replaceSubrange(off(p + 5)..<off(p + 5) + 8, with: d[off(p)..<off(p) + 8]) }
        for i in 0..<5 { d.replaceSubrange(off(data + i)..<off(data + i) + 8, with: bcd(i + 1)) }   // LASTx 1, T 2, Z 3, Y 4, X 5
        for b in 0..<7 { d[0x118 + b] &+= 5 }
        if flag8 { d[0x4C] |= 0x08; d[0xC4] |= 1 }
        return d
    }

    func testParseRealImageWithComplexOn() throws {
        let empty = try ProgramDocTests.fixture("E3E3-152-empty-usb-read.15c")
        let base = try XCTUnwrap(try Self.snapshotOf(empty, 152).pool)
        let s = try Self.snapshotOf(Data(Self.synthComplex(empty)), 152)
        let p = try XCTUnwrap(s.pool)
        XCTAssertTrue(s.isComplex)
        XCTAssertEqual(["X", "Y", "Z", "T", "LAST X"].map { s.imaginary(of: $0)?.text ?? "?" }, ["5", "4", "3", "2", "1"])
        XCTAssertEqual(p.free, base.free - 5)
        XCTAssertEqual(p.scratch, 0)
        XCTAssertEqual(p.segments.first?.kind, .complex)
        XCTAssertFalse(p.segments.contains { $0.kind == .workspace })
    }

    /// What 0.6.3 left on Jose's calculator: the 5 registers allocated, flag 8 clear (the firmware
    /// rewrote 0xC4 from the CPU bit). They were shown as "SOLVE"; the firmware counts them as free.
    func testLostFlag8IsNotASolveWorkspace() throws {
        let empty = try ProgramDocTests.fixture("E3E3-152-empty-usb-read.15c")
        let base = try XCTUnwrap(try Self.snapshotOf(empty, 152).pool)
        var d = Self.synthComplex(empty, flag8: false); d[0xC4] |= 1      // even with the stale S0A copy
        let s = try Self.snapshotOf(Data(d), 152)
        let p = try XCTUnwrap(s.pool)
        XCTAssertFalse(s.isComplex, "the firmware's flag 8 is the CPU bit")
        XCTAssertEqual(p.scratch, 0)
        XCTAssertEqual(p.gap, 5)
        XCTAssertEqual(p.segments.first?.kind, .free)
        XCTAssertEqual(p.free, base.free, "g MEM counts them as free, as the firmware does")
    }

    static func snapshotOf(_ data: Data, _ variant: Int) throws -> InspectorSnapshot {
        let m = try machine(variant)
        try m.putMemory(data)
        return try XCTUnwrap(m.calc.inspect())
    }
}
