// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// ProgramAnalysis.swift - what a program uses, read from its listing (the inspector's decoder,
// so names match the app): labels defined and where they are called (GTO, GSB, SOLVE, ∫),
// registers (STO, RCL, register arithmetic, x≷, DSE / ISG, I and (i), 15C matrices, 12C
// financial registers) and flags (SF, CF, F?), each with the steps that use it.
// HP-12C: no labels; the GTO targets (line numbers) are listed instead.

import Foundation

public struct ProgramAnalysis: Equatable, Sendable {
    public struct Label: Equatable, Sendable, Identifiable {
        public var id: String { name }
        public var name: String          // "A", "7", ".5", "I (indirect)"; 12C: "05" (a line number)
        public var defined: [Int] = []   // steps with LBL name (12C: the line itself)
        public var called: [Int] = []    // steps that GTO / GSB / SOLVE / ∫ it
        public var callKinds: [String] = []
        public var isIndirect = false
    }
    public enum RegisterKind: Int, Sendable, Comparable {
        case storage, index, indirect, financial, random, matrix, result
        public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }
    public struct Register: Equatable, Sendable, Identifiable {
        public var id: String { name }
        public var name: String          // "R4", "R.6", "RA" (16C), "I", "(i)", "PMT", "Matrix A", "RAN#"
        public var kind: RegisterKind
        public var steps: [Int] = []
        public var operations: [String] = []   // "STO", "RCL +", "x≷", "DSE" ... in order of first use
    }
    public struct Flag: Equatable, Sendable, Identifiable {
        public var id: String { name }
        public var name: String          // "0" ... "9", "I (indirect)"
        public var steps: [Int] = []
        public var operations: [String] = []
        public var meaning = ""          // 15C flag 8: "complex mode", 9: "overflow"
    }
    /// 15C matrix and complex operations (0.6.0): one row per matrix, RESULT, MATRIX n,
    /// DIM (i), complex mode and the SOLVE / ∫ workspace.
    public struct MatrixOp: Equatable, Sendable, Identifiable {
        public var id: String { item }
        public var item: String          // "Matrix A", "RESULT", "MATRIX n", "DIM (i)", "Complex", "SOLVE/∫ workspace"
        public var steps: [Int] = []
        public var operations: [String] = []
        public var notes: [String] = []
    }

    public var model: Int
    public var labels: [Label] = []
    public var registers: [Register] = []
    public var flags: [Flag] = []
    public var matrixOps: [MatrixOp] = []

