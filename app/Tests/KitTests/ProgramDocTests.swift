// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// 0.5.6 program documentation: label / register / flag detection, comment re-matching, the 12C
// listing, the screen view, the text export and the PDF (page count and text via pdftotext).

import Foundation
import XCTest
#if canImport(VoyagerKit)
@testable import VoyagerKit
#endif

final class ProgramDocTests: XCTestCase {
    static let e3e3 = ["HP12c-multi-152-ext16-E3E3.bin"]

    static func fixture(_ n: String) throws -> Data { try Data(contentsOf: Fixtures.fixturesDir.appendingPathComponent(n)) }

    /// FinancePac (15.2) listed by the inspector's decoder.
    static func financePac() throws -> [ProgramLine] {
        guard let fw = Fixtures.hp15c3ROM ?? Fixtures.find(e3e3) else { throw XCTSkip("no 15C firmware") }
        let m = CalculatorMachine(); try m.loadFirmware(fw); try m.boot(restoring: nil)
        if m.variant != 152 { try m.switchModel(to: 152) }
        try m.putMemory(try fixture("FinancePac.15c"))
        let p = m.calc.inspect()?.program ?? []
        XCTAssertEqual(p.count, 407)
        return p
    }

    func testFinancePacLabelsRegistersFlags() throws {
        let a = ProgramAnalysis(lines: try Self.financePac(), model: 15)
        func lab(_ n: String) -> ProgramAnalysis.Label? { a.labels.first { $0.name == n } }
        XCTAssertEqual(lab("A")?.defined, [19])
        XCTAssertEqual(lab("7")?.defined, [1])
        XCTAssertEqual(lab("1")?.defined, [91])
        XCTAssertEqual(Array(lab("1")?.called.prefix(4) ?? []), [22, 64, 74, 85])
        XCTAssertEqual(lab("1")?.callKinds, ["GSB"])
        XCTAssertEqual(lab("3")?.called, [52]); XCTAssertEqual(lab("3")?.callKinds, ["SOLVE"])
        XCTAssertEqual(lab(".2")?.defined, [140]); XCTAssertEqual(lab(".2")?.called, [144])
        XCTAssertEqual(lab(".0")?.defined, [], "GTO .0 without a LBL .0")
        XCTAssertTrue(lab(".0")?.called.contains(35) == true)
        XCTAssertTrue(a.undefinedLabels.contains { $0.name == ".0" })
        // label order: digits, then .digits, then letters
        let names = a.labels.map(\.name)
        XCTAssertLessThan(names.firstIndex(of: "9")!, names.firstIndex(of: ".1")!)
        XCTAssertLessThan(names.firstIndex(of: ".9")!, names.firstIndex(of: "A")!)
        func reg(_ n: String) -> ProgramAnalysis.Register? { a.registers.first { $0.name == n } }
        XCTAssertEqual(reg("I")?.steps.prefix(3).map { $0 }, [138, 141, 143])
        XCTAssertEqual(reg("I")?.operations.prefix(3).map { $0 }, ["STO", "(i)", "DSE"])
        XCTAssertEqual(reg("(i)")?.operations, ["RCL +"])
        XCTAssertNotNil(reg("R.6")); XCTAssertTrue(reg("R.6")!.operations.contains("STO"))
        XCTAssertTrue(reg("R3")?.operations.contains("RCL +") == true)
        XCTAssertTrue(reg("R.5")?.operations.contains("STO +") == true)
        XCTAssertEqual(a.flags.map(\.name), ["0", "1"])
        XCTAssertEqual(a.flags.first { $0.name == "1" }?.steps.prefix(3).map { $0 }, [51, 92, 119])
        XCTAssertEqual(a.flags.first { $0.name == "1" }?.operations, ["CF", "SF", "F?"])
        // the document pre-fills an entry for each
        var d = ProgramDocument(); d.prefill(from: a)
        XCTAssertEqual(Set(d.labels.keys), Set(a.labels.map(\.name)))
        XCTAssertEqual(Set(d.registers.keys), Set(a.registers.map(\.name)))
    }

