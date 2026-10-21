// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// PDFWriter.swift - a small PDF 1.4 writer in plain Swift (no PDFKit / CoreText), so the program
// documentation is made the same way on the Mac, iOS and in the Linux tests: pages of rectangles,
// lines and text in the standard PDF fonts (Helvetica, Helvetica-Bold, Courier, Courier-Bold,
// Symbol; nothing embedded). Text is laid out here with the fonts' own metrics. The calculator
// legends' special characters are drawn from Symbol (Σ π √ ∫ ≤ ≠ ← →) or built: ˣ ʸ ⁻ as
// superscripts, ₓ as subscript, x̄ / x̂ as accents over the letter, ≷ as a small > over <.
// 0.5.7: TrueType fonts (the HP 15C key-cap font, a seven-segment display font; bundled with the
// app since 0.6.7) can be added (PDFFontSet); they are embedded as subsets (Type0 / CIDFontType2, Identity-H, with
// a ToUnicode map so the text can still be searched and copied). Without them the standard
// fonts are used.
// Coordinates: points, origin top-left, y downwards (converted when written).

import Foundation

public enum PDFPaper: String, CaseIterable, Codable, Sendable {
    case a4, letter
    public var size: (width: Double, height: Double) { self == .a4 ? (595.28, 841.89) : (612, 792) }
    public var title: String { self == .a4 ? "A4" : "US Letter" }
}

public enum PDFFace: Int, Sendable, CaseIterable { case regular = 1, bold, mono, monoBold, symbol, keys, display
    var isEmbedded: Bool { self == .keys || self == .display }
    /// What a character the embedded font lacks is drawn with.
    var fallback: PDFFace { self == .display ? .monoBold : self == .keys ? .regular : self }
}

/// The user's TrueType fonts for a document, and which glyphs were drawn (for the subset).
public final class PDFFontSet: @unchecked Sendable {
    public private(set) var embedded: [PDFFace: TrueTypeFont] = [:]
    var used: [PDFFace: [UInt16: String]] = [:]
    public init(keys: TrueTypeFont? = nil, display: TrueTypeFont? = nil) {
        if let keys { embedded[.keys] = keys }
        if let display { embedded[.display] = display }
    }
    public func has(_ f: PDFFace) -> Bool { embedded[f] != nil }
    func mark(_ f: PDFFace, _ gid: UInt16, _ text: String) {
        if used[f, default: [:]][gid] == nil { used[f, default: [:]][gid] = text }
    }
}

public struct PDFColor: Sendable, Equatable {
    public var r, g, b: Double
    public init(_ hex: UInt32) {
        r = Double(hex >> 16 & 0xFF) / 255; g = Double(hex >> 8 & 0xFF) / 255; b = Double(hex & 0xFF) / 255
    }
    public static let black = PDFColor(0x000000)
}

public struct PDFStyle: Sendable {
    public var face: PDFFace
    public var size: Double
    public var color: PDFColor
    public init(_ face: PDFFace, _ size: Double, _ color: PDFColor = .black) { self.face = face; self.size = size; self.color = color }
}

/// One drawn glyph: font, encoded byte, scale and rise (in em of the style size).
struct PDFGlyph {
    var face: PDFFace
    var code: UInt16             // byte of a standard font, glyph number of an embedded one
    var scale = 1.0
    var rise = 0.0
    var overlay = false          // drawn centred over the previous glyph, no advance
    var adv = 0.0                // advance, 1/1000 em
    var text = ""                // what it means (embedded fonts: the ToUnicode text)
    var byte: UInt8 { UInt8(truncatingIfNeeded: code) }

    init(face: PDFFace, byte: UInt8, scale: Double = 1, rise: Double = 0, overlay: Bool = false) {
        self.face = face; self.code = UInt16(byte); self.scale = scale; self.rise = rise; self.overlay = overlay
        let table: [UInt16]
        switch face {
        case .regular, .keys: table = PDFFontMetrics.helvetica
        case .bold: table = PDFFontMetrics.helveticaBold
        case .mono, .monoBold, .display: table = PDFFontMetrics.courier
        case .symbol: table = PDFFontMetrics.symbol
        }
        adv = Double(table[Int(byte)])
    }
    init(embedded face: PDFFace, gid: UInt16, adv: Double, text: String, scale: Double = 1, rise: Double = 0) {
        self.face = face; self.code = gid; self.adv = adv; self.text = text; self.scale = scale; self.rise = rise
    }
    func width(_ size: Double) -> Double { adv / 1000 * size * scale }
}

