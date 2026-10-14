// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// TrueTypeFont.swift - just enough TrueType for the PDF writer (0.5.7): read a .ttf (or its
// tables, as CoreText hands them out), map characters to glyphs (cmap format 4 / 6 / 0),
// advance widths, and write a subset: the same glyph numbers, with only the glyphs used kept
// (all others empty), so a PDF embeds a few KB of the font, never the whole file.
// The user's fonts are never bundled with the app; they are read from the user's own copy.

import Foundation

public struct TrueTypeFont: Sendable {
    public enum FontError: Error { case notTrueType, missingTable(String) }

    public let tables: [String: Data]
    public let unitsPerEm: Int
    public let numGlyphs: Int
    public let ascent: Int, descent: Int
    public let bbox: (Int, Int, Int, Int)
    public let postScriptName: String
    public let familyName: String
    private let advances: [Int]
    private let cmap: [UInt32: UInt16]
    private let glyphOffsets: [Int]          // numGlyphs + 1 offsets into glyf

    public init(data: Data) throws {
        let d = [UInt8](data)
        guard d.count > 12 else { throw FontError.notTrueType }
        let tag = Self.u32(d, 0)
        guard tag == 0x00010000 || tag == 0x74727565 else { throw FontError.notTrueType }   // 1.0 or 'true'
        var t: [String: Data] = [:]
        let n = Int(Self.u16(d, 4))
        for i in 0..<n {
            let o = 12 + 16 * i
            guard o + 16 <= d.count else { throw FontError.notTrueType }
            let name = String(bytes: d[o..<o + 4], encoding: .ascii) ?? "????"
            let off = Int(Self.u32(d, o + 8)), len = Int(Self.u32(d, o + 12))
            guard off + len <= d.count else { throw FontError.notTrueType }
            t[name] = Data(d[off..<off + len])
        }
        try self.init(tables: t)
    }

    public init(tables t: [String: Data]) throws {
        tables = t
        func table(_ n: String) throws -> [UInt8] {
            guard let x = t[n] else { throw FontError.missingTable(n) }
            return [UInt8](x)
        }
        let head = try table("head"), hhea = try table("hhea"), maxp = try table("maxp")
        let hmtx = try table("hmtx"), loca = try table("loca")
        _ = try table("glyf")
        unitsPerEm = Int(Self.u16(head, 18))
        bbox = (Int(Self.s16(head, 36)), Int(Self.s16(head, 38)), Int(Self.s16(head, 40)), Int(Self.s16(head, 42)))
        let longLoca = Self.s16(head, 50) == 1
        numGlyphs = Int(Self.u16(maxp, 4))
        ascent = Int(Self.s16(hhea, 4)); descent = Int(Self.s16(hhea, 6))
        let nh = Int(Self.u16(hhea, 34))
        var adv: [Int] = []
        for g in 0..<numGlyphs {
            let i = min(g, max(0, nh - 1))
            adv.append(4 * i + 2 <= hmtx.count ? Int(Self.u16(hmtx, 4 * i)) : 0)
        }
        advances = adv
        var offs: [Int] = []
        for g in 0...numGlyphs {
            if longLoca { offs.append(4 * g + 4 <= loca.count ? Int(Self.u32(loca, 4 * g)) : 0) }
            else { offs.append(2 * g + 2 <= loca.count ? 2 * Int(Self.u16(loca, 2 * g)) : 0) }
        }
        glyphOffsets = offs
        cmap = Self.readCmap(t["cmap"].map { [UInt8]($0) } ?? [])
        var ps = "Font", fam = ""
        if let name = t["name"].map({ [UInt8]($0) }) { (ps, fam) = Self.readNames(name) }
        postScriptName = ps.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        familyName = fam
    }

