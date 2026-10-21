// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// 0.7.1 (port of the Qt 0.7.1 changes): Turbo removed (always real time) and the real-CE speed (IPC 0.577); View ▸ Click
// f/g Labels (on by default) and Key Click Sound (off); the lighter 15C / 16C LCD (screen 0x666666, 12C unchanged); opaque
// inspector section headers; keys typed in another window stay there; the HP-15C Matrix Editor (model with fake memory and
// through the real emulator); pictures of the faces and the editor ($VC_SCREENS_DIR). No HP code in here.
#if os(macOS)
import AppKit
import SwiftUI
import XCTest

@MainActor
final class Release071Tests: XCTestCase {
    private var outDir: URL {
        let env = ProcessInfo.processInfo.environment["VC_SCREENS_DIR"]
        let u = env.map { URL(fileURLWithPath: $0) } ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("VoyagerCalcScreens")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    private func until(_ what: String, timeout: Double = 20, _ cond: () -> Bool) async throws {
        let end = Date().addingTimeInterval(timeout)
        while !cond() {
            if Date() > end { XCTFail("timed out: \(what)"); return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func app15() throws -> AppModel {
        guard let fw = Fixtures.hp15c3ROM else { throw XCTSkip("no C8C8 15C firmware") }
        let m = CalculatorMachine()
        try m.loadFirmware(fw); try m.boot(restoring: nil)
        if m.variant != 150 { try m.switchModel(to: 150) }
        let app = AppModel()
        app.persistState = false; app.showInspector = true; app.skin = .automatic; app.faceStyle = .photo
        app.attach(m, firmwareName: "C8C8")
        return app
    }

    private func png(_ rep: NSBitmapImageRep, _ name: String) throws {
        let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let url = outDir.appendingPathComponent(name)
        try data.write(to: url)
        print("snapshot: \(url.path) \(rep.pixelsWide)x\(rep.pixelsHigh)")
    }

    private func render<V: View>(_ view: V, width: CGFloat, height: CGFloat, name: String) throws -> CGImage {
        let r = ImageRenderer(content: view.frame(width: width, height: height))
        r.scale = 2
        let cg = try XCTUnwrap(r.cgImage, name)
        try png(NSBitmapImageRep(cgImage: cg), name)
        return cg
    }

    /// A window that is never put on screen, drawn with its AppKit controls (text fields, steppers, pickers).
    private func renderWindow<V: View>(_ view: V, size: NSSize, title: String, name: String) throws {
        let win = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .resizable],
                           backing: .buffered, defer: false)
        win.isReleasedWhenClosed = false
        win.title = title
        win.appearance = NSAppearance(named: .aqua)
        win.contentView = NSHostingView(rootView: view)
        win.setContentSize(size)
        for _ in 0..<10 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            win.contentView?.layoutSubtreeIfNeeded()
        }
        win.displayIfNeeded()
        let frame = try XCTUnwrap(win.contentView?.superview)
        let rep = try XCTUnwrap(frame.bitmapImageRepForCachingDisplay(in: frame.bounds))
        frame.cacheDisplay(in: frame.bounds, to: rep)
        win.close()
        try png(rep, name)
    }

    // MARK: speed

    func testAlwaysRealTimeAtRealCESpeed() async throws {
        let app = try app15()
        defer { app.stopEngine() }
        let e = try XCTUnwrap(app.engine)
        XCTAssertEqual(e.performAndWait { $0.calc.clockIPC } ?? 0, 0.577, accuracy: 1e-9)
        let t0 = e.performAndWait { $0.simMs } ?? 0
        try await Task.sleep(nanoseconds: 1_000_000_000)
        let t1 = e.performAndWait { $0.simMs } ?? 0
        XCTAssertEqual(Double(t1 - t0), 1000, accuracy: 250, "calculator time follows the wall clock")
    }

    // MARK: view options

    func testViewOptionDefaults() {
        let d = UserDefaults.standard
        let saved = (d.object(forKey: AppModelKeys.legendClicks), d.object(forKey: AppModelKeys.keyClickSound))
        defer { d.set(saved.0, forKey: AppModelKeys.legendClicks); d.set(saved.1, forKey: AppModelKeys.keyClickSound) }
        d.removeObject(forKey: AppModelKeys.legendClicks); d.removeObject(forKey: AppModelKeys.keyClickSound)
        let app = AppModel()
        XCTAssertTrue(app.legendClicks, "Click f/g Labels is on by default (as the Qt app)")
        XCTAssertFalse(app.keyClickSound, "Key Click Sound is off by default")
        app.legendClicks = false; app.keyClickSound = true
        XCTAssertEqual(d.object(forKey: AppModelKeys.legendClicks) as? Bool, false)
        XCTAssertEqual(d.object(forKey: AppModelKeys.keyClickSound) as? Bool, true)
        XCTAssertFalse(AppModel().legendClicks)
    }

    /// Off: a click on the blue P/R legend is a click on the key itself (no PRGM); the keyboard's shifted shortcuts still shift.
    /// The key click plays once per press when on.
    func testLegendClicksOffAndKeyClick() async throws {
        let app = try app15()
        defer { app.stopEngine(); app.legendClicks = true; app.keyClickSound = false }
        try await until("15C running") { app.inspection?.model == 15 }
        app.legendClicks = false
        app.keyClickSound = true
        let plays = KeyClick.playCount
        app.press(20, part: .gLabel); try await Task.sleep(nanoseconds: 200_000_000); app.release(20)
        try await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertEqual(KeyClick.playCount, plays + 1)
        XCTAssertEqual(app.inspection?.programMode, false, "the legend did not shift with Click f/g Labels off")
        app.press(20, part: .gLabel, fromKeyboard: true); try await Task.sleep(nanoseconds: 200_000_000); app.release(20)
        try await until("PRGM from the keyboard shortcut") { app.inspection?.programMode == true }
        app.legendClicks = true
        app.press(20, part: .gLabel); try await Task.sleep(nanoseconds: 200_000_000); app.release(20)
        try await until("PRGM off with the legend click") { app.inspection?.programMode == false }
    }

    // MARK: LCD, headers, focus, self-test layout

    func testLCDLiftMatchesQt() throws {
        XCTAssertNil(PhotoCalculatorFace.lcdLift(model: 12), "the 12C keeps the photo's glass")
        XCTAssertEqual(PhotoCalculatorFace.lcdLift(model: 15), 0x666666)
        XCTAssertEqual(PhotoCalculatorFace.lcdLift(model: 16), 0x666666)
        XCTAssertEqual(PhotoCalculatorFace.screen(0x00, 0x66), 0x66)
        XCTAssertEqual(PhotoCalculatorFace.screen(0xFF, 0x66), 0xFF)
        XCTAssertEqual(PhotoCalculatorFace.screen(0x80, 0x66), 0xB3)          // 1 - (1 - 0.502)(1 - 0.4) = 0.701
        // the rendered glass is the screen blend of the photo's glass and 0x666666, like the Qt app
        for model in [CalculatorModel.hp15c, .hp16c, .hp12c] {
            let face = try XCTUnwrap(model.photoFace)
            let blank = LCDState()
            let w: CGFloat = 800, h = w / face.aspect
            let lifted = try render(PhotoCalculatorFace(model: model, face: face, lcd: blank, pressed: []), width: w, height: h,
                                    name: "lcd-lift-\(model.name.lowercased()).png")
            let photo = try XCTUnwrap(FaceImages.image(face.emptyLCDImageName))
            let plain = try render(photo.resizable(), width: w, height: h, name: "lcd-lift-\(model.name.lowercased())-photo.png")
            let x = Int((face.lcd.minX + face.lcd.width * 0.03) * w * 2), y = Int((face.lcd.minY + face.lcd.height * 0.85) * h * 2)
            let a = pixel(plain, x, y), b = pixel(lifted, x, y)
            for i in 0..<3 {
                let want = model.id == 12 ? a[i] : Int(PhotoCalculatorFace.screen(UInt8(a[i]), 0x66))
                XCTAssertEqual(Double(b[i]), Double(want), accuracy: 3, "\(model.name) channel \(i): photo \(a) rendered \(b)")
            }
        }
    }

    private func pixel(_ cg: CGImage, _ x: Int, _ y: Int) -> [Int] {
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return [-1, -1, -1, -1] }
        return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent].map { Int(($0 * 255).rounded()) }
    }

    func testInspectorSectionHeadersAreOpaque() throws {
        for scheme in [ColorScheme.light, .dark] {
            let cg = try render(SectionHeader(title: "Storage registers").environment(\.colorScheme, scheme),
                                width: 300, height: 24, name: "header-\(scheme == .dark ? "dark" : "light").png")
            for x in [4, 300, 590] { XCTAssertEqual(pixel(cg, x, 24)[3], 255, "header pixel \(x) is opaque") }
        }
    }

    func testKeysTypedInAnotherWindowStayThere() {
        let a = NSWindow(), b = NSWindow()
        XCTAssertFalse(keyEventIsForOtherWindow(a, home: a))
        XCTAssertTrue(keyEventIsForOtherWindow(b, home: a))
        XCTAssertTrue(keyEventIsForOtherWindow(nil, home: a))
        XCTAssertFalse(keyEventIsForOtherWindow(b, home: nil), "before the calculator's window is known, nothing changes")
    }

    func testOneAnnunciatorLayoutForEveryModel() {
        XCTAssertEqual(CalculatorModel.hp12c.annunciators, CalculatorModel.hp15c.annunciators)
        XCTAssertEqual(CalculatorModel.hp16c.annunciators, CalculatorModel.hp15c.annunciators)
    }

    // MARK: Matrix Editor

    private final class FakeMemory { var image = Data(); var variant = 150 }

    func testMatrixEditorPasteApplyCopy() throws {
        let url = Fixtures.fixturesDir.appendingPathComponent("pool15/v150_00_baseline.bin")
        guard let img = try? Data(contentsOf: url) else { throw XCTSkip("no pool dumps") }
        let mem = FakeMemory(); mem.image = img
        var clipboard = "1,5\t2\r\n3\t4.25\r\n"
        var copied = ""
        let ed = MatrixEditorModel()
        var h = MatrixEditorModel.Hooks()
        h.fetch = { (mem.image, mem.variant) }
        h.apply = { m, r, c, raw, done in
            do { try Matrix15.write(&mem.image, variant: mem.variant, matrix: m, rows: r, cols: c, raw: raw); done(nil) }
            catch { done((error as? LocalizedError)?.errorDescription) }
        }
        h.clipboardText = { clipboard }
        h.copyText = { copied = $0 }
        ed.hooks = h
        ed.setAvailable(true)
        XCTAssertEqual(ed.rows, 0); XCTAssertEqual(ed.room, 78)

        ed.matrix = 1                                                   // B
        ed.pasteMatrix()
        let t = try XCTUnwrap(ed.pendingPaste, "the preview comes first")
        XCTAssertEqual(t.rows, 2); XCTAssertEqual(t.cols, 2)
        XCTAssertTrue(ed.pastePreviewText.contains("2 rows × 2 columns"))
        XCTAssertEqual(ed.rows, 0, "nothing filled before Fill the Grid")
        ed.fillFromPaste()
        XCTAssertEqual(ed.rows, 2); XCTAssertEqual(ed.cols, 2); XCTAssertEqual(ed.cell(0, 0), "1,5")
        XCTAssertTrue(ed.applyNow())
        let s = try XCTUnwrap(Matrix15.read(mem.image, variant: 150, matrix: 1))
        XCTAssertEqual(s.rows, 2); XCTAssertEqual(s.raw.map(Matrix15.cellText), ["1.5", "2", "3", "4.25"])
        ed.copyTSV()
        XCTAssertEqual(copied, "1.5\t2\n3\t4.25")
        XCTAssertEqual(Matrix15.parseTable(copied).cells.compactMap(Matrix15.value), s.raw, "Copy then Paste is exact")

        // open an existing matrix: B from memory, A is empty
        ed.matrix = 0; XCTAssertEqual(ed.rows, 0)
        ed.matrix = 1; XCTAssertEqual(ed.rows, 2); XCTAssertEqual(ed.cell(1, 1), "4.25")

        // the free-memory check: too big cannot be applied, the image is unchanged
        ed.setSize(rows: 9, cols: 9)
        XCTAssertFalse(ed.fits)
        let before = mem.image
        XCTAssertFalse(ed.applyNow())
        XCTAssertTrue(ed.status.contains("Error 10"), ed.status)
        XCTAssertEqual(mem.image, before)

        // complex or text cells are refused, with the cell named
        ed.setSize(rows: 1, cols: 2); ed.setCell(0, 1, "3+4i")
        XCTAssertTrue(ed.isBad(0, 1))
        XCTAssertFalse(ed.applyNow())
        XCTAssertTrue(ed.status.contains("Row 1, column 2"), ed.status)

        // a bad paste is previewed with its bad cells
        clipboard = "1\tx\n2\t3"
        ed.pasteMatrix()
        XCTAssertTrue(ed.pastePreviewText.contains("1 cell(s) are not real numbers"))
        ed.cancelPaste(); XCTAssertNil(ed.pendingPaste)
    }

    /// Through the real AppModel and engine (C8C8): Apply writes matrix A into the emulator's memory, the inspector shows it.
    /// Pictures: the editor window, the paste preview, and the app with matrix A in the flyout.
    func testMatrixEditorInTheEmulatorAndPictures() async throws {
        let app = try app15()
        defer { app.stopEngine() }
        try await until("15C running") { app.inspection?.model == 15 }
        XCTAssertTrue(app.isMatrixEditorAvailable)
        XCTAssertTrue(app.prepareMatrixEditor())
        let ed = app.matrixEditor
        ed.matrix = 0
        ed.setSize(rows: 3, cols: 3)
        let values = ["2", "-1", "0", "-1", "2", "-1", "0", "-1", "2,5"]
        for (i, v) in values.enumerated() { ed.setCell(i / 3, i % 3, v) }
        XCTAssertTrue(ed.applyNow(), ed.status)
        try await until("matrix A in the inspector") { app.inspection?.matrices.first?.rows == 3 }
        try await until("applied") { ed.status.contains("is now in the emulator's memory") }
        XCTAssertEqual(app.inspection?.matrices.first?.values.last?.number ?? 0, 2.5, accuracy: 1e-12)
        ed.reload()
        XCTAssertEqual(ed.cell(2, 2), "2.5")

        try renderWindow(MatrixEditorView(editor: ed).environmentObject(app), size: NSSize(width: 640, height: 540),
                         title: "HP-15C Matrix Editor", name: "mac-0.7.1-matrix-editor.png")
        var h = ed.hooks
        h.clipboardText = { "1,5\t2\t3\n4\t5,25\t6\n7\t8\t9" }
        ed.hooks = h
        ed.matrix = 1
        ed.pasteMatrix()
        try renderWindow(PastePreviewSheet(editor: ed, table: try XCTUnwrap(ed.pendingPaste)), size: NSSize(width: 520, height: 360),
                         title: "Paste Matrix", name: "mac-0.7.1-paste-matrix-preview.png")
        ed.cancelPaste()

        // the app window with the flyout showing matrix A
        let w: CGFloat = 900, faceH = w / app.faceAspect
        let v = HStack(spacing: 0) {
            CalculatorView(forcedLayout: .landscape).environmentObject(app).frame(width: w, height: faceH)
                .frame(maxHeight: .infinity).background(Color(rgb: 0x1C1714))
            Divider()
            InspectorView().environmentObject(app).environment(\.inspectorStatic, true)
                .frame(width: 330).background(Color(rgb: 0x1E1E1E))
        }
        .environment(\.colorScheme, .dark)
        _ = try render(v, width: w + 331, height: 640, name: "mac-0.7.1-15c-with-matrix-A.png")
    }

    /// The three faces with a live display from the real firmware (photo face, the default).
    func testRenderFaces071() throws {
        func shot(_ fw: Data?, variant: Int?, keys: [String], model: CalculatorModel, name: String) throws {
            guard let fw else { return }
            let m = CalculatorMachine()
            try m.loadFirmware(fw); try m.boot(restoring: nil)
            if let v = variant, m.variant != v, m.images.contains(v) { try m.switchModel(to: v) }
            for k in keys { if let c = VoyagerCalculator.keyCode(model: model.id, name: k) { try m.tap(c) } }
            let face = try XCTUnwrap(model.photoFace)
            _ = try render(PhotoCalculatorFace(model: model, face: face, lcd: m.calc.lcd(), pressed: []),
                           width: 1000, height: 1000 / face.aspect, name: name)
        }
        try shot(Fixtures.hp15c3ROM, variant: 150, keys: ["1", "ENTER", "7", "÷"], model: .hp15c, name: "mac-0.7.1-15c.png")
        try shot(Fixtures.firmware16Ext, variant: nil, keys: ["B", "E", "E", "F"], model: .hp16c, name: "mac-0.7.1-16c.png")
        try shot(Fixtures.multi, variant: 120, keys: ["1", "2", "3", "4", "5", ".", "6", "7", "ENTER"], model: .hp12c, name: "mac-0.7.1-12c.png")
    }
}
#endif