enum PDFText {
    static let symbol: [UInt32: UInt8] = [
        0x03A3: 0x53, 0x2211: 0x53, 0x0394: 0x44, 0x2206: 0x44, 0x03C0: 0x70, 0x221A: 0xD6, 0x222B: 0xF2,
        0x2260: 0xB9, 0x2264: 0xA3, 0x2265: 0xB3, 0x2190: 0xAC, 0x2B05: 0xAC, 0x2191: 0xAD, 0x2192: 0xAE,
        0x2193: 0xAF, 0x2212: 0x2D, 0x221E: 0xA5, 0x2248: 0xBB, 0x03B1: 0x61, 0x03B2: 0x62, 0x03BC: 0x6D,
        0x03B8: 0x71, 0x03BB: 0x6C, 0x03C3: 0x73, 0x2194: 0xAB, 0x21D2: 0xDE,
    ]
    static let cp1252: [UInt32: UInt8] = [
        0x20AC: 0x80, 0x201A: 0x82, 0x0192: 0x83, 0x201E: 0x84, 0x2026: 0x85, 0x2020: 0x86, 0x2021: 0x87,
        0x02C6: 0x88, 0x2030: 0x89, 0x0160: 0x8A, 0x2039: 0x8B, 0x0152: 0x8C, 0x017D: 0x8E, 0x2018: 0x91,
        0x2019: 0x92, 0x201C: 0x93, 0x201D: 0x94, 0x2022: 0x95, 0x2013: 0x96, 0x2014: 0x97, 0x02DC: 0x98,
        0x2122: 0x99, 0x0161: 0x9A, 0x203A: 0x9B, 0x0153: 0x9C, 0x017E: 0x9E, 0x0178: 0x9F,
    ]
    static func winAnsi(_ v: UInt32) -> UInt8? {
        if v >= 0x20 && v < 0x7F { return UInt8(v) }
        if v >= 0xA0 && v <= 0xFF { return UInt8(v) }
        return cp1252[v]
    }

    /// The glyphs for a string in a face (regular / bold / mono / monoBold).
    static func shape(_ s: String, _ face: PDFFace, _ fonts: PDFFontSet? = nil) -> [PDFGlyph] {
        if face.isEmbedded {
            guard let f = fonts?.embedded[face] else { return shape(s, face.fallback) }
            var out: [PDFGlyph] = []
            for u in s.unicodeScalars {
                let g = f.glyph(for: u)
                if f.has(u) { out.append(PDFGlyph(embedded: face, gid: g, adv: f.advance(g), text: String(u))) }
                else { out += shape(String(u), face.fallback) }
            }
            return out
        }
        var out: [PDFGlyph] = []
        func plain(_ b: UInt8, scale: Double = 1, rise: Double = 0, overlay: Bool = false) {
            out.append(PDFGlyph(face: face, byte: b, scale: scale, rise: rise, overlay: overlay))
        }
        func scalar(_ u: Unicode.Scalar) {
            let v = u.value
            switch v {
            case 0x0A, 0x0D, 0x09: plain(0x20)
            case 0x02E3: plain(0x78, scale: 0.65, rise: 0.38)                    // ˣ
            case 0x02B8: plain(0x79, scale: 0.65, rise: 0.38)                    // ʸ
            case 0x207B: plain(0x2D, scale: 0.75, rise: 0.30)                    // ⁻
            case 0x2093: plain(0x78, scale: 0.65, rise: -0.14)                   // ₓ
            case 0x0304: plain(0xAF, overlay: true)                              // combining macron: x̄
            case 0x0302: plain(0x88, overlay: true)                              // combining circumflex: x̂ ŷ
            case 0x2277:                                                         // ≷: > over <
                plain(0x3E, scale: 0.62, rise: 0.40)
                plain(0x3C, scale: 0.62, rise: -0.02, overlay: true)
            default:
                if let b = winAnsi(v) { plain(b) }
                else if let b = symbol[v] { out.append(PDFGlyph(face: .symbol, byte: b)) }
                else {
                    let d = String(Character(u)).decomposedStringWithCanonicalMapping.unicodeScalars
                    if d.count > 1 { d.forEach(scalar) } else { plain(0x3F) }      // "?" for anything else
                }
            }
        }
        s.unicodeScalars.forEach(scalar)
        return out
    }