    public func glyph(for scalar: Unicode.Scalar) -> UInt16 { cmap[scalar.value] ?? 0 }
    /// The character is mapped to a glyph that draws something (or is a space).
    public func has(_ scalar: Unicode.Scalar) -> Bool {
        let g = Int(glyph(for: scalar))
        guard g != 0, g < numGlyphs else { return false }
        return scalar.properties.isWhitespace || glyphOffsets[g + 1] > glyphOffsets[g]
    }
    /// Advance width of a glyph in 1/1000 em.
    public func advance(_ gid: UInt16) -> Double {
        Int(gid) < advances.count ? Double(advances[Int(gid)]) * 1000 / Double(unitsPerEm) : 0
    }
    public func scaled(_ v: Int) -> Double { Double(v) * 1000 / Double(unitsPerEm) }

    // MARK: subset

    /// The font with only `keep` (and glyph 0) drawn; same glyph numbers, so CID = GID in the PDF.
    public func subset(_ keep: Set<UInt16>) -> Data {
        let glyf = [UInt8](tables["glyf"]!)
        var keepAll = keep; keepAll.insert(0)
        // composite glyphs pull in their components
        var queue = Array(keepAll)
        while let g = queue.popLast() {
            let gi = Int(g)
            guard gi < numGlyphs else { continue }
            let a = glyphOffsets[gi], b = glyphOffsets[gi + 1]
            guard b - a >= 10, a + 10 <= glyf.count, Self.s16(glyf, a) < 0 else { continue }
            var p = a + 10
            while p + 4 <= b {
                let flags = Self.u16(glyf, p), comp = Self.u16(glyf, p + 2)
                if !keepAll.contains(comp) { keepAll.insert(comp); queue.append(comp) }
                p += 4 + ((flags & 1) != 0 ? 4 : 2)
                if flags & 8 != 0 { p += 2 } else if flags & 0x40 != 0 { p += 4 } else if flags & 0x80 != 0 { p += 8 }
                if flags & 0x20 == 0 { break }
            }
        }
        var newGlyf: [UInt8] = [], newLoca: [UInt8] = []
        for g in 0..<numGlyphs {
            Self.put32(&newLoca, UInt32(newGlyf.count))
            if keepAll.contains(UInt16(g)) {
                let a = glyphOffsets[g], b = min(glyphOffsets[g + 1], glyf.count)
                if b > a { newGlyf += glyf[a..<b] }
                while newGlyf.count % 4 != 0 { newGlyf.append(0) }
            }
        }
        Self.put32(&newLoca, UInt32(newGlyf.count))
        var head = [UInt8](tables["head"]!)
        head[8] = 0; head[9] = 0; head[10] = 0; head[11] = 0      // checkSumAdjustment
        head[50] = 0; head[51] = 1                                // long loca
        var out: [String: [UInt8]] = ["head": head, "loca": newLoca, "glyf": newGlyf]
        for n in ["hhea", "hmtx", "maxp", "cvt ", "fpgm", "prep"] { if let x = tables[n] { out[n] = [UInt8](x) } }
        return Self.assemble(out)
    }

    static func assemble(_ t: [String: [UInt8]]) -> Data {
        let names = t.keys.sorted()
        let n = names.count
        var es = 0; while (1 << (es + 1)) <= n { es += 1 }
        var d: [UInt8] = []
        put32(&d, 0x00010000); put16(&d, UInt16(n))
        put16(&d, UInt16(16 << es)); put16(&d, UInt16(es)); put16(&d, UInt16(n * 16 - (16 << es)))
        var off = 12 + 16 * n
        var body: [UInt8] = []
        for name in names {
            let x = t[name]!
            var padded = x; while padded.count % 4 != 0 { padded.append(0) }
            var sum: UInt32 = 0
            for i in stride(from: 0, to: padded.count, by: 4) { sum = sum &+ u32(padded, i) }
            d += Array(name.utf8); put32(&d, sum); put32(&d, UInt32(off)); put32(&d, UInt32(x.count))
            body += padded; off += padded.count
        }
        return Data(d + body)
    }

    // MARK: parsing helpers