    func testMillerRabin16C() throws {
        guard let fw = Fixtures.firmware16Ext else { throw XCTSkip("no B7B7") }
        let m = CalculatorMachine(); try m.loadFirmware(fw); try m.boot(restoring: nil)
        try m.putMemory(Fixtures.millerRabin)
        let p = try XCTUnwrap(m.calc.inspect()?.program)
        XCTAssertGreaterThan(p.count, 50)
        let a = ProgramAnalysis(lines: p, model: 16)
        // every LBL in the listing is found, with its step
        for l in p where l.mnemonic.hasPrefix("LBL ") {
            let n = String(l.mnemonic.dropFirst(4))
            XCTAssertTrue(a.labels.first { $0.name == n }?.defined.contains(l.line) == true, "LBL \(n) at \(l.line)")
        }
        // every GSB / GTO target is listed as called from that step
        for l in p where l.mnemonic.hasPrefix("GSB ") || l.mnemonic.hasPrefix("GTO ") {
            let n = String(l.mnemonic.dropFirst(4))
            let name = n == "I" ? "I (indirect)" : n
            XCTAssertTrue(a.labels.first { $0.name == name }?.called.contains(l.line) == true, "\(l.mnemonic) at \(l.line)")
        }
        // registers: every STO / RCL of a register shows up
        for l in p where (l.mnemonic.hasPrefix("STO ") || l.mnemonic.hasPrefix("RCL ")) && l.mnemonic.split(separator: " ").count == 2 {
            let r = String(l.mnemonic.split(separator: " ")[1])
            let name = r == "I" || r == "(i)" ? r : "R" + r
            XCTAssertTrue(a.registers.first { $0.name == name }?.steps.contains(l.line) == true, "\(l.mnemonic) at \(l.line)")
        }
        XCTAssertFalse(a.labels.isEmpty); XCTAssertFalse(a.registers.isEmpty)
    }

    func test12CListingAndTargets() throws {
        guard let fw = Fixtures.find(Self.e3e3) else { throw XCTSkip("no E3E3") }
        let m = CalculatorMachine(); try m.loadFirmware(fw); try m.boot(restoring: nil)
        if m.variant != 120 { try m.switchModel(to: 120) }
        func tap(_ c: Int) throws { try m.tap(c) }
        try tap(31); try tap(20)                                  // f P/R
        // 1  STO 1  RCL n  +  g GTO 05  STO . 2  g x=0  g GTO 01  ENTER
        for k in [26, 33, 26, 34, 0, 39, 32, 22, 36, 17, 33, 37, 27, 32, 24, 32, 22, 36, 26, 25] { try tap(k) }
        let s = try XCTUnwrap(m.calc.inspect())
        XCTAssertEqual(s.model, 12); XCTAssertTrue(s.programMode)
        XCTAssertEqual(s.line, 9); XCTAssertEqual(s.lines, 15)
        let p = s.program.prefix(10).map { "\($0.screenView(model: 12)) \($0.fullMnemonic)" }
        // as the 12C display shows them (ten cells: "01-", then the keycodes right-aligned)
        XCTAssertEqual(p, ["01-      1 1", "02-   44 1 STO 1", "03-  45 11 RCL n", "04-     40 +", "05-43,33 05 g GTO 05",
                           "06-44 48 2 STO .2", "07-  43 35 g x=0?", "08-43,33 01 g GTO 01", "09-     36 ENTER", "10-43,33 00 g GTO 00"])
        XCTAssertEqual(s.program[8].screenView(model: 12), m.displayText.trimmingCharacters(in: .whitespaces), "the same as the display")
        XCTAssertTrue(m.displayText.hasPrefix("09-"), m.displayText)
        let a = ProgramAnalysis(lines: s.program, model: 12)
        XCTAssertEqual(a.labels.first { $0.name == "05" }?.called, [5])
        XCTAssertEqual(a.labels.first { $0.name == "05" }?.defined, [5])
        XCTAssertEqual(a.labels.first { $0.name == "01" }?.called, [8])
        XCTAssertEqual(a.registers.map(\.name), ["R1", "R.2", "n"])
        XCTAssertEqual(s.registerCount, 19, "15 lines take R.9")
    }

    func testScreenView() {
        let l = ProgramLine(line: 1, keys: "42,21,11", mnemonic: "LBL A", prefix: "f", bytes: [])
        XCTAssertEqual(l.screenView(model: 15), "001-42,21,11")
        XCTAssertEqual(ProgramLine(line: 2, keys: "15", mnemonic: "1/x", prefix: "", bytes: []).screenView(model: 15), "002-    15")
        XCTAssertEqual(ProgramLine(line: 5, keys: "44 .6", mnemonic: "STO .6", prefix: "", bytes: []).screenView(model: 15), "005-  44 .6")
        XCTAssertEqual(ProgramLine(line: 7, keys: "43,22, A", mnemonic: "LBL A", prefix: "g", bytes: []).screenView(model: 16), "007-43,22, A")
    }

