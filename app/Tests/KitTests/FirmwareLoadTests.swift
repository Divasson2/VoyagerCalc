// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// 0.6.5: firmware loading seen from Swift: full flash dumps, the checksum, plain-language errors,
// recognition by code shape, HP's original layout (0.6.6: the 12C runs, with limits). Synthetic images only,
// built here; no HP firmware is needed or included.

import Foundation
import XCTest
#if canImport(VoyagerKit)
@testable import VoyagerKit
#endif

final class FirmwareLoadTests: XCTestCase {
    static let size = 0x1C000

    static func put16(_ d: inout [UInt8], _ o: Int, _ v: Int) { d[o] = UInt8(v & 255); d[o + 1] = UInt8((v >> 8) & 255) }
    static func put32(_ d: inout [UInt8], _ o: Int, _ v: UInt32) { put16(&d, o, Int(v & 0xFFFF)); put16(&d, o + 2, Int(v >> 16)) }

    /// A synthetic image: vector table, a Nut ROM header (word 5 = w5), the paint-routine shape, optional ROM pointer.
    static func image(w5: Int, pointer: Bool, checksum: Int) -> [UInt8] {
        var d = [UInt8](repeating: 0xFF, count: size)
        put32(&d, 0, 0x200013C0); put32(&d, 4, 0x000110EF)
        for i in 2..<48 { put32(&d, 4 * i, 0x00011021) }
        let r = 0x480C - 0x4000
        for (i, w) in [0x107, 0x04E, 0x270, 0x238, 0x2EE, w5].enumerated() { put16(&d, r + 2 * i, w) }
        let p = 0xE1CA - 0x4000
        let shape = [0xB538, 0x4604, 0x2500, 0x5D29, 0x4628, 0xF7F1, 0xFE55, 0x1C6D, 0x2D14, 0xDBF8, 0xBD31, 0x4875, 0x7800, 0x28FF, 0xD009]
        for (i, w) in shape.enumerated() { put16(&d, p + 2 * i, w) }
        if pointer { put32(&d, 0xD7C8 - 0x4000, 0x20000010) }
        d[0x1BFEF] = 0x5A
        let sum = d.reduce(0) { $0 + Int($1) }
        let cur = (sum - Int(d[0x1BFEF])) & 255
        d[0x1B000] = UInt8((Int(d[0x1B000]) + checksum - cur) & 255)
        return d
    }

    static func dump(_ img: [UInt8], boot: UInt8 = 0xFF, total: Int = 0x20000) -> [UInt8] {
        var f = [UInt8](repeating: 0xFF, count: total)
        for i in 0..<0x4000 { f[i] = boot }
        put32(&f, 0, 0x20000800); put32(&f, 4, 0x000001C1)      // the bootloader's own vector table
        f.replaceSubrange(0x4000..<(0x4000 + img.count), with: img)
        return f
    }

    func load(_ bytes: [UInt8]) -> (VoyagerCalculator, CalculatorError?) {
        let c = VoyagerCalculator()
        do { try c.loadFirmware(Data(bytes)); return (c, nil) } catch { return (c, error as? CalculatorError) }
    }

    func testRecognisedByShapeShowsChecksum() {
        let (c, e) = load(Self.image(w5: 0x14F, pointer: true, checksum: 0xEF))
        XCTAssertNil(e)
        XCTAssertEqual(c.family, .hp15c)
        XCTAssertEqual(c.firmwareChecksum, "EFEF")
        XCTAssertEqual(c.firmwareBytesDropped, 0)
        XCTAssertTrue(c.firmwareInfo.contains("HP-12C CE firmware"), c.firmwareInfo)
    }

    func testFullFlashDumpIsAccepted() {
        let img = Self.image(w5: 0x14F, pointer: true, checksum: 0xEF)
        for (boot, total) in [(UInt8(0xFF), 0x20000), (0x00, 0x20000), (0xFF, 0x40000)] {
            let (c, e) = load(Self.dump(img, boot: boot, total: total))
            XCTAssertNil(e, "boot \(boot) size \(total)")
            XCTAssertEqual(c.firmwareBytesDropped, 0x4000)
            XCTAssertEqual(c.firmwareChecksum, "EFEF")
        }
    }

