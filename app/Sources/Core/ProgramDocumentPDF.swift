// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// ProgramDocumentPDF.swift - the program documentation as a PDF (A4 or US Letter):
//   page 1: title, model, firmware, memory file, step count, date, author, the description;
//   then the labels (defined at, called from, notes), registers and flags (use, steps, meaning),
//   and the listing: step, the display in program mode, the keys with their shift, the comment.
// Every page repeats a header line and is numbered "Page n of N". No branding of any kind.

import Foundation

public enum ProgramDocumentPDF {
    static let ink = PDFColor(0x1A1A1A), grey = PDFColor(0x6B6B6B), rule = PDFColor(0xC9C9C9)
    static let headFill = PDFColor(0xECECEC), labelBand = PDFColor(0xFBF1D9), lcd = PDFColor(0xDFE5D3)
    static let orphanInk = PDFColor(0x9A3B2A)
    static func poolColour(_ k: Pool15.Kind) -> PDFColor {
        switch k {
        case .workspace: return PDFColor(0xC77DCC)
        case .free: return PDFColor(0xE4E4E0)
        case .complex: return PDFColor(0xE07A5F)
        case .storage: return PDFColor(0x5AA9E6)
        case .matrix(let m): return [PDFColor(0xE3A33B), PDFColor(0xD4B04C), PDFColor(0xB9B957), PDFColor(0x9DBF62), PDFColor(0x7FBF73)][m]
        case .program: return PDFColor(0x4CBF6B)
        }
    }

    /// `fonts`: the HP 15C key-cap font and seven-segment display font, when available (0.5.7;
    /// bundled with the app since 0.6.7, so the app always passes them); the display font is used for the Display column of every model, the key caps for
    /// the 15C's Keys column. Without them the standard fonts are used, as in 0.5.6.
    public static func render(_ c: ProgramDocumentContent, paper: PDFPaper = .a4, fonts: PDFFontSet? = nil) -> Data {
        var r = Renderer(content: c, paper: paper, fonts: fonts ?? PDFFontSet())
        r.run()
        return r.writer.data()
    }

    struct Column {
        var title: String; var width: Double; var style: PDFStyle; var fill: PDFColor? = nil
        /// key caps drawn instead of the text (the text then follows small, beside or below)
        var glyphs: ((Int) -> [(Character, String)]?)? = nil
    }
    static let capStyle = PDFStyle(.keys, 10, PDFColor(0x1A1A1A))
    static let capText = PDFStyle(.regular, 7, PDFColor(0x6B6B6B))

    struct Renderer {
        let content: ProgramDocumentContent
        let writer: PDFDocumentWriter
        let W: Double, H: Double
        let left = 46.0, right: Double, top = 58.0, bottom: Double
        var page: PDFPage!
        var y = 0.0

        init(content: ProgramDocumentContent, paper: PDFPaper, fonts: PDFFontSet) {
            self.content = content
            writer = PDFDocumentWriter(paper: paper, fonts: fonts)
            writer.title = content.title
            W = paper.size.width; H = paper.size.height
            right = W - 46; bottom = H - 48
        }
        var width: Double { right - left }

        mutating func newPage() { page = writer.newPage(); y = top }
        mutating func need(_ h: Double) -> Bool {
            if y + h > bottom { newPage(); return true }
            return false
        }

        mutating func run() {
            newPage()
            cover()
            labels()
            registers()
            matrixOps()
            listing()
            orphans()
            // header and page numbers, now that the count is known
            let n = writer.pages.count
            let small = PDFStyle(.regular, 8, ProgramDocumentPDF.grey)
            for (i, p) in writer.pages.enumerated() {
                p.text(content.title, x: left, y: 32, PDFStyle(.bold, 8.5, ProgramDocumentPDF.ink))
                let tag = "\(content.info.modelName) program documentation"
                p.text(tag, x: right - p.width(tag, small), y: 32, small)
                p.line(left, 38, right, 38, width: 0.5, ProgramDocumentPDF.rule)
                let num = "Page \(i + 1) of \(n)"
                p.text(num, x: (W - p.width(num, small)) / 2, y: H - 26, small)
            }
        }

        // MARK: blocks