    private func lines(_ keys: [String]) -> [ProgramLine] {
        keys.enumerated().map { ProgramLine(line: $0 + 1, keys: $1, mnemonic: $1, prefix: "", bytes: []) }
    }

    func testCommentsFollowInsertsAndDeletes() {
        // a program-like mix of common keycodes (deterministic), with "40" (+) at step 21
        let pool = ["1", "2", "3", "40", "30", "20", "10", "36", "44 1", "45 2", "43 32", "34", "33"]
        var seed: UInt64 = 7
        var base = (1...60).map { _ -> String in
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return pool[Int(seed >> 33) % pool.count]
        }
        base[20] = "40"; base[29] = "44 1"; base[44] = "45 2"
        var d = ProgramDocument()
        d.setComment("start", at: 1, lines: lines(base))
        d.setComment("add here", at: 21, lines: lines(base))      // "40" (common keys)
        d.setComment("store", at: 45, lines: lines(base))
        d.setComment("gone soon", at: 30, lines: lines(base))
        XCTAssertEqual(d.comment(at: 21), "add here")
        // insert three steps after 10, delete step 30 (shifted to 33)
        var changed = base; changed.insert(contentsOf: ["26", "27", "28"], at: 10); changed.remove(at: 32)
        let r = d.rematch(to: lines(changed))
        XCTAssertEqual(d.comment(at: 1), "start")
        XCTAssertEqual(d.comment(at: 24), "add here", "21 + 3")
        XCTAssertEqual(d.comment(at: 47), "store", "45 + 3 - 1")
        XCTAssertEqual(d.orphanedComments.map(\.text), ["gone soon"])
        XCTAssertEqual(r, .init(kept: 1, moved: 2, orphaned: 1))
        // the sidecar round-trips, orphan flag included
        let back = try! ProgramDocument.decode(try! d.encoded())
        XCTAssertEqual(back, d)
        XCTAssertEqual(ProgramDocument.sidecarURL(for: URL(fileURLWithPath: "/x/FinancePac.15c")).lastPathComponent, "FinancePac.15c.voyagerdoc")
    }

    // MARK: export

    /// FinancePac with its detected tables and a few example notes (clearly marked as examples).
    static func sampleContent() throws -> ProgramDocumentContent {
        let p = try financePac()
        var d = ProgramDocument()
        d.title = "FinancePac"
        d.description = """
        [Example text] A set of financial routines for the HP-15C: time value of money, interest conversion and \
        cash-flow analysis. This description is a placeholder to show the layout; the real one is written in the app.

        ## Usage
        - [Example] Enter the values and press A to E for the matching calculation.
        - [Example] Flag 1 selects payments at the beginning of the period.
        """
        let a = ProgramAnalysis(lines: p, model: 15)
        d.prefill(from: a)
        d.labels["A"] = "[example] first user routine"
        d.labels["3"] = "[example] function solved by SOLVE"
        d.registers["I"] = RegisterNote(name: "[example] index", meaning: "loop counter for DSE")
        d.registers["R.6"] = RegisterNote(name: "[example] rate", meaning: "periodic interest rate")
        d.flags["1"] = "[example] payment at the beginning"
        d.setComment("[example] entry point of routine A", at: 19, lines: p)
        d.setComment("[example] solve for the root of LBL 3", at: 52, lines: p)
        d.setComment("[example] loop over the registers via (i)", at: 141, lines: p)
        return ProgramDocumentContent(doc: d, info: ProgramDocumentInfo(modelName: "HP-15C (15.2)",
                                      firmware: "HP12c-multi-152-ext16-E3E3.bin (15C mode)", memoryFile: "FinancePac.15c", model: 15,
                                      date: Date()), lines: p)
    }

    static func pdfText(_ data: Data) throws -> String? {
        let tool = ["/usr/bin/pdftotext", "/opt/homebrew/bin/pdftotext", "/usr/local/bin/pdftotext"].first { FileManager.default.isExecutableFile(atPath: $0) }
        guard let tool else { return nil }
        let dir = FileManager.default.temporaryDirectory
        let inp = dir.appendingPathComponent("vc-doc-\(UUID().uuidString).pdf"), out = inp.appendingPathExtension("txt")
        try data.write(to: inp)
        let p = Process(); p.executableURL = URL(fileURLWithPath: tool); p.arguments = ["-layout", inp.path, out.path]
        try p.run(); p.waitUntilExit()
        defer { try? FileManager.default.removeItem(at: inp); try? FileManager.default.removeItem(at: out) }
        return try String(contentsOf: out, encoding: .utf8)
    }

