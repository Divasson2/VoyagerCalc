// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// The USB HID link to the real calculator, against a fake calculator that parses the reports
// the way the CE firmware's HID handler does (ANALYSIS.md section 2), and the memory check.

import Foundation
import XCTest
#if canImport(VoyagerKit)
@testable import VoyagerKit
#endif

/// A fake HP CE in HID mode: command byte >= 0x40, otherwise [n, n bytes] into a queue that
/// the 'C' handler takes; 0xFE answers with the 2 KB memory in [n, n bytes] reports.
final class FakeCalculator: CalculatorTransport {
    var memory: [UInt8]
    var connected = true
    var chunk = 63                     // data bytes per input report
    var silent = false                 // never answers
    var stopAfter: Int?                // stop answering after this many dump bytes
    var ignoreBlocks: Set<Int> = []    // 'C' blocks the "firmware" drops (each time)
    var ignoreOnceBlocks: Set<Int> = []  // ... only on the first write
    var corruptLength = false          // answer with a report whose length byte is >= 64
    var stopsOnCPUStateChange = false  // like the real CE: a 'C' block that changes 0x00..0x6F stops it
    private var afterDump = true
    private(set) var sent: [[UInt8]] = []
    private(set) var opens = 0, closes = 0, writesSeen = 0
    private var queue: [UInt8] = []
    private var outbox: [[UInt8]] = []

    init(memory: [UInt8]) { self.memory = memory }

    func open() throws { guard connected else { throw LinkError.noDevice }; opens += 1 }
    func close() { closes += 1 }

    func send(_ r: [UInt8]) throws {
        XCTAssertEqual(r.count, CalculatorLink.reportSize)
        sent.append(r)
        guard connected else { throw LinkError.io("bad argument (0xE00002C2)") }
        if r[0] >= 0x40 { afterDump = true; command(r[0]); return }
        queue += r[1...Int(r[0])]
        while let c = queue.first {
            if c == 0x43 {
                guard queue.count >= 34 else { return }
                let block = Int(queue[1]), data = Array(queue[2..<34])
                queue.removeFirst(34)
                if afterDump { writesSeen += 1; afterDump = false }
                if stopsOnCPUStateChange, block * 32 < 0x70, (0..<min(32, 0x70 - block * 32)).contains(where: { i in
                    let a = block * 32 + i, mask: UInt8 = a == CalculatorLink.flag8Offset ? ~CalculatorLink.flag8Mask : 0xFF
                    return memory[a] & mask != data[i] & mask }) {
                    // assumed like the real CE: any CPU-state change stops it, except the flag-8 status bit
                    connected = false; return
                }
                if ignoreBlocks.contains(block) || (writesSeen == 1 && ignoreOnceBlocks.contains(block)) { continue }
                memory.replaceSubrange(block * 32..<block * 32 + 32, with: data)
            } else { queue.removeFirst(); afterDump = true; command(c) }
        }
    }

    private func command(_ c: UInt8) {
        guard c == 0xFE, !silent else { return }
        var pos = 0
        let end = min(memory.count, stopAfter ?? memory.count)
        while pos < end {
            let n = min(chunk, end - pos)
            var r = [UInt8](repeating: 0, count: 64)
            r[0] = UInt8(n); r.replaceSubrange(1...n, with: memory[pos..<pos + n])
            outbox.append(r); pos += n
        }
        if corruptLength { outbox.insert([0x40] + [UInt8](repeating: 0, count: 63), at: 1) }
    }

    func receive(timeout: TimeInterval) throws -> [UInt8]? {
        if outbox.isEmpty { Thread.sleep(forTimeInterval: min(timeout, 0.005)); return nil }
        return outbox.removeFirst()
    }
}

final class CalculatorLinkTests: XCTestCase {
    static func pattern(_ seed: Int) -> [UInt8] { (0..<2048).map { UInt8(truncatingIfNeeded: $0 * 31 + seed * 7 + ($0 >> 5)) } }

