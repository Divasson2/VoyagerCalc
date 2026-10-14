// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// Pool15.swift - the HP-15C memory pool (0.6.0): complex stack, matrices A-E, SOLVE/∫
// workspace, storage, free registers and program, as vc_inspect_pool15 decodes them
// (docs/HP15C-POOL-COMPLEX-MATRICES.md; reference decoder docs/pool15c/pool15.py).

import Foundation
import VoyagerCore

public struct Pool15: Equatable, Sendable {
    public var variant = 150
    public var base = 0xA0, top = 0x100
    public var data = 0xB2                 // R2
    public var starts = [Int](repeating: 0, count: 5)
    public var pool = 0xB2                 // first uncommitted register
    public var rows = [Int](repeating: 0, count: 5), cols = [Int](repeating: 0, count: 5)
    public var result = 0                  // 0..4 = A..E
    public var complex = false
    public var scratch = 0                 // SOLVE / ∫ workspace (freed at the next key)
    public var gap = 0                     // free registers below R2 (fresh 15.2 cold start)
    public var storage = 0                 // R2..R(DIM (i))
    public var dimI = 1
    public var matrixRegisters = 0
    public var programLow = 0x100, programRegisters = 0, programBytes = 0
    public var free = 0
    public var gmem = ""                   // "19 78 00-0"
    public init() {}

    public static let letters = ["A", "B", "C", "D", "E"]
    public var size: Int { top - base }
    public var resultLetter: String { Self.letters[max(0, min(4, result))] }
    public func dimension(_ m: Int) -> String { "\(rows[m])×\(cols[m])" }

    public enum Kind: Equatable, Sendable, Hashable {
        case workspace, free, complex, storage, matrix(Int), program
        public var title: String {
            switch self {
            case .workspace: "SOLVE/∫ workspace"
            case .free: "free"
            case .complex: "complex (imaginary stack)"
            case .storage: "R2…"
            case .matrix(let m): "matrix \(Pool15.letters[m])"
            case .program: "program"
            }
        }
    }
    public struct Segment: Equatable, Sendable, Identifiable {
        public var kind: Kind
        public var first: Int                // Nut address of the first register
        public var count: Int
        public var id: Int { first * 16 + (count & 15) }
        public var label: String {
            switch kind {
            case .storage: count == 0 ? "" : "R2–R\(count + 1)"
            default: kind.title
            }
        }
    }
    /// The pool from the bottom (low address) to the top, in the order the firmware keeps it.
    public var segments: [Segment] {
        var s: [Segment] = []
        var at = base
        func add(_ k: Kind, _ n: Int) { if n > 0 { s.append(Segment(kind: k, first: at, count: n)) }; at += max(0, n) }
        add(.workspace, scratch)
        add(.free, gap)
        add(.complex, complex ? 5 : 0)
        at = data
        add(.storage, storage)
        for m in 0..<5 { at = starts[m]; add(.matrix(m), rows[m] * cols[m]) }
        at = pool
        add(.free, programLow - pool)
        at = programLow
        add(.program, programRegisters)
        return s
    }
    /// "19 78 00-0 · pool 96 registers + R0, R1"
    public var caption: String { "g MEM \(gmem)  ·  pool \(size) registers + R0, R1" }
}

/// One matrix with its values (row-major).
public struct MatrixValue: Equatable, Sendable, Identifiable {
    public var index: Int
    public var rows: Int, cols: Int
    public var first: Int                    // Nut address of element (1,1)
    public var isResult: Bool
    public var values: [RegisterValue]
    public var id: Int { index }
    public var letter: String { Pool15.letters[index] }
    public var isEmpty: Bool { rows * cols == 0 }
    public func value(_ r: Int, _ c: Int) -> RegisterValue? {
        let i = (r - 1) * cols + (c - 1)
        return i >= 0 && i < values.count ? values[i] : nil
    }
    /// Tab-separated rows (Copy as TSV).
    public var tsv: String {
        (1...max(1, rows)).map { r in (1...max(1, cols)).map { c in value(r, c)?.text ?? "" }.joined(separator: "\t") }.joined(separator: "\n")
    }
}