    /// 0.6.6: HP's original 12C (original layout, 12C ROM) loads and is a 12C that runs the keyboard and the display only.
    func testOriginalHP12CLoadsWithLimits() throws {
        let (c, e) = load(Self.image(w5: 0x14F, pointer: false, checksum: 0xD1))
        XCTAssertNil(e)
        XCTAssertEqual(c.family, .stock)
        XCTAssertEqual(c.firmwareChecksum, "D1D1")
        XCTAssertEqual(c.capabilities, .keysDisplay)
        XCTAssertFalse(c.capabilities.contains(.inspect))
        XCTAssertFalse(c.capabilities.contains(.memory))
        XCTAssertFalse(c.capabilities.contains(.modelSwitch))
        XCTAssertTrue(c.firmwareInfo.contains("original HP-12C") && c.firmwareInfo.contains("no inspector"), c.firmwareInfo)
        XCTAssertEqual(c.model, 12)
        XCTAssertEqual(c.variant, 120)
        XCTAssertEqual(c.firmwareImages, [120])
        // CE-only features say so instead of returning the wrong RAM
        XCTAssertThrowsError(try c.saveMemory()) { err in
            guard case .unsupported(let msg)? = err as? CalculatorError else { return XCTFail("\(err)") }
            XCTAssertTrue(msg.contains("Continuous Memory"), msg)
        }
        XCTAssertThrowsError(try c.loadMemory(Data(count: VoyagerCalculator.memorySize)))
        XCTAssertNil(c.inspect())
        // the same inside a full flash dump
        let (d, e2) = load(Self.dump(Self.image(w5: 0x14F, pointer: false, checksum: 0xD1)))
        XCTAssertNil(e2)
        XCTAssertEqual(d.family, .stock)
        XCTAssertEqual(d.firmwareBytesDropped, 0x4000)
    }

    /// An original-layout image with another ROM is recognised but not run, and the message no longer blames the model report.
    func testOriginalLayoutWithOtherRomIsNotVerified() {
        let (c, e) = load(Self.image(w5: 0x10F, pointer: false, checksum: 0x33))
        guard case .unsupported(let msg)? = e else { return XCTFail("expected .unsupported, got \(String(describing: e))") }
        XCTAssertTrue(msg.contains("not been verified") && msg.contains("15C") && msg.contains("3333"), msg)
        XCTAssertFalse(msg.contains("never reports"), msg)
        XCTAssertEqual(c.family, .stock)
        XCTAssertThrowsError(try c.startWhole())
    }

    func testCEFirmwareKeepsEveryCapability() {
        let (c, e) = load(Self.image(w5: 0x14F, pointer: true, checksum: 0xEF))
        XCTAssertNil(e)
        XCTAssertEqual(c.capabilities, .all)
    }

    func testStockChordsAreTheVerifiedOnes() {
        let stock = KeyChord.allCases.filter { $0.isAvailable(model: 12, family: .stock) }
        XCTAssertEqual(Set(stock), [.selfTest, .memoryReset, .radixMark])
        XCTAssertFalse(stock.contains(.serviceMenu) || stock.contains(.usbMode))
        XCTAssertEqual(KeyChord.allCases.filter { $0.isAvailable(model: 12, family: .multi) }.count, KeyChord.allCases.count)
        XCTAssertEqual(KeyChord.allCases.filter { $0.isAvailable(model: 16, family: .hp16c) }.count, KeyChord.allCases.count - 1)   // no decimal-mark chord on the 16C
    }

    /// A machine on the stock layout refuses memory work before it touches the calculator.
    func testStockMachineRefusesMemoryBeforeTurningOff() throws {
        let m = CalculatorMachine()
        try m.loadFirmware(Data(Self.image(w5: 0x14F, pointer: false, checksum: 0xD1)))
        XCTAssertEqual(m.family, .stock)
        XCTAssertNotNil(m.memoryUnavailableReason)
        XCTAssertFalse(m.canSwitchModel)
        XCTAssertThrowsError(try m.memory())
        XCTAssertThrowsError(try m.putMemory(Data(count: VoyagerCalculator.memorySize)))
        XCTAssertThrowsError(try m.rawMemory())
    }

    // MARK: a synthetic stock-like program (written for the tests, assembled with clang; no HP code)