    private func link(_ f: FakeCalculator) -> CalculatorLink {
        let l = CalculatorLink(transport: f)
        l.commandPause = 0; l.packetPause = 0; l.readTimeout = 0.3
        return l
    }

    func testDumpCommandFraming() {
        let r = CalculatorLink.dumpReport()
        XCTAssertEqual(r.count, 64)
        XCTAssertEqual(r[0], 0xFE)
        XCTAssertTrue(r[1...].allSatisfy { $0 == 0 })
        XCTAssertEqual(CalculatorLink.vendorID, 0x03F0)
        XCTAssertEqual(CalculatorLink.productID, 0x1341)
    }

    func testWriteFraming() throws {
        let mem = Self.pattern(1)
        let reports = try CalculatorLink.writeReports(Data(mem))
        XCTAssertEqual(reports.count, 64)
        for (i, r) in reports.enumerated() {
            XCTAssertEqual(r.count, 64)
            XCTAssertEqual(r[0], 34, "length byte = 'C' + block + 32 bytes")
            XCTAssertEqual(r[1], UInt8(ascii: "C"))
            XCTAssertEqual(r[2], UInt8(i))
            XCTAssertEqual(Array(r[3..<35]), Array(mem[i * 32..<i * 32 + 32]))
            XCTAssertTrue(r[35...].allSatisfy { $0 == 0 })
        }
        XCTAssertThrowsError(try CalculatorLink.writeReports(Data(count: 2047))) { XCTAssertEqual($0 as? LinkError, .wrongSize(2047)) }
    }

    func testReassembly() throws {
        var d = Data()
        XCTAssertFalse(try CalculatorLink.append(report: [3, 1, 2, 3] + [UInt8](repeating: 9, count: 60), to: &d))
        XCTAssertEqual([UInt8](d), [1, 2, 3])
        XCTAssertFalse(try CalculatorLink.append(report: [UInt8](repeating: 0, count: 64), to: &d), "empty report ignored")
        XCTAssertThrowsError(try CalculatorLink.append(report: [64] + [UInt8](repeating: 0, count: 63), to: &d))
        var full = Data(count: 2040)
        XCTAssertThrowsError(try CalculatorLink.append(report: [9] + [UInt8](repeating: 0, count: 63), to: &full), "overflow past 2 KB")
        XCTAssertTrue(try CalculatorLink.append(report: [8] + [UInt8](repeating: 0, count: 63), to: &full))
    }

    func testReadInChunks() throws {
        for chunk in [63, 32, 17, 1] {
            let f = FakeCalculator(memory: Self.pattern(chunk)); f.chunk = chunk
            XCTAssertEqual([UInt8](try link(f).readMemory()), Self.pattern(chunk), "chunk \(chunk)")
            XCTAssertEqual(f.sent, [CalculatorLink.dumpReport()])
            XCTAssertEqual(f.opens, 1); XCTAssertEqual(f.closes, 1)
        }
    }

    func testNoDevice() {
        let f = FakeCalculator(memory: Self.pattern(0)); f.connected = false
        XCTAssertThrowsError(try link(f).readMemory()) { XCTAssertEqual($0 as? LinkError, .noDevice) }
        XCTAssertThrowsError(try link(f).writeMemory(Data(Self.pattern(1)))) { XCTAssertEqual($0 as? LinkError, .noDevice) }
        XCTAssertTrue(LinkError.noDevice.errorDescription!.contains("Connect the calculator by USB, turn it off, hold f and ENTER and press ON."))
    }

    func testTimeoutsDoNotHang() {
        let f = FakeCalculator(memory: Self.pattern(0)); f.silent = true
        let t0 = Date()
        XCTAssertThrowsError(try link(f).readMemory()) { XCTAssertEqual($0 as? LinkError, .timeout(received: 0)) }
        XCTAssertLessThan(Date().timeIntervalSince(t0), 1.5)
        let g = FakeCalculator(memory: Self.pattern(0)); g.stopAfter = 1000
        XCTAssertThrowsError(try link(g).readMemory()) { XCTAssertEqual($0 as? LinkError, .timeout(received: 1000 - 1000 % 63 + 1000 % 63)) }
        XCTAssertEqual(g.closes, 1, "closed after a timeout")
    }