        mutating func paragraph(_ s: String, _ st: PDFStyle, lineHeight: Double, indent: Double = 0) {
            for l in PDFText.wrap(s, st, width - indent) {
                _ = need(lineHeight)
                page.text(l, x: left + indent, y: y + st.size, st)
                y += lineHeight
            }
        }

        mutating func heading(_ s: String) {
            // keep a heading with its table header and first rows
            if !need(90) { y += 16 }
            page.text(s, x: left, y: y + 13, PDFStyle(.bold, 13, ProgramDocumentPDF.ink))
            y += 19
            page.line(left, y, right, y, width: 0.8, ProgramDocumentPDF.ink)
            y += 8
        }

        mutating func cover() {
            let c = content
            page.text(c.title, x: left, y: y + 22, PDFStyle(.bold, 22, ProgramDocumentPDF.ink))
            y += 32
            page.text("Program documentation", x: left, y: y + 11, PDFStyle(.regular, 11, ProgramDocumentPDF.grey))
            y += 26
            var rows: [(String, String)] = [("Model", c.info.modelName)]
            if !c.info.firmware.isEmpty { rows.append(("Firmware", c.info.firmware)) }
            if !c.info.memoryFile.isEmpty { rows.append(("Memory file", c.info.memoryFile)) }
            rows.append(("Steps", "\(c.lines.count)"))
            rows.append(("Labels", "\(c.analysis.labels.filter { !$0.defined.isEmpty && !$0.isIndirect }.count)"))
            rows.append(("Date", c.info.dateText))
            if !c.doc.author.isEmpty { rows.append(("Author", c.doc.author)) }
            let k = PDFStyle(.regular, 9, ProgramDocumentPDF.grey), v = PDFStyle(.regular, 10, ProgramDocumentPDF.ink)
            page.fill(left, y - 4, width, Double(rows.count) * 15 + 8, PDFColor(0xF5F5F2))
            for (a, b) in rows {
                page.text(a, x: left + 8, y: y + 10, k)
                page.text(b, x: left + 92, y: y + 10, v)
                y += 15
            }
            y += 10
            memory()
            if !c.doc.description.isEmpty {
                heading("Description")
                description(c.doc.description)
            }
        }

        /// The description: "## Usage" lines (or a line ending in ":") are subheadings, "- " bullets.
        mutating func description(_ text: String) {
            let body = PDFStyle(.regular, 10, ProgramDocumentPDF.ink)
            for raw in text.components(separatedBy: "\n") {
                let l = raw.trimmingCharacters(in: .whitespaces)
                if l.isEmpty { y += 6; continue }
                if l.hasPrefix("#") {
                    let t = l.drop { $0 == "#" || $0 == " " }
                    _ = need(30); y += 6
                    paragraph(String(t), PDFStyle(.bold, 10.5, ProgramDocumentPDF.ink), lineHeight: 14)
                } else if l.hasPrefix("- ") || l.hasPrefix("• ") {
                    _ = need(13)
                    page.text("•", x: left + 4, y: y + 10, body)
                    paragraph(String(l.dropFirst(2)), body, lineHeight: 13, indent: 14)
                } else {
                    paragraph(l, body, lineHeight: 13)
                }
            }
        }

        // MARK: tables

        mutating func tableHeader(_ cols: [Column]) {
            let h = 15.0
            page.fill(left, y, width, h, ProgramDocumentPDF.headFill)
            var x = left
            for c in cols {
                page.text(c.title, x: x + 4, y: y + 10.5, PDFStyle(.bold, 8.5, ProgramDocumentPDF.ink))
                x += c.width
            }
            y += h
        }

