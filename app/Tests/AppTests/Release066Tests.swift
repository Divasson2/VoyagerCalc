// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// 0.6.6: HP's original 12C firmware through the real AppModel and engine. The calculator runs; the CE-only features
// (Registers & Program, memory files, USB memory transfer, program documentation, model switch) are greyed out or
// say plainly that they are not available, instead of showing wrong data. Synthetic stock-like image only (no HP code).
#if os(macOS)
import AppKit
import SwiftUI
import XCTest

@MainActor
final class Release066Tests: XCTestCase {
    private func stockApp() throws -> (AppModel, CalculatorMachine) {
        let m = CalculatorMachine()
        try m.loadFirmware(Data(FirmwareLoadTests.Synthetic.image(stock: true, block: 0x20000100)))
        try m.boot(restoring: nil)
        let app = AppModel()
        app.persistState = false
        app.attach(m, firmwareName: "synthetic stock")
        return (app, m)
    }

    private let limit = "not available with HP's original 12C firmware"

    func testStockFirmwareGreysOutTheCEOnlyFeatures() throws {
        let (app, _) = try stockApp()
        defer { app.stopEngine() }
        XCTAssertTrue(app.isRunning)
        XCTAssertTrue(app.isStock)
        XCTAssertEqual(app.capabilities, .keysDisplay)
        XCTAssertFalse(app.hasInspector)
        XCTAssertFalse(app.hasMemoryFiles)
        XCTAssertTrue(app.familyDescription.contains("original 12C"), app.familyDescription)
        XCTAssertEqual(app.images, [120])
        XCTAssertFalse(app.canSwitchModel)
        XCTAssertTrue(AppModel.stockLimits.contains("Registers & Program") && AppModel.stockLimits.contains("Memory File"))

        // the inspector preference is kept, but nothing is shown
        let before = app.showInspector
        app.showInspector = true
        XCTAssertFalse(app.inspectorVisible)
        app.showInspector = before

        func expectRefusal(_ what: String, _ action: () -> Void, file: StaticString = #filePath, line: UInt = #line) {
            app.errorMessage = nil
            action()
            XCTAssertTrue(app.errorMessage?.contains(limit) == true, "\(what): \(app.errorMessage ?? "no message")", file: file, line: line)
            XCTAssertTrue(app.errorMessage?.contains("Registers & Program") == true, what, file: file, line: line)
        }
        expectRefusal("open memory") { app.openMemory() }
        XCTAssertFalse(app.showImporter)
        expectRefusal("open a memory file from Finder") { app.memoryPicked(.success(URL(fileURLWithPath: "/tmp/none.12c"))) }
        expectRefusal("save memory") { app.saveMemory() }
        XCTAssertNil(app.exportDocument)
        expectRefusal("switch model") { app.chooseModel(120) }
        XCTAssertNil(app.pendingAction)
        expectRefusal("program info") { app.openProgramInfo() }
        XCTAssertFalse(app.showProgramInfo)
        expectRefusal("program notes") { app.saveNotes() }
        expectRefusal("open notes") { app.openNotes() }
        XCTAssertFalse(app.showImporter)
        expectRefusal("export PDF") { app.exportPDF() }
        expectRefusal("export text") { app.exportText() }
        XCTAssertNil(app.exportDocument)
        #if os(macOS)
        expectRefusal("read from calculator") { app.readFromCalculator() }
        expectRefusal("write to calculator") { app.writeToCalculator() }
        XCTAssertNil(app.linkStatus)
        #endif
    }

    func testStockFirmwareKeepsRunningAfterTheRefusals() async throws {
        let (app, m) = try stockApp()
        defer { app.stopEngine() }
        app.saveStateNow()                       // nothing to save, and it must not turn the calculator off
        app.openMemory(); app.saveMemory(); app.chooseModel(120)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(app.isRunning)
        XCTAssertNil(app.pendingAction)
        XCTAssertTrue(app.snapshot.model == 12 || app.snapshot.model == 0)
        XCTAssertEqual(m.capabilities, .keysDisplay)
    }

    func testCEFirmwareKeepsEverything() throws {
        guard let fw = Fixtures.multi else { throw XCTSkip("no 12C multi firmware") }
        let m = CalculatorMachine()
        try m.loadFirmware(fw); try m.boot(restoring: nil)
        let app = AppModel()
        app.persistState = false
        app.attach(m, firmwareName: "multi")
        defer { app.stopEngine() }
        XCTAssertFalse(app.isStock)
        XCTAssertEqual(app.capabilities, .all)
        XCTAssertTrue(app.hasInspector && app.hasMemoryFiles)
        XCTAssertTrue(app.canSwitchModel)
    }
}
#endif
