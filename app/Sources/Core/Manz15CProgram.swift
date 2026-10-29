// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// Manz15CProgram.swift - read and write HP-15C program files in the plain-text format of Torsten Manz's
// HP-15C Simulator (".15c" / ".txt"), see docs/MANZ-15C-FORMAT.md. Pure code (no UI, no emulator), so it is
// unit-tested on any platform.
//
// Written from the HP-15C's own keycode rules (row/column of the key, digits as themselves), not from the
// simulator's source: only the documented file convention is shared.
//
// A file is a list of steps, one per line, whose keycodes sit between "{" and "}"; line numbers and mnemonics are
// documentation only. "#T:" title, "#D:" description lines, "#L<n>:", "#R<n>:", "#F<n>:" notes; other "#" lines
// are comments. The importer turns each step into the keys to press (HP15CKeyEntry) and the app types them
// in program mode, so the calculator's own firmware encodes the program.

import Foundation

// MARK: - keycodes

/// One keycode token of a 15C program step.
public enum HP15CToken: Equatable, Hashable, Sendable {
    /// A key: digit 0...9, or row/column 10...49 (the HP keycode).
    case key(Int)
    /// A decimal point followed by a digit (".3" = register / label .3), one token in the file.
    case dot(Int)
    /// Manz's trailing "u": STO / RCL of a matrix element or (i) keyed in USER mode.
    case user

    /// "42", " 0", ".3", " u" (two characters, right aligned, as in the file and the calculator's display).
    public var text: String {
        switch self {
        case .key(let k): return k < 10 ? " \(k)" : "\(k)"
        case .dot(let d): return ".\(d)"
        case .user: return " u"
        }
    }
}

/// One program step: its keycodes (step 000 is never stored; it is implied).
public struct HP15CStep: Equatable, Hashable, Sendable {
    public var tokens: [HP15CToken]
    public init(_ tokens: [HP15CToken]) { self.tokens = tokens }

    /// Keycodes without the USER marker, as the calculator lists them.
    public var plainTokens: [HP15CToken] { tokens.filter { $0 != .user } }
    public var isUser: Bool { tokens.contains(.user) }

    /// "42 21 11", "44 .3", "44 24  u" (each token two characters wide, one space between).
    public var keycodeText: String { tokens.map(\.text).joined(separator: " ") }
    /// Readable function with its shift key ("f LBL A", "STO + 1"), or nil if the keycodes are not an HP-15C step.
    public var mnemonic: String? { HP15CKeycodes.mnemonic(tokens) }
    public var isValid: Bool { mnemonic != nil }
}

public enum HP15CKeycodes {
    // HP keycode -> name of the key's own function / gold (f) / blue (g) function.
    static let plain: [Int: String] = [
        10: "÷", 11: "√x̅", 12: "eˣ", 13: "10ˣ", 14: "yˣ", 15: "1/x", 16: "CHS", 20: "×", 23: "SIN", 24: "COS", 25: "TAN",
        26: "EEX", 30: "−", 31: "R/S", 33: "R⬇", 34: "x↔y", 36: "ENTER", 40: "+", 48: ".", 49: "Σ+",
    ]
    static let gold: [Int: String] = [
        0: "x!", 1: "→R", 2: "→H.MS", 3: "→RAD", 24: "(i)", 25: "I", 30: "Re↔Im", 31: "PSE", 32: "CLEAR Σ", 34: "CLEAR REG",
        36: "RAN #", 40: "Py,x", 44: "FRAC", 48: "ŷ,r", 49: "L.R.",
    ]
    static let blue: [Int: String] = [
        0: "x̄", 1: "→P", 2: "→H", 3: "→DEG", 7: "DEG", 8: "RAD", 9: "GRD", 10: "x≤y", 11: "x²", 12: "LN", 13: "LOG", 14: "%",
        15: "Δ%", 16: "ABS", 20: "x=0", 23: "SIN⁻¹", 24: "COS⁻¹", 25: "TAN⁻¹", 26: "π", 32: "RTN", 33: "R⬆", 34: "RND", 35: "CLx",
        36: "LSTx", 40: "Cy,x", 44: "INT", 48: "s", 49: "Σ−",
    ]
    static let letters: [Int: String] = [11: "A", 12: "B", 13: "C", 14: "D", 15: "E"]
    static let tests = ["x≠0", "x>0", "x<0", "x≥0", "x≤0", "x=y", "x≠y", "x>y", "x<y", "x≥y"]
    static let arithmetic: [Int: String] = [10: "÷", 20: "×", 30: "−", 40: "+"]

