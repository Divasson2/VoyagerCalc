// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// 0.5.7: the user's HP 15C key-cap and display fonts in the documentation PDF.
// The fonts are not part of the repository; the tests look in $VC_FONT_DIR, art/fonts
// (Jose's renamed copies) and ~/Firmware/Fonts, and skip when they are not there.

import XCTest
#if canImport(VoyagerKit)
@testable import VoyagerKit
#endif

final class FontPDFTests: XCTestCase {
    static func fontDirs() -> [URL] {
        var d: [URL] = []
        if let e = ProcessInfo.processInfo.environment["VC_FONT_DIR"] { d.append(URL(fileURLWithPath: e)) }
        let here = URL(fileURLWithPath: #filePath)
        d.append(here.deletingLastPathComponent().appendingPathComponent("../../../art/fonts").standardized)
        var home = URL(fileURLWithPath: NSHomeDirectory())
        #if os(macOS)
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir { home = URL(fileURLWithPath: String(cString: dir)) }
        #endif
        d.append(home.appendingPathComponent("Firmware/Fonts"))
        return d
    }
    static func font(_ name: String) throws -> TrueTypeFont {
        for dir in fontDirs() {
            let u = dir.appendingPathComponent(name)
            if let data = try? Data(contentsOf: u) { return try TrueTypeFont(data: data) }
        }
        throw XCTSkip("\(name) not found (the user's own font)")
    }
    static func keys() throws -> TrueTypeFont { try font("HP15CSimulatorKeys.ttf") }
    static func display() throws -> TrueTypeFont { try font("HP15CSimulatorDisplay.ttf") }

    func testFontsLoadByFileWithDistinctNames() throws {
        let k = try Self.keys(), d = try Self.display()
        XCTAssertEqual(k.familyName, "HP15C Simulator Keys")
        XCTAssertEqual(d.familyName, "HP15C Simulator Display")
        XCTAssertNotEqual(k.postScriptName, d.postScriptName)
        XCTAssertNotEqual(d.glyph(for: "8"), 0); XCTAssertNotEqual(d.glyph(for: ","), 0)
        XCTAssertLessThan(d.advance(d.glyph(for: ",")), 100, "the comma tucks under the digit, like the LCD")
    }

    func testEveryLegendHasAKeyCap() throws {
        let k = try Self.keys()
        for col in [HP15CKeyGlyphs.Colour.primary, .gold, .blue] {
            for (code, ch) in HP15CKeyGlyphs.table(col) {
                XCTAssertNotEqual(k.glyph(for: ch.unicodeScalars.first!), 0, "\(col) \(code) '\(ch)'")
            }
        }
        // every key with a legend is covered
        for key in CalculatorModel.hp15c.keys {
            XCTAssertNotNil(HP15CKeyGlyphs.primary[key.code], key.name)
            if !key.f.isEmpty { XCTAssertNotNil(HP15CKeyGlyphs.gold[key.code], key.f) }
            if !key.g.isEmpty { XCTAssertNotNil(HP15CKeyGlyphs.blue[key.code], key.g) }
        }
    }

    func testFinancePacLinesAllGetKeyCaps() throws {
        let p = try ProgramDocTests.financePac()
        let missing = p.filter { HP15CKeyGlyphs.glyphs(for: $0) == nil }.map(\.fullMnemonic)
        XCTAssertEqual(Set(missing), [], "lines without key caps")
        let lbl = HP15CKeyGlyphs.glyphs(for: p.first { $0.line == 19 }!)!
        XCTAssertEqual(lbl.map(\.0), ["´", "b", "A"])          // f, gold LBL, gold A
        XCTAssertEqual(lbl.map(\.1), ["f", "LBL", "A"])
    }

    func testSubsetIsSmallAndValid() throws {
        let k = try Self.keys()
        let sub = k.subset([k.glyph(for: "b"), k.glyph(for: "A")])
        let back = try TrueTypeFont(tables: try Self.tables(sub))
        XCTAssertEqual(back.numGlyphs, k.numGlyphs)
        XCTAssertLessThan(sub.count, 12_000)
    }
    static func tables(_ d: Data) throws -> [String: Data] {
        // re-read through the file parser
        let f = try TrueTypeFont(data: d); return f.tables
    }

    func testPDFWithFonts() throws {
        let c = try ProgramDocTests.sampleContent()
        let fonts = PDFFontSet(keys: try Self.keys(), display: try Self.display())
        let pdf = ProgramDocumentPDF.render(c, paper: .a4, fonts: fonts)
        if let out = ProcessInfo.processInfo.environment["VC_DOC_FONT_OUT"] { try pdf.write(to: URL(fileURLWithPath: out)) }
        if let dir = ProcessInfo.processInfo.environment["VC_SCREENS_DIR"] {     // the Mac build's proof
            let u = URL(fileURLWithPath: dir).appendingPathComponent("mac-real/mac-financepac-doc-15cfont.pdf")
            try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? pdf.write(to: u)
        }
        let s = String(decoding: pdf, as: UTF8.self)
        XCTAssertTrue(s.contains("/BaseFont /VCKEYS+HP15CSimulatorKeys"))
        XCTAssertTrue(s.contains("/BaseFont /VCDISP+HP15CSimulatorDisplay"))
        XCTAssertEqual(s.components(separatedBy: "/FontFile2").count - 1, 2)
        XCTAssertLessThan(pdf.count, 700_000)
        let pages = ProgramDocTests.pageCount(pdf)
        XCTAssertGreaterThanOrEqual(pages, 8); XCTAssertLessThanOrEqual(pages, 18)
        guard let text = try ProgramDocTests.pdfText(pdf) else { return }
        // ToUnicode: the key caps and the display still read as text
        XCTAssertTrue(text.contains("019-42,21,11"), "display font text")
        XCTAssertTrue(text.contains("f LBL A"), "key caps text")
        XCTAssertTrue(text.contains("Page \(pages) of \(pages)"))
    }

    func testWithoutFontsNothingChanges() throws {
        let c = try ProgramDocTests.sampleContent()
        let a = ProgramDocumentPDF.render(c, paper: .a4), b = ProgramDocumentPDF.render(c, paper: .a4, fonts: PDFFontSet())
        XCTAssertEqual(ProgramDocTests.pageCount(a), ProgramDocTests.pageCount(b))
        XCTAssertFalse(String(decoding: a, as: UTF8.self).contains("FontFile2"))
    }
}
