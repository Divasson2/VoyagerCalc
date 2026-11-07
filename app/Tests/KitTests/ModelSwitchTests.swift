// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// The model chooser (CalculatorMachine.switchModel), the Keys menu chords and latched keys.

import Foundation
import XCTest
#if canImport(VoyagerKit)
@testable import VoyagerKit
#endif

final class ModelSwitchTests: XCTestCase {
    private func machine(_ data: Data?, _ name: String) throws -> CalculatorMachine {
        guard let data else { throw XCTSkip("no \(name) firmware") }
        let m = CalculatorMachine()
        try m.loadFirmware(data)
        try m.boot(restoring: nil)
        return m
    }

    private func key(_ m: CalculatorMachine, _ name: String) -> Int {
        VoyagerCalculator.keyCode(model: m.model, name: name)!
    }

    /// Type keys by name ("7", "STO", "1").
    private func type(_ m: CalculatorMachine, _ keys: String) throws {
        for k in keys.split(separator: " ") { try m.tap(key(m, String(k))) }
    }

    /// Store 77 in R1, switch, and tell whether R1 still holds it.
    private func switchKeepsR1(_ m: CalculatorMachine, to v: Int) throws -> Bool {
        try type(m, "7 7 STO 1")
        try m.switchModel(to: v)
        XCTAssertEqual(m.variant, v)
        XCTAssertFalse(m.showsPrError, "Pr Error cleared after the switch")
        XCTAssertFalse(m.displayText.trimmingCharacters(in: .whitespaces).isEmpty, "calculator on after the switch")
        try type(m, "RCL 1")
        let kept = m.displayText.contains("77")
        try m.tap(CalculatorMachine.keyBSP)
        return kept
    }

    func testFirmwareImages() throws {
        if let d = Fixtures.firmware16Ext { let c = VoyagerCalculator(); try c.loadFirmware(d); XCTAssertEqual(c.firmwareImages, [160]) }
        if let d = Fixtures.multiE3E3 { let c = VoyagerCalculator(); try c.loadFirmware(d); XCTAssertEqual(c.firmwareImages, [120, 152, 160]) }
        if let d = Fixtures.multi { let c = VoyagerCalculator(); try c.loadFirmware(d); XCTAssertEqual(c.firmwareImages, [120, 152, 160]) }
        if let d = Fixtures.hp15c3ROM { let c = VoyagerCalculator(); try c.loadFirmware(d); XCTAssertEqual(c.firmwareImages, [150, 152, 160]) }
        if let d = Fixtures.enhancedE9E9 { let c = VoyagerCalculator(); try c.loadFirmware(d); XCTAssertEqual(c.firmwareImages, [152, 160]) }
        if Fixtures.firmware16Ext == nil && Fixtures.multiE3E3 == nil && Fixtures.hp15c3ROM == nil && Fixtures.enhancedE9E9 == nil { throw XCTSkip("no firmware") }
    }

    /// 12C multi E3E3: every transition (including to the running model) clears memory.
    func testE3E3AllTransitions() throws {
        let m = try machine(Fixtures.multiE3E3, "E3E3")
        XCTAssertEqual(m.images, [120, 152, 160]); XCTAssertTrue(m.canSwitchModel)
        XCTAssertEqual(m.variant, 120)
        for v in [152, 160, 120, 160, 152, 120, 120] {
            let from = m.variant
            XCTAssertFalse(try switchKeepsR1(m, to: v), "E3E3 \(from) -> \(v) clears memory")
            XCTAssertEqual(m.model, v / 10)
        }
    }

    /// 15C 3-ROM C8C8: 15 / 15.2 / 16. Switches to or from the 16C clear memory; between 15.0
    /// and 15.2 the firmware keeps it (same register layout), as on the calculator.
    func testC8C8Transitions() throws {
        let m = try machine(Fixtures.hp15c3ROM, "C8C8")
        XCTAssertEqual(m.images, [150, 152, 160])
        XCTAssertEqual(m.variant, 150)
        let cases: [(Int, Bool)] = [(152, true), (160, false), (150, false), (160, false), (152, false), (150, true)]
        for (v, keeps) in cases {
            let from = m.variant
            XCTAssertEqual(try switchKeepsR1(m, to: v), keeps, "C8C8 \(from) -> \(v)")
        }
    }

