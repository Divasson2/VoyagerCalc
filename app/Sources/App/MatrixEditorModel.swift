// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// MatrixEditorModel.swift - state of the HP-15C Matrix Editor window (0.7.1, port of the Qt MatrixEditor): matrix A–E,
// size with the free-memory check and pool preview, a real-only grid, Paste Matrix (tab-separated range, preview first),
// Copy (TSV), open the matrix from the emulator's memory, Apply (DIM + values into the emulator's memory; then
// Real Calculator (USB) ▸ Write to Calculator… sends it). No views here, so the tests drive it directly.

import Foundation
import SwiftUI

@MainActor
final class MatrixEditorModel: ObservableObject {
    struct Hooks {
        /// The emulator's memory image and the running 15C variant (150 / 152); nil when there is none.
        var fetch: @MainActor () -> (image: Data, variant: Int)? = { nil }
        /// Write the matrix into the emulator's memory (engine thread); done(nil) or done(error text).
        var apply: @MainActor (_ m: Int, _ rows: Int, _ cols: Int, _ raw: [UInt64], _ done: @escaping @MainActor (String?) -> Void) -> Void = { _, _, _, _, d in d("The calculator is not running.") }
        var clipboardText: @MainActor () -> String = { "" }
        var copyText: @MainActor (String) -> Void = { _ in }
    }
    var hooks = Hooks()

    @Published var matrix = 0 { didSet { if matrix != oldValue, !updating { reload() } } }
    @Published private(set) var rows = 0
    @Published private(set) var cols = 0
    /// Row-major cell texts, rows * cols.
    @Published var cells: [String] = []
    @Published private(set) var status = ""
    @Published private(set) var statusIsError = false
    @Published private(set) var available = true
    @Published private(set) var room = 0
    @Published private(set) var fits = true
    @Published private(set) var previewPool: Pool15?
    @Published private(set) var memoryText = ""
    /// The paste waiting for the preview's "Fill the Grid".
    @Published var pendingPaste: Matrix15.Table?
    private(set) var pendingBad: [String] = []
    /// Set by Edit ▸ Paste Matrix… so the window runs the paste (with its preview) once it is open.
    @Published var wantsPaste = false

    private var image = Data()
    private var variant = 150
    private var updating = false

    init() {}

    var letter: String { Pool15.letters[matrix] }

    func cell(_ r: Int, _ c: Int) -> String {
        let i = r * cols + c
        return i >= 0 && i < cells.count ? cells[i] : ""
    }
    func setCell(_ r: Int, _ c: Int, _ text: String) {
        let i = r * cols + c
        guard i >= 0 && i < cells.count else { return }
        cells[i] = text
    }
    func isBad(_ r: Int, _ c: Int) -> Bool { Matrix15.value(cell(r, c)) == nil }

    /// Rows and columns from the steppers: like a spreadsheet, cells keep their row and column; new ones are empty (= 0).
    func setSize(rows r: Int, cols c: Int) {
        let r = max(0, min(Matrix15.maxSide, r)), c = max(0, min(Matrix15.maxSide, c))
        var out = [String](repeating: "", count: r * c)
        for i in 0..<min(r, rows) { for j in 0..<min(c, cols) { out[i * c + j] = cell(i, j) } }
        rows = r; cols = c; cells = out
        updateMemory()
    }

    func setAvailable(_ on: Bool, why: String? = nil) {
        available = on
        if !on { setStatus(why ?? "The Matrix Editor needs the HP-15C (switch the model back to the 15C).", error: true) }
        else { reload() }
    }

    /// Fetch the memory again and open the selected matrix ("Open from Memory").
    func reload() {
        image = Data()
        guard let got = hooks.fetch() else {
            previewPool = nil
            setStatus("The emulator's memory could not be read (is the calculator running as an HP-15C?).", error: true); return
        }
        image = got.image; variant = got.variant
        guard let s = Matrix15.read(image, variant: variant, matrix: matrix) else {
            setStatus("This memory is not an HP-15C memory.", error: true); return
        }
        fill(rows: s.rows, cols: s.cols, cells: s.raw.map(Matrix15.cellText))
        setStatus(s.rows * s.cols > 0 ? "Matrix \(letter) (\(s.rows) × \(s.cols)) from the emulator's memory."
                  : "Matrix \(letter) is not dimensioned (0 × 0). Set rows and columns, type or paste the values, then Apply.", error: false)
    }

    private func fill(rows r: Int, cols c: Int, cells t: [String]) {
        updating = true
        rows = r; cols = c; cells = t
        updating = false
        updateMemory()
    }

