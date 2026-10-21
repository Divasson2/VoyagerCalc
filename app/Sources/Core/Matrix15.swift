// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// Matrix15.swift - the logic behind the HP-15C Matrix Editor (0.7.1), without views (unit-tested in Matrix15Tests),
// ported from the Qt app's Matrix15.cpp: number cells as people type or paste them ("1,5", "1.5", "2E-3",
// "1.234,5", "1,234.5"), tab-separated clipboard ranges from Excel / Numbers / LibreOffice / Google Sheets, and a
// matrix read from / written into a 2 KB 15C memory image with the firmware's DIM bookkeeping (vc_matrix15_* in the core).
// Real numbers only: the editor has no complex cells.

import Foundation
import VoyagerCore

public enum Matrix15 {
    /// The firmware's limit for rows and columns.
    public static let maxSide = 99

    public enum CellError: Error, Equatable {
        case notANumber, complex, tooLarge
        public var text: String {
            switch self {
            case .notANumber: return "not a number"
            case .complex: return "complex numbers are not supported (real numbers only)"
            case .tooLarge: return "too large (the HP-15C goes up to 9.999999999e99)"
            }
        }
    }

    /// One cell -> the 15C register value (10 digits, rounded). Empty text is 0.
    public static func parseCell(_ text: String) -> Result<UInt64, CellError> {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for ch in ["\u{00A0}", "\u{202F}", " ", "'"] { t = t.replacingOccurrences(of: ch, with: "") }   // thousands spaces / apostrophes
        t = t.replacingOccurrences(of: "\u{2212}", with: "-")                                            // typographic minus
        if t.isEmpty { return .success(0) }
        let comma = t.filter { $0 == "," }.count, dot = t.filter { $0 == "." }.count
        if comma > 0 && dot > 0 {
            // both: the one that comes last is the decimal separator, the other groups thousands ("1.234,5" / "1,234.5")
            let lastComma = t.lastIndex(of: ",")!, lastDot = t.lastIndex(of: ".")!
            if lastComma > lastDot {
                if comma != 1 { return .failure(.notANumber) }
                t = t.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            } else {
                if dot != 1 { return .failure(.notANumber) }
                t = t.replacingOccurrences(of: ",", with: "")
            }
        } else if comma == 1 {
            t = t.replacingOccurrences(of: ",", with: ".")                                               // "1,5"
        } else if comma > 1 {
            // "1,234,567": thousands groups only
            guard t.range(of: #"^[+-]?\d{1,3}(,\d{3})+$"#, options: .regularExpression) != nil else { return .failure(.notANumber) }
            t = t.replacingOccurrences(of: ",", with: "")
        }
        if t.contains("i") || t.contains("j") { return .failure(.complex) }
        var v: UInt64 = 0
        if vc_bcd_from_text(t, &v) == Int32(VC_OK) { return .success(v) }
        if t.range(of: #"^[+-]?(\d+\.?\d*|\.\d+)[eE][+]?\d+$"#, options: .regularExpression) != nil { return .failure(.tooLarge) }
        return .failure(.notANumber)
    }

    public static func value(_ text: String) -> UInt64? {
        if case .success(let v) = parseCell(text) { return v }
        return nil
    }

    /// The register value as the calculator / the inspector shows it ("1.5", "-2e-3"); parseCell reads it back exactly.
    public static func cellText(_ raw: UInt64) -> String {
        var b = [CChar](repeating: 0, count: 64)
        _ = vc_bcd_text(raw, &b, b.count)
        return String(cString: b)
    }

    /// A rectangular block of text cells from the clipboard.
    public struct Table: Equatable, Sendable {
        public var rows = 0, cols = 0
        public var cells: [String] = []          // row-major, rows * cols (short rows are padded with "")
        public var ragged = false                // the rows had different lengths
        public var error = ""                    // not usable (empty clipboard, too big ...)
        public init() {}
        public func cell(_ r: Int, _ c: Int) -> String {
            let i = r * cols + c
            return i >= 0 && i < cells.count ? cells[i] : ""
        }
        public var ok: Bool { error.isEmpty && rows > 0 && cols > 0 }
    }

    private static func unquote(_ s: String) -> String {
        let c = s.trimmingCharacters(in: .whitespaces)
        if c.count >= 2, c.hasPrefix("\""), c.hasSuffix("\"") {
            return String(c.dropFirst().dropLast()).replacingOccurrences(of: "\"\"", with: "\"")
        }
        return c
    }

    /// Tab-separated text (lines by \n, \r\n or \r; a trailing line break is ignored; "quoted" cells are unquoted).
    /// A single column of numbers separated by ';' is also accepted. More than 99 rows or columns is an error.
    public static func parseTable(_ text: String) -> Table {
        var t = Table()
        let s = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var lines = s.components(separatedBy: "\n")
        while let l = lines.last, l.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        while let f = lines.first, f.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeFirst() }
        if lines.isEmpty { t.error = "The clipboard holds no cells. Copy a range of numbers in the spreadsheet first."; return t }
        let anyTab = s.contains("\t")
        var rows: [[String]] = lines.map { l in
            let cells: [String]
            if anyTab { cells = l.components(separatedBy: "\t") }
            else if l.contains(";") { cells = l.components(separatedBy: ";") }      // "CSV" of a European spreadsheet
            else { cells = [l] }
            return cells.map(unquote)
        }
        // trailing empty columns (some apps add a tab at the end of a line)
        var cols = 0
        for i in rows.indices {
            while rows[i].count > 1, rows[i].last?.isEmpty == true { rows[i].removeLast() }
            cols = max(cols, rows[i].count)
        }
        t.ragged = rows.contains { $0.count != cols }
        t.rows = rows.count; t.cols = cols
        if t.rows > maxSide || t.cols > maxSide {
            t.error = "The clipboard holds \(t.rows) × \(t.cols) cells; an HP-15C matrix has at most 99 rows and 99 columns."
            return t
        }
        for r in rows { for c in 0..<cols { t.cells.append(c < r.count ? r[c] : "") } }
        return t
    }

    /// The bad cells of a table (1-based "row,col: text (why)"), empty when every cell is a number.
    public static func badCells(_ t: Table) -> [String] {
        var out: [String] = []
        for r in 0..<t.rows { for c in 0..<t.cols {
            if case .failure(let e) = parseCell(t.cell(r, c)) { out.append("\(r + 1),\(c + 1): “\(t.cell(r, c))” (\(e.text))") }
        } }
        return out
    }

    /// Rows of tab-separated cellText values (what Copy puts on the clipboard).
    public static func toTSV(rows: Int, cols: Int, raw: [UInt64]) -> String {
        (0..<rows).map { r in
            (0..<cols).map { c in let i = r * cols + c; return i < raw.count ? cellText(raw[i]) : "0" }.joined(separator: "\t")
        }.joined(separator: "\n")
    }

    /// A matrix as stored in a 15C memory image.
    public struct Stored: Equatable, Sendable {
        public var rows = 0, cols = 0
        public var raw: [UInt64] = []            // row-major
        public init(rows: Int = 0, cols: Int = 0, raw: [UInt64] = []) { self.rows = rows; self.cols = cols; self.raw = raw }
    }

    /// Matrix m (0..4 = A..E) of the image; variant 150 / 152 (the running 15C mode).
    public static func read(_ image: Data, variant: Int, matrix m: Int) -> Stored? {
        guard image.count == VoyagerCalculator.memorySize, (0...4).contains(m) else { return nil }
        let b = [UInt8](image)
        var p = vc_pool15()
        guard vc_image_pool15(b, Int32(variant), &p) == Int32(VC_OK) else { return nil }
        let pool = Pool15(core: p)
        var s = Stored(rows: pool.rows[m], cols: pool.cols[m])
        var v = vc_value()
        for r in 0..<s.rows { for c in 0..<s.cols {
            guard vc_image_matrix15(b, Int32(variant), Int32(m), Int32(r + 1), Int32(c + 1), &v) == Int32(VC_OK) else { return nil }
            s.raw.append(v.raw)
        } }
        return s
    }

    /// The pool of the image (what the inspector's pool bar shows).
    public static func pool(_ image: Data, variant: Int) -> Pool15? {
        guard image.count == VoyagerCalculator.memorySize else { return nil }
        var p = vc_pool15()
        guard vc_image_pool15([UInt8](image), Int32(variant), &p) == Int32(VC_OK) else { return nil }
        return Pool15(core: p)
    }

    /// The largest rows*cols matrix m can have in this image (its own registers count as free); -1 when not a 15C image.
    public static func room(_ image: Data, variant: Int, matrix m: Int) -> Int {
        guard image.count == VoyagerCalculator.memorySize else { return -1 }
        var avail: Int32 = -1
        return vc_matrix15_room([UInt8](image), Int32(variant), Int32(m), 0, 0, &avail) == Int32(VC_OK) ? Int(avail) : -1
    }

    /// The pool as it would be after dimensioning m to rows x cols (nothing written to `image`).
    public static func poolAfter(_ image: Data, variant: Int, matrix m: Int, rows: Int, cols: Int) -> Pool15? {
        guard image.count == VoyagerCalculator.memorySize else { return nil }
        var b = [UInt8](image)
        guard vc_matrix15_write(&b, Int32(variant), Int32(m), Int32(rows), Int32(cols), nil) == Int32(VC_OK) else { return nil }
        return pool(Data(b), variant: variant)
    }

    public enum WriteError: Error, Equatable, LocalizedError {
        case message(String)
        public var errorDescription: String? { if case .message(let m) = self { return m }; return nil }
    }

    /// DIM matrix m to rows x cols and store raw (row-major, rows*cols values) into the image. Throws why it was refused.
    public static func write(_ image: inout Data, variant: Int, matrix m: Int, rows: Int, cols: Int, raw: [UInt64]) throws {
        func fail(_ s: String) -> WriteError { .message(s) }
        guard image.count == VoyagerCalculator.memorySize else { throw fail("The emulator's memory could not be read.") }
        guard (0...4).contains(m) else { throw fail("There is no matrix \(m).") }
        guard (0...maxSide).contains(rows), (0...maxSide).contains(cols) else { throw fail("An HP-15C matrix has 0 to 99 rows and 0 to 99 columns.") }
        guard rows * cols == raw.count else { throw fail("The grid does not have \(rows) × \(cols) values.") }
        guard pool(image, variant: variant) != nil else { throw fail("The emulator's memory is not an HP-15C memory.") }
        let avail = room(image, variant: variant, matrix: m)
        let letter = Pool15.letters[m]
        if rows * cols > avail {
            throw fail("Matrix \(letter) \(rows) × \(cols) needs \(rows * cols) registers, but only \(avail) are free for it (the calculator would show Error 10). "
                       + "Make it smaller, or free memory on the calculator (smaller DIM (i), other matrices, program).")
        }
        var b = [UInt8](image)
        let r: Int32 = raw.isEmpty
            ? vc_matrix15_write(&b, Int32(variant), Int32(m), Int32(rows), Int32(cols), nil)
            : raw.withUnsafeBufferPointer { vc_matrix15_write(&b, Int32(variant), Int32(m), Int32(rows), Int32(cols), $0.baseAddress) }
        guard r == Int32(VC_OK) else { throw fail("Matrix \(letter) could not be written.") }
        image = Data(b)
    }
}

extension CalculatorMachine {
    /// 15C: DIM matrix m (0..4) to rows x cols and store raw (row-major BCD) in the memory, as the Matrix Editor's Apply.
    public func writeMatrix15(_ m: Int, rows: Int, cols: Int, raw: [UInt64]) throws {
        guard model == 15 else { throw Matrix15.WriteError.message("The Matrix Editor needs the HP-15C (the calculator runs another model now).") }
        var mem = try memory(turnBackOn: true)
        try Matrix15.write(&mem, variant: variant, matrix: m, rows: rows, cols: cols, raw: raw)
        try putMemory(mem)
    }
}
