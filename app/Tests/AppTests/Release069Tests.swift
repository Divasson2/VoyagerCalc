// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// 0.6.9: (1) memory files: default ending .bin12c/.bin15c/.bin16c, any ending accepted, legacy endings and text files, notes lookup;
// (2) a reset / model switch / firmware change clears ALL notes; (3) the window keeps the calculator's shape (pure arithmetic and the
// delegate in front of SwiftUI's); (4) 12C branch target 00 is always defined and the text export has BRANCH TARGETS;
// (5) Esc: one place handles it. Synthetic data only (no HP code).
#if os(macOS)
import AppKit
import SwiftUI
import XCTest

@MainActor
final class Release069Tests: XCTestCase {
    // MARK: 1. memory file names

    func testDefaultEndingsAreBinNNc() {
        XCTAssertEqual(CalculatorModel.hp12c.fileExtension, "bin12c")
        XCTAssertEqual(CalculatorModel.hp15c.fileExtension, "bin15c")
        XCTAssertEqual(CalculatorModel.hp16c.fileExtension, "bin16c")
        for id in [12, 15, 16] { XCTAssertEqual(MemoryFileNames.defaultExtension(forModel: id), "bin\(id)c") }
    }

    func testEndingsHintAtTheModelOldAndNew() {
        for (e, id) in [("bin12c", 12), ("12c", 12), ("12cmem", 12), ("BIN15C", 15), ("15c", 15), ("15cmem", 15), ("bin16c", 16), ("16C", 16), ("16cmem", 16)] {
            XCTAssertEqual(MemoryFileNames.modelHint(forExtension: e), id, e)
        }
        for e in ["", "bin", "txt", "bin17c", "15", "c15"] { XCTAssertNil(MemoryFileNames.modelHint(forExtension: e), e) }
    }

    func testAnyEndingOpensByContent() {
        let image = Data(repeating: 0x5A, count: 2048)
        XCTAssertEqual(MemoryFileNames.classify(image), .image)
        XCTAssertNil(MemoryFileNames.problem(with: image, name: "anything.xyz"))
        XCTAssertNil(MemoryFileNames.problem(with: Data((0..<2048).map { UInt8($0 & 255) }), name: "noending"))
        XCTAssertEqual(MemoryFileNames.classify(Data(repeating: 0, count: 100)), .wrongSize(100))
        XCTAssertTrue(MemoryFileNames.problem(with: Data(repeating: 1, count: 100), name: "x.bin15c")!.contains("exactly 2048 bytes; this one has 100"))
    }

    func testTextProgramsGetTheirOwnMessage() {
        let manz = "# HEWLETT·PACKARD 15C Simulator program\n# Created with something\n{ 001 } 42 21 11  # LBL A\n{ 002 } 15\n"
        for data in [Data(manz.utf8), Data([0xFF, 0xFE]) + (manz.data(using: .utf16LittleEndian) ?? Data()), Data([0xEF, 0xBB, 0xBF]) + Data(manz.utf8)] {
            XCTAssertEqual(MemoryFileNames.classify(data), .text)
            let m = MemoryFileNames.problem(with: data, name: "prog.15c")
            XCTAssertTrue(m?.contains("text program") == true, m ?? "nil")
        }
        // a text file of exactly 2048 bytes is still text (BOM / printable test comes before the size test)
        let padded = Data((manz + String(repeating: "# pad\n", count: 400)).utf8.prefix(2048))
        XCTAssertEqual(padded.count, 2048)
        XCTAssertEqual(MemoryFileNames.classify(padded), .text)
        // a binary image full of every byte value is not text
        XCTAssertEqual(MemoryFileNames.classify(Data((0..<2048).map { UInt8(($0 &* 7) & 255) })), .image)
    }

