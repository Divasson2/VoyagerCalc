// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// MemoryFileNames.swift - memory file names and what is inside a file (0.6.9).
//
// The default ending of a saved memory file is .bin12c / .bin15c / .bin16c (other programs use .12c / .15c / .16c for TEXT
// programs). The ending is only a default: the save panel lets the user type any ending, and opening looks at the CONTENT
// (2048 bytes), never at the ending. The old endings (.12c .15c .16c, and .12cmem .15cmem .16cmem) are still understood for the
// "saved from a 15C, running as a 16C" note and for finding the notes file (sidecar).

import Foundation

enum MemoryFileNames {
    /// The default ending for a model id (12, 15, 16).
    static func defaultExtension(forModel id: Int) -> String { "bin\(id)c" }

    /// The model (12, 15 or 16) an ending hints at: bin15c, 15c, 15cmem (case-insensitive); nil for anything else.
    static func modelHint(forExtension ext: String) -> Int? {
        let e = ext.lowercased()
        for id in [12, 15, 16] where e == "bin\(id)c" || e == "\(id)c" || e == "\(id)cmem" { return id }
        return nil
    }

    /// Where the notes of a memory file may be: "<name>.voyagerdoc" first, then the same name with another memory ending
    /// (an old FinancePac.15c.voyagerdoc next to FinancePac.bin15c, and the other way round), then "<base>.voyagerdoc".
    static func sidecarCandidates(for url: URL, sidecarExtension: String = "voyagerdoc") -> [URL] {
        var out = [url.appendingPathExtension(sidecarExtension)]
        let dir = url.deletingLastPathComponent(), base = url.deletingPathExtension().lastPathComponent
        let own = url.pathExtension.lowercased()
        if let id = modelHint(forExtension: own) {
            for e in [defaultExtension(forModel: id), "\(id)c", "\(id)cmem"] where e != own {
                out.append(dir.appendingPathComponent(base + "." + e).appendingPathExtension(sidecarExtension))
            }
        }
        out.append(dir.appendingPathComponent(base).appendingPathExtension(sidecarExtension))
        return out
    }

    enum Content: Equatable {
        case image                  // 2048 bytes, not text: a memory image (any ending)
        case text                   // a text program (Manz simulator format, rejig, JRPN ...)
        case wrongSize(Int)         // something else
    }

    /// Tell a memory image from a text program and from other files by content.
    static func classify(_ data: Data) -> Content {
        if looksLikeText(data) { return .text }
        return data.count == VoyagerCalculator.memorySize ? .image : .wrongSize(data.count)
    }

    /// A byte-order mark of UTF-8 / UTF-16, or (nearly) only printable text containing "{" or "#" program lines.
    static func looksLikeText(_ d: Data) -> Bool {
        let b = [UInt8](d.prefix(4096))
        guard b.count >= 8 else { return false }
        if b.starts(with: [0xFF, 0xFE]) || b.starts(with: [0xFE, 0xFF]) || b.starts(with: [0xEF, 0xBB, 0xBF]) { return true }
        let printable = b.filter { $0 == 9 || $0 == 10 || $0 == 13 || ($0 >= 32 && $0 < 127) }.count
        // non-ASCII letters (the "·" of a Manz header, accents) are fine; control bytes (NUL, 0x01 ...) are what a binary image is full of
        let control = b.filter { ($0 < 32 && $0 != 9 && $0 != 10 && $0 != 13) || $0 == 127 }.count
        guard Double(printable) / Double(b.count) >= 0.9, control * 100 <= b.count else { return false }
        return b.contains(UInt8(ascii: "{")) || b.contains(UInt8(ascii: "#")) || b.contains(UInt8(ascii: "\n"))
    }

    /// The message for a file that cannot be a memory file; nil for a memory image.
    static func problem(with data: Data, name: String) -> String? {
        switch classify(data) {
        case .image: return nil
        case .text:
            return "“\(name)” is a text program (the format other HP simulators write), not a calculator memory file. "
                + "VoyagerCalc opens the 2048-byte memory files it saves, that VoyagerInterface writes, or that a calculator backup produces. Importing text programs is not available yet."
        case .wrongSize(let n):
            return "“\(name)” is not a calculator memory file (it must be exactly 2048 bytes; this one has \(n))."
        }
    }
}
