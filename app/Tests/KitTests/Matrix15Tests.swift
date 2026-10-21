// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// 0.7.1: the HP-15C Matrix Editor's logic (port of the Qt tst_matrix cases), the key click samples and the real-speed IPC.

import Foundation
import XCTest
#if canImport(VoyagerKit)
@testable import VoyagerKit
#endif

final class Matrix15Tests: XCTestCase {
    private func num(_ s: String, file: StaticString = #filePath, line: UInt = #line) -> UInt64 {
        guard case .success(let v) = Matrix15.parseCell(s) else { XCTFail("“\(s)” did not parse", file: file, line: line); return .max }
        return v
    }

    func testCellsAcceptCommaPointAndExponents() {
        XCTAssertEqual(num("1,5"), num("1.5"))
        XCTAssertEqual(num("1.5"), 0x01500000000000)
        XCTAssertEqual(num("2E-3"), 0x02000000000997)
        XCTAssertEqual(num("2e-3"), num("0,002"))
        XCTAssertEqual(num("-1,25E+2"), num("-125"))
        XCTAssertEqual(num("1.234,5"), num("1234.5"))
        XCTAssertEqual(num("1,234.5"), num("1234.5"))
        XCTAssertEqual(num("1,234,567"), num("1234567"))
        XCTAssertEqual(num("1 234,5"), num("1234.5"))
        XCTAssertEqual(num("\u{2212}3"), num("-3"))
        XCTAssertEqual(num(""), 0)
        XCTAssertEqual(num("  7  "), num("7"))
        XCTAssertEqual(Matrix15.parseCell("abc"), .failure(.notANumber))
        XCTAssertEqual(Matrix15.parseCell("3+4i"), .failure(.complex))
        XCTAssertEqual(Matrix15.parseCell("1e100"), .failure(.tooLarge))
        XCTAssertNil(Matrix15.value("1,2,3"))
        XCTAssertNil(Matrix15.value("1.2.3"))
        XCTAssertEqual(Matrix15.cellText(num("1,5")), "1.5")
        XCTAssertEqual(Matrix15.cellText(num("2E-3")), "0.002")
        XCTAssertEqual(Matrix15.cellText(num("1.23456789012")), "1.23456789")
    }

    func testTablesFromSpreadsheets() {
        var t = Matrix15.parseTable("1\t2\t3\r\n4,5\t5\t6\r\n")
        XCTAssertTrue(t.ok); XCTAssertEqual(t.rows, 2); XCTAssertEqual(t.cols, 3); XCTAssertEqual(t.cell(1, 0), "4,5"); XCTAssertFalse(t.ragged)
        t = Matrix15.parseTable("\"1.5\"\t2E-3\n-7\t8")
        XCTAssertTrue(t.ok); XCTAssertEqual(t.rows, 2); XCTAssertEqual(t.cols, 2); XCTAssertEqual(t.cell(0, 0), "1.5")
        XCTAssertTrue(Matrix15.badCells(t).isEmpty)
        t = Matrix15.parseTable("1\n2\n3\n")
        XCTAssertEqual(t.rows, 3); XCTAssertEqual(t.cols, 1)
        t = Matrix15.parseTable("1\t2\t3\n4\n")
        XCTAssertEqual(t.cols, 3); XCTAssertTrue(t.ragged); XCTAssertEqual(t.cell(1, 2), "")
        t = Matrix15.parseTable("1\t2\t\n3\t4\t\n")
        XCTAssertEqual(t.cols, 2)
        t = Matrix15.parseTable("1,5;2\n3;4")
        XCTAssertEqual(t.rows, 2); XCTAssertEqual(t.cols, 2); XCTAssertEqual(t.cell(0, 0), "1,5")
        t = Matrix15.parseTable("1\tx\n3\t4")
        XCTAssertEqual(Matrix15.badCells(t).count, 1); XCTAssertTrue(Matrix15.badCells(t)[0].hasPrefix("1,2"))
        XCTAssertFalse(Matrix15.parseTable("").ok)
        XCTAssertFalse(Matrix15.parseTable("\n\n").ok)
        XCTAssertFalse(Matrix15.parseTable(String(repeating: "1\n", count: 100)).ok)
    }