    public init(lines: [ProgramLine], model: Int) {
        self.model = model
        var labs: [String: Label] = [:], regs: [String: Register] = [:], fl: [String: Flag] = [:]
        func label(_ n: String, indirect: Bool = false) -> String {
            if labs[n] == nil { labs[n] = Label(name: n, isIndirect: indirect) }
            return n
        }
        func use(_ name: String, _ kind: RegisterKind, _ op: String, _ step: Int) {
            var r = regs[name] ?? Register(name: name, kind: kind)
            if r.steps.last != step { r.steps.append(step) }
            if !r.operations.contains(op) { r.operations.append(op) }
            regs[name] = r
        }
        func flag(_ name: String, _ op: String, _ step: Int) {
            var f = fl[name] ?? Flag(name: name)
            if f.steps.last != step { f.steps.append(step) }
            if !f.operations.contains(op) { f.operations.append(op) }
            fl[name] = f
        }
        let arith: Set<String> = ["+", "−", "×", "÷"]
        for l in lines {
            let t = l.mnemonic.split(separator: " ").map(String.init)
            guard let op = t.first else { continue }
            let step = l.line
            // labels and calls
            if op == "LBL", t.count == 2, Self.isLabel(t[1], model: model) {
                labs[label(t[1]), default: Label(name: t[1])].defined.append(step)
                continue
            }
            if ["GTO", "GSB", "SOLVE", "∫ʸₓ"].contains(op), t.count == 2 {
                let a = t[1]
                if model == 12, op == "GTO", a.count == 2, let n = Int(a) {
                    let k = label(a); labs[k]!.called.append(step)
                    if !labs[k]!.callKinds.contains("GTO") { labs[k]!.callKinds.append("GTO") }
                    if n >= 1, n <= lines.count, labs[k]!.defined.isEmpty { labs[k]!.defined = [n] }
                    continue
                }
                if a == "I" || a == "(i)" {
                    let k = label("I (indirect)", indirect: true); labs[k]!.called.append(step)
                    if !labs[k]!.callKinds.contains(op) { labs[k]!.callKinds.append(op) }
                    use("I", .index, op, step)
                    continue
                }
                if Self.isLabel(a, model: model) {
                    let k = label(a); labs[k]!.called.append(step)
                    if !labs[k]!.callKinds.contains(op) { labs[k]!.callKinds.append(op) }
                }
                continue
            }
            // flags
            if ["SF", "CF", "F?"].contains(op), t.count == 2, model != 12 {
                if t[1] == "I" || t[1] == "(i)" { flag("I (indirect)", op, step); use("I", .index, op, step) }
                else if t[1].count == 1, t[1].first!.isNumber { flag(t[1], op, step) }
                continue
            }
            // 16C: DSZ / ISZ count in I; x≷I, x≷(i)
            if model == 16 {
                if op == "DSZ" || op == "ISZ" { use("I", .index, op, step); continue }
                if op == "x≷I" { use("I", .index, "x≷", step); continue }
                if op == "x≷(i)" { use("(i)", .indirect, "x≷", step); use("I", .index, "(i)", step); continue }
            }
            // 15C matrices
            if model == 15, ["DIM", "RESULT"].contains(op), t.count == 2, Self.isMatrix(t[1]) {
                use("Matrix \(t[1])", .matrix, op, step); continue
            }
            if model == 15, op == "DIM" || op == "MATRIX" { continue }          // DIM (i), MATRIX n: matrixOps
            if model == 15, ["STO", "RCL"].contains(op), t.count == 3, t[1] == "DIM", t[2] == "(i)" { continue }   // not register (i)
            // register operations
            guard ["STO", "RCL", "x≷", "DSE", "ISG"].contains(op), t.count >= 2 else { continue }
            var opName = op
            var rest = Array(t.dropFirst())
            if rest.count >= 2, arith.contains(rest[0]) { opName += " " + rest[0]; rest.removeFirst() }
            if rest.count >= 2, ["g", "MATRIX", "DIM"].contains(rest[0]) {
                if model == 12 { continue }                    // 12C RCL g CFj: cash flow registers
                opName += " " + rest[0]; rest.removeFirst()
            }
            guard rest.count == 1, let a = rest.first else { continue }
            if a == "I" { use("I", .index, opName, step) }
            else if a == "(i)" { use("(i)", .indirect, opName, step); use("I", .index, "(i)", step) }
            else if a == "RAN#" { use("RAN#", .random, opName, step) }
            else if a == "RESULT" { use("RESULT", .result, opName, step) }
            else if model == 12, ["n", "i", "PV", "PMT", "FV"].contains(a) { use(a, .financial, opName, step) }
            else if model == 15, Self.isMatrix(a) { use("Matrix \(a)", .matrix, opName, step) }
            else if Self.isRegister(a, model: model) { use("R" + a, .storage, opName, step) }
        }
        if model == 15 {
            for f in fl.keys {
                if f == "8" { fl[f]!.meaning = "complex mode (5 registers for the imaginary stack)" }
                if f == "9" { fl[f]!.meaning = "overflow (blinking display)" }
            }
            matrixOps = Self.matrixOperations(lines)
        }
        labels = labs.values.sorted { Self.labelOrder($0, model: model) < Self.labelOrder($1, model: model) }
        registers = regs.values.sorted { ($0.kind, Self.regOrder($0.name)) < ($1.kind, Self.regOrder($1.name)) }
        flags = fl.values.sorted { ($0.name.count, $0.name) < ($1.name.count, $1.name) }
    }

    static let matrixFunctions = [
        "0": "MATRIX 0: all matrices to 0×0 (memory returned)",
        "1": "MATRIX 1: R0 = R1 = 1 (start of element-by-element access)",
        "2": "MATRIX 2: complex matrix, partitioned form to the inverse-ready form",
        "3": "MATRIX 3: inverse of MATRIX 2",
        "4": "MATRIX 4: transpose",
        "5": "MATRIX 5: transpose(Y) × X",
        "6": "MATRIX 6: residual",
        "7": "MATRIX 7: row norm",
        "8": "MATRIX 8: Frobenius norm",
        "9": "MATRIX 9: determinant",
    ]

