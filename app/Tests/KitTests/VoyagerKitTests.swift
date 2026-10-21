// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// Tests of the Swift side: wrapper, machine, model data. Firmware is never bundled: the
// tests look for the user's own files in $VC_FIRMWARE_DIR, ~/Firmware or /workspace/Firmware
// and are skipped when none is there.

import Foundation
import XCTest
#if canImport(VoyagerKit)
@testable import VoyagerKit
#endif

enum Fixtures {
    static var firmwareDirs: [URL] {
        var d: [URL] = []
        if let e = ProcessInfo.processInfo.environment["VC_FIRMWARE_DIR"] { d.append(URL(fileURLWithPath: e)) }
        d.append(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Firmware"))
        d.append(URL(fileURLWithPath: "/workspace/Firmware"))
        d.append(URL(fileURLWithPath: "/workspace"))
        d += d.map { $0.appendingPathComponent("hp12c-user") }      // HP's original 12C, kept in its own subfolder (0.6.6)
        return d
    }

    static func find(_ names: [String]) -> Data? {
        for dir in firmwareDirs {
            for n in names {
                let u = dir.appendingPathComponent(n)
                if let data = try? Data(contentsOf: u) { return data }
            }
        }
        return nil
    }

    static var firmware16Ext: Data? { find(["Voyager16-ext-path-c-trim4-show-B7B7.bin"]) }
    static var multi: Data? { find(["HP12c-multi.bin"]) }
    /// HP's original 2015 HP-12C firmware: only ever read from the user's own folder, for local checks. Never part of the repo.
    static var stock12C: Data? { find(["HP12C_SAM4_01-30-2015.bin"]) }
    static var hp15c3ROM: Data? { find(["hp15c-3rom-mute120-fsm5-rel80-opt5cycle-debounce-menu-stopwatch-48fix-keys-batt-trim4-show-C8C8.bin"]) }

    static var fixturesDir: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")
    }
    static var millerRabin: Data { (try? Data(contentsOf: fixturesDir.appendingPathComponent("miller-rabin-ext-ready.16c"))) ?? Data() }
}

final class ModelDataTests: XCTestCase {
    func testEveryKeyIsKnownToTheCore() {
        for m in CalculatorModel.all {
            XCTAssertEqual(m.keys.count, 39, "\(m.name): 40 matrix positions, ENTER covers two")
            XCTAssertEqual(Set(m.keys.map(\.code)).count, 39)
            for k in m.keys {
                XCTAssertEqual(VoyagerCalculator.keyCode(model: m.id, name: k.name), k.code, "\(m.name) \(k.name)")
            }
        }
    }

    func testShortcutsAreUniquePerModel() {
        for m in CalculatorModel.all {
            var seen: [KeyShortcut: String] = [:]
            for k in m.keys {
                for s in k.shortcuts {
                    XCTAssertNil(seen[s.normalized], "\(m.name): \(s.label) used by \(seen[s.normalized] ?? "") and \(k.name)")
                    seen[s.normalized] = k.name
                }
            }
            XCTAssertEqual(m.key(for: .special(.returnKey))?.name, "ENTER")
            XCTAssertEqual(m.key(for: .special(.shift))?.style, .fShift)
            XCTAssertEqual(m.key(for: .special(.option))?.style, .gShift)
            XCTAssertEqual(m.key(for: .char("7"))?.code, 6)
        }
        XCTAssertEqual(CalculatorModel.hp16c.key(for: .char("A"))?.name, "A")
        XCTAssertEqual(CalculatorModel.hp16c.key(for: .special(.delete))?.name, "BSP")
    }