    static func pageCount(_ data: Data) -> Int {
        let s = String(decoding: data, as: UTF8.self)
        guard let r = s.range(of: "/Type /Pages /Kids [") else { return 0 }
        let tail = s[r.upperBound...]
        guard let c = tail.range(of: "/Count ") else { return 0 }
        return Int(tail[c.upperBound...].prefix { $0.isNumber }) ?? 0
    }

    func testPDFFinancePac() throws {
        let c = try Self.sampleContent()
        for paper in PDFPaper.allCases {
            let pdf = ProgramDocumentPDF.render(c, paper: paper)
            XCTAssertTrue(pdf.starts(with: Data("%PDF-1.4".utf8)))
            let pages = Self.pageCount(pdf)
            XCTAssertGreaterThanOrEqual(pages, 8, paper.title); XCTAssertLessThanOrEqual(pages, 14, paper.title)
            if paper == .a4, let out = ProcessInfo.processInfo.environment["VC_DOC_OUT"] {
                try pdf.write(to: URL(fileURLWithPath: out))
            }
            guard let text = try Self.pdfText(pdf) else { continue }    // no pdftotext (the Mac): page count only
            XCTAssertTrue(text.contains("FinancePac"))
            XCTAssertTrue(text.contains("HP-15C (15.2) program documentation"))
            XCTAssertTrue(text.contains("Page 1 of \(pages)")); XCTAssertTrue(text.contains("Page \(pages) of \(pages)"))
            XCTAssertTrue(text.contains("001-42,21, 7"), "screen view of step 1")
            XCTAssertTrue(text.contains("019-42,21,11"))
            XCTAssertTrue(text.contains("f LBL A"))
            XCTAssertTrue(text.contains("f SOLVE 3"))
            XCTAssertTrue(text.contains("RCL + (i)"))
            XCTAssertTrue(text.contains("[example] entry point of routine A"))
            XCTAssertTrue(text.contains("[example] rate: periodic interest rate"))
            XCTAssertTrue(text.contains("Labels")); XCTAssertTrue(text.contains("Registers and flags")); XCTAssertTrue(text.contains("Program listing"))
            XCTAssertTrue(text.contains("407-"), "last step")
            XCTAssertFalse(text.lowercased().contains("copyright"))
            XCTAssertFalse(text.contains("©"))
            // the header is on every page: count its occurrences
            XCTAssertEqual(text.components(separatedBy: "HP-15C (15.2) program documentation").count - 1, pages)
        }
    }

    func testPlainText() throws {
        let t = try Self.sampleContent().plainText()
        XCTAssertTrue(t.hasPrefix("FinancePac\n=========="))
        XCTAssertTrue(t.contains("Model:     HP-15C (15.2)"))
        let l19 = t.components(separatedBy: "\n").first { $0.hasPrefix("019") } ?? ""
        XCTAssertNotNil(l19.range(of: #"^019 +019-42,21,11 +f LBL A +\[example\] entry point of routine A$"#, options: .regularExpression), l19)
        XCTAssertTrue(t.contains("LBL 3"))
        XCTAssertEqual(t.components(separatedBy: "\n").filter { $0.range(of: #"^\d{3} +\d{3}-"#, options: .regularExpression) != nil }.count, 407)
    }

    func testTextShapingSymbols() {
        // the calculator legends come out as Symbol glyphs or built-up superscripts, never "?"
        for s in ["x≷y", "√x", "eˣ", "yˣ", "SIN⁻¹", "∫ʸₓ", "Σ+", "π", "x̄", "ŷ,r", "→H.MS", "x≤y", "x≠0", "R↓", "⬅", "12×", "÷", "−", "ÁÉÍÓÚ ñ ¿¡ €"] {
            XCTAssertFalse(PDFText.shape(s, .regular).contains { $0.byte == 0x3F && $0.face != .symbol }, s)
        }
        let w = PDFText.width("ABC", PDFStyle(.regular, 10))
        XCTAssertEqual(w, (667 + 667 + 722) / 100, accuracy: 0.001)
        XCTAssertEqual(PDFText.wrap("one two three four", PDFStyle(.regular, 10), 40), ["one two", "three", "four"])
    }
}
