// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// 0.5.6 program documentation through the real AppModel and engine: comments typed in the
// listing follow the program when a line is inserted on the calculator, the PDF and text
// exports, and a snapshot of the listing with its comment column.
#if os(macOS)
import AppKit
import SwiftUI
import XCTest

@MainActor
final class ProgramDocAppTests: XCTestCase {
    private func until(_ what: String, timeout: Double = 20, _ cond: () -> Bool) async throws {
        let end = Date().addingTimeInterval(timeout)
        while !cond() {
            if Date() > end { XCTFail("timed out: \(what)"); return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    func testCommentsFollowTheProgramAndExport() async throws {
        guard let fw = Fixtures.hp15c3ROM else { throw XCTSkip("no C8C8") }
        let fp = try Fixtures.data("FinancePac.15c")
        let m = CalculatorMachine()
        try m.loadFirmware(fw); try m.boot(restoring: nil)
        if m.variant != 152 { try m.switchModel(to: 152) }
        try m.putMemory(fp)
        let app = AppModel()
        app.persistState = false; app.showInspector = true; app.skin = .automatic; app.faceStyle = .photo
        app.attach(m, firmwareName: "C8C8")
        defer { app.stopEngine() }
        app.memoryFileName = "FinancePac.15c"
        try await until("FinancePac listed") { app.inspection?.program.count == 407 }

        // enter PRGM (g P/R) and see where the pointer is
        app.press(20, part: .gLabel); try await Task.sleep(nanoseconds: 200_000_000); app.release(20)
        try await until("PRGM") { app.inspection?.programMode == true }
        let l0 = try XCTUnwrap(app.inspection?.line)
        XCTAssertLessThan(l0, 380)
        app.setComment("[example] two steps below the pointer", at: l0 + 2)
        app.setComment("[example] near the end", at: 400)
        XCTAssertEqual(app.comment(at: 400), "[example] near the end")
        // key a digit: a step is inserted after the pointer, the rest moves down by one
        let one = try XCTUnwrap(VoyagerCalculator.keyCode(model: 15, name: "1"))
        app.press(one); try await Task.sleep(nanoseconds: 200_000_000); app.release(one)
        try await until("408 steps") { app.inspection?.program.count == 408 }
        try await until("comments moved") { app.comment(at: 401) == "[example] near the end" }
        XCTAssertEqual(app.comment(at: l0 + 3), "[example] two steps below the pointer")
        XCTAssertEqual(app.comment(at: 400), "")
        XCTAssertTrue(app.programDoc.orphanedComments.isEmpty)

        // exports
        let s = try XCTUnwrap(app.inspection)
        let content = app.documentContent(s)
        XCTAssertEqual(content.info.modelName, "HP-15C (15.2)")
        XCTAssertEqual(content.title, "FinancePac.15c")
        let pdf = ProgramDocumentPDF.render(content, paper: .a4)
        XCTAssertTrue(pdf.starts(with: Data("%PDF-1.4".utf8)))
        let text = content.plainText()
        XCTAssertTrue(text.contains("[example] near the end"))
        XCTAssertTrue(text.contains("Steps:     408"))
        let back = try ProgramDocument.decode(try app.programDoc.encoded())
        XCTAssertEqual(back.comments.count, 2)

        // snapshot: the listing with the comment column
        let w: CGFloat = 900, h = w / app.faceAspect
        let v = HStack(spacing: 0) {
            CalculatorView(forcedLayout: .landscape).environmentObject(app).frame(width: w, height: h)
                .frame(maxHeight: .infinity).background(Color(rgb: 0x1C1714))
            Divider()
            InspectorView().environmentObject(app).environment(\.inspectorStatic, true)
                .frame(width: 420).background(Color(rgb: 0x1E1E1E))
        }
        .environment(\.colorScheme, .dark)
        let r = ImageRenderer(content: v.frame(width: w + 421, height: 640)); r.scale = 2
        let cg = try XCTUnwrap(r.cgImage)
        let dir = ProcessInfo.processInfo.environment["VC_SCREENS_DIR"].map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("VoyagerCalcScreens")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try XCTUnwrap(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
            .write(to: dir.appendingPathComponent("mac-15c-program-comments.png"))
        try pdf.write(to: dir.appendingPathComponent("mac-financepac-doc.pdf"))
    }
}
#endif
