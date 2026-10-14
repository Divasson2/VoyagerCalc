// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// The inspector's program pointer must be exactly the line the calculator shows in PRGM mode
// ("042- 42 b" -> line 42), and the listing row there must hold what the display shows.
// Checked after SST, BST, GTO .nnn, wrap-around at both ends, a fresh PRGM entry, in run mode
// (the line that will execute next = what PRGM would show), and after R/S stops a program.
// All models with a listing: 16C Path-C (B7B7), 16C stock, 12C multi's 16C and 15.2 modes,
// 15C 3-ROM 15.0 and 15.2.

import Foundation
import XCTest
#if canImport(VoyagerKit)
@testable import VoyagerKit
#endif

final class ProgramPointerTests: XCTestCase {
    struct Config { let name: String; let firmware: [String]; let variant: Int? }
    static let configs: [Config] = [
        Config(name: "16C Path-C B7B7", firmware: ["Voyager16-ext-path-c-trim4-show-B7B7.bin"], variant: nil),
        Config(name: "16C stock", firmware: ["_baseline_hp16c-firmware.bin", "hp16c-firmware.bin"], variant: nil),
        Config(name: "12C multi E3E3, 16C", firmware: ["HP12c-multi-152-ext16-E3E3.bin"], variant: 160),
        Config(name: "12C multi E3E3, 15.2", firmware: ["HP12c-multi-152-ext16-E3E3.bin"], variant: 152),
        Config(name: "15C C8C8, 15.0", firmware: ["hp15c-3rom-mute120-fsm5-rel80-opt5cycle-debounce-menu-stopwatch-48fix-keys-batt-trim4-show-C8C8.bin"], variant: 150),
        Config(name: "15C C8C8, 15.2", firmware: ["hp15c-3rom-mute120-fsm5-rel80-opt5cycle-debounce-menu-stopwatch-48fix-keys-batt-trim4-show-C8C8.bin"], variant: 152),
    ]

    // varied programs, with the 15C two-byte instructions (STO .1, GTO .1, FIX 4, LBL .1 ...)
    static let program16 = "g GTO A 1 2 + f A f B f C 3 STO 1 RCL . 2 STO + . . g GSB HEX DEC OCT BIN f 4 f 5 f 6 g 4 1 g 5 2 g 6 3 f STO f RCL g GTO B f E f F 4 5 ENTER g SST GSB B GTO A g GSB"
    static let program15 = "f SST SQRT f SST . 1 STO . 1 RCL . 5 STO + 3 STO × . 2 RCL - 4 GTO . 1 GSB SQRT f 7 4 f 8 2 f 9 3 g 7 g 8 g 9 STO SQRT RCL e^x STO TAN RCL COS f COS 1 f 6 1 f 5 2 g 4 3 g 5 4 g 6 5 f TAN f SIN 3 f SIN . 4 1 2 3 EEX 4 CHS + g GSB"

    private func type(_ m: CalculatorMachine, _ s: String) throws {
        for w in s.split(separator: " ").map(String.init) {
            if let k = VoyagerCalculator.keyCode(model: m.model, name: w) { try m.tap(k); continue }
            for ch in w { try m.tap(XCTUnwrap(VoyagerCalculator.keyCode(model: m.model, name: String(ch)), "\(ch)")) }
        }
    }

    /// Line number and keycodes the display shows in PRGM mode, e.g. "042-  42 b" -> (42, "42 b").
    static func shown(_ text: String) -> (line: Int, keys: String)? {
        let t = text.drop { $0 == " " }
        guard t.count >= 4, let n = Int(t.prefix(3)), t.dropFirst(3).first == "-" else { return nil }
        return (n, String(t.dropFirst(4)))
    }
    /// Blank (16C) or "running" (15C; letters the text decoder shows as ?) while a program runs.
    static func isBlankOrRunning(_ t: String) -> Bool { t.allSatisfy { $0 == " " } || t.contains("?") }
    static func norm(_ s: String) -> String { s.filter { !" ,.".contains($0) } }

    private func gto(_ m: CalculatorMachine, _ line: Int) throws {
        try type(m, (m.model == 16 ? "GTO . " : "GTO CHS ") + String(format: "%03d", line).map(String.init).joined(separator: " "))
    }

    private func clearError(_ m: CalculatorMachine) throws {
        if m.displayText.contains("Error") { try m.tap(CalculatorMachine.keyBSP) }
    }

    private func machine(_ cfg: Config) throws -> CalculatorMachine? {
        guard let fw = Fixtures.find(cfg.firmware) else { return nil }
        let m = CalculatorMachine()
        try m.loadFirmware(fw)
        try m.boot(restoring: nil)
        if let v = cfg.variant, m.variant != v { try m.switchModel(to: v) }
        return m
    }

