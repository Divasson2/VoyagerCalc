// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// 0.7.4 (with the Qt app): the inspector's context menus - GTO nnn and RCL / STO / STO+−×÷ / RCL+−×÷ / x≷ on a
// register - key exactly what a person keys on the calculator; View ▸ Show Calculator Back (HP-15C / HP-16C).
// No HP code in here (firmware from the fixtures folder, skipped when absent).
#if os(macOS)
import XCTest

@MainActor
final class Release074Tests: XCTestCase {
    private func need(_ d: Data?, _ why: String) throws -> Data { guard let d else { throw XCTSkip(why) }; return d }
    private let D = [36, 26, 27, 28, 16, 17, 18, 6, 7, 8]

    private func boot(_ fw: Data, variant: Int = 0) throws -> CalculatorMachine {
        let m = CalculatorMachine()
        try m.loadFirmware(fw); try m.boot(restoring: nil)
        if variant != 0 && m.variant != variant { try m.switchModel(to: variant) }
        try m.powerOn()
        return m
    }
    private func keys(_ m: CalculatorMachine, _ k: [Int]) throws { try m.perform(keys: k) }
    private func number(_ m: CalculatorMachine, _ n: Int) throws { try keys(m, String(n).map { D[$0.wholeNumberValue!] }) }
    private func snap(_ m: CalculatorMachine) -> InspectorSnapshot { m.calc.inspect() ?? InspectorSnapshot() }
    private func reg(_ s: InspectorSnapshot, _ n: String) -> String {
        ((s.stack + s.registers).first { $0.name == n }?.text ?? "?").trimmingCharacters(in: .whitespaces)
    }
    private func num(_ t: String) -> String {
        var s = t.replacingOccurrences(of: " ", with: "")
        if s.contains(".") { while s.hasSuffix("0") { s.removeLast() } }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }
    private func item(_ m: [CalcAction], _ t: String) -> CalcAction? { m.first { $0.title == t } }

    /// R = 12 stored in `name` by keys, Y = 7, X = 3, then the menu item; X, Y, Z, LAST X, the register.
    private func check(_ fw: Data, _ variant: Int, _ name: String, _ title: String, _ hpKeys: [Int], _ want: [String],
                       file: StaticString = #filePath, line: UInt = #line) throws {
        let m = try boot(fw, variant: variant)
        let addr = CalcActions.addressKeys(model: snap(m).model, name: name)
        XCTAssertFalse(addr.isEmpty, "address \(name)", file: file, line: line)
        try number(m, 12); try keys(m, [33] + addr)
        try keys(m, [25]); try number(m, 7); try keys(m, [25]); try number(m, 3)
        let a = try XCTUnwrap(item(CalcActions.registerMenu(snap(m), name: name), title), title, file: file, line: line)
        XCTAssertTrue(a.enabled, title, file: file, line: line)
        XCTAssertEqual(a.keys, hpKeys, title, file: file, line: line)
        try keys(m, a.keys)
        let s = snap(m)
        XCTAssertEqual(["X", "Y", "Z", "LAST X", name].map { num(reg(s, $0)) }, want, title, file: file, line: line)
        // the menu item and the HP keystroke sequence pressed by hand leave the same calculator
        let p = try boot(fw, variant: variant), q = try boot(fw, variant: variant)
        for c in [p, q] { try number(c, 5); try keys(c, [25]); try number(c, 4) }
        try keys(p, a.keys)
        for k in hpKeys { try q.calc.tap(k) }
        try q.run(ms: 400)
        XCTAssertEqual(snap(p).stack, snap(q).stack, title, file: file, line: line)
        XCTAssertEqual(snap(p).registers, snap(q).registers, title, file: file, line: line)
        XCTAssertEqual(p.displayText, q.displayText, title, file: file, line: line)
    }

    private func pr(_ m: CalculatorMachine) -> [Int] { m.model == 12 ? [31, 20] : [32, 20] }
    private func gtoCase(_ fw: Data, _ variant: Int, prgm: Bool, _ line: Int, _ label: String) throws {
        let m = try boot(fw, variant: variant)
        try keys(m, pr(m)); for i in 0..<6 { try keys(m, [D[(i + 1) % 10]]) }; try keys(m, pr(m))
        if prgm { try keys(m, pr(m)) }
        let s = snap(m)
        XCTAssertEqual(s.programMode, prgm); XCTAssertGreaterThanOrEqual(s.lines, 6)
        let a = CalcActions.gto(s, line: line)
        XCTAssertEqual(a.title, "GTO " + label); XCTAssertTrue(a.enabled)
        try keys(m, a.keys)
        let t = snap(m)
        XCTAssertEqual(t.line, line); XCTAssertEqual(t.lines, s.lines); XCTAssertEqual(t.programMode, prgm)   // nothing keyed in
        if prgm { XCTAssertTrue(m.displayText.trimmingCharacters(in: .whitespaces).hasPrefix(label), m.displayText) }
        XCTAssertFalse(CalcActions.gto(s, line: s.lines + 1).enabled)
    }