    static func u16(_ d: [UInt8], _ o: Int) -> UInt16 { o + 1 < d.count ? UInt16(d[o]) << 8 | UInt16(d[o + 1]) : 0 }
    static func s16(_ d: [UInt8], _ o: Int) -> Int16 { Int16(bitPattern: u16(d, o)) }
    static func u32(_ d: [UInt8], _ o: Int) -> UInt32 { UInt32(u16(d, o)) << 16 | UInt32(u16(d, o + 2)) }
    static func put16(_ d: inout [UInt8], _ v: UInt16) { d.append(UInt8(v >> 8)); d.append(UInt8(v & 0xFF)) }
    static func put32(_ d: inout [UInt8], _ v: UInt32) { put16(&d, UInt16(v >> 16)); put16(&d, UInt16(v & 0xFFFF)) }

    static func readCmap(_ c: [UInt8]) -> [UInt32: UInt16] {
        guard c.count >= 4 else { return [:] }
        var best: (rank: Int, off: Int)?
        for i in 0..<Int(u16(c, 2)) {
            let p = u16(c, 4 + 8 * i), e = u16(c, 6 + 8 * i), off = Int(u32(c, 8 + 8 * i))
            let rank = p == 3 && e == 1 ? 3 : p == 0 ? 2 : p == 3 && e == 0 ? 1 : 0
            if best == nil || rank > best!.rank { best = (rank, off) }
        }
        guard let b = best, b.off + 6 <= c.count else { return [:] }
        var m: [UInt32: UInt16] = [:]
        let o = b.off
        switch u16(c, o) {
        case 4:
            let segX2 = Int(u16(c, o + 6)), seg = segX2 / 2
            let ends = o + 14, starts = ends + segX2 + 2, deltas = starts + segX2, ranges = deltas + segX2
            for s in 0..<seg {
                let end = Int(u16(c, ends + 2 * s)), start = Int(u16(c, starts + 2 * s))
                let delta = Int(s16(c, deltas + 2 * s)), ro = Int(u16(c, ranges + 2 * s))
                guard start <= end, end != 0xFFFF || start != 0xFFFF else { continue }
                for ch in start...end where ch != 0xFFFF {
                    var g: Int
                    if ro == 0 { g = (ch + delta) & 0xFFFF }
                    else {
                        let p = ranges + 2 * s + ro + 2 * (ch - start)
                        g = Int(u16(c, p)); if g != 0 { g = (g + delta) & 0xFFFF }
                    }
                    if g != 0 { m[UInt32(ch)] = UInt16(g) }
                }
            }
        case 6:
            let first = Int(u16(c, o + 6)), count = Int(u16(c, o + 8))
            for i in 0..<count { let g = u16(c, o + 10 + 2 * i); if g != 0 { m[UInt32(first + i)] = g } }
        case 0:
            for i in 0..<256 where o + 6 + i < c.count { let g = UInt16(c[o + 6 + i]); if g != 0 { m[UInt32(i)] = g } }
        default: break
        }
        return m
    }

    static func readNames(_ n: [UInt8]) -> (String, String) {
        var ps = "", fam = ""
        let count = Int(u16(n, 2)), strings = Int(u16(n, 4))
        for i in 0..<count {
            let r = 6 + 12 * i
            let pid = u16(n, r), id = u16(n, r + 6), len = Int(u16(n, r + 8)), off = strings + Int(u16(n, r + 10))
            guard off + len <= n.count, id == 6 || id == 1 else { continue }
            let bytes = Array(n[off..<off + len])
            let s: String
            if pid == 3 || pid == 0 {
                var u: [UInt16] = []
                for k in stride(from: 0, to: bytes.count - 1, by: 2) { u.append(UInt16(bytes[k]) << 8 | UInt16(bytes[k + 1])) }
                s = String(decoding: u, as: UTF16.self)
            } else { s = String(decoding: bytes, as: UTF8.self) }
            if id == 6, ps.isEmpty { ps = s }
            if id == 1, fam.isEmpty { fam = s }
        }
        return (ps.isEmpty ? fam : ps, fam)
    }
}