    /// In PRGM mode: highlighted line == displayed line, and the listing row matches the display.
    private func assertPointer(_ m: CalculatorMachine, _ what: String, _ cfg: Config, file: StaticString = #filePath, line: UInt = #line) {
        guard let s = m.calc.inspect() else { return XCTFail("\(cfg.name): no inspection", file: file, line: line) }
        guard let d = Self.shown(m.displayText) else { return XCTFail("\(cfg.name) \(what): display \(m.displayText) is not a program line", file: file, line: line) }
        XCTAssertTrue(s.programMode, "\(cfg.name) \(what): PRGM", file: file, line: line)
        XCTAssertEqual(s.line, d.line, "\(cfg.name) \(what): highlighted line vs display \"\(m.displayText)\"", file: file, line: line)
        if d.line > 0 {
            let row = s.program.first { $0.line == d.line }
            XCTAssertEqual(row.map { Self.norm($0.keys) }, Self.norm(d.keys), "\(cfg.name) \(what): listing row \(d.line) vs display \"\(m.displayText)\"", file: file, line: line)
        }
    }

    /// $VC_POINTER_SEED changes the random sequences (default: the same every run).
    private var seedSalt: UInt64 { UInt64(ProcessInfo.processInfo.environment["VC_POINTER_SEED"] ?? "") ?? 0x5EED }

    func testPointerIsTheDisplayedLine() throws {
        var ran = 0
        for cfg in Self.configs {
            guard let m = try machine(cfg) else { continue }
            ran += 1
            let p16 = m.model == 16
            if !p16 { try type(m, "1 9 f SIN COS") }        // 19 DIM (i): R0..R.9 exist (15.2 starts with 2)
            try type(m, "g R/S " + (p16 ? Self.program16 : Self.program15))
            assertPointer(m, "after keying the program", cfg)
            let lines = try XCTUnwrap(m.calc.inspect()).lines
            XCTAssertGreaterThan(lines, 30, cfg.name)
            // every line: SST from the top, content too
            try gto(m, 0); assertPointer(m, "GTO .000", cfg)
            for i in 1...lines { try type(m, "SST"); assertPointer(m, "SST to \(i)", cfg) }
            // wrap-around at both ends
            try type(m, "SST"); assertPointer(m, "SST past the end (wraps to 000)", cfg)
            XCTAssertEqual(m.calc.inspect()?.line, 0, cfg.name)
            try type(m, "g SST"); assertPointer(m, "BST at 000 (wraps to the end)", cfg)
            XCTAssertEqual(m.calc.inspect()?.line, lines, cfg.name)
            // random SST / BST / GTO .nnn
            var rng = SplitMix(seed: UInt64(cfg.name.utf8.reduce(0) { $0 &* 31 &+ Int($1) } & 0xFFFFFF) ^ seedSalt)
            for i in 0..<60 {
                switch rng.next() % 10 {
                case 0..<4: try type(m, "SST"); assertPointer(m, "#\(i) SST", cfg)
                case 4..<7: try type(m, "g SST"); assertPointer(m, "#\(i) BST", cfg)
                default:
                    let k = Int(rng.next() % UInt64(lines + 1))
                    try gto(m, k); assertPointer(m, "#\(i) GTO .\(k)", cfg)
                    XCTAssertEqual(m.calc.inspect()?.line, k, "\(cfg.name) GTO .\(k)")
                }
            }
            // fresh PRGM entry, and run mode: the highlight is the line that executes next
            try type(m, "g R/S")
            for i in 0..<12 {
                try gto(m, Int(rng.next() % UInt64(lines + 1)))
                for _ in 0..<Int(rng.next() % 3) {
                    try type(m, rng.next() % 2 == 0 ? "SST" : "g SST")
                    try clearError(m)                          // a line SST executes may give Error n
                }
                try m.run(ms: 500)
                let before = try XCTUnwrap(m.calc.inspect())
                XCTAssertFalse(before.programMode, cfg.name)
                try type(m, "g R/S")
                assertPointer(m, "run mode #\(i), then PRGM", cfg)
                XCTAssertEqual(before.line, Self.shown(m.displayText)?.line, "\(cfg.name) run mode #\(i): next line")
                try type(m, "g R/S")
            }
            // R/S stops a running loop: the highlight is where it will go on
            try type(m, "g R/S"); try gto(m, lines)
            try type(m, p16 ? "g GTO 9 1 + GTO 9" : "f SST 9 1 + GTO 9")
            try type(m, "g R/S GSB 9"); try m.run(ms: 1500)
            XCTAssertEqual(m.calc.inspect()?.running, true, "\(cfg.name): loop running")
            // R/S: a running program sees the key only at its next key check; tap it again
            // until the display shows X instead of "running" (never once it has stopped)
            let rs = VoyagerCalculator.keyCode(model: m.model, name: "R/S")!
            var taps = 0
            while Self.isBlankOrRunning(m.displayText) && taps < 12 {
                m.press(rs); try m.run(ms: 150); m.release(rs); try m.run(ms: 700); taps += 1
            }
            try m.run(ms: 1500)
            print("\(cfg.name): stopped after \(taps) R/S, display \(m.displayText)")
            let stopped = try XCTUnwrap(m.calc.inspect())
            XCTAssertFalse(stopped.running, "\(cfg.name): stopped")
            XCTAssertTrue((lines + 1...lines + 4).contains(stopped.line), "\(cfg.name): stopped inside the loop, at \(stopped.line)")
            try type(m, "g R/S")
            assertPointer(m, "after R/S stop", cfg)
            XCTAssertEqual(stopped.line, Self.shown(m.displayText)?.line, "\(cfg.name): after R/S stop")
        }
        if ran == 0 { throw XCTSkip("no firmware") }
    }
}

/// Small deterministic random numbers (the same sequence everywhere).
struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