    /// A digit key 0...9 as a name.
    static func digit(_ t: HP15CToken) -> String? {
        if case .key(let k) = t, k <= 9 { return "\(k)" }
        return nil
    }
    /// Label: 0...9, .0....9, A...E.
    static func label(_ t: HP15CToken) -> String? {
        if let d = digit(t) { return d }
        if case .dot(let d) = t { return ".\(d)" }
        if case .key(let k) = t { return letters[k] }
        return nil
    }
    /// Storage register (incl. I and (i)): 0...9, .0....9, I, (i).
    static func register(_ t: HP15CToken) -> String? {
        if let d = digit(t) { return d }
        if case .dot(let d) = t { return ".\(d)" }
        if t == .key(25) { return "I" }
        if t == .key(24) { return "(i)" }
        return nil
    }
    static func matrix(_ t: HP15CToken) -> String? {
        if case .key(let k) = t { return letters[k] }
        return nil
    }
    static func trig(_ t: HP15CToken) -> String? { t == .key(23) ? "SIN" : t == .key(24) ? "COS" : t == .key(25) ? "TAN" : nil }
    static func digitOrI(_ t: HP15CToken) -> String? { t == .key(25) ? "I" : digit(t) }

    /// The mnemonic of a complete step, or nil when the keycodes are not something the HP-15C can store.
    public static func mnemonic(_ t: [HP15CToken]) -> String? {
        guard let first = t.first, case .key(let a) = first else { return nil }
        let rest = Array(t.dropFirst())
        func one(_ f: (HP15CToken) -> String?) -> String? { rest.count == 1 ? f(rest[0]) : nil }
        switch a {
        case 0...9: return rest.isEmpty ? "\(a)" : nil
        case 42:                                                   // f
            guard let b = rest.first, case .key(let k) = b else { return nil }
            let arg = Array(rest.dropFirst())
            func op(_ name: String, _ f: (HP15CToken) -> String?) -> String? {
                guard arg.count == 1, let x = f(arg[0]) else { return nil }
                return "f \(name) \(x)"
            }
            switch k {
            case 4: return op("x↔", register)
            case 5: return op("DSE", register)
            case 6: return op("ISG", register)
            case 7: return op("FIX", digitOrI)
            case 8: return op("SCI", digitOrI)
            case 9: return op("ENG", digitOrI)
            case 10: return op("SOLVE", label)
            case 20: return op("∫xy", label)
            case 16: return op("MATRIX", digit)
            case 21: return op("LBL", label)
            case 22: return op("HYP", trig)
            case 23: return op("DIM", { matrix($0) ?? ($0 == .key(24) ? "(i)" : $0 == .key(25) ? "I" : nil) })
            case 26: return op("RESULT", matrix)
            default: return arg.isEmpty ? gold[k].map { "f " + $0 } : nil
            }
        case 43:                                                   // g
            guard let b = rest.first, case .key(let k) = b else { return nil }
            let arg = Array(rest.dropFirst())
            func op(_ name: String, _ f: (HP15CToken) -> String?) -> String? {
                guard arg.count == 1, let x = f(arg[0]) else { return nil }
                return "g \(name) \(x)"
            }
            switch k {
            case 4: return op("SF", digitOrI)
            case 5: return op("CF", digitOrI)
            case 6: return op("F?", digitOrI)
            case 22: return op("HYP⁻¹", trig)
            case 30: return op("TEST", { t in digit(t).map { tests[Int($0)!] } })
            default: return arg.isEmpty ? blue[k].map { "g " + $0 } : nil
            }
        case 22, 32:                                               // GTO, GSB
            let name = a == 22 ? "GTO" : "GSB"
            return one { t in (label(t) ?? (t == .key(25) ? "I" : nil)).map { "\(name) \($0)" } }
        case 44, 45:                                               // STO, RCL
            return storeRecall(a == 44 ? "STO" : "RCL", rest, recall: a == 45)
        default:
            return rest.isEmpty ? plain[a] : nil
        }
    }

