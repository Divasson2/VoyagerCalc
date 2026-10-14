// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// The registers / program inspector through the Swift wrapper and the engine, in the
// whole-calculator engine the app uses. (core/tests/test_inspect.c checks the C side in depth.)

import Foundation
import XCTest
#if canImport(VoyagerKit)
@testable import VoyagerKit
#endif

extension Fixtures {
    static var multiE3E3: Data? { find(["HP12c-multi-152-ext16-E3E3.bin"]) }
}

final class InspectorTests: XCTestCase {
    private func type(_ m: CalculatorMachine, _ s: String, model: Int = 16) throws {
        for w in s.split(separator: " ").map(String.init) {
            if let k = VoyagerCalculator.keyCode(model: model, name: w) { try m.tap(k); continue }
            for ch in w { try m.tap(try XCTUnwrap(VoyagerCalculator.keyCode(model: model, name: String(ch)), String(ch))) }
        }
    }
    private func inspect(_ m: CalculatorMachine) throws -> InspectorSnapshot { try XCTUnwrap(m.calc.inspect()) }
    private func value(_ s: InspectorSnapshot, _ name: String) -> String? {
        (s.stack + s.registers).first { $0.name == name }?.text
    }

    func testMillerRabinListingRegistersAndPointer() throws {
        guard let fw = Fixtures.firmware16Ext else { throw XCTSkip("no extended-memory 16C firmware file found") }
        let m = CalculatorMachine()
        try m.loadFirmware(fw)
        try m.boot(restoring: nil)
        try m.putMemory(Fixtures.millerRabin)
        var s = try inspect(m)
        XCTAssertEqual(s.model, 16); XCTAssertTrue(s.extendedMemory)
        XCTAssertEqual(s.lines, 117); XCTAssertEqual(s.program.count, 117); XCTAssertEqual(s.registerCount, 139)
        XCTAssertEqual(s.program[0].keys, "43,22, A"); XCTAssertEqual(s.program[0].fullMnemonic, "g LBL A")
        XCTAssertEqual(s.program[3].fullMnemonic, "f WSIZE")
        XCTAssertEqual(s.program[116].fullMnemonic, "g RTN")
        XCTAssertEqual(s.modeSummary, "DEC  WSIZE 64  UNSGN")
        // run it (97 is prime): X = 1, R0 = n, R1 = n - 1, R2 = d, R3 = s
        try type(m, "9 7 GSB A")
        var waited = 0
        while (m.calc.inspect()?.running ?? false) && waited < 60_000 { try m.run(ms: 500); waited += 500 }
        s = try inspect(m)
        XCTAssertFalse(s.running)
        XCTAssertEqual(value(s, "X"), "1"); XCTAssertEqual(value(s, "R0"), "97"); XCTAssertEqual(value(s, "R1"), "96")
        XCTAssertEqual(value(s, "R2"), "3"); XCTAssertEqual(value(s, "R3"), "5")
        // pointer: GTO label, SST / BST in program mode
        try type(m, "GTO F"); XCTAssertEqual(try inspect(m).line, 114)
        try type(m, "g R/S"); XCTAssertTrue(try inspect(m).programMode)
        try type(m, "SST"); XCTAssertEqual(try inspect(m).line, 115)
        try type(m, "g SST g SST"); XCTAssertEqual(try inspect(m).line, 113)
        try type(m, "g R/S"); XCTAssertFalse(try inspect(m).programMode)
    }

    func testBasesAndPathCTopRegister() throws {
        guard let fw = Fixtures.firmware16Ext else { throw XCTSkip("no extended-memory 16C firmware file found") }
        let m = CalculatorMachine()
        try m.loadFirmware(fw)
        try m.boot(restoring: nil)
        try type(m, "DEC 1 6 f STO f 2 1 0 0 CHS")
        var s = try inspect(m)
        XCTAssertEqual(s.wordSize, 16); XCTAssertEqual(s.registerCount, 616)
        XCTAssertEqual(value(s, "X"), "-100")
        try type(m, "HEX")
        s = try inspect(m)
        let x = try XCTUnwrap(s.stack.first)
        XCTAssertEqual(x.text, "FF9C"); XCTAssertEqual(x.decimal, "-100"); XCTAssertTrue(x.isInteger)
        try type(m, "2 6 7 STO SST 7 7 7 7 STO R/S")      // I = 615, STO (i): R615 = 7777h
        s = try inspect(m)
        XCTAssertEqual(value(s, "I"), "267"); XCTAssertEqual(value(s, "R615"), "7777")
        XCTAssertEqual(s.registers.last?.name, "R615")
    }

    func testEnginePublishesInspectorSnapshots() throws {
        guard let fw = Fixtures.firmware16Ext else { throw XCTSkip("no 16C firmware file found") }
        let m = CalculatorMachine()
        try m.loadFirmware(fw)
        try m.boot(restoring: nil)
        let e = CalculatorEngine(machine: m)
        let got7 = expectation(description: "X = 7 in the inspector")
        var count = 0
        e.onInspector = { s in
            count += 1
            if s?.stack.first?.text == "7" { got7.fulfill() }
        }
        e.start()
        e.send(.setInspector(true))
        e.send(.press(6)); e.send(.release(6))
        wait(for: [got7], timeout: 5)
        Thread.sleep(forTimeInterval: 1.0)
        let before = count
        Thread.sleep(forTimeInterval: 1.0)
        e.send(.setInspector(false))
        e.stop()
        XCTAssertLessThanOrEqual(count - before, 1, "nothing changes: no new snapshots")
        XCTAssertLessThan(count, 20, "throttled to 10 Hz at most")
    }

    func testMulti15CAnd12C() throws {
        guard let fw = Fixtures.multiE3E3 else { throw XCTSkip("no HP12c-multi-152-ext16-E3E3.bin found") }
        let m = CalculatorMachine()
        try m.loadFirmware(fw)
        try m.boot(restoring: nil)
        try type(m, "1 2 n 4 5 PV 1 1 STO 0 4 4 STO . 9", model: 12)
        var s = try inspect(m)
        XCTAssertEqual(s.model, 12); XCTAssertTrue(s.hasProgram)   // 0.5.6: the 12C listing
        XCTAssertEqual(s.lines, 8); XCTAssertEqual(s.registerCount, 20)
        XCTAssertEqual(s.program.count, 8); XCTAssertEqual(s.program.first?.fullMnemonic, "g GTO 00")
        XCTAssertEqual(value(s, "n"), "12"); XCTAssertEqual(value(s, "PV"), "45")
        XCTAssertEqual(value(s, "R0"), "11"); XCTAssertEqual(value(s, "R.9"), "44")
        try m.switchVariant(to: 152)
        try type(m, "1 ENTER 3 ÷ STO 2 g R/S f SST SQRT 2 × g GSB g R/S", model: 15)
        s = try inspect(m)
        XCTAssertEqual(s.model, 15); XCTAssertEqual(s.variant, 152)
        XCTAssertEqual(value(s, "X"), "0.3333333333"); XCTAssertEqual(value(s, "R2"), "0.3333333333")
        XCTAssertEqual(s.program.map(\.keys), ["42,21,11", "2", "20", "43 32"])
        XCTAssertEqual(s.program.map(\.fullMnemonic), ["f LBL A", "2", "×", "g RTN"])
    }
}
