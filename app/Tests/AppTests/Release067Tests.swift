// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// 0.6.7: (1) the window's title bar has one colour across the whole width, with and without the
// Registers & Program flyout (rendered from a real, never-shown NSWindow holding the real ContentView);
// (2) the greyed emblem panels; (3) the HP 15C Simulator fonts are in the app bundle and the PDF uses them.
// Synthetic image only (no HP code).
#if os(macOS)
import AppKit
import SwiftUI
import XCTest

@MainActor
final class Release067Tests: XCTestCase {
    private var outDir: URL {
        let env = ProcessInfo.processInfo.environment["VC_SCREENS_DIR"]
        let u = env.map { URL(fileURLWithPath: $0) } ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("VoyagerCalcScreens")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    private func runningApp(inspector: Bool) throws -> AppModel {
        let m = CalculatorMachine()
        try m.loadFirmware(Data(FirmwareLoadTests.Synthetic.image(stock: false, block: 0x20000854)))
        try m.boot(restoring: nil)
        let app = AppModel()
        app.persistState = false
        app.attach(m, firmwareName: "synthetic")
        app.showInspector = inspector
        return app
    }

    /// The whole window (title bar included) drawn from a window that is never put on screen.
    private func renderWindow(_ app: AppModel, width: CGFloat, appearance: NSAppearance.Name) throws -> NSBitmapImageRep {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 560),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                           backing: .buffered, defer: false)
        win.isReleasedWhenClosed = false
        win.title = "VoyagerCalc"
        win.appearance = NSAppearance(named: appearance)
        win.contentView = NSHostingView(rootView: ContentView().environmentObject(app))
        win.setFrame(NSRect(x: 0, y: 0, width: width, height: 560), display: false)
        for _ in 0..<8 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            win.contentView?.layoutSubtreeIfNeeded()
        }
        win.displayIfNeeded()
        let frame = try XCTUnwrap(win.contentView?.superview)
        let rep = try XCTUnwrap(frame.bitmapImageRepForCachingDisplay(in: frame.bounds))
        frame.cacheDisplay(in: frame.bounds, to: rep)
        win.close()
        return rep
    }

    private func rgb(_ rep: NSBitmapImageRep, xFrac: Double, yPt: Double) -> [Int] {
        let scale = Double(rep.pixelsWide) / Double(rep.size.width)
        let c = rep.colorAt(x: Int(xFrac * Double(rep.pixelsWide - 1)), y: Int(yPt * scale))?.usingColorSpace(.sRGB)
        guard let c else { return [-1, -1, -1] }
        return [Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded())]
    }

    /// 1. The title bar has one colour from the left edge to the right edge: closed and open flyout, light and dark.
    func testTitleBarHasOneColourAcrossTheWindow() throws {
        defer { WindowChrome.enabled = true }
        for (inspector, width) in [(false, CGFloat(900)), (true, CGFloat(1220))] {
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let tag = "\(inspector ? "flyout" : "noflyout")-\(appearance == .aqua ? "light" : "dark")"
                let app = try runningApp(inspector: inspector)
                defer { app.stopEngine() }

                WindowChrome.enabled = false                       // the 0.6.6 behaviour, kept as a picture for comparison
                let before = try renderWindow(app, width: width, appearance: appearance)
                try before.representation(using: .png, properties: [:])?.write(to: outDir.appendingPathComponent("titlebar-0.6.6-\(tag).png"))

                WindowChrome.enabled = true
                let rep = try renderWindow(app, width: width, appearance: appearance)
                try rep.representation(using: .png, properties: [:])?.write(to: outDir.appendingPathComponent("titlebar-0.6.7-\(tag).png"))
                let fractions = [0.08, 0.2, 0.35, 0.65, 0.8, 0.92, 0.985]
                let bar = fractions.map { rgb(rep, xFrac: $0, yPt: 5) }
                let old = fractions.map { rgb(before, xFrac: $0, yPt: 5) }
                print("TITLEBAR \(tag): 0.6.7 \(bar) | 0.6.6 \(old)")
                for c in bar {
                    XCTAssertGreaterThanOrEqual(c.min() ?? -1, 0, tag)
                    for k in 0..<3 { XCTAssertLessThanOrEqual(abs(c[k] - bar[0][k]), 1, "\(tag): title bar colour changes along the width: \(bar)") }
                }
            }
        }
    }

    // MARK: 3. the two HP 15C Simulator fonts are part of the app

    func testBundledFontsLoadWithoutAnyUserFile() throws {
        for f in [DocFontStore.keysFile, DocFontStore.displayFile] {
            let u = try XCTUnwrap(DocFontStore.bundledURL(f), "\(f) is not in the bundle")
            XCTAssertTrue(u.path.contains(".xctest/") || u.path.contains(".app/"), u.path)
            XCTAssertGreaterThan(try Data(contentsOf: u).count, 30_000)
        }
        let fonts = DocFontStore().load()
        XCTAssertNotNil(fonts.keys); XCTAssertNotNil(fonts.display)
        XCTAssertEqual(fonts.summary, "HP 15C key and display fonts")
        XCTAssertEqual(DocFontStore.role(try XCTUnwrap(fonts.keys)), .keys)
        XCTAssertEqual(DocFontStore.role(try XCTUnwrap(fonts.display)), .display)
    }

    func testFontCreditNamesRechlinAndManz() {
        let c = DocFontStore.credit
        XCTAssertTrue(c.contains("key-cap font by Eric Rechlin"), c)
        XCTAssertTrue(c.contains("display font by Torsten Manz") && c.contains("© 2005 Torsten Manz, Freeware"), c)
        XCTAssertFalse(c.contains("HP Inc"), "the key font is not HP's")
    }

    func testPDFAlwaysUsesTheBundledFonts() throws {
        let fonts = DocFontStore().load()
        let c = try ProgramDocTests.sampleContent()
        let pdf = ProgramDocumentPDF.render(c, paper: .a4, fonts: fonts.pdfSet())
        let s = String(decoding: pdf, as: UTF8.self)
        XCTAssertTrue(s.contains("/BaseFont /VCKEYS+HP15CSimulatorKeys"))
        XCTAssertTrue(s.contains("/BaseFont /VCDISP+HP15CSimulatorDisplay"))
        XCTAssertEqual(s.components(separatedBy: "/FontFile2").count - 1, 2)
        if let dir = ProcessInfo.processInfo.environment["VC_SCREENS_DIR"] {
            try? pdf.write(to: URL(fileURLWithPath: dir).appendingPathComponent("mac-financepac-doc-bundled-fonts-0.6.7.pdf"))
        }
    }

    /// File ▸ Export Program Documentation (PDF)… through the real AppModel: the document handed to the save panel
    /// carries both fonts, with nothing chosen by the user.
    func testExportPDFFromTheAppEmbedsTheBundledFonts() async throws {
        guard let fw = Fixtures.hp15c3ROM else { throw XCTSkip("no C8C8") }
        let fp = try Data(contentsOf: Fixtures.fixturesDir.appendingPathComponent("FinancePac.15c"))
        let m = CalculatorMachine()
        try m.loadFirmware(fw); try m.boot(restoring: nil)
        if m.variant != 152 { try m.switchModel(to: 152) }
        try m.putMemory(fp)
        let app = AppModel()
        app.persistState = false; app.showInspector = true
        app.attach(m, firmwareName: "C8C8")
        defer { app.stopEngine() }
        app.memoryFileName = "FinancePac.15c"
        let end = Date().addingTimeInterval(20)
        while app.inspection?.program.count != 407, Date() < end { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(app.inspection?.program.count, 407)
        app.exportPDF()
        while app.exportDocument == nil, Date() < end { try await Task.sleep(nanoseconds: 20_000_000) }
        let doc = try XCTUnwrap(app.exportDocument, "no PDF was produced")
        XCTAssertTrue(doc.data.starts(with: Data("%PDF-1.4".utf8)))
        let s = String(decoding: doc.data, as: UTF8.self)
        XCTAssertTrue(s.contains("VCKEYS+HP15CSimulatorKeys") && s.contains("VCDISP+HP15CSimulatorDisplay"))
        XCTAssertEqual(s.components(separatedBy: "/FontFile2").count - 1, 2)
    }

    // MARK: 2. greyed emblem panels

    /// The unlit panels of the emblem on the faces are about 18 % closer to the lit tone than the 0.6.5 ones
    /// (70 / 60 before, 96 / 88 now, mean about 92, against a lit panel of about 205-215): neutral grey, so the
    /// lettering (34) reads better; the model's own panel stays lit. Badge squares as measured (art/faces/geometry.json).
    func testEmblemUnlitPanelsAreLighterButStillGrey() throws {
        let faces: [(name: String, badge: CGRect, lit: Int)] = [
            ("face_12c_nolcd", CGRect(x: 1739, y: 82, width: 148, height: 148), 0),
            ("face_15c_nolcd", CGRect(x: 1740, y: 113, width: 147, height: 147), 1),      // v3 / v4 photo faces (0.7.4: re-measured)
            ("face_16c_nolcd", CGRect(x: 1741, y: 116, width: 147, height: 147), 2)]
        for f in faces {
            let url = try XCTUnwrap(Bundle(for: Release067Tests.self).url(forResource: f.name, withExtension: "png"), f.name)
            let rep = try XCTUnwrap(NSBitmapImageRep(data: try Data(contentsOf: url)))
            XCTAssertEqual(rep.pixelsWide, 2000)
            func tone(_ row: Int) -> (r: Double, g: Double, b: Double) {
                // left of the lettering, inside the panel: x = 7 % of the badge; row centres of the three panels
                let fy = [0.2, 0.5, 0.83][row]
                let x = Int(f.badge.minX + 0.07 * f.badge.width), y = Int(f.badge.minY + fy * f.badge.height)
                let c = rep.colorAt(x: x, y: y)!
                return (Double(c.redComponent * 255), Double(c.greenComponent * 255), Double(c.blueComponent * 255))
            }
            for row in 0..<3 {
                let t = tone(row)
                if row == f.lit {
                    XCTAssertGreaterThan(t.r, 190, "\(f.name): the model's own panel stays lit")
                } else {
                    XCTAssertGreaterThan(t.r, 86, "\(f.name) panel \(row): lighter than the 0.6.5 grey (70..60): \(t)")
                    XCTAssertLessThan(t.r, 100, "\(f.name) panel \(row): still a modest change: \(t)")
                    XCTAssertEqual(t.r, t.b, accuracy: 3, "\(f.name) panel \(row): neutral grey")
                }
            }
        }
    }
}
#endif