    func testBadReport() {
        let f = FakeCalculator(memory: Self.pattern(0)); f.corruptLength = true
        XCTAssertThrowsError(try link(f).readMemory()) { XCTAssertEqual($0 as? LinkError, .badReport(length: 64)) }
    }

    /// Header (CPU state, 0x00..0x6F) and trailer (0x7E0..) of `a`, memory of `b`.
    static func merged(_ a: [UInt8], _ b: [UInt8]) -> [UInt8] {
        Array(a[0..<0x70]) + Array(b[0x70..<0x7F0]) + Array(a[0x7F0...])
    }

    func testWriteVerifies() throws {
        let f = FakeCalculator(memory: Self.pattern(0))
        let new = Data(Self.pattern(5))
        let back = try link(f).writeMemory(new)
        XCTAssertEqual([UInt8](back), Self.merged(Self.pattern(0), Self.pattern(5)))
        XCTAssertEqual(f.memory, Self.merged(Self.pattern(0), Self.pattern(5)), "the calculator keeps its own CPU state and trailer")
        let blocks = f.sent.filter { $0[1] == UInt8(ascii: "C") }.map { Int($0[2]) }
        XCTAssertEqual(blocks, Array(3...63), "blocks 0-2 (CPU state only) are not sent; 63 holds the program top")
        XCTAssertEqual(f.sent.first, CalculatorLink.dumpReport(), "the calculator is read first")
        XCTAssertEqual(f.sent.last, CalculatorLink.dumpReport())
    }

    /// The 0.5.2 bug: the emulator's image (saved while off) in blocks 0-2 stopped the real
    /// calculator after block 2, and block 3 failed with kIOReturnBadArgument.
    func testWriteKeepsTheCalculatorsCPUState() throws {
        let f = FakeCalculator(memory: Self.pattern(0)); f.stopsOnCPUStateChange = true
        let new = Data(Self.pattern(8))
        XCTAssertEqual([UInt8](try link(f).writeMemory(new))[0x70..<0x7F0], Self.pattern(8)[0x70..<0x7F0])
        XCTAssertTrue(f.connected)
        // what 0.5.2 sent (all 64 blocks as they are) stops it at block 0
        let g = FakeCalculator(memory: Self.pattern(0)); g.stopsOnCPUStateChange = true
        XCTAssertThrowsError(try { for r in try CalculatorLink.writeReports(new) { try g.send(r) } }())
        XCTAssertFalse(g.connected)
    }