    /// Flash 0x6000 = reset, 0x6100 = AST handler, 0x6180 = ADC handler, 0x61F0 = configuration words.
    /// It enables the AST tick, ADCIFE (IER) and NVIC IRQ 69; for every tick it sets a "pending" byte at block+1, starts a
    /// conversion and waits for the ADC handler to clear it (block+0x10 = ticks, block+0x14 = completed conversions).
    enum Synthetic {
    static let main: [UInt8] = [0x12, 0x48, 0x80, 0x21, 0x01, 0x60, 0x46, 0xF2, 0xF0, 0x15, 0x11, 0x48, 0x01, 0x21, 0x09, 0x02, 0x01, 0x60, 0x29, 0x68, 0x01, 0x63, 0x0F, 0x48, 0x69, 0x68, 0x01, 0x60, 0xA9, 0x68, 0x00, 0x29, 0x01, 0xD0, 0xE8, 0x68, 0x01, 0x60, 0x2C, 0x69, 0x30, 0xBF, 0x21, 0x69, 0xA2, 0x69, 0x91, 0x42, 0xFA, 0xD0, 0xA1, 0x61, 0x01, 0x21, 0x61, 0x70, 0x05, 0x48, 0x08, 0x21, 0x01, 0x60, 0x61, 0x78, 0x00, 0x29, 0xFC, 0xD1, 0x61, 0x69, 0x01, 0x31, 0x61, 0x61, 0xED, 0xE7, 0x04, 0xE1, 0x00, 0xE0, 0x00, 0x80, 0x03, 0x40, 0x08, 0xE1, 0x00, 0xE0]
    static let ast: [UInt8] = [0x46, 0xF2, 0xF0, 0x10, 0x00, 0x69, 0x01, 0x69, 0x01, 0x31, 0x01, 0x61, 0x70, 0x47, 0x00, 0x00]
    static let adc: [UInt8] = [0x05, 0x48, 0xC1, 0x6A, 0x46, 0xF2, 0xF0, 0x12, 0x12, 0x69, 0x51, 0x60, 0x01, 0x21, 0xC1, 0x60, 0x00, 0x21, 0x51, 0x70, 0x70, 0x47, 0x00, 0x00, 0x00, 0x80, 0x03, 0x40]
        static func image(stock: Bool, block: UInt32, ier: UInt32 = 1, nvic: UInt32 = 0x20) -> [UInt8] {
            var d = FirmwareLoadTests.image(w5: 0x14F, pointer: !stock, checksum: stock ? 0xD1 : 0xEF)
            let at = 0x6000 - 0x4000
            d.replaceSubrange(at..<(at + main.count), with: main)
            d.replaceSubrange((at + 0x100)..<(at + 0x100 + ast.count), with: ast)
            d.replaceSubrange((at + 0x180)..<(at + 0x180 + adc.count), with: adc)
            FirmwareLoadTests.put32(&d, at + 0x1F0, ier); FirmwareLoadTests.put32(&d, at + 0x1F4, nvic)
            FirmwareLoadTests.put32(&d, at + 0x1F8, 0); FirmwareLoadTests.put32(&d, at + 0x1FC, 0)
            FirmwareLoadTests.put32(&d, at + 0x200, block)
            FirmwareLoadTests.put32(&d, 4, 0x6001)
            FirmwareLoadTests.put32(&d, 4 * (16 + 39), 0x6101)
            FirmwareLoadTests.put32(&d, 4 * (16 + 69), 0x6181)
            return d
        }
    }

    /// The ADC end-of-conversion interrupt follows the hardware state, not a firmware RAM address (the 0.6.5 stock-12C bug).
    func testAdcInterruptIsDeliveredWhereverTheFirmwareKeepsItsFlag() throws {
        for (stock, block) in [(true, UInt32(0x20000000)), (true, 0x20000100), (false, 0x20000854), (false, 0x20000000)] {
            let m = CalculatorMachine()
            try m.loadFirmware(Data(Synthetic.image(stock: stock, block: block)))
            XCTAssertEqual(m.family, stock ? .stock : .hp15c)
            try m.calc.startWhole()
            try m.run(ms: 1000)
            XCTAssertGreaterThan(m.calc.debugRead32(block + 0x10), 50, "ticks, stock \(stock) block \(String(block, radix: 16))")
            XCTAssertGreaterThanOrEqual(m.calc.debugRead32(block + 0x14), 20, "conversions, stock \(stock) block \(String(block, radix: 16))")
        }
        // the interrupt must not be delivered when the firmware has not enabled it in the ADC
        let m = CalculatorMachine()
        try m.loadFirmware(Data(Synthetic.image(stock: true, block: 0x20000100, ier: 0)))
        try m.calc.startWhole()
        try m.run(ms: 1000)
        XCTAssertEqual(m.calc.debugRead32(0x20000114), 0)
    }