    static func storeRecall(_ name: String, _ r: [HP15CToken], recall: Bool) -> String? {
        guard let b = r.first else { return nil }
        let arg = Array(r.dropFirst())
        // STO A u, STO (i) u: USER mode (matrix element with auto-increment)
        if arg == [.user], let x = matrix(b) ?? (b == .key(24) ? "(i)" : nil) { return "\(name) \(x)" }
        if arg.isEmpty {
            if let x = register(b) ?? matrix(b) { return "\(name) \(x)" }
            if b == .key(36) { return "\(name) RAN #" }
            if b == .key(26) { return "\(name) RESULT" }
            if recall, b == .key(49) { return "RCL Σ+" }
            return nil
        }
        guard arg.count == 1, case .key(let k) = b else { return nil }
        let x = arg[0]
        if let op = arithmetic[k], let reg = register(x) ?? matrix(x) { return "\(name) \(op) \(reg)" }
        if k == 16, let m = matrix(x) { return "\(name) MATRIX \(m)" }
        if k == 43, let m = matrix(x) ?? (x == .key(24) ? "(i)" : nil) { return "\(name) g \(m)" }
        if recall, k == 23, let m = matrix(x) ?? (x == .key(24) ? "(i)" : x == .key(25) ? "I" : nil) { return "RCL DIM \(m)" }
        return nil
    }

    // MARK: parsing keycodes

    /// The keycodes of a Manz step ("42 21 11", "44 .3", ",5", "44 24 u", old "45 48 3"), or nil if a token is not a keycode.
    public static func parseManz(_ s: String) -> [HP15CToken]? {
        var out: [HP15CToken] = []
        for raw in s.split(whereSeparator: { $0 == " " || $0 == "\t" }) {
            let w = String(raw)
            if w == "u" { out.append(.user); continue }
            if w.count == 2, let p = w.first, p == "." || p == ",", let d = w.last?.wholeNumberValue { out.append(.dot(d)); continue }
            guard w.count <= 2, w.allSatisfy({ $0.isASCII && $0.isNumber }), let k = Int(w) else { return nil }
            out.append(.key(k))
        }
        return normalized(out)
    }

    /// Keycodes as the calculator (and the inspector) shows them: "42,21,11", "44 .3", "45,10, .5", "43,30, 0".
    public static func parseDisplay(_ s: String) -> [HP15CToken]? {
        var out: [HP15CToken] = []
        for raw in s.split(whereSeparator: { $0 == " " || $0 == "," }) {
            let w = String(raw)
            if w == "u" { out.append(.user); continue }
            if w.count == 2, w.first == ".", let d = w.last?.wholeNumberValue { out.append(.dot(d)); continue }
            guard w.count <= 2, w.allSatisfy({ $0.isASCII && $0.isNumber }), let k = Int(w) else { return nil }
            out.append(.key(k))
        }
        return normalized(out)
    }

    /// Old files write the point as its own keycode 48 before a digit ("44 48 3" = STO .3): one ".d" token.
    static func normalized(_ t: [HP15CToken]) -> [HP15CToken] {
        guard t.count >= 3 else { return t }
        var out: [HP15CToken] = []
        var i = 0
        while i < t.count {
            if i > 0, t[i] == .key(48), i + 1 < t.count, case .key(let d) = t[i + 1], d <= 9 {
                out.append(.dot(d)); i += 2
            } else { out.append(t[i]); i += 1 }
        }
        return out
    }
}

// MARK: - keys to press

/// How to type a step on the HP-15C in program mode: physical key indexes of the app's 15C face (row × 10 + column,
/// 0-based; ENTER = 25, ON = 30, f = 31, g = 32, STO = 33, RCL = 34, 0 = 36, . = 37, Σ+ = 38, + = 39) and whether USER
/// mode must be on.
public enum HP15CKeyEntry {
    public static let keyF = 31, keyG = 32, keyRCL = 34