    /// Glyphs with their x offsets from the start, and the total advance.
    static func place(_ g: [PDFGlyph], _ size: Double) -> ([(Double, PDFGlyph)], Double) {
        var x = 0.0, lastX = 0.0, lastW = 0.0
        var out: [(Double, PDFGlyph)] = []
        for gl in g {
            let w = gl.width(size)
            if gl.overlay { out.append((lastX + (lastW - w) / 2, gl)); continue }
            out.append((x, gl)); lastX = x; lastW = w; x += w
        }
        return (out, x)
    }

    static func width(_ s: String, _ st: PDFStyle, _ fonts: PDFFontSet? = nil) -> Double { place(shape(s, st.face, fonts), st.size).1 }

    /// Wrap text to a width: paragraphs at newlines, then words; a word wider than the line is cut.
    static func wrap(_ s: String, _ st: PDFStyle, _ width: Double, _ fonts: PDFFontSet? = nil) -> [String] {
        var lines: [String] = []
        for para in s.components(separatedBy: "\n") {
            var cur = ""
            for word in para.split(separator: " ", omittingEmptySubsequences: false).map(String.init) {
                let cand = cur.isEmpty ? word : cur + " " + word
                if Self.width(cand, st, fonts) <= width || cur.isEmpty && Self.width(word, st, fonts) <= width { cur = cand; continue }
                if !cur.isEmpty { lines.append(cur); cur = "" }
                var w = word
                while Self.width(w, st, fonts) > width, w.count > 1 {             // cut a too-long word
                    var n = w.count - 1
                    while n > 1, Self.width(String(w.prefix(n)), st, fonts) > width { n -= 1 }
                    lines.append(String(w.prefix(n))); w = String(w.dropFirst(n))
                }
                cur = w
            }
            lines.append(cur)
        }
        return lines
    }

    static func pdfString(_ bytes: [UInt8]) -> String {
        var s = "("
        for b in bytes {
            switch b {
            case 0x28, 0x29, 0x5C: s += "\\" + String(UnicodeScalar(b))
            case 0x20...0x7E: s += String(UnicodeScalar(b))
            default: s += String(format: "\\%03o", b)
            }
        }
        return s + ")"
    }
}

/// One page being drawn.
public final class PDFPage {
    public let width: Double, height: Double
    var ops: [String] = []
    let fonts: PDFFontSet
    init(width: Double, height: Double, fonts: PDFFontSet) { self.width = width; self.height = height; self.fonts = fonts }

    private func n(_ v: Double) -> String { String(format: "%.2f", v) }
    private func rgb(_ c: PDFColor, _ op: String) -> String { "\(n(c.r)) \(n(c.g)) \(n(c.b)) \(op)" }

    public func fill(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ c: PDFColor) {
        ops.append("\(rgb(c, "rg")) \(n(x)) \(n(height - y - h)) \(n(w)) \(n(h)) re f")
    }
    public func line(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, width: Double = 0.5, _ c: PDFColor = .black) {
        ops.append("\(rgb(c, "RG")) \(n(width)) w \(n(x1)) \(n(height - y1)) m \(n(x2)) \(n(height - y2)) l S")
    }
    /// Text with its baseline at y. Returns the advance width.
    @discardableResult
    public func text(_ s: String, x: Double, y: Double, _ st: PDFStyle) -> Double {
        draw(PDFText.shape(s, st.face, fonts), x: x, y: y, st)
    }