    /// Local check with the user's own copy of HP's original 12C firmware (skipped when it is not there).
    func testRealOriginalHP12CCalculates() throws {
        guard let fw = Fixtures.stock12C else { throw XCTSkip("no HP original 12C firmware in $VC_FIRMWARE_DIR, ~/Firmware[/hp12c-user] or /workspace/Firmware/hp12c-user") }
        let m = CalculatorMachine()
        try m.loadFirmware(fw)
        XCTAssertEqual(m.family, .stock)
        XCTAssertEqual(m.calc.firmwareChecksum, "D1D1")
        XCTAssertEqual(m.capabilities, .keysDisplay)
        try m.boot(restoring: nil)
        func type(_ names: [String]) throws { for n in names { try m.tap(try XCTUnwrap(VoyagerCalculator.keyCode(model: 12, name: n), n)) } }
        func shown() -> String { m.displayText.trimmingCharacters(in: .whitespaces) }
        XCTAssertEqual(m.model, 12)
        XCTAssertEqual(shown(), "0.00")
        try type(["1", "ENTER", "2", "+"])
        XCTAssertEqual(shown(), "3.00")
        try type(["6", "ENTER", "7", "*"])
        XCTAssertEqual(shown(), "42.00")
        try type(["1", "0", "n", "5", "i", "0", "PMT", "1", "0", "0", "0", "FV", "PV"])
        XCTAssertEqual(shown(), "-613.91")
        // CE-only calls refuse, and the calculator keeps running
        XCTAssertThrowsError(try m.memory())
        try type(["1", "ENTER", "1", "+"])
        XCTAssertEqual(shown(), "2.00")
    }

    func testErrorsSayWhatWasWrongAndWhatIsExpected() {
        func message(_ bytes: [UInt8]) -> String { load(bytes).1?.errorDescription ?? "" }
        let img = Self.image(w5: 0x14F, pointer: true, checksum: 0xEF)
        XCTAssertTrue(message([]).contains("empty"))
        let short = message(Array(img.prefix(2048)))
        XCTAssertTrue(short.contains("2048 bytes") && short.contains("114,688"), short)
        XCTAssertTrue(message(Array(img.dropLast())).contains("cut short"))
        XCTAssertTrue(message([UInt8](repeating: 0, count: 0x50000)).contains("larger than"))
        XCTAssertTrue(message([UInt8](repeating: 0x78, count: Self.size)).contains("ARM vector table"))
        let noFirmwareInDump = message([UInt8](repeating: 0xFF, count: 0x20000))
        XCTAssertTrue(noFirmwareInDump.contains("full flash dump") && noFirmwareInDump.contains("0x4000"), noFirmwareInDump)
    }

    func testRealFirmwareInsideAFullDumpIsTheSameFirmware() throws {
        guard let fw = Fixtures.hp15c3ROM else { throw XCTSkip("no 15C 3-ROM firmware found") }
        let (a, e1) = load([UInt8](fw)); XCTAssertNil(e1)
        let (b, e2) = load(Self.dump([UInt8](fw))); XCTAssertNil(e2)
        XCTAssertEqual(a.family, b.family)
        XCTAssertEqual(a.firmwareChecksum, "C8C8")
        XCTAssertEqual(b.firmwareChecksum, "C8C8")
        XCTAssertEqual(b.firmwareBytesDropped, 0x4000)
        // and it runs: 5 ENTER 3 +
        try b.startWhole()
        try b.tap(30, holdMs: 150, afterMs: 1500)
        try b.tap(24)
        let m = b.model
        for n in ["5", "ENTER", "3", "+"] { try b.tap(VoyagerCalculator.keyCode(model: m, name: n)!) }
        XCTAssertTrue(b.displayText.contains("8"), b.displayText)
    }
}
