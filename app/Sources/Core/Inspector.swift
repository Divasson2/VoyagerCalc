// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// Inspector.swift - read-only view of the calculator's registers, modes and program
// (vc_inspect* in the C core). Reading never changes the calculator or its timing.

import Foundation
import VoyagerCore

/// One register as the calculator holds it.
public struct RegisterValue: Equatable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String        // "X", "LAST X", "I", "R0", "R.1", "R615", "PMT"
    public var text: String        // as the calculator shows it: integer in the current base, or the float
    public var decimal: String     // decimal value (16C integers per the complement mode)
    public var isInteger: Bool     // 16C integer mode
    public var isNegative: Bool
    public var number: Double
    public var word: UInt64        // 16C integer: the word (word-size bits)
    public var raw: UInt64         // the 56-bit Nut register as stored
    public init(name: String, text: String, decimal: String, isInteger: Bool, isNegative: Bool, number: Double, word: UInt64, raw: UInt64) {
        self.name = name; self.text = text; self.decimal = decimal; self.isInteger = isInteger
        self.isNegative = isNegative; self.number = number; self.word = word; self.raw = raw
    }
    /// What changes when the stored value changes (not when only the display base changes).
    public var stored: UInt64 { isInteger ? word : raw }
}

/// One program line, e.g. 001- 43,22, A  g LBL A.
public struct ProgramLine: Equatable, Sendable, Identifiable {
    public var id: Int { line }
    public var line: Int
    public var keys: String        // keycodes as the calculator shows them
    public var mnemonic: String    // readable function, without the shift key
    public var prefix: String      // "f", "g" or ""
    public var bytes: [UInt8]
    public var lineLabel: String { String(format: "%03d", line) }
    /// Mnemonic with its shift key, e.g. "g LBL A".
    public var fullMnemonic: String { prefix.isEmpty ? mnemonic : prefix + " " + mnemonic }
}

public struct InspectorSnapshot: Equatable, Sendable {
    public var model = 0              // 12, 15, 16
    public var variant = 0
    public var base = 10              // 16C: 16, 10, 8, 2, or 0 = FLOAT
    public var wordSize = 0           // 16C
    public var complement = 0         // 16C: 0 UNSGN, 1 1's, 2 2's
    public var flags: UInt32 = 0
    public var programMode = false
    public var running = false
    public var line = 0               // current program line (0 = 000)
    public var lines = 0
    public var registerCount = 0
    public var hasI = false
    public var hasProgram = false
    public var extendedMemory = false
    public var stack: [RegisterValue] = []
    public var registers: [RegisterValue] = []
    public var program: [ProgramLine] = []
    /// HP-15C (0.6.0): the memory pool, the imaginary stack (X, Y, Z, T, LAST X; complex mode)
    /// and matrices A..E.
    public var pool: Pool15?
    public var imaginary: [RegisterValue] = []
    public var matrices: [MatrixValue] = []
    public init() {}

    public var baseName: String {
        switch base { case 16: return "HEX"; case 8: return "OCT"; case 2: return "BIN"; case 0: return "FLOAT"; default: return "DEC" }
    }
    public var complementName: String { ["UNSGN", "1's", "2's"][max(0, min(2, complement))] }
    /// Numbers of the set flags (16C 0..5: 4 = carry C, 5 = out of range G; 15C 0..9).
    public var setFlags: [Int] { (0..<10).filter { flags >> UInt32($0) & 1 == 1 } }
    /// "HEX  WSIZE 16  2's" on the 16C, "" on the others.
    public var modeSummary: String {
        guard model == 16 else { return "" }
        return base == 0 ? "FLOAT" : "\(baseName)  WSIZE \(wordSize)  \(complementName)"
    }
}

private func cString<T>(_ tuple: T) -> String {
    withUnsafeBytes(of: tuple) { raw in
        let b = raw.bindMemory(to: UInt8.self)
        let n = b.firstIndex(of: 0) ?? b.count
        return String(decoding: b[0..<n], as: UTF8.self)
    }
}

extension RegisterValue {
    init(_ v: vc_value) {
        self.init(name: cString(v.name), text: cString(v.text), decimal: cString(v.dec), isInteger: v.kind == Int32(VC_VAL_INT),
                  isNegative: v.negative != 0, number: v.number, word: v.word, raw: v.raw)
    }
}

extension VoyagerCalculator {
    /// Registers, modes and (optionally) the program, or nil when there is nothing to inspect
    /// (no firmware, or the firmware is switching models). At most `maxRegisters` storage registers.
    public func inspect(includeProgram: Bool = true, maxRegisters: Int = 4096) -> InspectorSnapshot? {
        let h = rawHandle
        var info = vc_inspect_info()
        guard vc_inspect(h, &info) == Int32(VC_OK), info.model != 0 else { return nil }
        var s = InspectorSnapshot()
        s.model = Int(info.model); s.variant = Int(info.variant); s.base = Int(info.base)
        s.wordSize = Int(info.word_size); s.complement = Int(info.complement); s.flags = info.flags
        s.programMode = info.prgm_mode != 0; s.running = info.running != 0
        s.line = Int(info.line); s.lines = Int(info.lines); s.registerCount = Int(info.registers)
        s.hasI = info.has_i != 0; s.hasProgram = info.has_program != 0; s.extendedMemory = info.ext_memory != 0
        var v = vc_value()
        let stackRegs: [Int32] = s.model == 12
            ? [Int32(VC_REG_X), Int32(VC_REG_Y), Int32(VC_REG_Z), Int32(VC_REG_T), Int32(VC_REG_LASTX),
               Int32(VC_REG_FIN_N), Int32(VC_REG_FIN_I), Int32(VC_REG_FIN_PV), Int32(VC_REG_FIN_PMT), Int32(VC_REG_FIN_FV)]
            : [Int32(VC_REG_X), Int32(VC_REG_Y), Int32(VC_REG_Z), Int32(VC_REG_T), Int32(VC_REG_LASTX)] + (s.hasI ? [Int32(VC_REG_I)] : [])
        for r in stackRegs where vc_inspect_stack(h, r, &v) == Int32(VC_OK) { s.stack.append(RegisterValue(v)) }
        let n = min(s.registerCount, maxRegisters)
        s.registers.reserveCapacity(n)
        for i in 0..<n where vc_inspect_register(h, Int32(i), &v) == Int32(VC_OK) { s.registers.append(RegisterValue(v)) }
        if s.model == 15 { inspectPool15(into: &s) }
        if includeProgram && s.hasProgram && s.lines > 0 {
            var buf = [vc_prog_line](repeating: vc_prog_line(), count: s.lines)
            let got = Int(vc_inspect_program(h, 1, &buf, Int32(s.lines)))
            if got > 0 {
                s.program = buf[0..<got].map { p in
                    let pre = p.prefix == 0 ? "" : String(UnicodeScalar(UInt8(bitPattern: p.prefix)))
                    let bytes = withUnsafeBytes(of: p.code) { Array($0.prefix(Int(p.len))) }
                    return ProgramLine(line: Int(p.line), keys: cString(p.keys), mnemonic: cString(p.mnemonic), prefix: pre, bytes: bytes)
                }
            }
        }
        return s
    }
}