    func testSidecarLookupFindsOldAndNewNames() {
        let new = URL(fileURLWithPath: "/x/FinancePac.bin15c")
        let c = MemoryFileNames.sidecarCandidates(for: new).map(\.lastPathComponent)
        XCTAssertEqual(c.first, "FinancePac.bin15c.voyagerdoc")
        XCTAssertTrue(c.contains("FinancePac.15c.voyagerdoc") && c.contains("FinancePac.15cmem.voyagerdoc") && c.contains("FinancePac.voyagerdoc"))
        let old = MemoryFileNames.sidecarCandidates(for: URL(fileURLWithPath: "/x/FinancePac.15c")).map(\.lastPathComponent)
        XCTAssertEqual(old.first, "FinancePac.15c.voyagerdoc")
        XCTAssertTrue(old.contains("FinancePac.bin15c.voyagerdoc"))
        // another ending (typed by the user): its own name, then the bare name
        let other = MemoryFileNames.sidecarCandidates(for: URL(fileURLWithPath: "/x/mine.dat")).map(\.lastPathComponent)
        XCTAssertEqual(other, ["mine.dat.voyagerdoc", "mine.voyagerdoc"])
    }

    func testTheEndingTypedLastTimeIsOfferedAgain() {
        var n = ExportNameMemory()
        XCTAssertNil(n.ending(for: "memory"))
        n.remember("memory", url: URL(fileURLWithPath: "/x/Calc.dat"))
        XCTAssertEqual(n.ending(for: "memory"), "dat")
        XCTAssertEqual(n.name(for: "memory", default: "d"), "Calc")
        n.remember("memory", url: URL(fileURLWithPath: "/x/Noext"))
        XCTAssertNil(n.ending(for: "memory"))
        n.remember("memory", url: URL(fileURLWithPath: "/x/A.bin16c")); n.forgetAll()
        XCTAssertNil(n.ending(for: "memory")); XCTAssertTrue(n.isEmpty)
    }

    func testSuggestedFileNameAndSaving() throws {
        let app = AppModel(); app.persistState = false
        XCTAssertTrue(app.memorySuggestedFileName.hasSuffix(".bin\(app.model.id)c"), app.memorySuggestedFileName)
        // the panel's result: the typed ending is kept exactly, and the next suggestion uses it
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vc069-\(UUID().uuidString).whatever")
        defer { try? FileManager.default.removeItem(at: url) }
        let data = Data(repeating: 7, count: 2048)
        app.memoryPanelFinished(.OK, url: url, data: data)
        XCTAssertEqual(try Data(contentsOf: url), data)
        XCTAssertNil(app.errorMessage)
        XCTAssertTrue(app.memorySuggestedFileName.hasSuffix(".whatever"), app.memorySuggestedFileName)
        // a cancelled panel writes nothing and says nothing
        let none = FileManager.default.temporaryDirectory.appendingPathComponent("vc069-none-\(UUID().uuidString).bin15c")
        app.memoryPanelFinished(.cancel, url: none, data: data)
        XCTAssertFalse(FileManager.default.fileExists(atPath: none.path)); XCTAssertNil(app.errorMessage)
        // an unwritable place is an error message, not a crash
        app.memoryPanelFinished(.OK, url: URL(fileURLWithPath: "/nonexistent-folder-069/x.bin15c"), data: data)
        XCTAssertNotNil(app.errorMessage)
    }

    func testOpeningALegacyAndATextFileThroughMemoryPicked() throws {
        let m = CalculatorMachine()
        try m.loadFirmware(Data(FirmwareLoadTests.Synthetic.image(stock: false, block: 0x20000854)))
        try m.boot(restoring: nil)
        let app = AppModel(); app.persistState = false
        app.attach(m, firmwareName: "synthetic")
        defer { app.stopEngine() }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vc069-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let text = dir.appendingPathComponent("prog.15c")
        try Data("# Simulator program\n{ 001 } 42 21 11\n".utf8).write(to: text)
        app.memoryPicked(.success(text))
        XCTAssertTrue(app.errorMessage?.contains("text program") == true, app.errorMessage ?? "nil")
        app.errorMessage = nil
        let small = dir.appendingPathComponent("small.bin15c")
        try Data(repeating: 0, count: 10).write(to: small)
        app.memoryPicked(.success(small))
        XCTAssertTrue(app.errorMessage?.contains("exactly 2048 bytes") == true, app.errorMessage ?? "nil")
    }