    /// Glyphs of an embedded font by character, each with the text it stands for (ToUnicode),
    /// e.g. the key-cap glyph "b" of the HP 15C font as "LBL". Missing glyphs: the text instead.
    @discardableResult
    public func glyphs(_ items: [(Character, String)], x: Double, y: Double, _ st: PDFStyle, gap: Double = 0) -> Double {
        draw(Self.glyphRun(items, st, fonts, gap: gap), x: x, y: y, st)
    }
    static func glyphRun(_ items: [(Character, String)], _ st: PDFStyle, _ fonts: PDFFontSet, gap: Double = 0) -> [PDFGlyph] {
        var g: [PDFGlyph] = []
        let f = fonts.embedded[st.face]
        for (i, (c, text)) in items.enumerated() {
            let t = i + 1 < items.count ? text + " " : text
            if let f, let u = c.unicodeScalars.first, f.has(u) {
                let gid = f.glyph(for: u)
                g.append(PDFGlyph(embedded: st.face, gid: gid, adv: f.advance(gid) + gap * 1000 / st.size, text: t))
            } else {
                g += PDFText.shape(t, st.face.fallback)
            }
        }
        return g
    }
    public func glyphsWidth(_ items: [(Character, String)], _ st: PDFStyle, gap: Double = 0) -> Double {
        PDFText.place(Self.glyphRun(items, st, fonts, gap: gap), st.size).1
    }

    @discardableResult
    func draw(_ shaped: [PDFGlyph], x: Double, y: Double, _ st: PDFStyle) -> Double {
        let (placed, w) = PDFText.place(shaped, st.size)
        guard !placed.isEmpty else { return 0 }
        var out = "BT \(rgb(st.color, "rg"))"
        var i = 0
        while i < placed.count {
            // a run: same font, scale and rise, each glyph starting where the previous one ended
            let (x0, g0) = placed[i]
            var run = [g0], end = x0 + g0.width(st.size), j = i + 1
            while j < placed.count, !placed[j].1.overlay, placed[j].1.face == g0.face, placed[j].1.scale == g0.scale,
                  placed[j].1.rise == g0.rise, abs(placed[j].0 - end) < 0.001, !g0.face.isEmbedded {
                run.append(placed[j].1); end += placed[j].1.width(st.size); j += 1
            }
            let size = st.size * g0.scale
            let str: String
            if g0.face.isEmbedded {
                run.forEach { fonts.mark(g0.face, $0.code, $0.text) }
                str = "<" + run.map { String(format: "%04X", $0.code) }.joined() + ">"
            } else {
                str = PDFText.pdfString(run.map(\.byte))
            }
            out += " /F\(g0.face.rawValue) \(n(size)) Tf 1 0 0 1 \(n(x + x0)) \(n(height - y + g0.rise * st.size)) Tm \(str) Tj"
            i = j
        }
        ops.append(out + " ET")
        return w
    }
    public func width(_ s: String, _ st: PDFStyle) -> Double { PDFText.width(s, st, fonts) }
}

/// A PDF made of pages.
public final class PDFDocumentWriter {
    public let paper: PDFPaper
    public var title = ""
    public let fonts: PDFFontSet
    public private(set) var pages: [PDFPage] = []
    public init(paper: PDFPaper, fonts: PDFFontSet = PDFFontSet()) { self.paper = paper; self.fonts = fonts }

    public func newPage() -> PDFPage {
        let p = PDFPage(width: paper.size.width, height: paper.size.height, fonts: fonts); pages.append(p); return p
    }