    /// The 0.5.3 bug (Jose, E3E3 in 15.2): FinancePac written into an empty calculator came
    /// back with lines 1-14 as f LBL 0: 0x7E0..0x7EF (the program's first 14 bytes) was kept
    /// from the calculator (zeros = LBL 0) and not compared. Also a 16C image (pointer at 0x7E0).
    func testWriteKeepsTheProgramTop() throws {
        let empty = try Self.fixture("E3E3-152-empty-usb-read.15c")
        for name in ["FinancePac.15c", "pi-1010-ready.16c"] {
            let img = try Self.fixture(name)
            XCTAssertFalse(img[0x7E0..<0x7F0].allSatisfy { $0 == 0 }, name)
            let f = FakeCalculator(memory: [UInt8](empty)); f.stopsOnCPUStateChange = true
            let back = [UInt8](try link(f).writeMemory(img))
            XCTAssertEqual(back[0x70..<0x7F0], [UInt8](img)[0x70..<0x7F0], "\(name): the whole user area, program top included")
            XCTAssertEqual(back[0x7F0...], [UInt8](empty)[0x7F0...], "\(name): the calculator keeps its trailer")
        }
        // the 15C on E3E3 lists FinancePac from line 1 (LBL 7), not 14 x LBL 0
        guard let fw = Fixtures.find(Self.e3e3) else { throw XCTSkip("no E3E3 firmware") }
        let f = FakeCalculator(memory: [UInt8](empty))
        let back = try link(f).writeMemory(try Self.fixture("FinancePac.15c"))
        let m = CalculatorMachine(); try m.loadFirmware(fw); try m.boot(restoring: nil); try m.switchModel(to: 152)
        try m.putMemory(back)
        let prog = m.calc.inspect(includeProgram: true)?.program ?? []
        XCTAssertEqual(prog.count, 407)
        XCTAssertEqual(prog.first?.fullMnemonic, "f LBL 7", "\(prog.prefix(3).map { $0.fullMnemonic })")
        XCTAssertFalse(prog.prefix(14).contains { $0.fullMnemonic == "f LBL 0" })
        // and a lost top is caught by the read-back
        let g = FakeCalculator(memory: [UInt8](empty)); g.ignoreBlocks = [63]
        XCTAssertThrowsError(try link(g).writeMemory(try Self.fixture("FinancePac.15c"))) {
            guard case .mismatch(_, let o)? = $0 as? LinkError else { return XCTFail("\($0)") }
            XCTAssertGreaterThanOrEqual(o, 0x7E0)
        }
    }

    func testWriteRetriesAfterADroppedBlock() throws {
        let f = FakeCalculator(memory: Self.pattern(0)); f.ignoreOnceBlocks = [17]
        let new = Data(Self.pattern(6))
        XCTAssertEqual([UInt8](try link(f).writeMemory(new)), Self.merged(Self.pattern(0), Self.pattern(6)))
        XCTAssertEqual(f.writesSeen, 2)
        XCTAssertEqual(f.sent.filter { $0[1] == UInt8(ascii: "C") }.count, 61 + 1, "the retry sends only the block that was still different")
    }

    func testWriteMismatchIsReported() {
        let f = FakeCalculator(memory: Self.pattern(0)); f.ignoreBlocks = [3]
        let new = Data(Self.pattern(7))
        let diffs = (0x70..<128).filter { Self.pattern(0)[$0] != Self.pattern(7)[$0] }
        XCTAssertThrowsError(try link(f).writeMemory(new)) {
            XCTAssertEqual($0 as? LinkError, .mismatch(differences: diffs.count, firstOffset: diffs.first!))
        }
        XCTAssertEqual(f.writesSeen, 3, "three attempts")
    }

    // MARK: the memory check (what Read from Calculator / Open Memory File do before loading)

    func testMemoryCheck() throws {
        guard let fw16 = Fixtures.firmware16Ext else { throw XCTSkip("no 16C firmware") }
        let m = CalculatorMachine()
        try m.loadFirmware(fw16); try m.boot(restoring: nil); try m.putMemory(Fixtures.millerRabin)
        let mem16 = try m.memory()
        XCTAssertTrue(CalculatorMachine.checkMemory(mem16, firmware: fw16, variant: 160).fits)
        XCTAssertEqual(CalculatorMachine.checkMemory(Data(count: 100), firmware: fw16, variant: 160), .wrongSize(100))
        XCTAssertFalse(CalculatorMachine.checkMemory(Data(count: 2048), firmware: fw16, variant: 160).fits)
        if let fw15 = Fixtures.find(["hp15c-3rom-mute120-fsm5-rel80-opt5cycle-debounce-menu-stopwatch-48fix-keys-batt-trim4-show-C8C8.bin"]) {
            let m15 = CalculatorMachine(); try m15.loadFirmware(fw15); try m15.boot(restoring: nil)
            let mem15 = try m15.memory()
            XCTAssertEqual(CalculatorMachine.checkMemory(mem15, firmware: fw16, variant: 160), .rejected, "a 15C memory on the 16C")
            XCTAssertFalse(CalculatorMachine.checkMemory(mem16, firmware: fw15, variant: 150).fits, "a 16C memory on the 15C")
            XCTAssertEqual(CalculatorMachine.identifyMemory(mem15, firmware: fw15, among: [150, 152, 160]), [150, 152])
            XCTAssertEqual(CalculatorMachine.identifyMemory(mem16, firmware: fw15, among: [150, 152, 160]), [160])
        }
        if let multi = Fixtures.find(["HP12c-multi-152-ext16-E3E3.bin"]) {
            let m12 = CalculatorMachine(); try m12.loadFirmware(multi); try m12.boot(restoring: nil)
            let mem12 = try m12.memory()
            XCTAssertEqual(CalculatorMachine.identifyMemory(mem12, firmware: multi, among: m12.images), [120])
            XCTAssertEqual(CalculatorMachine.identifyMemory(mem16, firmware: multi, among: m12.images), [160])
        }
    }