    func testGTO15() throws {
        let fw = try need(Fixtures.hp15c3ROM, "no 15C firmware")
        try gtoCase(fw, 0, prgm: true, 4, "004"); try gtoCase(fw, 0, prgm: false, 2, "002"); try gtoCase(fw, 0, prgm: true, 0, "000")
    }
    func testGTO16() throws {
        let fw = try need(Fixtures.firmware16Ext, "no 16C firmware")
        try gtoCase(fw, 0, prgm: true, 5, "005"); try gtoCase(fw, 0, prgm: false, 3, "003")
    }
    func testGTO12() throws {
        let fw = try need(Fixtures.multi, "no multi firmware")
        try gtoCase(fw, 120, prgm: true, 4, "04"); try gtoCase(fw, 120, prgm: false, 2, "02")
    }
    func testGTOKeys() {
        XCTAssertEqual(CalcActions.gtoKeys(model: 15, programMode: false, line: 12, lines: 20), [11, 5, 36, 26, 27])
        XCTAssertEqual(CalcActions.gtoKeys(model: 16, programMode: false, line: 12, lines: 20), [11, 37, 36, 26, 27])
        XCTAssertEqual(CalcActions.gtoKeys(model: 12, programMode: false, line: 12, lines: 20), [32, 22, 26, 27])
        XCTAssertEqual(CalcActions.gtoKeys(model: 12, programMode: true, line: 12, lines: 20), [32, 22, 37, 26, 27])
    }
    func testRegisters15() throws {
        let fw = try need(Fixtures.hp15c3ROM, "no 15C firmware")
        try check(fw, 0, "R5", "RCL R5", [34, 17], ["12", "3", "7", "0", "12"])
        try check(fw, 0, "R5", "STO R5", [33, 17], ["3", "7", "12", "0", "3"])
        try check(fw, 0, "R5", "STO+ R5", [33, 39, 17], ["3", "7", "12", "0", "15"])
        try check(fw, 0, "R5", "STO− R5", [33, 29, 17], ["3", "7", "12", "0", "9"])
        try check(fw, 0, "R5", "STO× R5", [33, 19, 17], ["3", "7", "12", "0", "36"])
        try check(fw, 0, "R5", "STO÷ R5", [33, 9, 17], ["3", "7", "12", "0", "4"])
        try check(fw, 0, "R5", "RCL+ R5", [34, 39, 17], ["15", "7", "12", "0", "12"])
        try check(fw, 0, "R5", "RCL− R5", [34, 29, 17], ["-9", "7", "12", "0", "12"])
        try check(fw, 0, "R5", "RCL× R5", [34, 19, 17], ["36", "7", "12", "0", "12"])
        try check(fw, 0, "R5", "RCL÷ R5", [34, 9, 17], ["0.25", "7", "12", "0", "12"])
        try check(fw, 0, "R5", "x≷ R5", [31, 16, 17], ["12", "7", "12", "0", "3"])
        try check(fw, 0, "R.3", "STO+ R.3", [33, 39, 37, 28], ["3", "7", "12", "0", "15"])
        try check(fw, 0, "I", "RCL I", [34, 14], ["12", "3", "7", "0", "12"])
        try check(fw, 0, "I", "STO+ I", [33, 39, 14], ["3", "7", "12", "0", "15"])
        try check(fw, 0, "I", "x≷ I", [31, 16, 14], ["12", "7", "12", "0", "3"])
    }
    func testRegisters16() throws {
        let fw = try need(Fixtures.firmware16Ext, "no 16C firmware")
        try check(fw, 0, "R5", "RCL R5", [34, 17], ["12", "3", "7", "0", "12"])
        try check(fw, 0, "R5", "STO R5", [33, 17], ["3", "7", "12", "0", "3"])
        try check(fw, 0, "RB", "RCL RB", [34, 1], ["12", "3", "7", "0", "12"])
        try check(fw, 0, "R.A", "STO R.A", [33, 37, 0], ["3", "7", "12", "0", "3"])
        try check(fw, 0, "I", "RCL I", [34, 21], ["12", "3", "7", "0", "12"])
        try check(fw, 0, "I", "x≷ I", [31, 11], ["12", "7", "12", "0", "3"])
    }
    func testRegisters12() throws {
        let fw = try need(Fixtures.multi, "no multi firmware")
        try check(fw, 120, "R3", "RCL R3", [34, 28], ["12", "3", "7", "0", "12"])
        try check(fw, 120, "R3", "STO+ R3", [33, 39, 28], ["3", "7", "12", "0", "15"])
        try check(fw, 120, "R3", "STO÷ R3", [33, 9, 28], ["3", "7", "12", "0", "4"])
        try check(fw, 120, "R.3", "STO R.3", [33, 37, 28], ["3", "7", "12", "0", "3"])
        try check(fw, 120, "PMT", "RCL PMT", [34, 3], ["12", "3", "7", "0", "12"])
        try check(fw, 120, "PMT", "STO PMT", [33, 3], ["3", "7", "12", "0", "3"])
    }
    func testMenusPerModel() {
        var s = InspectorSnapshot(); s.model = 15
        for n in ["X", "Y", "Z", "T", "LAST X", "R25"] { XCTAssertTrue(CalcActions.registerMenu(s, name: n).allSatisfy { !$0.enabled }, n) }
        XCTAssertEqual(CalcActions.registerMenu(s, name: "R1").map(\.title),
                       ["RCL R1", "STO R1", "STO+ R1", "STO− R1", "STO× R1", "STO÷ R1", "RCL+ R1", "RCL− R1", "RCL× R1", "RCL÷ R1", "x≷ R1"])
        s.running = true; XCTAssertTrue(CalcActions.registerMenu(s, name: "R1").allSatisfy { !$0.enabled })
        XCTAssertFalse(CalcActions.gto(s, line: 0).enabled)
        s.running = false; s.model = 16
        let m16 = CalcActions.registerMenu(s, name: "R1")
        XCTAssertEqual(m16.map(\.title), ["RCL R1", "STO R1", "x≷ I"]); XCTAssertEqual(m16.map(\.enabled), [true, true, false])
        XCTAssertTrue(CalcActions.registerMenu(s, name: "I")[2].enabled)
        s.model = 12
        let m12 = CalcActions.registerMenu(s, name: "R5")
        XCTAssertEqual(m12.count, 6); XCTAssertTrue(m12[1].enabled); XCTAssertFalse(m12[2].enabled)   // STO arithmetic on R0..R4 only
        XCTAssertTrue(CalcActions.registerMenu(s, name: "R4")[2].enabled)
        XCTAssertFalse(CalcActions.registerMenu(s, name: "PMT")[2].enabled)
        XCTAssertFalse(CalcActions.registerMenu(s, name: "R.1")[2].enabled)
    }

