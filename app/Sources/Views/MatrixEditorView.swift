// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// MatrixEditorView.swift - the HP-15C Matrix Editor window (Mac, 0.7.1; port of the Qt MatrixEditor): matrix A–E, size with
// the free-memory bar, a spreadsheet-style real-only grid (Tab moves right, Return moves down), Paste Matrix with a preview,
// Copy (tab-separated), Open from Memory, Apply.

#if os(macOS)
import SwiftUI
import AppKit

struct MatrixEditorView: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var editor: MatrixEditorModel
    @FocusState private var focus: Int?
    @Environment(\.dismiss) private var dismiss

    static let windowID = "matrixEditor"
    static let cellWidth: CGFloat = 92, cellHeight: CGFloat = 24, headerWidth: CGFloat = 34

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            top
            if let p = editor.previewPool {
                PoolBar(pool: p).padding(.top, 2)
                Text(p.caption).font(.system(size: 11)).monospaced().foregroundStyle(.secondary)
            }
            Text(editor.memoryText)
                .font(.callout)
                .foregroundStyle(editor.fits ? Color.secondary : Color(rgb: 0xC0392B))
                .fixedSize(horizontal: false, vertical: true)
            grid
            Text(editor.status)
                .font(.callout)
                .foregroundStyle(editor.statusIsError ? Color(rgb: 0xC0392B) : Color.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            bottom
        }
        .padding(14)
        .frame(minWidth: 560, minHeight: 460)
        .disabled(false)
        .onAppear {
            editor.setAvailable(app.isMatrixEditorAvailable)
            if editor.wantsPaste { editor.wantsPaste = false; editor.pasteMatrix() }
        }
        .onChange(of: app.isMatrixEditorAvailable) { _, on in editor.setAvailable(on) }
        .onChange(of: editor.wantsPaste) { _, want in if want { editor.wantsPaste = false; editor.pasteMatrix() } }
        .sheet(item: Binding(get: { editor.pendingPaste.map(PastePreview.init) }, set: { if $0 == nil { editor.cancelPaste() } })) { p in
            PastePreviewSheet(editor: editor, table: p.table)
        }
    }

    private var top: some View {
        HStack(spacing: 10) {
            Picker("", selection: $editor.matrix) {
                ForEach(0..<5, id: \.self) { Text("Matrix \(Pool15.letters[$0])").tag($0) }
            }
            .labelsHidden()
            .frame(width: 120)
            Text("Rows")
            sizeField(value: editor.rows) { editor.setSize(rows: $0, cols: editor.cols) }
            Text("×  Columns")
            sizeField(value: editor.cols) { editor.setSize(rows: editor.rows, cols: $0) }
            Spacer()
            Button("Open from Memory") { editor.reload() }
                .help("Show the selected matrix as it is in the emulator's memory now")
        }
        .disabled(!editor.available)
    }

    private func sizeField(value: Int, set: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 2) {
            TextField("", value: Binding(get: { value }, set: { set($0) }), format: .number)
                .frame(width: 40)
                .multilineTextAlignment(.trailing)
            Stepper("", value: Binding(get: { value }, set: { set($0) }), in: 0...Matrix15.maxSide).labelsHidden()
        }
    }

    private var grid: some View {
        let rows = editor.rows, cols = editor.cols
        return ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                HStack(spacing: 0) {
                    Text("").frame(width: Self.headerWidth)
                    ForEach(0..<cols, id: \.self) { c in
                        Text("\(c + 1)").font(.caption).foregroundStyle(.secondary).frame(width: Self.cellWidth, height: 18)
                    }
                }
                ForEach(0..<rows, id: \.self) { r in
                    HStack(spacing: 0) {
                        Text("\(r + 1)").font(.caption).foregroundStyle(.secondary).frame(width: Self.headerWidth, height: Self.cellHeight)
                        ForEach(0..<cols, id: \.self) { c in cellField(r, c, rows: rows, cols: cols) }
                    }
                }
            }
            .padding(4)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.4)))
        .frame(minHeight: 200)
        .disabled(!editor.available)
    }

    private func cellField(_ r: Int, _ c: Int, rows: Int, cols: Int) -> some View {
        let i = r * cols + c
        let bad = editor.isBad(r, c)
        return TextField("0", text: Binding(get: { editor.cell(r, c) }, set: { editor.setCell(r, c, $0) }))
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .font(.system(size: 12).monospacedDigit())
            .padding(.horizontal, 4)
            .frame(width: Self.cellWidth, height: Self.cellHeight)
            .background(bad ? Color(rgb: 0xF5B7B1) : Color.clear)
            .foregroundStyle(bad ? Color(rgb: 0x1A1A1A) : Color.primary)
            .overlay(Rectangle().stroke(Color.secondary.opacity(focus == i ? 0.9 : 0.25), lineWidth: focus == i ? 1.5 : 0.5))
            .help(bad ? "“\(editor.cell(r, c))” is \(Matrix15.parseCell(editor.cell(r, c)).errorText)" : "")
            .focused($focus, equals: i)
            .onSubmit {
                // Return moves down (then to the top of the next column), like a spreadsheet
                var nr = r + 1, nc = c
                if nr >= rows { nr = 0; nc = c + 1 >= cols ? 0 : c + 1 }
                focus = nr * cols + nc
            }
    }

    private var bottom: some View {
        HStack {
            Button("Paste Matrix…") { editor.pasteMatrix() }
                .help("Fill the grid from a range copied in Numbers, Excel, LibreOffice Calc or Google Sheets (tab-separated); the size is taken from the range")
                .disabled(!editor.available)
            Button("Copy") { editor.copyTSV() }
                .help("Copy the grid for a spreadsheet (tab-separated, the calculator's own digits)")
            Spacer()
            Button("Apply") { editor.applyNow() }
                .help("Put this matrix into the emulator's memory (then Real Calculator (USB) ▸ Write to Calculator… sends it)")
                .disabled(!editor.available || !editor.fits)
            Button("Close") { dismiss() }
        }
    }
}

private struct PastePreview: Identifiable {
    let table: Matrix15.Table
    var id: String { "\(table.rows)x\(table.cols)-\(table.cells.hashValue)" }
}

/// The preview before Paste Matrix fills the grid.
struct PastePreviewSheet: View {
    @ObservedObject var editor: MatrixEditorModel
    let table: Matrix15.Table

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Paste Matrix").font(.headline)
            Text(editor.pastePreviewText).fixedSize(horizontal: false, vertical: true)
            ScrollView([.horizontal, .vertical]) {
                Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    ForEach(0..<table.rows, id: \.self) { r in
                        GridRow {
                            ForEach(0..<table.cols, id: \.self) { c in
                                let t = table.cell(r, c)
                                Text(t.isEmpty ? " " : t)
                                    .font(.system(size: 12).monospacedDigit())
                                    .frame(width: 84, height: 22, alignment: .trailing)
                                    .padding(.horizontal, 3)
                                    .background(Matrix15.value(t) == nil ? Color(rgb: 0xF5B7B1) : Color.clear)
                                    .overlay(Rectangle().stroke(Color.secondary.opacity(0.25), lineWidth: 0.5))
                            }
                        }
                    }
                }
            }
            .frame(minHeight: 140)
            HStack {
                Spacer()
                Button("Cancel") { editor.cancelPaste() }.keyboardShortcut(.cancelAction)
                Button("Fill the Grid") { editor.fillFromPaste() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(minWidth: 480, minHeight: 320)
    }
}

extension Result where Success == UInt64, Failure == Matrix15.CellError {
    var errorText: String { if case .failure(let e) = self { return e.text }; return "" }
}
#endif
