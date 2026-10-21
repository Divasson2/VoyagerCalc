// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// ProgramDocument.swift - the notes that document a program, kept in a sidecar file next to the
// memory file ("FinancePac.15c" -> "FinancePac.15c.voyagerdoc", JSON): title, author,
// description (what it does, how to use it), notes per label, register and flag, and comments
// per step. Each comment also stores the step's keycodes and those of its neighbours, so that
// after lines are inserted or deleted it can be found again by content near its old position
// (rematch); one that cannot be placed is kept and flagged as orphaned.

import Foundation

public struct RegisterNote: Codable, Equatable, Sendable {
    public var name: String = ""       // short name, e.g. "rate"
    public var meaning: String = ""    // what it holds
    public init(name: String = "", meaning: String = "") { self.name = name; self.meaning = meaning }
    public var isEmpty: Bool { name.isEmpty && meaning.isEmpty }
}

public struct StepComment: Codable, Equatable, Sendable {
    public var step: Int
    public var text: String
    public var keys: String            // the step's keycodes when the comment was written ("42,21,11")
    public var before: [String] = []   // keycodes of the two steps before and after
    public var after: [String] = []
    public var orphaned = false
    public init(step: Int, text: String, keys: String, before: [String] = [], after: [String] = [], orphaned: Bool = false) {
        self.step = step; self.text = text; self.keys = keys; self.before = before; self.after = after; self.orphaned = orphaned
    }
}

public struct ProgramDocument: Codable, Equatable, Sendable {
    public static let fileExtension = "voyagerdoc"
    public var format = "voyagerdoc"
    public var version = 1
    public var title = ""
    public var author = ""
    public var description = ""
    public var model = ""                          // "HP-15C (15.2)", informative
    public var labels: [String: String] = [:]      // label -> note
    public var registers: [String: RegisterNote] = [:]
    public var flags: [String: String] = [:]
    public var comments: [StepComment] = []

    public init() {}

    public var isEmpty: Bool {
        title.isEmpty && author.isEmpty && description.isEmpty && labels.values.allSatisfy(\.isEmpty)
            && registers.values.allSatisfy(\.isEmpty) && flags.values.allSatisfy(\.isEmpty) && comments.isEmpty
    }

    // MARK: file

    public static func sidecarURL(for memoryFile: URL) -> URL {
        memoryFile.appendingPathExtension(fileExtension)
    }
    public func encoded() throws -> Data {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(self)
    }
    public static func decode(_ data: Data) throws -> ProgramDocument {
        let d = try JSONDecoder().decode(ProgramDocument.self, from: data)
        guard d.format == "voyagerdoc" else { throw CocoaError(.fileReadCorruptFile) }
        return d
    }

    // MARK: comments

    public func comment(at step: Int) -> String? {
        comments.first { $0.step == step && !$0.orphaned }?.text
    }
    public var orphanedComments: [StepComment] { comments.filter(\.orphaned) }

    /// Set (or with empty text remove) the comment of a step, remembering its keycodes.
    public mutating func setComment(_ text: String, at step: Int, lines: [ProgramLine]) {
        comments.removeAll { $0.step == step && !$0.orphaned }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let i = lines.firstIndex(where: { $0.line == step }) else { return }
        let (b, a) = Self.context(lines, i)
        comments.append(StepComment(step: step, text: t, keys: lines[i].keys, before: b, after: a))
        comments.sort { $0.step < $1.step }
    }

    static func context(_ lines: [ProgramLine], _ i: Int) -> ([String], [String]) {
        let b = (max(0, i - 2)..<i).map { lines[$0].keys }
        let a = ((i + 1)..<min(lines.count, i + 3)).map { lines[$0].keys }
        return (b, a)
    }

    public struct RematchReport: Equatable, Sendable {
        public var kept = 0, moved = 0, orphaned = 0
    }

