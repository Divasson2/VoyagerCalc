// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// Renders the calculator faces to PNG files (no app window is opened): the display
// content comes from the real core and the user's firmware when it is found, otherwise
// from a made-up display. Output: $VC_SCREENS_DIR or $TMPDIR/VoyagerCalcScreens.

#if os(macOS)
import AppKit
import SwiftUI
import XCTest

@MainActor
final class SnapshotTests: XCTestCase {
    private var outDir: URL {
        let env = ProcessInfo.processInfo.environment["VC_SCREENS_DIR"]
        let u = env.map { URL(fileURLWithPath: $0) } ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("VoyagerCalcScreens")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    private func render<V: View>(_ view: V, width: CGFloat, height: CGFloat, name: String) throws {
        let r = ImageRenderer(content: view.frame(width: width, height: height))
        r.scale = 2
        guard let cg = r.cgImage else { return XCTFail("render failed: \(name)") }
        let rep = NSBitmapImageRep(cgImage: cg)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let url = outDir.appendingPathComponent(name)
        try png.write(to: url)
        print("snapshot: \(url.path) \(cg.width)x\(cg.height)")
        XCTAssertGreaterThan(cg.width, 100)
    }

    /// A display state from the real core, by typing keys.
    private func lcd(firmware: Data?, variant: Int?, keys: [String], model: Int) -> LCDState? {
        guard let fw = firmware else { return nil }
        let m = CalculatorMachine()
        do {
            try m.loadFirmware(fw)
            try m.boot(restoring: nil)
            if let v = variant { try m.switchVariant(to: v) }
            for k in keys {
                guard let code = VoyagerCalculator.keyCode(model: model, name: k) else { continue }
                try m.tap(code)
            }
            return m.calc.lcd()
        } catch { return nil }
    }

    private static let digitBits: [Character: UInt8] = ["0": 63, "1": 6, "2": 91, "3": 79, "4": 102, "5": 109, "6": 125, "7": 7, "8": 127, "9": 111, " ": 0]

    private func fake(_ s: String) -> LCDState {
        var l = LCDState()
        let chars = Array(s.padding(toLength: 10, withPad: " ", startingAt: 0))
        for (i, c) in chars.enumerated() where i < 10 { l.segments[i] = Self.digitBits[c] ?? 0 }
        l.text = s
        return l
    }

    // MARK: registers and program inspector

    private func machine16(_ keys: String, millerRabin: Bool = true) throws -> CalculatorMachine? {
        guard let fw = Fixtures.firmware16Ext else { return nil }
        let m = CalculatorMachine()
        try m.loadFirmware(fw)
        try m.boot(restoring: nil)
        if millerRabin { try m.putMemory(Fixtures.millerRabin) }
        try typeKeys(m, keys, model: 16)
        return m
    }

    private func typeKeys(_ m: CalculatorMachine, _ s: String, model: Int) throws {
        for w in s.split(separator: " ").map(String.init) {
            if let k = VoyagerCalculator.keyCode(model: model, name: w) { try m.tap(k); continue }
            for ch in w { if let k = VoyagerCalculator.keyCode(model: model, name: String(ch)) { try m.tap(k) } }
        }
    }

    private func renderWithInspector(_ m: CalculatorMachine, model: CalculatorModel, name: String, phonePortrait: Bool = false, scheme: ColorScheme = .dark, height: CGFloat = 640) throws {
        let app = AppModel()
        app.inspection = m.calc.inspect()
        XCTAssertNotNil(app.inspection, name)
        let lcd = m.calc.lcd()
        let panel = InspectorView(compact: phonePortrait).environmentObject(app).environment(\.inspectorStatic, true)
        if phonePortrait {
            let v = VStack(spacing: 0) {
                CalculatorFace(model: model, lcd: lcd, pressed: [], layout: .portrait).frame(width: 393, height: 494)
                panel.frame(width: 393, height: 358).background(scheme == .dark ? Color(rgb: 0x1E1E1E) : Color.white)
            }
            .environment(\.colorScheme, scheme)
            try render(v, width: 393, height: 852, name: name)
        } else {
            let face = try XCTUnwrap(model.photoFace)
            let w: CGFloat = 900
            let v = HStack(spacing: 0) {
                PhotoCalculatorFace(model: model, face: face, lcd: lcd, pressed: []).frame(width: w, height: w / face.aspect)
                    .frame(maxHeight: .infinity).background(Color(rgb: 0x1C1714))
                Divider()
                panel.frame(width: 330).background(scheme == .dark ? Color(rgb: 0x1E1E1E) : Color.white)
            }
            .environment(\.colorScheme, scheme)
            try render(v, width: w + 331, height: height, name: name)
        }
    }

    // MARK: model chooser and latched keys (the real AppModel and engine)

    /// Wait (letting the main queue run) until `cond` holds.
    private func until(_ what: String, timeout: Double = 20, _ cond: () -> Bool) async throws {
        let end = Date().addingTimeInterval(timeout)
        while !cond() {
            if Date() > end { XCTFail("timed out: \(what)"); return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func renderApp(_ app: AppModel, name: String) throws {
        let w: CGFloat = 900, h = w / app.faceAspect
        let v = HStack(spacing: 0) {
            CalculatorView(forcedLayout: .landscape).environmentObject(app).frame(width: w, height: h)
                .frame(maxHeight: .infinity).background(Color(rgb: 0x1C1714))
            Divider()
            InspectorView().environmentObject(app).environment(\.inspectorStatic, true)
                .frame(width: 330).background(Color(rgb: 0x1E1E1E))
        }
        .environment(\.colorScheme, .dark)
        try render(v, width: w + 331, height: 640, name: name)
    }

    /// E3E3: the Model menu switches 12C -> 15C (15.2) -> 16C; the face, keys and inspector
    /// follow as soon as the new model runs. Then a switch made on the calculator itself
    /// (g and ENTER latched, ON, 4, the 12 key) is followed too.
    func testModelChooserSwitchesTheFace() async throws {
        guard let fw = Fixtures.find(["HP12c-multi-152-ext16-E3E3.bin"]) else { throw XCTSkip("no E3E3") }
        let m = CalculatorMachine()
        try m.loadFirmware(fw)
        try m.boot(restoring: nil)
        let app = AppModel()
        app.persistState = false
        app.skin = .automatic; app.faceStyle = .photo; app.showInspector = true
        app.attach(m, firmwareName: "E3E3")
        defer { app.stopEngine() }
        XCTAssertEqual(app.images, [120, 152, 160])
        try await until("12C running") { app.snapshot.variant == 120 && app.inspection?.model == 12 }
        XCTAssertEqual(app.model.id, 12)
        app.press(VoyagerCalculator.keyCode(model: 12, name: "7")!); app.release(VoyagerCalculator.keyCode(model: 12, name: "7")!)
        try await until("7 on the display") { app.snapshot.lcd.text.contains("7") }
        try renderApp(app, name: "mac-model-1-12c.png")

        for (v, name) in [(152, "mac-model-2-15c.png"), (160, "mac-model-3-16c.png")] {
            app.chooseModel(v)
            XCTAssertEqual(app.pendingAction, .switchModel(v), "asks first")
            app.confirm(.switchModel(v))
            try await until("switch to \(v)") { !app.isSwitchingModel }
            XCTAssertNil(app.errorMessage)
            XCTAssertEqual(app.snapshot.variant, v, "face follows at once")
            XCTAssertEqual(app.model.id, v / 10)
            try await until("inspector decodes \(v)") { app.inspection?.variant == v }
            XCTAssertFalse(app.snapshot.lcd.text.contains("7"), "memory cleared")
            try renderApp(app, name: name)
        }

        // a switch made on the calculator: latch g and ENTER, ON, then 4 and the 12 key
        app.press(CalculatorMachine.keyON); app.release(CalculatorMachine.keyON)       // off
        try await until("off") { app.snapshot.lcd.text.trimmingCharacters(in: .whitespaces).isEmpty }
        // as by hand: a key pressed within ~20 ms of turning off is taken by the power-off
        // routine (the firmware does that on the calculator too), so wait a moment
        try await Task.sleep(nanoseconds: 800_000_000)
        app.toggleLatch(CalculatorMachine.keyG); app.toggleLatch(CalculatorMachine.keyENTER)
        XCTAssertEqual(app.latchedKeys, [CalculatorMachine.keyG, CalculatorMachine.keyENTER])
        try renderApp(app, name: "mac-keys-latched-g-enter.png")
        try await Task.sleep(nanoseconds: 400_000_000)
        app.press(CalculatorMachine.keyON)
        try await Task.sleep(nanoseconds: 300_000_000)
        app.release(CalculatorMachine.keyON)
        XCTAssertTrue(app.latchedKeys.isEmpty)
        try await until("service menu") { app.snapshot.lcd.text.contains("1.L2.C3.H") }
        for k in [16, 1] {
            app.press(k); try await Task.sleep(nanoseconds: 200_000_000); app.release(k)
            try await Task.sleep(nanoseconds: 700_000_000)
        }
        try await until("12C after the switch on the calculator") { app.snapshot.variant == 120 }
        XCTAssertEqual(app.model.id, 12)
        try await until("12C inspector") { app.inspection?.model == 12 }
    }

    // MARK: legend clicks (0.5.5)

    /// Through the real AppModel and engine on the 15C: a latched f is let go, then the gold
    /// LBL legend (over SST) and A give "f LBL A"; the blue P/R legend enters PRGM; a pending
    /// g is replaced by the gold legend's f (never "g f LBL").
    func testLegendClicksThroughTheApp() async throws {
        guard let fw = Fixtures.hp15c3ROM else { throw XCTSkip("no C8C8") }
        let m = CalculatorMachine()
        try m.loadFirmware(fw); try m.boot(restoring: nil)
        if m.variant != 150 { try m.switchModel(to: 150) }
        let app = AppModel()
        app.persistState = false; app.showInspector = true; app.skin = .automatic; app.faceStyle = .photo
        app.attach(m, firmwareName: "C8C8")
        defer { app.stopEngine() }
        try await until("15C running") { app.inspection?.model == 15 }
        func click(_ code: Int, _ part: KeyPart = .face) async throws {
            app.press(code, part: part); try await Task.sleep(nanoseconds: 200_000_000); app.release(code)
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        func current() async throws -> String {
            try await Task.sleep(nanoseconds: 300_000_000)
            guard let s = app.inspection, let l = s.program.first(where: { $0.line == s.line }) else { return "-" }
            return "\(l.keys) \(l.fullMnemonic)"
        }
        try await click(20, .gLabel)                                     // g P/R
        try await until("PRGM") { app.inspection?.programMode == true }
        app.toggleLatch(CalculatorMachine.keyF)                          // f latched down
        XCTAssertEqual(app.latchedKeys, [CalculatorMachine.keyF])
        try await click(10, .fLabel); try await click(0)                 // LBL, A
        XCTAssertTrue(app.latchedKeys.isEmpty)
        let first = try await current()
        XCTAssertEqual(first, "42,21,11 f LBL A")
        try await click(CalculatorMachine.keyG)                           // g pending
        try await click(10, .fLabel); try await click(1)                 // LBL, B
        let second = try await current()
        XCTAssertEqual(second, "42,21,12 f LBL B")
        try renderApp(app, name: "mac-15c-legend-clicks.png")
    }

    // MARK: program pointer band

    /// The green pointer band, light and dark, stopped and running; and through the real app
    /// (AppModel + engine): after each SST / BST / GTO the highlighted line is the displayed one.
    func testPointerBandSnapshotsAndAppPointer() async throws {
        if let m = try machine16("GTO . 0 4 2 g R/S") {
            XCTAssertEqual(m.calc.inspect()?.line, 42)
            XCTAssertTrue(m.displayText.hasPrefix("042-"), m.displayText)
            try renderWithInspector(m, model: .hp16c, name: "mac-16c-pointer-band-042-light.png", scheme: .light)
            try renderWithInspector(m, model: .hp16c, name: "mac-16c-pointer-band-042-dark.png", scheme: .dark)
            try typeKeys(m, "g R/S 2 1 4 7 4 8 3 6 4 7 GSB A", model: 16)
            try m.run(ms: 700)
            XCTAssertEqual(m.calc.inspect()?.running, true)
            try renderWithInspector(m, model: .hp16c, name: "mac-16c-pointer-band-running-light.png", scheme: .light)
            try renderWithInspector(m, model: .hp16c, name: "mac-16c-pointer-band-running-dark.png", scheme: .dark)
        }
        if let fw = Fixtures.find(["HP12c-multi-152-ext16-E3E3.bin"]) {
            let m = CalculatorMachine()
            try m.loadFirmware(fw); try m.boot(restoring: nil); try m.switchModel(to: 152)
            try typeKeys(m, "g R/S f SST SQRT 2 STO . 1 RCL . 1 × f 7 4 g GSB GTO CHS 0 0 3", model: 15)
            XCTAssertEqual(m.calc.inspect()?.line, 3)
            try renderWithInspector(m, model: .hp15c, name: "mac-15c-pointer-band-light.png", scheme: .light)
        }

        // through the app
        guard let fw = Fixtures.firmware16Ext else { return }
        let m = CalculatorMachine()
        try m.loadFirmware(fw); try m.boot(restoring: nil); try m.putMemory(Fixtures.millerRabin)
        let app = AppModel()
        app.persistState = false; app.showInspector = true; app.skin = .automatic
        app.attach(m, firmwareName: "B7B7")
        defer { app.stopEngine() }
        func key(_ name: String) async throws {
            let k = try XCTUnwrap(VoyagerCalculator.keyCode(model: 16, name: name), name)
            app.press(k); try await Task.sleep(nanoseconds: 150_000_000); app.release(k)
            try await Task.sleep(nanoseconds: 450_000_000)
        }
        func settled() async throws -> (Int?, Int?) {
            // the inspector is published at most 10 times a second: wait until both agree or 2 s pass
            for _ in 0..<100 {
                let d = ProgramPointerTests.shown(app.snapshot.lcd.text)?.line, h = app.inspection?.line
                if d != nil && d == h { return (d, h) }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            return (ProgramPointerTests.shown(app.snapshot.lcd.text)?.line, app.inspection?.line)
        }
        try await until("inspector") { app.inspection?.lines == 117 }
        try await key("g"); try await key("R/S")                  // PRGM
        var rng = SplitMix(seed: 42)
        for i in 0..<25 {
            switch rng.next() % 3 {
            case 0: try await key("SST")
            case 1: try await key("g"); try await key("SST")
            default:
                let n = Int(rng.next() % 118)
                for k in ["GTO", "."] + String(format: "%03d", n).map(String.init) { try await key(k) }
            }
            let (d, h) = try await settled()
            XCTAssertNotNil(d, "#\(i): display \(app.snapshot.lcd.text)")
            XCTAssertEqual(h, d, "#\(i): highlighted line vs display \(app.snapshot.lcd.text)")
        }
    }

    /// 0.6.0: 15C (15.0, C8C8) with complex mode on (5 + 6i in X) and matrices A 2×2, B 1×2,
    /// C 1×3 (RESULT C), from docs/pool15c dump v150_34: Complex tag, imaginary column, pool bar, matrices.
    func testRenderInspectorComplexMatrices() throws {
        guard let fw = Fixtures.hp15c3ROM else { throw XCTSkip("no C8C8 15C firmware") }
        let m = CalculatorMachine(); try m.loadFirmware(fw); try m.boot(restoring: nil)
        if m.variant != 150 { try m.switchModel(to: 150) }
        try m.putMemory(try Fixtures.data("pool15/v150_34_sf8_with_matrices.bin"))
        try typeKeys(m, "1 ENTER 2 f TAN 5 ENTER 6 f TAN", model: 15)
        let s = try XCTUnwrap(m.calc.inspect())
        XCTAssertTrue(s.isComplex)
        XCTAssertEqual(s.imaginary(of: "X")?.text, "6")
        XCTAssertEqual(s.imaginary(of: "Y")?.text, "2")
        XCTAssertEqual(s.pool?.resultLetter, "C")
        try renderWithInspector(m, model: .hp15c, name: "mac-15c-inspector-complex-matrices.png", height: 900)
        try renderWithInspector(m, model: .hp15c, name: "mac-15c-inspector-complex-matrices-light.png", scheme: .light, height: 900)
        try renderWithInspector(m, model: .hp15c, name: "iphone-15c-portrait-complex-matrices.png", phonePortrait: true)
    }

    func testRenderInspector() throws {
        // 16C: Miller-Rabin after 97 GSB A, stepping in program mode at line 042
        if let m = try machine16("9 7 GSB A") {
            var waited = 0
            while (m.calc.inspect()?.running ?? false) && waited < 60_000 { try m.run(ms: 500); waited += 500 }
            try typeKeys(m, "GTO . 0 4 1 g R/S SST", model: 16)
            XCTAssertEqual(m.calc.inspect()?.line, 42)
            try renderWithInspector(m, model: .hp16c, name: "mac-16c-inspector-sst.png")
            try typeKeys(m, "g R/S", model: 16)
            try renderWithInspector(m, model: .hp16c, name: "iphone-16c-portrait-inspector.png", phonePortrait: true)
        }
        // 16C: running (live pointer), 2147483647 GSB A
        if let m = try machine16("2 1 4 7 4 8 3 6 4 7 GSB A") {
            try m.run(ms: 700)
            XCTAssertEqual(m.calc.inspect()?.running, true)
            try renderWithInspector(m, model: .hp16c, name: "mac-16c-inspector-running.png")
        }
        // 16C: HEX, WSIZE 16, 2's complement, negative numbers, R615
        if let m = try machine16("HEX 1 0 f STO F F 9 C ENTER 7 F F F STO 1 2 6 7 STO SST 1 2 3 4 STO R/S 4 2 CHS STO 0 g 4 3 1 ENTER", millerRabin: false) {
            try renderWithInspector(m, model: .hp16c, name: "mac-16c-inspector-hex-ws16.png")
        }
        // multi E3E3: 15C (15.2) with a small program
        if let fw = Fixtures.find(["HP12c-multi-152-ext16-E3E3.bin"]) {
            let m = CalculatorMachine()
            try m.loadFirmware(fw)
            try m.boot(restoring: nil)
            try m.switchVariant(to: 152)
            try typeKeys(m, "2 STO 0 1 ENTER 7 ÷ STO 1 g R/S f SST SQRT g SQRT RCL 0 × g GSB g R/S GTO SQRT g R/S SST SST", model: 15)
            try renderWithInspector(m, model: .hp15c, name: "mac-15c-inspector.png")
            try m.switchVariant(to: 120)
            try typeKeys(m, "3 6 0 n 6 . 5 g i 2 0 0 0 0 0 PV PMT", model: 12)
            try renderWithInspector(m, model: .hp12c, name: "mac-12c-inspector.png")
        }
    }

    func testRenderFaces() throws {
        let fw16 = Fixtures.firmware16Ext
        let multi = Fixtures.multi
        let l16 = lcd(firmware: fw16, variant: nil, keys: ["B", "E", "E", "F", "f"], model: 16) ?? fake("      8888")
        let l15 = lcd(firmware: multi, variant: 152, keys: ["1", "ENTER", "7", "÷", "CHS", "g"], model: 15) ?? fake("  14285714")
        let l12 = lcd(firmware: multi, variant: nil, keys: ["1", "2", "3", "4", "5", ".", "6", "7", "ENTER"], model: 12) ?? fake("  12345 67")

        try render(CalculatorFace(model: .hp16c, lcd: l16, pressed: [], layout: .landscape), width: 1000, height: 617, name: "mac-16c.png")
        try render(CalculatorFace(model: .hp15c, lcd: l15, pressed: [], layout: .landscape), width: 1000, height: 617, name: "mac-15c.png")
        try render(CalculatorFace(model: .hp12c, lcd: l12, pressed: [], layout: .landscape), width: 1000, height: 617, name: "mac-12c.png")
        try render(CalculatorFace(model: .hp16c, lcd: l16, pressed: [25], layout: .landscape, turbo: true), width: 760, height: 469, name: "mac-16c-small-turbo-enter-pressed.png")
        try render(CalculatorFace(model: .hp16c, lcd: l16, pressed: [], layout: .portrait), width: 393, height: 852, name: "iphone-16c-portrait.png")
        try render(CalculatorFace(model: .hp12c, lcd: l12, pressed: [], layout: .portrait), width: 393, height: 852, name: "iphone-12c-portrait.png")
        // photo faces (the default face): live display over the empty glass, pressed keys
        for (model, l) in [(CalculatorModel.hp16c, l16), (.hp15c, l15), (.hp12c, l12)] {
            let face = try XCTUnwrap(model.photoFace)
            XCTAssertNotNil(FaceImages.image(face.emptyLCDImageName), "face image \(face.emptyLCDImageName) is in the bundle")
            try render(PhotoCalculatorFace(model: model, face: face, lcd: l, pressed: []),
                       width: 1000, height: 1000 / face.aspect, name: "mac-\(model.name.lowercased())-photo.png")
        }
        try render(PhotoCalculatorFace(model: .hp16c, face: .hp16c, lcd: l16, pressed: [25, 31], turbo: true),
                   width: 760, height: 760 / PhotoFace.hp16c.aspect, name: "mac-16c-photo-small-turbo-enter-f-pressed.png")
        try render(PhotoCalculatorFace(model: .hp16c, face: .hp16c, lcd: l16, pressed: []), width: 852, height: 393,
                   name: "iphone-16c-landscape-photo.png")
        try render(LCDView(lcd: l16, model: .hp16c), width: 600, height: 110, name: "lcd-16c.png")
        try render(LCDView(lcd: l12, model: .hp12c), width: 600, height: 110, name: "lcd-12c.png")
    }
}
#endif