    // MARK: real memory files (regression: 0.5.1 rejected Jose's FinancePac)

    static func fixture(_ name: String) throws -> Data {
        let d = try Data(contentsOf: Fixtures.fixturesDir.appendingPathComponent(name))
        XCTAssertEqual(d.count, 2048, name)
        return d
    }
    static let c8c8 = ["hp15c-3rom-mute120-fsm5-rel80-opt5cycle-debounce-menu-stopwatch-48fix-keys-batt-trim4-show-C8C8.bin"]
    static let e3e3 = ["HP12c-multi-152-ext16-E3E3.bin"]

    /// FinancePac was saved while the calculator was on (as every USB dump is): the first ON
    /// turns that calculator off. 0.5.1 pressed ON once, saw a blank display and said "would not
    /// start". It must fit the 15C (15.0 and 15.2, C8C8 and E3E3) and load with its 407 lines.
    /// FinancePac is a 15.2 (double memory) image: 96 33 64-5 at g MEM in 15.2, Error 10 in
    /// 15.0 (Jose's Error 10 after Read from Calculator: calculator and app on different 15C modes).
    /// A small image read from a calculator in 15.0 mode fits both.
    func testFinancePacNeeds152() throws {
        let fp = try Self.fixture("FinancePac.15c"), small = try Self.fixture("Calc15-0-usb-read.15c")
        guard let fw = Fixtures.find(Self.c8c8) else { throw XCTSkip("no C8C8 firmware") }
        XCTAssertEqual(CalculatorMachine.checkMemory(fp, firmware: fw, variant: 150), .needsMoreMemory)
        XCTAssertEqual(CalculatorMachine.identifyMemory(fp, firmware: fw, among: [150, 152, 160]), [152])
        XCTAssertTrue(CalculatorMachine.checkMemory(small, firmware: fw, variant: 150).fits)
        XCTAssertTrue(CalculatorMachine.checkMemory(small, firmware: fw, variant: 152).fits)
        // the Write to Calculator warning ("set the calculator to 15C (15.2) mode first")
        XCTAssertTrue(CalculatorMachine.needs152(fp, firmware: fw, among: [150, 152, 160]))
        XCTAssertFalse(CalculatorMachine.needs152(small, firmware: fw, among: [150, 152, 160]))
        XCTAssertFalse(CalculatorMachine.needs152(fp, firmware: fw, among: [152]), "no 15.0 image: nothing to warn about")
    }