    func testSingleImageCannotSwitch() throws {
        let m = try machine(Fixtures.firmware16Ext, "B7B7")
        XCTAssertEqual(m.images, [160]); XCTAssertFalse(m.canSwitchModel)
        XCTAssertThrowsError(try m.switchModel(to: 150)) { e in
            XCTAssertEqual(e as? CalculatorMachine.SwitchError, .notInFirmware(150))
        }
    }

    func testRestoreOnLaunchKeepsTheChosenModel() throws {
        let m = try machine(Fixtures.multiE3E3, "E3E3")
        try m.switchModel(to: 160)
        try type(m, "A B C")
        let saved = try m.savedState(turnBackOn: false)
        XCTAssertEqual(saved.variant, 160)
        let m2 = CalculatorMachine()
        try m2.loadFirmware(Fixtures.multiE3E3!)
        XCTAssertNil(try m2.boot(restoring: saved))
        XCTAssertEqual(m2.variant, 160)
        XCTAssertTrue(m2.displayText.contains("abc") || m2.displayText.uppercased().contains("ABC"), m2.displayText)
    }

    /// Key under the picker label: Multi uses 1/3/5; Enhanced (E9E9) uses 1 for 16C and 3 for 15.2.
    func testModelMenuKeys() {
        XCTAssertEqual(CalculatorMachine.modelMenuKey(for: 160, images: [120, 152, 160]), 5)
        XCTAssertEqual(CalculatorMachine.modelMenuKey(for: 152, images: [120, 152, 160]), 3)
        XCTAssertEqual(CalculatorMachine.modelMenuKey(for: 120, images: [120, 152, 160]), 1)
        XCTAssertEqual(CalculatorMachine.modelMenuKey(for: 160, images: [152, 160]), 1)
        XCTAssertEqual(CalculatorMachine.modelMenuKey(for: 152, images: [152, 160]), 3)
        XCTAssertNil(CalculatorMachine.modelMenuKey(for: 120, images: [152, 160]))
        XCTAssertTrue(CalculatorMachine.isEnhanced16C152([152, 160]))
        XCTAssertFalse(CalculatorMachine.isEnhanced16C152([120, 152, 160]))
        XCTAssertFalse(CalculatorMachine.isEnhanced16C152([150, 152, 160]))
    }

    /// HP-16C Enhanced E9E9: switching 16C <-> 15.2 keeps each mode's own memory.
    func testE9E9BothDirectionsKeepPerModeMemory() throws {
        let m = try machine(Fixtures.enhancedE9E9, "E9E9")
        XCTAssertEqual(m.images, [152, 160])
        XCTAssertTrue(m.canSwitchModel)
        XCTAssertTrue(m.keepsMemoryOnModelSwitch)
        XCTAssertEqual(m.variant, 160)
        try type(m, "7 7 STO 1")                         // 16C: R1 = 77
        try m.switchModel(to: 152)
        XCTAssertEqual(m.variant, 152)
        try type(m, "5 5 STO 1")                         // 15.2: R1 = 55
        try m.switchModel(to: 160)
        XCTAssertEqual(m.variant, 160)
        try type(m, "RCL 1")
        XCTAssertTrue(m.displayText.contains("77"), "16C memory kept: \(m.displayText)")
        try m.tap(CalculatorMachine.keyBSP)
        try m.switchModel(to: 152)
        try type(m, "RCL 1")
        XCTAssertTrue(m.displayText.contains("55"), "15.2 memory kept: \(m.displayText)")
    }

    // MARK: Keys menu

    private func each(_ body: (CalculatorMachine, String) throws -> Void) throws {
        var any = false
        for (d, n) in [(Fixtures.firmware16Ext, "B7B7"), (Fixtures.hp15c3ROM, "C8C8"), (Fixtures.multiE3E3, "E3E3")] where d != nil {
            any = true
            try body(try machine(d, n), n)
        }
        if !any { throw XCTSkip("no firmware") }
    }

    private func settle(_ m: CalculatorMachine, _ ms: Int = 1500) throws { try m.run(ms: ms) }