    /// Face key index of an HP keycode (digit keys are found by their digit).
    public static func keyIndex(_ code: Int) -> Int? {
        switch code {
        case 7, 8, 9: return code - 1           // 6, 7, 8
        case 4, 5, 6: return code + 12          // 16, 17, 18
        case 1, 2, 3: return code + 25          // 26, 27, 28
        case 0: return 36
        case 10...49:
            let row = code / 10, col = code % 10
            guard row >= 1, row <= 4 else { return nil }
            // columns 7...9 hold the digit keys (keycodes 0...9), and row 4 has no keys 46 (ENTER spans two rows) or 47 (the 0 key)
            guard (1...6).contains(col) || col == 0 || code == 48 || code == 49, code != 46 else { return nil }
            return (row - 1) * 10 + (col == 0 ? 9 : col - 1)
        default: return nil
        }
    }

    /// The keys of a valid step, in order. After STO / RCL the gold functions MATRIX, DIM, RESULT and RAN # are keyed
    /// with f (the calculator shows the keycode without it).
    public static func keys(for step: HP15CStep) -> [Int]? {
        guard step.isValid else { return nil }
        var out: [Int] = []
        let t = step.plainTokens
        for (i, tok) in t.enumerated() {
            switch tok {
            case .key(let k):
                if i == 1, case .key(let a) = t[0], a == 44 || a == 45, [16, 23, 26, 36].contains(k) { out.append(keyF) }
                guard let idx = keyIndex(k) else { return nil }
                out.append(idx)
            case .dot(let d):
                guard let p = keyIndex(48), let n = keyIndex(d) else { return nil }
                out += [p, n]
            case .user: break
            }
        }
        return out
    }
}

// MARK: - the file

public struct Manz15CProgram: Equatable, Sendable {
    public var title = ""
    public var description = ""                       // the #D: lines joined with "\n"
    /// "#L-1:" ... in file order: key "L-1", "R0", "RI", "R(i)", "F3", "T", value the text.
    public var labelNotes: [(key: String, text: String)] = []
    public var steps: [HP15CStep] = []                // step 001 onwards (000 is implied)

    public init() {}

    public static func == (a: Self, b: Self) -> Bool {
        a.title == b.title && a.description == b.description && a.steps == b.steps
            && a.labelNotes.map(\.key) == b.labelNotes.map(\.key) && a.labelNotes.map(\.text) == b.labelNotes.map(\.text)
    }

    public enum ReadError: Error, Equatable, LocalizedError {
        case notText
        case invalidLine(line: Int, text: String)
        case unknownStep(line: Int, keycodes: String)
        case tooManySteps(Int)
        case noSteps
        public var errorDescription: String? {
            switch self {
            case .notText: return "The file is not a text file."
            case .invalidLine(let n, let t): return "Line \(n) is not a program step (no keycodes between { and }): “\(t)”."
            case .unknownStep(let n, let k): return "Line \(n) has keycodes the HP-15C does not know as a program step: {\(k)}."
            case .tooManySteps(let n): return "The program has \(n) steps; a program file holds at most 999."
            case .noSteps: return "The file has no program steps."
            }
        }
    }

    /// Steps 001...999 (the simulator's limit). What fits the calculator depends on its memory (15.0: 448 one-byte steps at
    /// most, 15.2 double memory more), checked by the app before and while the program is keyed in.
    public static let maxSteps = 999

    // MARK: text decoding

    /// UTF-16LE with BOM (FF FE), UTF-8 with BOM (EF BB BF); without a BOM UTF-8, then Windows-1252.
    public static func decodeText(_ data: Data) -> String? {
        let b = [UInt8](data.prefix(3))
        if b.count >= 2, b[0] == 0xFF, b[1] == 0xFE {
            return String(data: data.dropFirst(2), encoding: .utf16LittleEndian)
        }
        if b.count >= 3, b[0] == 0xEF, b[1] == 0xBB, b[2] == 0xBF {
            return String(data: data.dropFirst(3), encoding: .utf8)
        }
        if let s = String(data: data, encoding: .utf8) { return s }
        return String(data: data, encoding: .windowsCP1252)
    }

    public static func read(_ data: Data) throws -> Manz15CProgram {
        guard let text = decodeText(data) else { throw ReadError.notText }
        return try parse(text)
    }