    /// Place every comment on the program as it is now: on its old step if the keycodes there
    /// still match, otherwise on the nearest step with the same keycodes whose neighbours match
    /// best. A comment that matches nowhere well enough is kept, flagged orphaned.
    @discardableResult
    public mutating func rematch(to lines: [ProgramLine]) -> RematchReport {
        var report = RematchReport()
        var taken = Set<Int>()
        var out: [StepComment] = []
        func score(_ c: StepComment, _ i: Int) -> Int {
            let (b, a) = Self.context(lines, i)
            var s = 0
            for (k, v) in c.before.reversed().enumerated() where k < b.count && b[b.count - 1 - k] == v { s += 1 }
            for (k, v) in c.after.enumerated() where k < a.count && a[k] == v { s += 1 }
            return s
        }
        for var c in comments.sorted(by: { $0.step < $1.step }) {
            let old = c.step
            var best: (i: Int, s: Int, d: Int)?
            for (i, l) in lines.enumerated() where l.keys == c.keys && !taken.contains(l.line) {
                let s = score(c, i), d = abs(l.line - old)
                if best == nil || s > best!.s || (s == best!.s && d < best!.d) { best = (i, s, d) }
            }
            let contextSize = c.before.count + c.after.count
            // the best candidate (most matching neighbours, then nearest) is taken when three or
            // more of its four neighbours match, two within 60 steps, or one within 3 steps
            if let b = best, b.s >= 3 || (b.s >= 2 && b.d <= 60) || (b.s >= 1 && b.d <= 3)
                || (contextSize == 0 && b.d == 0) || (b.s == contextSize && b.d <= 60) {
                let l = lines[b.i]
                if l.line == old && !c.orphaned { report.kept += 1 } else { report.moved += 1 }
                c.step = l.line; c.orphaned = false
                let (bb, aa) = Self.context(lines, b.i); c.before = bb; c.after = aa
                taken.insert(l.line)
            } else {
                if !c.orphaned { report.orphaned += 1 }
                c.orphaned = true
            }
            out.append(c)
        }
        comments = out.sorted { ($0.orphaned ? 1 : 0, $0.step) < ($1.orphaned ? 1 : 0, $1.step) }
        return report
    }

    // MARK: pre-fill from the program

    /// Add an (empty) entry for every label, register and flag the program uses, keeping notes.
    public mutating func prefill(from a: ProgramAnalysis) {
        for l in a.labels where labels[l.name] == nil { labels[l.name] = "" }
        for r in a.registers where registers[r.name] == nil { registers[r.name] = RegisterNote() }
        for f in a.flags where flags[f.name] == nil { flags[f.name] = "" }
    }
}

// MARK: - the listing as the calculator shows it

extension ProgramLine {
    /// The step as the display shows it in program mode, e.g. "001-42,21,11", "002-    15",
    /// 12C "01-43,33 00": line number, a minus, then the keycodes right-aligned in the ten
    /// digit cells (a comma or point shares the cell of the digit before it).
    public func screenView(model: Int) -> String {
        let number = model == 12 ? String(format: "%02d", line) : String(format: "%03d", line)
        let prefix = number + "-"
        let cells = keys.reduce(0) { $0 + ($1 == "," || $1 == "." ? 0 : 1) }
        let pad = max(0, 10 - prefix.count - cells)
        return prefix + String(repeating: " ", count: pad) + keys
    }
    /// The step's number as the calculator writes it (three digits, two on the 12C).
    public func number(model: Int) -> String {
        model == 12 ? String(format: "%02d", line) : String(format: "%03d", line)
    }
}

/// What the document says about the calculator and the program.
public struct ProgramDocumentInfo: Sendable {
    public var modelName: String       // "HP-15C (15.2)"
    public var firmware: String        // firmware file name
    public var memoryFile: String      // "FinancePac.15c" or ""
    public var model: Int              // 12, 15, 16
    public var date: Date
    public init(modelName: String, firmware: String, memoryFile: String = "", model: Int, date: Date = Date()) {
        self.modelName = modelName; self.firmware = firmware; self.memoryFile = memoryFile; self.model = model; self.date = date
    }

    /// "HP-12C", "HP-15C", "HP-15C (15.2)", "HP-16C" for a running variant (120, 150, 152, 160).
    public static func modelName(variant: Int, model: Int) -> String {
        switch variant {
        case 152: return "HP-15C (15.2)"
        case 150: return "HP-15C"
        default: return "HP-\(model)C"
        }
    }
    public var dateText: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "d MMMM yyyy"
        return f.string(from: date)
    }
}

/// Everything the PDF and the text export show, worked out once.
public struct ProgramDocumentContent: Sendable {
    public var doc: ProgramDocument
    public var info: ProgramDocumentInfo
    public var lines: [ProgramLine]
    public var analysis: ProgramAnalysis
    /// HP-15C memory configuration from the loaded memory (0.6.0); nil for the other models.
    public var pool: Pool15?
    public var setFlags: [Int] = []