    public func data() -> Data {
        var objects: [Data] = []                   // object n is objects[n - 1]
        func add(_ s: String) -> Int { objects.append(Data(s.utf8)); return objects.count }
        func addStream(_ dict: String, _ body: Data) -> Int {
            var d = Data("<< \(dict) /Length \(body.count) >>\nstream\n".utf8); d.append(body); d.append(Data("\nendstream".utf8))
            objects.append(d); return objects.count
        }
        let std = ["Helvetica", "Helvetica-Bold", "Courier", "Courier-Bold", "Symbol"]
        // pages are numbered after the fonts: reserve 1 (catalog), 2 (pages), then the fonts
        _ = add("<< /Type /Catalog /Pages 2 0 R >>")
        _ = add("")                                 // pages, filled in below
        var fontRefs: [String] = []
        for (i, f) in std.enumerated() {
            let enc = f == "Symbol" ? "" : " /Encoding /WinAnsiEncoding"
            let o = add("<< /Type /Font /Subtype /Type1 /Name /F\(i + 1) /BaseFont /\(f)\(enc) >>")
            fontRefs.append("/F\(i + 1) \(o) 0 R")
        }
        for face in [PDFFace.keys, .display] {
            guard let f = fonts.embedded[face], let used = fonts.used[face], !used.isEmpty else { continue }
            let tag = face == .keys ? "VCKEYS" : "VCDISP"
            let base = tag + "+" + (f.postScriptName.isEmpty ? "Font\(face.rawValue)" : f.postScriptName)
            let sub = f.subset(Set(used.keys))
            let file = addStream("/Length1 \(sub.count)", sub)
            let (x0, y0, x1, y1) = f.bbox
            let box: String = [x0, y0, x1, y1].map { String(Int(f.scaled($0))) }.joined(separator: " ")
            let asc = Int(f.scaled(f.ascent)), dsc = Int(f.scaled(f.descent))
            let desc = add("<< /Type /FontDescriptor /FontName /\(base) /Flags 4 /FontBBox [\(box)] /ItalicAngle 0 /Ascent \(asc) /Descent \(dsc) /CapHeight \(asc) /StemV 80 /FontFile2 \(file) 0 R >>")
            let gids = used.keys.sorted()
            let w = gids.map { "\($0) [\(Int(f.advance($0).rounded()))]" }.joined(separator: " ")
            let cid = add("<< /Type /Font /Subtype /CIDFontType2 /BaseFont /\(base) /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> /FontDescriptor \(desc) 0 R /W [\(w)] /CIDToGIDMap /Identity >>")
            var cmap = "/CIDInit /ProcSet findresource begin 12 dict begin begincmap /CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def /CMapName /Adobe-Identity-UCS def /CMapType 2 def 1 begincodespacerange <0000> <FFFF> endcodespacerange\n"
            for chunk in stride(from: 0, to: gids.count, by: 100) {
                let part = gids[chunk..<min(gids.count, chunk + 100)]
                cmap += "\(part.count) beginbfchar\n"
                for g in part {
                    let hex = (used[g] ?? "").utf16.map { String(format: "%04X", $0) }.joined()
                    cmap += String(format: "<%04X> <", g) + (hex.isEmpty ? "0020" : hex) + ">\n"
                }
                cmap += "endbfchar\n"
            }
            cmap += "endcmap CMapName currentdict /CMap defineresource pop end end"
            let tu = addStream("", Data(cmap.utf8))
            let o = add("<< /Type /Font /Subtype /Type0 /BaseFont /\(base) /Encoding /Identity-H /DescendantFonts [\(cid) 0 R] /ToUnicode \(tu) 0 R >>")
            fontRefs.append("/F\(face.rawValue) \(o) 0 R")
        }
        let res = "<< /Font << " + fontRefs.joined(separator: " ") + " >> >>"
        let pageObj0 = objects.count + 1
        let kids = pages.indices.map { "\(pageObj0 + 2 * $0) 0 R" }.joined(separator: " ")
        objects[1] = Data("<< /Type /Pages /Kids [\(kids)] /Count \(pages.count) >>".utf8)
        for (i, p) in pages.enumerated() {
            let content = p.ops.joined(separator: "\n")
            _ = add("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 \(String(format: "%.2f", p.width)) \(String(format: "%.2f", p.height))] /Resources \(res) /Contents \(pageObj0 + 2 * i + 1) 0 R >>")
            _ = addStream("", Data(content.utf8))
        }
        let titleBytes = PDFText.shape(title, .regular).map(\.byte)
        let infoObj = add("<< /Title \(PDFText.pdfString(titleBytes)) >>")
        var out = Data("%PDF-1.4\n%\u{E2}\u{E3}\u{CF}\u{D3}\n".utf8)
        var offsets: [Int] = []
        for (i, o) in objects.enumerated() {
            offsets.append(out.count)
            out.append(Data("\(i + 1) 0 obj\n".utf8)); out.append(o); out.append(Data("\nendobj\n".utf8))
        }
        let xref = out.count
        var x = "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for o in offsets { x += String(format: "%010d 00000 n \n", o) }
        x += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R /Info \(infoObj) 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        out.append(Data(x.utf8))
        return out
    }
}