    func updateMemory() {
        guard !image.isEmpty else { previewPool = nil; memoryText = ""; return }
        room = Matrix15.room(image, variant: variant, matrix: matrix)
        fits = rows * cols <= room
        previewPool = fits ? Matrix15.poolAfter(image, variant: variant, matrix: matrix, rows: rows, cols: cols) : Matrix15.pool(image, variant: variant)
        let now = Matrix15.pool(image, variant: variant)
        if fits {
            memoryText = "\(rows) × \(cols) = \(rows * cols) registers; matrix \(letter) can have up to \(room) here (g MEM now \(now?.gmem ?? "?")). The bar shows the memory after Apply."
        } else {
            memoryText = "\(rows) × \(cols) = \(rows * cols) registers does not fit: only \(room) are free for matrix \(letter) (the calculator would show Error 10)."
        }
    }

    private func setStatus(_ t: String, error: Bool) { status = t; statusIsError = error }

    /// The values of the grid, or the first bad cell's message.
    func collect() -> Result<[UInt64], Matrix15.WriteError> {
        var raw: [UInt64] = []
        for r in 0..<rows { for c in 0..<cols {
            switch Matrix15.parseCell(cell(r, c)) {
            case .success(let v): raw.append(v)
            case .failure(let e):
                return .failure(.message("Row \(r + 1), column \(c + 1): “\(cell(r, c))” is \(e.text). Use numbers like 1.5, 1,5 or 2E-3."))
            }
        } }
        return .success(raw)
    }

    /// Validate and write. False (and why in the status line) when nothing was written.
    @discardableResult
    func applyNow() -> Bool {
        guard available else { return false }
        let raw: [UInt64]
        switch collect() {
        case .success(let v): raw = v
        case .failure(let e): setStatus(e.errorDescription ?? "", error: true); return false
        }
        // check against the memory as it is now (the calculator may have run since the window opened)
        if let got = hooks.fetch() { image = got.image; variant = got.variant }
        var test = image
        let m = matrix, r = rows, c = cols
        do { try Matrix15.write(&test, variant: variant, matrix: m, rows: r, cols: c, raw: raw) }
        catch { setStatus((error as? LocalizedError)?.errorDescription ?? "\(error)", error: true); updateMemory(); return false }
        setStatus("Writing…", error: false)
        hooks.apply(m, r, c, raw) { [weak self] err in
            guard let self else { return }
            if let err { self.setStatus(err, error: true); return }
            if let got = self.hooks.fetch() { self.image = got.image; self.variant = got.variant }
            self.updateMemory()
            let L = Pool15.letters[m]
            self.setStatus(r * c > 0 ? "Matrix \(L) (\(r) × \(c)) is now in the emulator's memory. To send it to the real calculator: Calculator ▸ Real Calculator (USB) ▸ Write to Calculator…"
                           : "Matrix \(L) was set to 0 × 0 (its registers are free again).", error: false)
        }
        return true
    }

    /// The grid as Copy puts it on the clipboard (the calculator's own digits where a cell is a number).
    var tsv: String {
        (0..<rows).map { r in
            (0..<cols).map { c in let t = cell(r, c); return Matrix15.value(t).map(Matrix15.cellText) ?? t }.joined(separator: "\t")
        }.joined(separator: "\n")
    }

    func copyTSV() {
        hooks.copyText(tsv)
        setStatus("Copied \(rows) × \(cols) cells (tab-separated): paste them into a spreadsheet.", error: false)
    }

    /// Paste Matrix: read the clipboard and show the preview (pendingPaste); fillFromPaste() takes it.
    func pasteMatrix() {
        guard available else { return }
        let t = Matrix15.parseTable(hooks.clipboardText())
        guard t.ok else { setStatus(t.error.isEmpty ? "The clipboard holds no cells." : t.error, error: true); return }
        pendingBad = Matrix15.badCells(t)
        pendingPaste = t
    }

    /// The preview's headline (size, ragged rows, memory, bad cells).
    var pastePreviewText: String {
        guard let t = pendingPaste else { return "" }
        var s = "\(t.rows) rows × \(t.cols) columns from the clipboard, for matrix \(letter)."
        if t.ragged { s += "\nThe rows have different lengths: the missing cells become 0." }
        let need = t.rows * t.cols, avail = image.isEmpty ? -1 : Matrix15.room(image, variant: variant, matrix: matrix)
        if avail >= 0 && need > avail { s += "\n\(need) registers needed, only \(avail) free for this matrix: Apply will refuse it until it is smaller." }
        if !pendingBad.isEmpty {
            s += "\n\(pendingBad.count) cell(s) are not real numbers (marked red; fix them before Apply): "
                + pendingBad.prefix(4).joined(separator: "; ") + (pendingBad.count > 4 ? " …" : "")
        }
        return s
    }

    func fillFromPaste() {
        guard let t = pendingPaste else { return }
        pendingPaste = nil
        fill(rows: t.rows, cols: t.cols, cells: t.cells)
        let bad = pendingBad.count
        setStatus("Pasted \(t.rows) × \(t.cols) cells into the grid\(bad == 0 ? "" : " (\(bad) to fix, marked red)"). Apply puts them into matrix \(letter).", error: bad > 0)
    }

    func cancelPaste() { pendingPaste = nil }
}