    func testFinancePacFits15C() throws {
        let fp = try Self.fixture("FinancePac.15c")
        var ran = 0
        for (names, variants) in [(Self.c8c8, [152]), (Self.e3e3, [152])] {
            guard let fw = Fixtures.find(names) else { continue }
            for v in variants {
                ran += 1
                let r = CalculatorMachine.checkMemory(fp, firmware: fw, variant: v)
                XCTAssertTrue(r.fits, "FinancePac on \(names[0].suffix(8)) \(v): \(r)")
                // and the real load keeps the programs
                let m = CalculatorMachine(); try m.loadFirmware(fw); try m.boot(restoring: nil)
                if m.variant != v { try m.switchModel(to: v) }
                try m.putMemory(fp)
                XCTAssertEqual(m.calc.inspect()?.lines, 407, "FinancePac program lines on \(v)")
                XCTAssertFalse(m.displayText.contains("Error"), m.displayText)
            }
            if names == Self.e3e3 {
                XCTAssertFalse(CalculatorMachine.checkMemory(fp, firmware: fw, variant: 160).fits, "a 15C memory on the 16C")
                XCTAssertFalse(CalculatorMachine.checkMemory(fp, firmware: fw, variant: 120).fits, "a 15C memory on the 12C")
                XCTAssertEqual(CalculatorMachine.identifyMemory(fp, firmware: fw, among: [120, 152, 160]), [152])
            }
        }
        if let fw16 = Fixtures.firmware16Ext {
            XCTAssertEqual(CalculatorMachine.checkMemory(fp, firmware: fw16, variant: 160), .rejected)
        }
        if ran == 0 { throw XCTSkip("no 15C firmware") }
    }

    /// Known-good 16C files fit the 16C (Path-C and stock) and not the 15C, where the 15C
    /// firmware cold-starts without Pr Error: caught by the memory compare.
    func testKnown16CFiles() throws {
        let files = ["pi-1010-ready.16c", "fill-regs-jf-ws64-ready.16c", "e-2881-programE-ready.16c", "phi-336-stock-programE-ready.16c", "miller-rabin-ext-ready.16c"]
        let fw16 = [Fixtures.firmware16Ext, Fixtures.find(["_baseline_hp16c-firmware.bin", "hp16c-firmware.bin"])].compactMap { $0 }
        guard !fw16.isEmpty else { throw XCTSkip("no 16C firmware") }
        let fw15 = Fixtures.find(Self.c8c8)
        for f in files {
            let d = try Self.fixture(f)
            for fw in fw16 {
                let r = CalculatorMachine.checkMemory(d, firmware: fw, variant: 160)
                if f == "miller-rabin-ext-ready.16c" && fw != Fixtures.firmware16Ext { continue }   // extended-memory layout
                XCTAssertTrue(r.fits, "\(f): \(r)")
            }
            if let fw15 {
                let r = CalculatorMachine.checkMemory(d, firmware: fw15, variant: 150)
                XCTAssertFalse(r.fits, "\(f) on the 15C: \(r)")
            }
        }
    }

    /// Every model: an image taken while the calculator is on (what Read from Calculator gets)
    /// and one taken while it is off both fit their own model, with a stored register kept.
    func testOnAndOffImagesFitEveryModel() throws {
        var ran = 0
        for (names, variants) in [(Self.e3e3, [120, 152, 160]), (Self.c8c8, [150, 152])] {
            guard let fw = Fixtures.find(names) else { continue }
            for v in variants {
                ran += 1
                let m = CalculatorMachine(); try m.loadFirmware(fw); try m.boot(restoring: nil)
                if m.variant != v { try m.switchModel(to: v) }
                for k in ["4", "2", "STO", "1"] { try m.tap(XCTUnwrap(VoyagerCalculator.keyCode(model: m.model, name: k), k)) }
                try m.run(ms: 300)
                let on = try m.rawMemory()                 // live, calculator on
                let off = try m.memory(turnBackOn: false)  // as saved to a file
                for (what, img) in [("on", on), ("off", off)] {
                    let r = CalculatorMachine.checkMemory(img, firmware: fw, variant: v)
                    XCTAssertTrue(r.fits, "\(v) \(what) image: \(r)")
                }
            }
        }
        if ran == 0 { throw XCTSkip("no firmware") }
    }

    // MARK: 0.6.4, HP-15C flag 8 (docs/BUG-0.6.3-FLAG8-WRITE.md)