    public init(doc: ProgramDocument, info: ProgramDocumentInfo, lines: [ProgramLine], pool: Pool15? = nil, setFlags: [Int] = []) {
        self.doc = doc; self.info = info; self.lines = lines
        self.analysis = ProgramAnalysis(lines: lines, model: info.model)
        self.pool = info.model == 15 ? pool : nil
        self.setFlags = setFlags
    }

    /// "Memory configuration" (15C): what the loaded memory holds now.
    public var memoryRows: [(String, String)] {
        guard let p = pool else { return [] }
        var r: [(String, String)] = []
        let last = p.dimI < 10 ? "R\(p.dimI)" : p.dimI < 20 ? "R.\(p.dimI - 10)" : "R\(p.dimI)"
        r.append(("DIM (i)", "\(p.dimI): R0–\(last), \(p.dimI + 1) storage registers"))
        let dims = (0..<5).filter { p.rows[$0] * p.cols[$0] > 0 }.map { "\(Pool15.letters[$0]) \(p.dimension($0))" }
        r.append(("Matrices", dims.isEmpty ? "none dimensioned (all 0×0)" : dims.joined(separator: ", ") + " (\(p.matrixRegisters) registers)"))
        r.append(("RESULT", "matrix \(p.resultLetter)"))
        r.append(("Complex mode", p.complex ? "on (flag 8): 5 registers hold the imaginary stack" : "off"))
        let fl = setFlags.filter { $0 <= 9 }
        r.append(("Flags set", fl.isEmpty ? "none" : fl.map { $0 == 8 ? "8 (complex)" : $0 == 9 ? "9 (overflow)" : "\($0)" }.joined(separator: ", ")))
        r.append(("g MEM", "\(p.gmem)   (DIM (i), free registers, program registers–bytes left; pool \(p.size) registers + R0, R1)"))
        let ws = analysis.matrixOps.first { $0.item == "SOLVE/∫ workspace" }
        let work = ws.map { $0.operations.contains("∫ʸₓ") ? ($0.operations.contains("SOLVE") ? 28 : 23) : 5 } ?? 0
        let need = p.storage + p.matrixRegisters + (p.complex ? 5 : 0) + p.programRegisters + work
        var needText = "\(need) of \(p.size) pool registers (R2… \(p.storage), matrices \(p.matrixRegisters), complex \(p.complex ? 5 : 0), program \(p.programRegisters)"
        needText += work > 0 ? ", SOLVE/∫ workspace \(work))" : ")"
        r.append(("Needs at least", needText))
        return r
    }

    public struct MatrixOpRow: Sendable { public var item, operations, steps, notes: String }
    public var matrixOpRows: [MatrixOpRow] {
        analysis.matrixOps.map { m in
            var notes = m.notes
            if m.item.hasPrefix("Matrix "), let p = pool, let i = Pool15.letters.firstIndex(of: String(m.item.dropFirst(7))) {
                notes.insert("now \(p.dimension(i))" + (p.result == i ? ", the RESULT matrix" : ""), at: 0)
            }
            return MatrixOpRow(item: m.item, operations: m.operations.joined(separator: ", "), steps: steps(m.steps), notes: notes.joined(separator: "; "))
        }
    }

    public var title: String { doc.title.isEmpty ? (info.memoryFile.isEmpty ? "Untitled program" : info.memoryFile) : doc.title }

    func steps(_ s: [Int]) -> String { s.map { info.model == 12 ? String(format: "%02d", $0) : String(format: "%03d", $0) }.joined(separator: ", ") }

    public struct LabelRow: Sendable { public var label, notes, defined, called: String }
    public struct RegisterRow: Sendable { public var register, name, use, steps: String }
    public struct ListingRow: Sendable {
        public var step: String, screen: String, keys: String, comment: String
        public var isLabel: Bool
    }

    /// Heading of the 12C's branch-target section (text export; the PDF writes it in sentence case).
    public static let branchTargetsTitle = "BRANCH TARGETS"