extension RegisterValue {
    /// A matrix descriptor (RCL MATRIX A or a matrix result): nibble 13 = 1, nibble 12 = A..E.
    public var matrixDescriptor: Int? {
        guard !isInteger, raw >> 52 & 0xF == 1, raw & 0x0000_FFFF_FFFF_FFFF == 0 else { return nil }
        let l = Int(raw >> 48 & 0xF)
        return (0xA...0xE).contains(l) ? l - 0xA : nil
    }
}

extension InspectorSnapshot {
    public var isComplex: Bool { model == 15 && flags >> 8 & 1 == 1 }
    /// The imaginary part of a stack register (X, Y, Z, T, LAST X) in complex mode.
    public func imaginary(of name: String) -> RegisterValue? {
        guard isComplex else { return nil }
        let order = ["X", "Y", "Z", "T", "LAST X"]
        guard let i = order.firstIndex(of: name), i < imaginary.count else { return nil }
        return imaginary[i]
    }
    /// "matrix A (2×3)" for a descriptor, nil otherwise.
    public func descriptorText(_ v: RegisterValue) -> String? {
        guard model == 15, let m = v.matrixDescriptor else { return nil }
        if let p = pool { return "matrix \(Pool15.letters[m]) (\(p.dimension(m)))" }
        return "matrix \(Pool15.letters[m])"
    }
}

extension VoyagerCalculator {
    func inspectPool15(into s: inout InspectorSnapshot) {
        let h = rawHandle
        var p = vc_pool15()
        guard vc_inspect_pool15(h, &p) == Int32(VC_OK) else { return }
        var o = Pool15()
        o.variant = Int(p.variant); o.base = Int(p.base); o.top = Int(p.top); o.data = Int(p.data)
        o.starts = withUnsafeBytes(of: p.start) { Array($0.bindMemory(to: Int32.self)).map(Int.init) }
        o.rows = withUnsafeBytes(of: p.rows) { Array($0.bindMemory(to: Int32.self)).map(Int.init) }
        o.cols = withUnsafeBytes(of: p.cols) { Array($0.bindMemory(to: Int32.self)).map(Int.init) }
        o.pool = Int(p.pool); o.result = Int(p.result); o.complex = p.complex != 0
        o.scratch = Int(p.scratch); o.gap = Int(p.gap); o.storage = Int(p.storage); o.dimI = Int(p.dim_i)
        o.matrixRegisters = Int(p.matrices); o.programLow = Int(p.prog_low)
        o.programRegisters = Int(p.prog_regs); o.programBytes = Int(p.prog_bytes); o.free = Int(p.free)
        o.gmem = withUnsafeBytes(of: p.gmem) { raw in
            let b = raw.bindMemory(to: UInt8.self); return String(decoding: b.prefix { $0 != 0 }, as: UTF8.self)
        }
        s.pool = o
        var v = vc_value()
        if o.complex {
            s.imaginary = [VC_REG_X, VC_REG_Y, VC_REG_Z, VC_REG_T, VC_REG_LASTX].compactMap { r in
                vc_inspect_imag(h, Int32(r), &v) == Int32(VC_OK) ? RegisterValue(v) : nil
            }
        }
        s.matrices = (0..<5).map { m in
            var vals: [RegisterValue] = []
            if o.rows[m] * o.cols[m] <= 256 {
                for r in 0..<o.rows[m] { for c in 0..<o.cols[m] where vc_inspect_matrix(h, Int32(m), Int32(r + 1), Int32(c + 1), &v) == Int32(VC_OK) {
                    vals.append(RegisterValue(v))
                } }
            }
            return MatrixValue(index: m, rows: o.rows[m], cols: o.cols[m], first: o.starts[m], isResult: o.result == m, values: vals)
        }
    }
}
