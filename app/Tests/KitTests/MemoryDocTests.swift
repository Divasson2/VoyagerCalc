// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// 0.6.0: matrix / complex operations in the analysis, and the PDF's memory configuration block.

import Foundation
import XCTest
#if canImport(VoyagerKit)
@testable import VoyagerKit
#endif

final class MemoryDocTests: XCTestCase {
    /// The prog_ops program (docs/pool15c/prog_ops.py), then 2×3 A, 1×2 B and 5+6i (f I) keyed in.
    static func progOpsMachine() throws -> CalculatorMachine {
        guard let fw = Fixtures.hp15c3ROM else { throw XCTSkip("no C8C8 15C firmware") }
        let m = CalculatorMachine(); try m.loadFirmware(fw); try m.boot(restoring: nil)
        if m.variant != 150 { try m.switchModel(to: 150) }
        try m.putMemory(try Data(contentsOf: Fixtures.fixturesDir.appendingPathComponent("pool15/v150_50_prog_ops.bin")))
        // 2 ENTER 3 f DIM A   1 ENTER 2 f DIM B   f RESULT B   5 ENTER 6 f I
        for k in [27, 25, 28, 31, 12, 0, 26, 25, 27, 31, 12, 1, 31, 15, 1, 17, 25, 18, 31, 14] { try m.tap(k) }
        try m.run(ms: 500)
        return m
    }

    func testMatrixAndComplexOperations() throws {
        let m = try Self.progOpsMachine()
        let s = try XCTUnwrap(m.calc.inspect())
        XCTAssertEqual(s.program.count, 28)
        let a = ProgramAnalysis(lines: s.program, model: 15)
        func op(_ n: String) -> ProgramAnalysis.MatrixOp? { a.matrixOps.first { $0.item == n } }
        XCTAssertEqual(op("DIM (i)")?.steps, [2])
        XCTAssertEqual(op("MATRIX n")?.operations, ["MATRIX 1", "MATRIX 0", "MATRIX 5"])
        XCTAssertEqual(op("Matrix A")?.operations, ["DIM", "RCL MATRIX", "STO", "RCL", "STO g", "RCL DIM"])
        XCTAssertEqual(op("Matrix B")?.steps, [7, 13, 17])
        XCTAssertEqual(op("RESULT")?.operations, ["RESULT C", "STO RESULT", "RCL RESULT"])
        XCTAssertEqual(op("Complex")?.operations, ["f I", "Re≷Im", "SF 8", "F? 8", "CF 8"])
        XCTAssertEqual(op("Complex")?.steps, [21, 22, 23, 24, 25])
        XCTAssertEqual(op("SOLVE/∫ workspace")?.operations, ["SOLVE", "∫ʸₓ"])
        XCTAssertEqual(a.matrixOps.first?.item, "DIM (i)")
        XCTAssertNil(a.registers.first { $0.name == "(i)" }, "RCL DIM (i) / DIM (i) are no use of register (i)")
        XCTAssertEqual(a.flags.first { $0.name == "8" }?.meaning.hasPrefix("complex mode"), true)
    }

    func testRclDimIIsNotRegisterI() {
        let l = [ProgramLine(line: 1, keys: "45,23,24", mnemonic: "RCL DIM (i)", prefix: "", bytes: []),
                 ProgramLine(line: 2, keys: "45 24", mnemonic: "RCL (i)", prefix: "", bytes: [])]
        let a = ProgramAnalysis(lines: l, model: 15)
        XCTAssertEqual(a.registers.first { $0.name == "(i)" }?.steps, [2])
        XCTAssertEqual(a.matrixOps.first?.operations, ["RCL DIM (i)"])
    }

    func testMemoryBlockInPDF() throws {
        let m = try Self.progOpsMachine()
        let s = try XCTUnwrap(m.calc.inspect())
        let p = try XCTUnwrap(s.pool)
        XCTAssertTrue(p.complex); XCTAssertEqual(p.dimension(0), "2×3"); XCTAssertEqual(p.dimension(1), "1×2"); XCTAssertEqual(p.resultLetter, "B")
        var d = ProgramDocument(); d.title = "Matrix and complex operations"
        d.description = "[Example] The listing from docs/pool15c/prog_ops.py, with A 2×3, B 1×2 and 5 + 6i keyed in."
        let c = ProgramDocumentContent(doc: d, info: ProgramDocumentInfo(modelName: "HP-15C", firmware: "C8C8 (15.0 mode)", memoryFile: "v150_50_prog_ops",
                                                                         model: 15, date: Date()), lines: s.program, pool: p, setFlags: s.setFlags)
        let rows = Dictionary(uniqueKeysWithValues: c.memoryRows)
        XCTAssertEqual(rows["Matrices"], "A 2×3, B 1×2 (8 registers)")
        XCTAssertEqual(rows["RESULT"], "matrix B")
        XCTAssertTrue(rows["Complex mode"]?.hasPrefix("on (flag 8)") == true)
        XCTAssertTrue(rows["g MEM"]?.hasPrefix(p.gmem) == true)
        XCTAssertTrue(rows["Needs at least"]?.contains("SOLVE/∫ workspace 28") == true)
        XCTAssertEqual(c.matrixOpRows.first { $0.item == "Matrix A" }?.notes.hasPrefix("now 2×3"), true)
        var fonts: PDFFontSet? = nil
        if let k = try? FontPDFTests.keys(), let dsp = try? FontPDFTests.display() { fonts = PDFFontSet(keys: k, display: dsp) }
        let pdf = ProgramDocumentPDF.render(c, paper: .a4, fonts: fonts)
        if let out = ProcessInfo.processInfo.environment["VC_DOC_MEM_OUT"] { try pdf.write(to: URL(fileURLWithPath: out)) }
        if let dir = ProcessInfo.processInfo.environment["VC_SCREENS_DIR"] {
            try? pdf.write(to: URL(fileURLWithPath: dir).appendingPathComponent("mac-real/mac-memory-config-doc.pdf"))
        }
        XCTAssertTrue(c.plainText().contains("MEMORY CONFIGURATION"))
        guard let text = try ProgramDocTests.pdfText(pdf) else { return }
        XCTAssertTrue(text.contains("Memory configuration"))
        XCTAssertTrue(text.contains("Matrices and complex"))
        XCTAssertTrue(text.contains(p.gmem))
        XCTAssertTrue(text.contains("MATRIX 1: R0 = R1 = 1"))
    }
}