    /// The matrix / complex operations table (15C): exact mnemonics of the decoder.
    static func matrixOperations(_ lines: [ProgramLine]) -> [MatrixOp] {
        var items: [String: MatrixOp] = [:]
        var order: [String] = []
        func add(_ item: String, _ op: String, _ step: Int, note: String? = nil) {
            if items[item] == nil { items[item] = MatrixOp(item: item); order.append(item) }
            if items[item]!.steps.last != step { items[item]!.steps.append(step) }
            if !items[item]!.operations.contains(op) { items[item]!.operations.append(op) }
            if let note, !items[item]!.notes.contains(note) { items[item]!.notes.append(note) }
        }
        let arith: Set<String> = ["+", "−", "×", "÷"]
        for l in lines {
            let t = l.mnemonic.split(separator: " ").map(String.init)
            guard let op = t.first else { continue }
            let step = l.line, sn = String(format: "%03d", step)
            switch op {
            case "DIM" where t.count == 2:
                if isMatrix(t[1]) { add("Matrix \(t[1])", "DIM", step, note: "dimensioned by the program at step \(sn) (size from the stack)") }
                else if t[1] == "(i)" { add("DIM (i)", "DIM (i)", step, note: "storage registers set by the program at step \(sn) (from X)") }
            case "MATRIX" where t.count == 2:
                add("MATRIX n", "MATRIX \(t[1])", step, note: matrixFunctions[t[1]])
            case "RESULT" where t.count == 2 && isMatrix(t[1]):
                add("RESULT", "RESULT \(t[1])", step, note: "results go to matrix \(t[1])")
                add("Matrix \(t[1])", "RESULT", step)
            case "I":
                add("Complex", "f I", step, note: "f I and Re≷Im turn on complex mode (flag 8)")
            case "Re≷Im":
                add("Complex", "Re≷Im", step, note: "f I and Re≷Im turn on complex mode (flag 8)")
            case "SF", "CF", "F?":
                if t.count == 2, t[1] == "8" { add("Complex", "\(op) 8", step, note: "flag 8 = complex mode (5 registers)") }
            case "SOLVE": add("SOLVE/∫ workspace", "SOLVE", step, note: "SOLVE borrows 5 registers while it runs")
            case "∫ʸₓ": add("SOLVE/∫ workspace", "∫ʸₓ", step, note: "∫ borrows 23 registers while it runs")
            case "STO", "RCL", "x≷":
                var rest = Array(t.dropFirst()), name = op
                if rest.count >= 2, arith.contains(rest[0]) { name += " " + rest[0]; rest.removeFirst() }
                if rest.count == 2, rest[0] == "DIM" {
                    if isMatrix(rest[1]) { add("Matrix \(rest[1])", "\(name) DIM", step) }
                    else if rest[1] == "(i)" { add("DIM (i)", "\(name) DIM (i)", step) }
                } else if rest.count == 2, rest[0] == "MATRIX", isMatrix(rest[1]) {
                    add("Matrix \(rest[1])", "\(name) MATRIX", step, note: name == "RCL" ? "descriptor recalled to X (for matrix arithmetic)" : nil)
                } else if rest.count == 2, rest[0] == "g", isMatrix(rest[1]) {
                    add("Matrix \(rest[1])", "\(name) g", step, note: "element at row Y, column X")
                } else if rest.count == 1, isMatrix(rest[0]) {
                    add("Matrix \(rest[0])", name, step, note: "element at R0, R1 (USER mode steps the indices)")
                } else if rest.count == 1, rest[0] == "RESULT" {
                    add("RESULT", "\(name) RESULT", step)
                }
            default: break
            }
        }
        let rank: (String) -> String = { $0.hasPrefix("Matrix") ? "1" + $0 : $0 == "RESULT" ? "2" : $0 == "MATRIX n" ? "3" : $0 == "DIM (i)" ? "0" : $0 == "Complex" ? "4" : "5" }
        return order.map { items[$0]! }.sorted { rank($0.item) < rank($1.item) }
    }

    static func isLabel(_ a: String, model: Int) -> Bool {
        let letters = model == 16 ? "ABCDEF" : model == 15 ? "ABCDE" : ""
        if a.count == 1, let c = a.first { return c.isNumber || letters.contains(c) }
        if a.count == 2, a.first == ".", let c = a.last { return c.isNumber }
        return false
    }
    static func isMatrix(_ a: String) -> Bool { a.count == 1 && "ABCDE".contains(a) }
    static func isRegister(_ a: String, model: Int) -> Bool {
        if a.count == 1, let c = a.first { return c.isNumber || (model == 16 && "ABCDEF".contains(c)) }
        if a.count == 2, a.first == ".", let c = a.last { return c.isNumber || (model == 16 && "ABCDEF".contains(c)) }
        return false
    }
    static func labelOrder(_ l: Label, model: Int) -> String {
        if l.isIndirect { return "9" }
        if model == 12 { return "0" + l.name }
        let n = l.name
        if n.hasPrefix(".") { return "2" + n }
        if let c = n.first, c.isNumber { return "1" + n }
        return "3" + n
    }
    static func regOrder(_ n: String) -> String {
        let fin = ["n": "1", "i": "2", "PV": "3", "PMT": "4", "FV": "5"]
        if let f = fin[n] { return f }
        if n.hasPrefix("R.") { return "2" + n }
        if n.hasPrefix("R"), let c = n.dropFirst().first, c.isNumber { return "1" + n }
        return "3" + n
    }

    /// Every label name the document should list (defined, called or both).
    public var labelNames: [String] { labels.map(\.name) }
    /// Steps where a label is defined but no LBL exists (called only), for a warning.
    public var undefinedLabels: [Label] { labels.filter { $0.defined.isEmpty && !$0.isIndirect } }
}