    /// Jose's 0.6.3 bug: an image with flag 8 set, written into an empty calculator, came back
    /// with flag 8 clear: the flag is a CPU status bit (0x4C bit 3), and the whole CPU state was kept.
    func testWriteCarriesFlag8() throws {
        let empty = try Self.fixture("E3E3-152-empty-usb-read.15c")
        let cx = try Data(contentsOf: Fixtures.fixturesDir.appendingPathComponent("pool15/v152_81_prog_dimA_cx_dim25.bin"))
        XCTAssertTrue(CalculatorLink.flag8(cx)); XCTAssertFalse(CalculatorLink.flag8(empty))
        let f = FakeCalculator(memory: [UInt8](empty)); f.stopsOnCPUStateChange = true
        let back = [UInt8](try link(f).writeMemory(cx, flag8: true))
        XCTAssertTrue(f.connected)
        XCTAssertEqual(back[0x70..<0x7F0], [UInt8](cx)[0x70..<0x7F0])
        XCTAssertEqual(back[0x4C] & 0x08, 0x08, "flag 8 status bit set")
        var exp = [UInt8](empty); exp[0x4C] |= 0x08
        XCTAssertEqual(back[0..<0x70], exp[0..<0x70], "nothing else of the CPU state changed")
        let blocks = f.sent.filter { $0[1] == UInt8(ascii: "C") }.map { Int($0[2]) }
        XCTAssertTrue(blocks.contains(2)); XCTAssertFalse(blocks.contains(0)); XCTAssertFalse(blocks.contains(1))
        // without the flag (as 0.6.3 did) the bit stays clear: the bug
        let g = FakeCalculator(memory: [UInt8](empty))
        XCTAssertFalse(CalculatorLink.flag8(try link(g).writeMemory(cx)))
        // and a flag-8-off image clears a calculator that had it on
        let h = FakeCalculator(memory: [UInt8](cx)); h.stopsOnCPUStateChange = true
        let off = [UInt8](try link(h).writeMemory(empty, flag8: false))
        XCTAssertEqual(off[0x4C] & 0x08, 0); XCTAssertEqual(off[0xC4] & 1, 0)
    }

    /// The round trip through the firmware: written with flag 8, loaded into the E3E3 15.2 core
    /// (which runs the CE firmware), flag 8 survives a key and power-cycle and the 5 registers
    /// are the imaginary stack, not a SOLVE workspace. Without the fix they came back as "SOLVE".
    func testFlag8RoundTripThroughTheFirmware() throws {
        guard let fw = Fixtures.find(Self.e3e3) else { throw XCTSkip("no E3E3 firmware") }
        let empty = try Self.fixture("E3E3-152-empty-usb-read.15c")
        let m = CalculatorMachine(); try m.loadFirmware(fw); try m.boot(restoring: nil); try m.switchModel(to: 152)
        try m.tap(32); try m.tap(16); try m.tap(7)                 // g SF 8
        let image = try m.memory()
        XCTAssertTrue(CalculatorLink.flag8(image), "the emulator sets the status bit")
        for (fix, wantComplex) in [(true, true), (false, false)] {
            let f = FakeCalculator(memory: [UInt8](empty))
            let back = try link(f).writeMemory(image, flag8: fix ? true : nil)
            let c = CalculatorMachine(); try c.loadFirmware(fw); try c.boot(restoring: nil); try c.switchModel(to: 152)
            try c.putMemory(back)                                   // power-cycles: the firmware rewrites S0A
            let s = try XCTUnwrap(c.calc.inspect()); let p = try XCTUnwrap(s.pool)
            XCTAssertEqual(s.isComplex, wantComplex, "fix \(fix)")
            XCTAssertEqual(p.scratch, 0, "fix \(fix): never a SOLVE workspace")
            XCTAssertFalse(p.segments.contains { $0.kind == .workspace }, "fix \(fix)")
            XCTAssertEqual(p.segments.first?.kind, wantComplex ? .complex : .free, "fix \(fix)")
            XCTAssertEqual(p.segments.first?.count, 5)
        }
    }
}