    // MARK: through the app (what the context menus call)

    private func until(_ what: String, timeout: Double = 20, _ cond: () -> Bool) async throws {
        let end = Date().addingTimeInterval(timeout)
        while !cond() {
            if Date() > end { XCTFail("timed out: \(what)"); return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
    private func app(_ fw: Data, variant: Int) throws -> AppModel {
        let m = try boot(fw, variant: variant)
        let a = AppModel()
        a.persistState = false; a.showInspector = true
        a.attach(m, firmwareName: "fixture")
        return a
    }
    private func idle(_ a: AppModel) -> Bool { a.inspection.map { !$0.running } ?? false }

    func testAppGTOAndRegisterItemsInProgramMode() async throws {
        let fw = try need(Fixtures.hp15c3ROM, "no 15C firmware")
        let a = try app(fw, variant: 0)
        defer { a.stopEngine() }
        a.performKeys([32, 20] + [26, 27, 28, 16, 17] + [32, 20])      // a 5-line program, run mode
        try await until("program") { idle(a) && a.inspection?.lines == 5 && a.inspection?.programMode == false }
        a.performKeys(CalcActions.gto(a.inspection!, line: 3).keys)  // run mode: the pointer moves
        try await until("GTO 003") { a.inspection?.line == 3 }
        a.performKeys([32, 20])
        try await until("PRGM") { idle(a) && a.inspection?.programMode == true }
        let g = CalcActions.gto(a.inspection!, line: 1)
        XCTAssertEqual(g.title, "GTO 001")
        a.performKeys(g.keys)                                        // program mode: the display shows line 001
        try await until("GTO 001") { a.inspection?.line == 1 && a.snapshot.lcd.text.contains("001") }
        XCTAssertEqual(a.inspection?.lines, 5)
        try await until("idle") { idle(a) }
        let sto = try XCTUnwrap(CalcActions.registerMenu(a.inspection!, name: "R2").first { $0.title == "STO R2" })
        a.performKeys(sto.keys)                                      // keyed into the program after 001
        try await until("STO 2 keyed") { a.inspection?.lines == 6 && a.inspection?.line == 2 }
        XCTAssertTrue(a.inspection?.program.first { $0.line == 2 }?.fullMnemonic.contains("STO") ?? false)
    }

    func testCalculatorBack() throws {
        XCTAssertNotNil(FaceImages.image("back_15c")); XCTAssertNotNil(FaceImages.image("back_16c"))
        XCTAssertEqual(CalculatorBackView.imageName(model: 15), "back_15c")
        XCTAssertEqual(CalculatorBackView.imageName(model: 16), "back_16c")
        XCTAssertNil(CalculatorBackView.imageName(model: 12))
        XCTAssertEqual(CalculatorBackView.title(model: 16), "HP-16C Back")
        XCTAssertTrue(DocFontStore.credit.contains("(front and back) by Warren Young"))
    }
    func testBackMenuFollowsModel() async throws {
        let fw = try need(Fixtures.multiE3E3, "no multi firmware")
        for (v, on) in [(120, false), (152, true), (160, true)] {
            let a = try app(fw, variant: v)
            try await until("snapshot \(v)") { a.snapshot.model == v / 10 }
            XCTAssertEqual(a.canShowCalculatorBack, on, "\(v)")
            a.stopEngine()
        }
    }
}
#endif