    func testSHA256() {
        XCTAssertEqual(SHA256Hex.of(Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}

final class MachineTests: XCTestCase {
    private func type(_ m: CalculatorMachine, _ names: [String], model: Int = 16) throws {
        for n in names { try m.tap(try XCTUnwrap(VoyagerCalculator.keyCode(model: model, name: n), n)) }
    }

    /// The milestone acceptance test through the Swift wrapper, in the whole-calculator
    /// engine the app uses: Miller-Rabin on 2147483647 gives "1 d" and the same memory as
    /// the Python simulator.
    func testMillerRabinThroughSwift() throws {
        guard let fw = Fixtures.firmware16Ext else { throw XCTSkip("no extended-memory 16C firmware file found") }
        let m = CalculatorMachine()
        try m.loadFirmware(fw)
        XCTAssertEqual(m.family, .hp16c)
        try m.boot(restoring: nil)
        XCTAssertEqual(m.calc.displayText.trimmingCharacters(in: .whitespaces), "0 h")
        try m.putMemory(Fixtures.millerRabin)
        try type(m, ["f", "0"])
        XCTAssertEqual(m.calc.displayText, "P-2 r-0139")
        try m.run(ms: 3000)
        try type(m, "2147483647".map { String($0) } + ["GSB", "A"])
        var waited = 0
        while m.calc.displayText.trimmingCharacters(in: .whitespaces) != "1 d" && waited < 300_000 {
            try m.run(ms: 1000); waited += 1000
        }
        XCTAssertEqual(m.calc.displayText.trimmingCharacters(in: .whitespaces), "1 d")
        try? m.rawMemory().write(to: URL(fileURLWithPath: NSTemporaryDirectory() + "mr-raw.16c"))
        try? m.memory().write(to: URL(fileURLWithPath: NSTemporaryDirectory() + "mr-off.16c"))
        // byte 0x7FB is the firmware's last-key byte (ON, from loading the memory), not user data
        var mem = try m.rawMemory(); mem[0x7FB] = 0
        XCTAssertEqual(SHA256Hex.of(mem), "\(Self.expectedMemorySHA)")
        print("Miller-Rabin: 1 d after \(waited / 1000) simulated seconds")
    }
    static let expectedMemorySHA = "b32d11104bd7e9e5ccf6b794b05911e8fc4d2f821e59e95b45291f2cae14f191"

    func testSaveAndRestoreState() throws {
        guard let fw = Fixtures.firmware16Ext else { throw XCTSkip("no 16C firmware file found") }
        let a = CalculatorMachine()
        try a.loadFirmware(fw)
        try a.boot(restoring: nil)
        try type(a, ["1", "2", "3", "ENTER", "4", "5", "ENTER", "+"])   // X = 8a, Y = 123
        XCTAssertEqual(a.calc.displayText.trimmingCharacters(in: .whitespaces), "8A h")
        let saved = try a.savedState()

        let b = CalculatorMachine()
        try b.loadFirmware(fw)
        XCTAssertNil(try b.boot(restoring: saved))
        XCTAssertEqual(b.calc.displayText.trimmingCharacters(in: .whitespaces), "8A h")
        try type(b, ["x<>y"])
        XCTAssertEqual(b.calc.displayText.trimmingCharacters(in: .whitespaces), "123 h")
    }

    func testQuickClickIsHeldLongEnough() throws {
        guard let fw = Fixtures.firmware16Ext else { throw XCTSkip("no 16C firmware file found") }
        let m = CalculatorMachine()
        try m.loadFirmware(fw)
        try m.boot(restoring: nil)
        m.press(27); m.release(27)          // press and release before any time passes
        try m.run(ms: 600)
        XCTAssertEqual(m.calc.displayText.trimmingCharacters(in: .whitespaces), "2 h")
    }

    func testMultiFirmwareModelFollowsTheCalculator() throws {
        guard let fw = Fixtures.multi else { throw XCTSkip("no HP12c-multi.bin found") }
        let m = CalculatorMachine()
        try m.loadFirmware(fw)
        XCTAssertEqual(m.family, .multi)
        try m.boot(restoring: nil)
        XCTAssertEqual(m.model, 12)
        try m.switchVariant(to: 160)
        XCTAssertEqual(m.model, 16)
        try type(m, ["1", "ENTER", "2", "+"])
        let saved = try m.savedState()
        XCTAssertEqual(saved.variant, 160)
        try m.switchVariant(to: 152)
        XCTAssertEqual(m.variant, 152)

        // a new launch comes back in 16C mode with its memory
        let n = CalculatorMachine()
        try n.loadFirmware(fw)
        XCTAssertNil(try n.boot(restoring: saved))
        XCTAssertEqual(n.model, 16)
        XCTAssertEqual(n.calc.displayText.trimmingCharacters(in: .whitespaces), "3 h")
    }

    func testEngineRunsInRealTime() throws {
        guard let fw = Fixtures.firmware16Ext else { throw XCTSkip("no 16C firmware file found") }
        let m = CalculatorMachine()
        try m.loadFirmware(fw)
        try m.boot(restoring: nil)
        let start = m.simMs
        let e = CalculatorEngine(machine: m)
        let shown = expectation(description: "display shows 7")
        e.onSnapshot = { s in if s.lcd.text.trimmingCharacters(in: .whitespaces) == "7 h" { shown.fulfill() } }
        e.start()
        e.send(.press(6)); e.send(.release(6))
        wait(for: [shown], timeout: 5)
        Thread.sleep(forTimeInterval: 1.0)
        let got = expectation(description: "state")
        var simAfter = 0
        e.send(.saveState { _ in got.fulfill() })
        wait(for: [got], timeout: 5)
        simAfter = m.simMs - start
        e.stop()
        // about 1.x seconds of calculator time for ~1.x s of wall time (not 100 s)
        XCTAssertGreaterThan(simAfter, 700)
        XCTAssertLessThan(simAfter, 5000)
    }
}

final class PhotoFaceTests: XCTestCase {
    /// Every key of every model has a measured rectangle on its photo, inside the image and
    /// below the LCD, and the click areas of different keys never overlap.
    func testEveryKeyHasARectangle() throws {
        for model in CalculatorModel.all {
            let face = try XCTUnwrap(model.photoFace, model.name)
            XCTAssertEqual(face.keys.count, 39, model.name)
            XCTAssertGreaterThan(face.lcd.width, 0.3); XCTAssertLessThan(face.lcd.maxY, 0.3)
            for k in model.keys {
                let r = try XCTUnwrap(face.keyRect(k.code), "\(model.name) \(k.name)")
                XCTAssertTrue(CGRect(x: 0, y: 0, width: 1, height: 1).contains(r), "\(model.name) \(k.name)")
                XCTAssertGreaterThan(r.minY, face.lcd.maxY, "\(model.name) \(k.name)")
            }
            let codes = face.keys.keys.sorted()
            for (i, a) in codes.enumerated() {
                for b in codes[(i + 1)...] {
                    let ra = face.hitRect(a)!, rb = face.hitRect(b)!
                    let o = ra.intersection(rb)
                    XCTAssertTrue(o.isNull || o.width * o.height < 1e-6, "\(model.name) \(a) / \(b) overlap")
                }
            }
        }
    }

    /// The keys sit on the Voyager grid: 10 columns, 4 rows, the tall ENTER covering 25 and 35.
    func testHitTestingFindsTheRealKeys() throws {
        for model in CalculatorModel.all {
            let face = try XCTUnwrap(model.photoFace)
            XCTAssertEqual(face.pitch.width, 0.0885, accuracy: 0.004, model.name)
            for k in model.keys {
                let r = face.keyRect(k.code)!
                XCTAssertEqual(face.key(at: CGPoint(x: r.midX, y: r.midY)), k.code, "\(model.name) \(k.name)")
                // on the gold legend just above the cap still counts as the key
                let h = face.hitRect(k.code)!
                XCTAssertEqual(face.key(at: CGPoint(x: r.midX, y: (h.minY + r.minY) / 2)), k.code, "\(model.name) \(k.name) legend")
            }
            XCTAssertEqual(face.keyRect(35), face.keyRect(25))
            let enter = face.keyRect(25)!, plus = face.keyRect(39)!
            XCTAssertEqual(enter.maxY, plus.maxY, accuracy: 0.01, "ENTER reaches the bottom row")
            XCTAssertNil(face.key(at: CGPoint(x: 0.5, y: 0.1)), "the display is not a key")
        }
    }
}