    public var labelRows: [LabelRow] {
        analysis.labels.map { l in
            var called = steps(l.called)
            if !l.callKinds.isEmpty, !l.called.isEmpty { called += " (" + l.callKinds.joined(separator: ", ") + ")" }
            var defined = l.defined.isEmpty ? (l.isIndirect ? "computed in I" : "not defined") : steps(l.defined)
            if info.model == 12, !l.isIndirect, l.defined == [0] { defined = "00 (start)" }       // line 00 always exists (0.6.9)
            let name = info.model == 12 && !l.isIndirect ? "line \(l.name)" : (l.isIndirect ? l.name : "LBL \(l.name)")
            return LabelRow(label: name, notes: doc.labels[l.name] ?? "", defined: defined, called: called.isEmpty ? "—" : called)
        }
    }
    public var registerRows: [RegisterRow] {
        analysis.registers.map { r in
            let n = doc.registers[r.name] ?? RegisterNote()
            let name = [n.name, n.meaning].filter { !$0.isEmpty }.joined(separator: ": ")
            return RegisterRow(register: r.name, name: name, use: r.operations.joined(separator: ", "), steps: steps(r.steps))
        }
    }
    public var flagRows: [RegisterRow] {
        analysis.flags.map { f in
            RegisterRow(register: "Flag \(f.name)", name: (doc.flags[f.name] ?? "").isEmpty ? f.meaning : doc.flags[f.name]!,
                        use: f.operations.joined(separator: ", "), steps: steps(f.steps))
        }
    }
    public var listingRows: [ListingRow] {
        lines.map { l in
            ListingRow(step: l.number(model: info.model), screen: l.screenView(model: info.model), keys: l.fullMnemonic,
                       comment: doc.comment(at: l.line) ?? "", isLabel: l.mnemonic.hasPrefix("LBL "))
        }
    }

    // MARK: plain text

    /// The whole document as plain text (Export Listing as Text).
    public func plainText() -> String {
        var o: [String] = []
        o.append(title)
        o.append(String(repeating: "=", count: max(8, title.count)))
        o.append("Model:     \(info.modelName)")
        if !info.firmware.isEmpty { o.append("Firmware:  \(info.firmware)") }
        if !info.memoryFile.isEmpty { o.append("Memory:    \(info.memoryFile)") }
        o.append("Steps:     \(lines.count)")
        o.append("Date:      \(info.dateText)")
        if !doc.author.isEmpty { o.append("Author:    \(doc.author)") }
        if !doc.description.isEmpty { o += ["", doc.description] }
        func table(_ head: [String], _ rows: [[String]]) {
            let w = head.indices.map { i in max(head[i].count, rows.map { $0[i].count }.max() ?? 0) }
            func fmt(_ r: [String]) -> String {
                r.enumerated().map { i, c in i == r.count - 1 ? c : c.padding(toLength: w[i], withPad: " ", startingAt: 0) }
                    .joined(separator: "  ").trimmingCharacters(in: .whitespaces)
            }
            o.append(fmt(head)); o.append(fmt(w.map { String(repeating: "-", count: $0) }))
            rows.forEach { o.append(fmt($0)) }
        }
        if info.model == 12 {      // 0.6.9: the 12C text export always has the section, named as in the PDF
            o += ["", Self.branchTargetsTitle, ""]
            if labelRows.isEmpty { o.append("No GTO in this program.") }
            else { table(["Line", "Defined", "Called from", "Notes"], labelRows.map { [$0.label, $0.defined, $0.called, $0.notes] }) }
        } else if !labelRows.isEmpty {
            o += ["", "LABELS", ""]
            table(["Label", "Defined", "Called from", "Notes"], labelRows.map { [$0.label, $0.defined, $0.called, $0.notes] })
        }
        if !registerRows.isEmpty || !flagRows.isEmpty {
            o += ["", "REGISTERS AND FLAGS", ""]
            table(["Register", "Use", "Steps", "Name / meaning"], (registerRows + flagRows).map { [$0.register, $0.use, $0.steps, $0.name] })
        }
        if !memoryRows.isEmpty {
            o += ["", "MEMORY CONFIGURATION", ""]
            for (k, v) in memoryRows { o.append(k.padding(toLength: 16, withPad: " ", startingAt: 0) + v) }
        }
        if !matrixOpRows.isEmpty {
            o += ["", "MATRICES AND COMPLEX", ""]
            table(["Item", "Operations", "Steps", "Notes"], matrixOpRows.map { [$0.item, $0.operations, $0.steps, $0.notes] })
        }
        o += ["", "LISTING", ""]
        table(["Step", "Display", "Keys", "Comment"], listingRows.map { [$0.step, $0.screen, $0.keys, $0.comment] })
        if !doc.orphanedComments.isEmpty {
            o += ["", "COMMENTS NO LONGER MATCHING A STEP", ""]
            for c in doc.orphanedComments { o.append("was \(String(format: "%03d", c.step)) (\(c.keys)): \(c.text)") }
        }
        return o.joined(separator: "\n") + "\n"
    }
}