        /// Rows of cells (wrapped); the header is repeated on every page the table runs onto.
        mutating func table(_ title: String, _ cols: [Column], _ rows: [[String]], band: (Int) -> PDFColor? = { _ in nil },
                            styles: (Int, Int) -> PDFStyle? = { _, _ in nil }) {
            _ = need(15 + 2 * 14)
            tableHeader(cols)
            for (ri, row) in rows.enumerated() {
                // key caps: (glyphs, text beside them?) per column
                var caps: [Int: ([(Character, String)], Bool)] = [:]
                for (i, c) in cols.enumerated() {
                    guard let g = c.glyphs?(ri) else { continue }
                    let w = page.glyphsWidth(g, ProgramDocumentPDF.capStyle, gap: 1)
                    let beside = w + 5 + page.width(row[i], ProgramDocumentPDF.capText) <= c.width - 8
                    caps[i] = (g, beside)
                }
                let wrapped: [[String]] = row.enumerated().map { i, s in
                    if caps[i] != nil { return [] }
                    let st = styles(ri, i) ?? cols[i].style
                    return PDFText.wrap(s, st, cols[i].width - 8)
                }
                let lineH = 11.5
                var h = Double(max(1, wrapped.map(\.count).max() ?? 1)) * lineH + 3
                for (_, (_, beside)) in caps { h = max(h, beside ? 15 : 23) }
                if need(h) {
                    page.text("\(title) (continued)", x: left, y: y + 9, PDFStyle(.regular, 8.5, ProgramDocumentPDF.grey))
                    y += 14
                    tableHeader(cols)
                }
                if let b = band(ri) { page.fill(left, y, width, h, b) }
                var x = left
                for (i, c) in cols.enumerated() {
                    if let f = c.fill { page.fill(x + 2, y + 1.5, c.width - 4, h - 3, f) }
                    let st = styles(ri, i) ?? c.style
                    if let (g, beside) = caps[i] {
                        let w = page.glyphs(g, x: x + 4, y: y + 11, ProgramDocumentPDF.capStyle, gap: 1)
                        if beside { page.text(row[i], x: x + 4 + w + 5, y: y + 10.5, ProgramDocumentPDF.capText) }
                        else { page.text(row[i], x: x + 4, y: y + 20, ProgramDocumentPDF.capText) }
                    }
                    for (li, l) in wrapped[i].enumerated() {
                        page.text(l, x: x + 4, y: y + 10 + Double(li) * lineH, st)
                    }
                    x += c.width
                }
                y += h
                page.line(left, y, right, y, width: 0.3, ProgramDocumentPDF.rule)
            }
        }

        /// HP-15C memory configuration from the loaded memory, with a small pool bar (0.6.0).
        mutating func memory() {
            let rows = content.memoryRows
            guard !rows.isEmpty, let p = content.pool else { return }
            heading("Memory configuration")
            let k = PDFStyle(.regular, 9, ProgramDocumentPDF.grey), v = PDFStyle(.regular, 9.5, ProgramDocumentPDF.ink)
            for (a, b) in rows {
                let wrapped = PDFText.wrap(b, v, width - 100, writer.fonts)
                _ = need(Double(wrapped.count) * 12.5)
                page.text(a, x: left + 4, y: y + 9.5, k)
                for (i, l) in wrapped.enumerated() { page.text(l, x: left + 100, y: y + 9.5 + Double(i) * 12.5, v) }
                y += Double(wrapped.count) * 12.5
            }
            // the pool, bottom of memory on the left
            _ = need(40)
            y += 6
            let segs = p.segments, total = Double(max(1, segs.map(\.count).reduce(0, +)))
            var x = left
            for sg in segs {
                let w = width * Double(sg.count) / total
                page.fill(x, y, max(0.8, w - 0.6), 10, ProgramDocumentPDF.poolColour(sg.kind))
                x += w
            }
            y += 22
            // legend
            var lx = left
            var seen = Set<String>()
            let small = PDFStyle(.regular, 7.5, ProgramDocumentPDF.grey)
            for sg in segs {
                let name: String
                if case .matrix = sg.kind { name = "matrices" } else { name = sg.kind == .storage ? "R2…" : sg.kind.title }
                guard !seen.contains(name) else { continue }
                seen.insert(name)
                let n = segs.filter { a in
                    if case .matrix = a.kind, name == "matrices" { return true }
                    return a.kind == sg.kind
                }.map(\.count).reduce(0, +)
                let t = "\(name) \(n)"
                page.fill(lx, y - 6.5, 7, 7, ProgramDocumentPDF.poolColour(sg.kind))
                page.text(t, x: lx + 10, y: y, small)
                lx += 10 + page.width(t, small) + 12
            }
            y += 10
        }