    func testCopyThenPasteIsExact() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            let r = Int.random(in: 1...8, using: &rng), c = Int.random(in: 1...8, using: &rng)
            var raw: [UInt64] = []
            for _ in 0..<(r * c) {
                var v: UInt64 = Bool.random(using: &rng) ? 9 : 0
                v = v << 4 | UInt64.random(in: 1...9, using: &rng)
                for _ in 0..<9 { v = v << 4 | UInt64.random(in: 0...9, using: &rng) }
                let e = Int.random(in: -99...99, using: &rng), ee = e < 0 ? 1000 + e : e
                v = v << 12 | UInt64(ee / 100) << 8 | UInt64(ee / 10 % 10) << 4 | UInt64(ee % 10)
                if Int.random(in: 0..<10, using: &rng) == 0 { v = 0 }
                raw.append(v)
            }
            let t = Matrix15.parseTable(Matrix15.toTSV(rows: r, cols: c, raw: raw))
            XCTAssertTrue(t.ok); XCTAssertEqual(t.rows, r); XCTAssertEqual(t.cols, c)
            for i in 0..<(r * c) { XCTAssertEqual(num(t.cells[i]), raw[i]) }
        }
    }

    func testWriteAndReadInAnImage() throws {
        let url = Fixtures.fixturesDir.appendingPathComponent("pool15/v150_00_baseline.bin")
        guard var img = try? Data(contentsOf: url) else { throw XCTSkip("no pool dumps") }
        XCTAssertEqual(Matrix15.pool(img, variant: 150)?.free, 78)
        XCTAssertEqual(Matrix15.room(img, variant: 150, matrix: 0), 78)
        let v = [num("1"), num("2,5"), num("-3E-4"), num("4"), num("5"), num("6")]
        try Matrix15.write(&img, variant: 150, matrix: 2, rows: 3, cols: 2, raw: v)
        let s = try XCTUnwrap(Matrix15.read(img, variant: 150, matrix: 2))
        XCTAssertEqual(s.rows, 3); XCTAssertEqual(s.cols, 2); XCTAssertEqual(s.raw, v)
        XCTAssertEqual(Matrix15.pool(img, variant: 150)?.free, 72)
        XCTAssertEqual(Matrix15.poolAfter(img, variant: 150, matrix: 0, rows: 4, cols: 4)?.free, 72 - 16)
        XCTAssertEqual(Matrix15.pool(img, variant: 150)?.free, 72)                // preview only
        let before = img
        XCTAssertThrowsError(try Matrix15.write(&img, variant: 150, matrix: 0, rows: 9, cols: 9, raw: Array(repeating: num("1"), count: 81))) {
            XCTAssertTrue(($0 as? LocalizedError)?.errorDescription?.contains("Error 10") == true)
        }
        XCTAssertEqual(img, before)
        XCTAssertThrowsError(try Matrix15.write(&img, variant: 150, matrix: 0, rows: 2, cols: 2, raw: [num("1")]))
        try Matrix15.write(&img, variant: 150, matrix: 2, rows: 0, cols: 0, raw: [])
        XCTAssertEqual(Matrix15.pool(img, variant: 150)?.free, 78)
    }

    func testKeyClickIsTheQtSound() {
        let s = KeyClickSound.samples()
        XCTAssertEqual(s.count, 2205)                          // 50 ms at 44.1 kHz
        XCTAssertGreaterThan(s.map { abs(Int($0)) }.max() ?? 0, 8000)
        XCTAssertLessThan(abs(Int(s.last ?? 0)), 200)          // faded out
        let w = KeyClickSound.wav()
        XCTAssertEqual(w.count, 44 + 2205 * 2)
        XCTAssertEqual(String(decoding: w.prefix(4), as: UTF8.self), "RIFF")
    }

    func testAppsRunAtRealCESpeed() {
        XCTAssertEqual(VoyagerCalculator().clockIPC, 0.577, accuracy: 1e-9)
    }
}