    func testServiceMenuChord() throws {
        try each { m, n in
            try m.perform(.serviceMenu)
            XCTAssertTrue(m.displayText.contains("1.L2.C3.H"), "\(n): \(m.displayText)")
            try m.tap(16)                                    // 4: model menu
            if m.canSwitchModel { XCTAssertTrue(m.displayText.contains("15.2"), "\(n): \(m.displayText)") }
        }
    }

    func testMemoryResetChord() throws {
        try each { m, n in
            try type(m, "7 STO 1")
            try m.perform(.memoryReset)
            XCTAssertTrue(m.showsPrError, "\(n): \(m.displayText)")
            try m.clearPrError()
            try type(m, "RCL 1")
            XCTAssertFalse(m.displayText.contains("7"), "\(n): memory cleared, \(m.displayText)")
        }
    }

    func testSelfTestChords() throws {
        try each { m, n in
            try m.perform(.selfTest); try settle(m, 4000)
            XCTAssertTrue(m.displayText.contains("-8,8,8,8,8,8,8,8,8,8,"), "\(n) self-test: \(m.displayText)")
            try m.powerOff()
            try m.perform(.keyboardTest); try settle(m, 500)
            XCTAssertTrue(m.displayText.contains("?"), "\(n) keyboard test: \(m.displayText)")
            try m.powerOff(); try m.powerOn()
        }
    }

    func testUSBChordJustTurnsOn() throws {
        try each { m, n in
            try type(m, "1 2 3")
            try m.perform(.usbMode)
            XCTAssertTrue(m.displayText.contains("123"), "\(n): \(m.displayText)")
        }
    }

    func testRadixChord() throws {
        try each { m, n in
            guard KeyChord.radixMark.isAvailable(model: m.model) else { return }
            try type(m, "1 2 3")
            try m.perform(.radixMark)
            XCTAssertTrue(m.displayText.contains("123,"), "\(n): \(m.displayText)")
            try m.perform(.radixMark)
            XCTAssertTrue(m.displayText.contains("123."), "\(n): back, \(m.displayText)")
        }
    }

    // MARK: latched keys

    func testKeyLatchLogic() {
        var l = KeyLatch()
        XCTAssertEqual(l.toggle(32), [.press(32)])
        XCTAssertEqual(l.toggle(25), [.press(25)])
        XCTAssertEqual(l.press(30), [.press(30)])
        XCTAssertEqual(l.release(30), [.release(30), .releaseLater([25, 32])])
        XCTAssertTrue(l.isEmpty)
        // clicking a latched key lets everything go, and its own release is swallowed
        _ = l.toggle(31)
        XCTAssertEqual(l.press(31), [.release(31)])
        XCTAssertEqual(l.release(31), [])
        // long-press: the key is already down; lifting the finger keeps it down
        XCTAssertEqual(l.press(7), [.press(7)])
        XCTAssertEqual(l.holdBecameLatch(7), [])
        XCTAssertEqual(l.release(7), [])
        XCTAssertEqual(l.toggle(7), [.release(7)])
    }

    /// Latch g and ENTER by hand, then click ON: the service menu opens, as with the preset.
    func testLatchedChordOpensTheServiceMenu() throws {
        let m = try machine(Fixtures.multiE3E3 ?? Fixtures.firmware16Ext, "multi or 16C")
        try m.powerOff()
        var l = KeyLatch()
        func apply(_ a: [KeyLatch.Action]) {
            for x in a {
                switch x {
                case .press(let k): m.press(k)
                case .release(let k): m.release(k)
                case .releaseLater(let ks): m.release(ks, afterMs: KeyLatch.releaseDelayMs)
                }
            }
        }
        apply(l.toggle(CalculatorMachine.keyG)); try m.run(ms: 300)
        apply(l.toggle(CalculatorMachine.keyENTER)); try m.run(ms: 300)
        apply(l.press(CalculatorMachine.keyON)); try m.run(ms: 150)
        apply(l.release(CalculatorMachine.keyON)); try m.run(ms: 1200)
        XCTAssertTrue(m.displayText.contains("1.L2.C3.H"), m.displayText)
        XCTAssertTrue(m.keysDown.isEmpty)
    }
}