        mutating func matrixOps() {
            let rows = content.matrixOpRows
            guard !rows.isEmpty else { return }
            heading("Matrices and complex")
            let s = PDFStyle(.regular, 9, ProgramDocumentPDF.ink)
            table("Matrices and complex", [Column(title: "Item", width: 84, style: PDFStyle(.bold, 9, ProgramDocumentPDF.ink)),
                                           Column(title: "Operations", width: 120, style: s),
                                           Column(title: "Steps", width: 100, style: s),
                                           Column(title: "Notes", width: width - 304, style: s)],
                  rows.map { [$0.item, $0.operations, $0.steps, $0.notes] })
        }

        mutating func labels() {
            let rows = content.labelRows
            guard !rows.isEmpty else { return }
            heading(content.info.model == 12 ? "Branch targets" : "Labels")
            let s = PDFStyle(.regular, 9, ProgramDocumentPDF.ink)
            let w = width
            table("Labels", [Column(title: content.info.model == 12 ? "Line" : "Label", width: 64, style: PDFStyle(.bold, 9, ProgramDocumentPDF.ink)),
                             Column(title: "Defined at", width: 62, style: s),
                             Column(title: "Called from", width: 150, style: s),
                             Column(title: "Notes", width: w - 276, style: s)],
                  rows.map { [$0.label, $0.defined, $0.called, $0.notes] },
                  styles: { r, i in i == 1 && rows[r].defined == "not defined" ? PDFStyle(.regular, 9, ProgramDocumentPDF.orphanInk) : nil })
        }

        mutating func registers() {
            let rows = content.registerRows + content.flagRows
            guard !rows.isEmpty else { return }
            heading(content.flagRows.isEmpty ? "Registers" : "Registers and flags")
            let s = PDFStyle(.regular, 9, ProgramDocumentPDF.ink)
            table("Registers", [Column(title: "Register", width: 64, style: PDFStyle(.bold, 9, ProgramDocumentPDF.ink)),
                                Column(title: "Name / meaning", width: width - 64 - 112 - 140, style: s),
                                Column(title: "Use", width: 112, style: s),
                                Column(title: "Steps", width: 140, style: s)],
                  rows.map { [$0.register, $0.name, $0.use, $0.steps] })
        }

        mutating func listing() {
            let rows = content.listingRows
            heading("Program listing")
            guard !rows.isEmpty else {
                paragraph("The calculator holds no program.", PDFStyle(.regular, 10, ProgramDocumentPDF.grey), lineHeight: 13); return
            }
            let s = PDFStyle(.regular, 9, ProgramDocumentPDF.ink)
            let screenW = content.info.model == 12 ? 82.0 : 92.0
            let fonts = writer.fonts
            let screen = fonts.has(.display) ? PDFStyle(.display, 11, ProgramDocumentPDF.ink) : PDFStyle(.monoBold, 9, ProgramDocumentPDF.ink)
            let lines = content.lines
            let useCaps = content.info.model == 15 && fonts.has(.keys)
            let keysW = useCaps ? 150.0 : 104.0
            var keys = Column(title: "Keys", width: keysW, style: s)
            if useCaps { keys.glyphs = { HP15CKeyGlyphs.glyphs(for: lines[$0]) } }
            table("Program listing", [Column(title: "Step", width: 34, style: PDFStyle(.regular, 9, ProgramDocumentPDF.grey)),
                                      Column(title: "Display", width: screenW, style: screen, fill: ProgramDocumentPDF.lcd),
                                      keys,
                                      Column(title: "Comment", width: width - 34 - screenW - keysW, style: s)],
                  rows.map { [$0.step, $0.screen, $0.keys, $0.comment] },
                  band: { rows[$0].isLabel ? ProgramDocumentPDF.labelBand : nil },
                  styles: { r, i in i == 2 && rows[r].isLabel ? PDFStyle(.bold, 9, ProgramDocumentPDF.ink) : nil })
        }

        mutating func orphans() {
            let o = content.doc.orphanedComments
            guard !o.isEmpty else { return }
            heading("Comments that no longer match a step")
            let s = PDFStyle(.regular, 9, ProgramDocumentPDF.ink)
            table("Comments", [Column(title: "Was step", width: 52, style: PDFStyle(.regular, 9, ProgramDocumentPDF.grey)),
                               Column(title: "Keys then", width: 92, style: PDFStyle(.mono, 9, ProgramDocumentPDF.ink)),
                               Column(title: "Comment", width: width - 144, style: s)],
                  o.map { [String(format: "%03d", $0.step), $0.keys, $0.text] })
        }
    }
}