    // MARK: parsing

    public static func parse(_ text: String) throws -> Manz15CProgram {
        var p = Manz15CProgram()
        var desc: [String] = []
        var first = true
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r\n" })
        for (i, raw) in lines.enumerated() {
            let n = i + 1
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            if line.hasPrefix("#") {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let key = String(line[line.index(after: line.startIndex)..<colon])
                let value = String(line[line.index(after: colon)...])
                guard let k = key.first, "TDLRF".contains(k) else { continue }
                if key == "D" { desc.append(value) }
                else if key == "T" { p.title = value }
                else if k != "D", k != "T" { p.labelNotes.append((key, value)) }
                continue
            }
            guard let open = line.firstIndex(of: "{"), let close = line.lastIndex(of: "}"), open < close else {
                throw ReadError.invalidLine(line: n, text: line)
            }
            let inner = String(line[line.index(after: open)..<close])
            let tokens = inner.trimmingCharacters(in: .whitespaces)
            if tokens.isEmpty {
                if first { first = false; continue }              // step 000
                throw ReadError.unknownStep(line: n, keycodes: inner)
            }
            first = false
            guard let t = HP15CKeycodes.parseManz(tokens), HP15CKeycodes.mnemonic(t) != nil else {
                throw ReadError.unknownStep(line: n, keycodes: tokens)
            }
            p.steps.append(HP15CStep(t))
        }
        p.description = desc.joined(separator: "\n")
        if p.steps.count > maxSteps { throw ReadError.tooManySteps(p.steps.count) }
        return p
    }

    // MARK: writing

    static let rule = "# " + String(repeating: "-", count: 78)

    /// The file as the simulator writes it: UTF-16LE with a BOM, CRLF line ends, no line end after the last rule.
    public func fileData() -> Data {
        var d = Data([0xFF, 0xFE])
        d.append(text().data(using: .utf16LittleEndian)!)
        return d
    }

    /// "   001 {    42 21 11 } f LBL A"
    public static func stepLine(_ n: Int, _ step: HP15CStep?) -> String {
        let keys = step?.keycodeText ?? ""
        let pad = String(repeating: " ", count: max(0, 12 - keys.count)) + keys
        return String(format: "   %03d {", n) + pad + " } " + (step?.mnemonic ?? "")
    }

    public func text() -> String {
        var l: [String] = [Self.rule, "# HEWLETT·PACKARD 15C Simulator program", "# Created with version 4.6.00", Self.rule]
        if !title.isEmpty { l.append("#T:" + title) }
        if !description.isEmpty {
            for d in description.components(separatedBy: "\n") { l.append("#D:" + d) }
        }
        for n in labelNotes { l.append("#\(n.key):\(n.text)") }
        l.append(Self.rule)
        l.append("")
        l.append(Self.stepLine(0, nil))
        for (i, s) in steps.enumerated() { l.append(Self.stepLine(i + 1, s)) }
        l.append("")
        l.append(Self.rule)
        return l.joined(separator: "\r\n")
    }

    // MARK: notes <-> ProgramDocument

    /// Manz note key -> the name ProgramDocument uses: "L-1" -> label "A", "L12" -> ".2", "R3" -> "R3", "R13" -> "R.3",
    /// "RI" -> "I", "R(i)" -> "(i)", "F2" -> flag "2". nil for anything else (kept as is for the next export).
    public static func documentName(_ key: String) -> (kind: Character, name: String)? {
        guard let k = key.first else { return nil }
        let rest = String(key.dropFirst())
        switch k {
        case "L":
            guard let n = Int(rest) else { return nil }
            if n >= -5, n <= -1 { return ("L", ["A", "B", "C", "D", "E"][-n - 1]) }
            if n >= 0, n <= 9 { return ("L", "\(n)") }
            if n >= 10, n <= 19 { return ("L", ".\(n - 10)") }
            return nil
        case "R":
            if rest == "I" { return ("R", "I") }
            if rest == "(i)" { return ("R", "(i)") }
            guard let n = Int(rest) else { return nil }
            if n >= 0, n <= 9 { return ("R", "R\(n)") }
            if n >= 10, n <= 19 { return ("R", "R.\(n - 10)") }
            return nil
        case "F":
            guard let n = Int(rest), n >= 0, n <= 9 else { return nil }
            return ("F", "\(n)")
        default: return nil
        }
    }