    func testInfoPlistsNoLongerClaimTheOldEndings() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for name in ["macOS", "iOS"] {
            let url = root.appendingPathComponent("Resources/\(name)/Info.plist")
            let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: try Data(contentsOf: url), format: nil) as? [String: Any])
            let exported = try XCTUnwrap(plist["UTExportedTypeDeclarations"] as? [[String: Any]])
            var extensions: [String] = []
            for d in exported {
                let spec = d["UTTypeTagSpecification"] as? [String: Any]
                extensions += (spec?["public.filename-extension"] as? [String]) ?? []
            }
            XCTAssertEqual(Set(extensions), Set(["bin12c", "bin15c", "bin16c", "voyagerdoc"]), name)
            for old in ["12c", "15c", "16c", "12cmem", "15cmem", "16cmem"] { XCTAssertFalse(extensions.contains(old), "\(name) still declares .\(old)") }
        }
    }

    // MARK: 2. everything is cleared

    private func synthetic(block: UInt32, stock: Bool = false) throws -> CalculatorMachine {
        let m = CalculatorMachine()
        try m.loadFirmware(Data(FirmwareLoadTests.Synthetic.image(stock: stock, block: block)))
        try m.boot(restoring: nil)
        return m
    }

    private func richDoc() -> ProgramDocument {
        var d = ProgramDocument()
        d.title = "T"; d.author = "A"; d.description = "D"
        d.labels["A"] = "label note"; d.registers["R1"] = RegisterNote(name: "n", meaning: "m"); d.flags["1"] = "flag note"
        d.comments = [StepComment(step: 3, text: "kept", keys: "40"), StepComment(step: 9, text: "gone", keys: "30", orphaned: true)]
        return d
    }

    func testFirmwareChangeClearsEverything() throws {
        let app = AppModel(); app.persistState = false
        app.attach(try synthetic(block: 0x20000854), firmwareName: "one")
        app.programDoc = richDoc(); app.programDocURL = URL(fileURLWithPath: "/x/n.voyagerdoc"); app.memoryFileName = "x.bin15c"
        // the same firmware again (a restart of the engine): notes stay
        app.attach(try synthetic(block: 0x20000854), firmwareName: "one")
        XCTAssertEqual(app.programDoc, richDoc())
        // another firmware: nothing is left
        app.attach(try synthetic(block: 0x20000000), firmwareName: "two")
        defer { app.stopEngine() }
        XCTAssertEqual(app.programDoc, ProgramDocument())
        XCTAssertTrue(app.programDoc.isEmpty); XCTAssertTrue(app.programDoc.orphanedComments.isEmpty)
        XCTAssertNil(app.programDocURL); XCTAssertNil(app.memoryFileName)
    }

    func testMemoryResetClearsEverything() throws {
        let app = AppModel(); app.persistState = false
        app.attach(try synthetic(block: 0x20000854), firmwareName: "one")
        defer { app.stopEngine() }
        app.programDoc = richDoc(); app.memoryFileName = "x.bin15c"
        app.confirm(.memoryReset)
        XCTAssertTrue(app.programDoc.isEmpty); XCTAssertEqual(app.programDoc.title, ""); XCTAssertEqual(app.programDoc.author, "")
        XCTAssertEqual(app.programDoc.description, ""); XCTAssertTrue(app.programDoc.comments.isEmpty)
        XCTAssertNil(app.memoryFileName)
    }

    func testStoredNotesDoNotComeBackAfterAFirmwareChange() throws {
        let app = AppModel()                       // persistState on: the notes are kept per firmware between launches
        app.persistState = true
        app.attach(try synthetic(block: 0x20000854), firmwareName: "one")
        app.programDoc = richDoc()
        XCTAssertNotNil(UserDefaults.standard.data(forKey: app.docDefaultsKey))
        app.attach(try synthetic(block: 0x20000000), firmwareName: "two")          // another firmware: cleared
        XCTAssertTrue(app.programDoc.isEmpty)
        app.attach(try synthetic(block: 0x20000854), firmwareName: "one")          // back again: still nothing (it was cleared, not parked)
        defer { app.stopEngine(); app.clearAllNotes(forgetStored: true) }
        XCTAssertTrue(app.programDoc.isEmpty)
    }

    // MARK: 4. 12C branch targets

    private func lines12(_ m: [String]) -> [ProgramLine] {
        m.enumerated().map { ProgramLine(line: $0 + 1, keys: "x", mnemonic: $1, prefix: $1.hasPrefix("GTO") ? "g" : "", bytes: []) }
    }

    private func content12(_ mn: [String]) -> ProgramDocumentContent {
        ProgramDocumentContent(doc: ProgramDocument(), info: ProgramDocumentInfo(modelName: "HP-12C", firmware: "", memoryFile: "t.bin12c", model: 12,
                                                                                 date: Date(timeIntervalSince1970: 0)), lines: lines12(mn))
    }

    func testTwelveCTargetZeroIsAlwaysDefined() {
        let a = ProgramAnalysis(lines: lines12(["GTO 00", "1", "GTO 03", "GTO 09"]), model: 12)
        func lab(_ n: String) -> ProgramAnalysis.Label? { a.labels.first { $0.name == n } }
        XCTAssertEqual(lab("00")?.defined, [0]); XCTAssertEqual(lab("00")?.called, [1])
        XCTAssertEqual(lab("03")?.defined, [3])
        XCTAssertEqual(lab("09")?.defined, [], "line 9 is beyond the program")
        let c = content12(["GTO 00", "1", "GTO 03", "GTO 09"])
        let rows = Dictionary(uniqueKeysWithValues: c.labelRows.map { ($0.label, $0.defined) })
        XCTAssertEqual(rows["line 00"], "00 (start)")
        XCTAssertEqual(rows["line 03"], "03")
        XCTAssertEqual(rows["line 09"], "not defined")
        // an EMPTY 12C program is eight GTO 00 steps: no red "not defined"
        let empty = content12(Array(repeating: "GTO 00", count: 8))
        XCTAssertEqual(empty.labelRows.map(\.defined), ["00 (start)"])
        XCTAssertFalse(empty.plainText().contains("not defined"))
        XCTAssertTrue(ProgramDocumentPDF.render(empty, paper: .a4).starts(with: Data("%PDF-1.4".utf8)))
    }

    func testTwelveCTextExportAlwaysHasBranchTargets() {
        let t = content12(["GTO 00", "1", "GTO 03"]).plainText()
        XCTAssertTrue(t.contains("\nBRANCH TARGETS\n"), t)
        XCTAssertTrue(t.contains("Line"), t); XCTAssertTrue(t.contains("line 00") && t.contains("00 (start)"), t)
        XCTAssertFalse(t.contains("\nLABELS\n"))
        // a program without any GTO: the section is still there
        let none = content12(["1", "2", "+"]).plainText()
        XCTAssertTrue(none.contains("\nBRANCH TARGETS\n"), none); XCTAssertTrue(none.contains("No GTO in this program."), none)
        // the section comes before the listing, as in the PDF
        XCTAssertLessThan(t.range(of: "BRANCH TARGETS")!.lowerBound, t.range(of: "LISTING")!.lowerBound)
        // 15C / 16C keep LABELS
        let c15 = ProgramDocumentContent(doc: ProgramDocument(), info: ProgramDocumentInfo(modelName: "HP-15C", firmware: "", memoryFile: "", model: 15,
                                         date: Date(timeIntervalSince1970: 0)),
                                         lines: [ProgramLine(line: 1, keys: "42,21,11", mnemonic: "LBL A", prefix: "f", bytes: []),
                                                 ProgramLine(line: 2, keys: "43,32", mnemonic: "GTO A", prefix: "", bytes: [])])
        XCTAssertTrue(c15.plainText().contains("\nLABELS\n")); XCTAssertFalse(c15.plainText().contains("BRANCH TARGETS"))
    }

    // MARK: 5. Esc is handled in one place

    func testEscPressesOnOnceFromTheKeyRouterAndNeverTwiceFromTheMenu() throws {
        let app = AppModel(); app.persistState = false
        app.attach(try synthetic(block: 0x20000854), firmwareName: "one")
        defer { app.stopEngine() }
        var downs = 0
        let original = app.keyRouter.press
        app.keyRouter.press = { downs += 1; original($0) }
        // Esc down + up: the router presses ON once (and keeps it held until the key goes up)
        XCTAssertTrue(app.keyRouter.keyDown(id: 53, shortcut: .special(.escape), isRepeat: false))
        XCTAssertTrue(app.keyRouter.keyDown(id: 53, shortcut: .special(.escape), isRepeat: true), "auto-repeat is swallowed")
        XCTAssertEqual(downs, 1)
        XCTAssertTrue(app.keyRouter.keyUp(id: 53))
        // the same key arriving at the menu item (sheet / text field in front): the menu does nothing
        app.powerMenuAction(fromKeyboard: true)
        XCTAssertEqual(app.powerToggleCount, 0)
        // a click on the menu item presses ON
        app.powerMenuAction(fromKeyboard: false)
        XCTAssertEqual(app.powerToggleCount, 1)
    }

    func testOnOffMenuItemHasNoEscInItsTitle() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for f in ["Sources/App/VoyagerCalcApp.swift", "Sources/Views/MainViews.swift"] {
            let s = try String(contentsOf: root.appendingPathComponent(f), encoding: .utf8)
            XCTAssertTrue(s.contains("Button(\"ON / OFF\")"), f)
            XCTAssertFalse(s.contains("ON / OFF (Esc)"), f)
            XCTAssertTrue(s.contains(".keyboardShortcut(.escape, modifiers: [])"), f)
        }
    }

    // MARK: 3. the window keeps the calculator's shape

    func testShapeRuleIsExactForEveryHeightAndFlyoutState() {
        let a: CGFloat = 2000.0 / 1240.0
        let screen = CGSize(width: 2000, height: 1200)
        for flyout in [false, true] {
            for h in stride(from: CGFloat(300), through: 900, by: 37) {
                let c = WindowFit.fitContent(proposed: CGSize(width: 10, height: h), current: CGSize(width: 10, height: h + 1), aspect: a, flyout: flyout, maxContent: screen)
                let calc = c.width - (flyout ? 320 : 0)
                XCTAssertEqual(calc / c.height, a, accuracy: 0.003, "h \(h) flyout \(flyout)")
            }
        }
        // closing the flyout: the width comes back to the shape exactly, however the window was before (no stored delta)
        let open = WindowFit.fitContent(proposed: CGSize(width: 1300, height: 560), current: CGSize(width: 1300, height: 560), aspect: a, flyout: true, maxContent: screen)
        let closed = WindowFit.fitContent(proposed: open, current: open, aspect: a, flyout: false, maxContent: screen)
        XCTAssertEqual(closed.width, (560 * a).rounded()); XCTAssertEqual(closed.height, 560)
    }

    func testDraggingTheWidthLeadsWhenTheWidthChangedMore() {
        let a: CGFloat = 1.6, screen = CGSize(width: 3000, height: 2000)
        let r = WindowFit.fitContent(proposed: CGSize(width: 1280, height: 601), current: CGSize(width: 960, height: 600), aspect: a, flyout: false, maxContent: screen)
        XCTAssertEqual(r.width, 1280); XCTAssertEqual(r.height, 800)
        let r2 = WindowFit.fitContent(proposed: CGSize(width: 961, height: 800), current: CGSize(width: 960, height: 600), aspect: a, flyout: false, maxContent: screen)
        XCTAssertEqual(r2.height, 800); XCTAssertEqual(r2.width, 1280)
        // with the flyout the 320 pt column is added, not scaled
        let r3 = WindowFit.fitContent(proposed: CGSize(width: 1600, height: 601), current: CGSize(width: 1280, height: 600), aspect: a, flyout: true, maxContent: screen)
        XCTAssertEqual(r3.width, 1600); XCTAssertEqual(r3.height, 800)
    }

    func testShapeRuleRespectsTheMinimumAndTheScreen() {
        let a: CGFloat = 1.6
        let small = WindowFit.fitContent(proposed: CGSize(width: 100, height: 100), current: CGSize(width: 900, height: 560), aspect: a, flyout: false, maxContent: CGSize(width: 3000, height: 2000))
        XCTAssertEqual(small.height, WindowFit.minCalculatorHeight); XCTAssertEqual(small.width, 480)
        let big = WindowFit.fitContent(proposed: CGSize(width: 5000, height: 4000), current: CGSize(width: 900, height: 560), aspect: a, flyout: true, maxContent: CGSize(width: 1440, height: 800))
        XCTAssertLessThanOrEqual(big.width, 1440); XCTAssertLessThanOrEqual(big.height, 800)
        XCTAssertEqual((big.width - 320) / big.height, a, accuracy: 0.01)
    }

    func testShapedFrameKeepsTopLeftAndStaysOnTheScreen() {
        let visible = CGRect(x: 0, y: 0, width: 1600, height: 900)
        let f = CGRect(x: 100, y: 200, width: 1220, height: 560 + 28)       // a flyout-sized window, flyout now closed
        let r = WindowFit.shapedFrame(f, titleBarHeight: 28, aspect: 1.6, flyout: false, visible: visible)
        XCTAssertEqual(r.width, 896); XCTAssertEqual(r.height, 588)
        XCTAssertEqual(r.minX, 100); XCTAssertEqual(r.maxY, f.maxY, "the top edge stays")
        let o = WindowFit.shapedFrame(CGRect(x: 1000, y: 100, width: 896, height: 588), titleBarHeight: 28, aspect: 1.6, flyout: true, visible: visible)
        XCTAssertEqual(o.width, 1216); XCTAssertEqual(o.maxX, 1600, "shifted left to stay on the screen")
        // idempotent
        XCTAssertEqual(WindowFit.shapedFrame(o, titleBarHeight: 28, aspect: 1.6, flyout: true, visible: visible), o)
    }

    final class OriginalDelegate: NSObject, NSWindowDelegate {
        var closeAsked = 0
        func windowShouldClose(_ sender: NSWindow) -> Bool { closeAsked += 1; return false }
    }

    func testTheDelegateInFrontEnforcesTheShapeAndForwardsTheRest() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 560), styleMask: [.titled, .closable, .resizable],
                         backing: .buffered, defer: true)                                    // never shown
        let original = OriginalDelegate()
        w.delegate = original
        let d = WindowShapeDelegate(original: original)
        d.aspect = 1.6; d.flyout = false
        w.delegate = d
        // forwarding: a method only the original has
        XCTAssertTrue(d.responds(to: #selector(NSWindowDelegate.windowShouldClose(_:))))
        let asDelegate: NSWindowDelegate = d
        XCTAssertEqual(asDelegate.windowShouldClose?(w), false); XCTAssertEqual(original.closeAsked, 1)
        // a drag of the right edge: the height follows
        let cur = w.frame.size
        let dragged = NSSize(width: cur.width + 320, height: cur.height)
        let r = asDelegate.windowWillResize?(w, to: dragged) ?? .zero
        let c = w.contentRect(forFrameRect: NSRect(origin: .zero, size: r)).size
        XCTAssertEqual(c.width / c.height, 1.6, accuracy: 0.01)
        XCTAssertGreaterThan(c.width, 900)
        // with the flyout open the 320 pt column is excluded from the ratio
        d.flyout = true
        let r2 = asDelegate.windowWillResize?(w, to: NSSize(width: cur.width + 400, height: cur.height)) ?? .zero
        let c2 = w.contentRect(forFrameRect: NSRect(origin: .zero, size: r2)).size
        XCTAssertEqual((c2.width - 320) / c2.height, 1.6, accuracy: 0.01)
    }
}
#endif