    /// The inverse of documentName.
    public static func manzKey(kind: Character, name: String) -> String? {
        switch kind {
        case "L":
            if let i = ["A", "B", "C", "D", "E"].firstIndex(of: name) { return "L-\(i + 1)" }
            if let n = Int(name), n >= 0, n <= 9 { return "L\(n)" }
            if name.hasPrefix("."), let n = Int(name.dropFirst()), n >= 0, n <= 9 { return "L\(n + 10)" }
            return nil
        case "R":
            if name == "I" || name == "(i)" { return "R" + name }
            if name.hasPrefix("R."), let n = Int(name.dropFirst(2)), n >= 0, n <= 9 { return "R\(n + 10)" }
            if name.hasPrefix("R"), let n = Int(name.dropFirst()), n >= 0, n <= 9 { return "R\(n)" }
            return nil
        case "F":
            if let n = Int(name), n >= 0, n <= 9 { return "F\(n)" }
            return nil
        default: return nil
        }
    }

    /// Fill a program document's title, description and label / register / flag notes from the file.
    public func apply(to doc: inout ProgramDocument) {
        if !title.isEmpty { doc.title = title }
        if !description.isEmpty { doc.description = description }
        for n in labelNotes {
            guard let (kind, name) = Self.documentName(n.key) else { continue }
            switch kind {
            case "L": doc.labels[name] = n.text
            case "R": var r = doc.registers[name] ?? RegisterNote(); r.meaning = n.text; doc.registers[name] = r
            default: doc.flags[name] = n.text
            }
        }
    }

    /// Notes for export: from the document (non-empty ones), in the simulator's order (labels A..E, 0..9, .0...9;
    /// registers 0...9, .0....9, I, (i); flags), plus notes from an imported file the document has no place for.
    public static func notes(from doc: ProgramDocument, keeping extra: [(key: String, text: String)] = []) -> [(key: String, text: String)] {
        func order(_ key: String) -> (Int, Int) {
            let k = key.first!
            let rest = String(key.dropFirst())
            let kindOrder = k == "L" ? 0 : k == "R" ? 1 : 2
            if rest == "I" { return (kindOrder, 100) }
            if rest == "(i)" { return (kindOrder, 101) }
            return (kindOrder, Int(rest) ?? 200)
        }
        var out: [(key: String, text: String)] = []
        for (n, t) in doc.labels where !t.isEmpty { if let k = manzKey(kind: "L", name: n) { out.append((k, t)) } }
        for (n, r) in doc.registers where !r.isEmpty {
            let t = r.name.isEmpty ? r.meaning : r.meaning.isEmpty ? r.name : r.name + ": " + r.meaning
            if let k = manzKey(kind: "R", name: n) { out.append((k, t)) }
        }
        for (n, t) in doc.flags where !t.isEmpty { if let k = manzKey(kind: "F", name: n) { out.append((k, t)) } }
        for e in extra where documentName(e.key) == nil && !out.contains(where: { $0.key == e.key }) { out.append(e) }
        return out.sorted { order($0.key) < order($1.key) }
    }
}

// MARK: - the calculator's listing

extension Manz15CProgram {
    /// Steps from the calculator's listing (ProgramLine.keys). When `imported` lists the same keycodes (ignoring USER
    /// markers), its steps are used, so the "u" of USER-mode STO / RCL survives an import / export round trip.
    /// Throws unknownStep (line = step number) for a listing step this file format cannot express.
    public static func steps(fromListing keys: [String], imported: [HP15CStep]? = nil) throws -> [HP15CStep] {
        var out: [HP15CStep] = []
        for (i, k) in keys.enumerated() {
            guard let t = HP15CKeycodes.parseDisplay(k) else { throw ReadError.unknownStep(line: i + 1, keycodes: k) }
            out.append(HP15CStep(t))
        }
        if let imp = imported, imp.map(\.plainTokens) == out.map(\.plainTokens) { return imp }
        return out
    }
}
