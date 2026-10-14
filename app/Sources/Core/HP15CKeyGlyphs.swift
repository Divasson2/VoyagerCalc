// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// HP15CKeyGlyphs.swift - which character of the "HP 15C" key-cap font (HP_15c_v2.0.ttf, the
// font the key map .docx is written in) draws each HP-15C key legend, by core key code
// (0..39, row by row as on the keyboard) and colour: primary (key face), gold (f) and blue (g).
// Worked out by rendering the docx grids with the font (art/fonts/keymap-glyphs.png).
// The font itself is not part of the app; it is read from the user's own copy.

import Foundation

public enum HP15CKeyGlyphs {
    public enum Colour: Sendable { case primary, gold, blue }

    /// key code -> character, for each colour
    public static let primary: [Int: Character] = [
        0: "¤", 1: "'", 2: "@", 3: "y", 4: "⁄", 5: "”", 6: "7", 7: "8", 8: "9", 9: "÷",
        10: "Â", 11: "t", 12: "[", 13: "\\", 14: "]", 15: "“", 16: "4", 17: "5", 18: "6", 19: "*",
        20: "¦", 21: "G", 22: ")", 23: "®", 24: "−", 25: "v", 26: "1", 27: "2", 28: "3", 29: "-",
        30: "=", 31: "´", 32: "|", 33: "O", 34: "l", 36: "0", 37: ".", 38: "z", 39: "+",
    ]
    public static let gold: [Int: Character] = [
        0: "A", 1: "B", 2: "C", 3: "Á", 4: "E", 5: ">", 6: "•", 7: "i", 8: "^", 9: "_",
        10: "b", 11: "P", 12: "m", 13: "%", 14: "V", 15: "<", 16: "X", 17: "e", 18: "I", 19: "f",
        20: "©", 21: "∑", 22: "M", 23: "Q", 24: "u", 25: "#", 26: ";", 27: "h", 28: "r", 29: "}",
        33: "q", 34: "U", 36: "!", 37: "j", 38: "L", 39: "p",
    ]
    public static let blue: [Int: Character] = [
        0: "x", 1: "N", 2: "o", 3: "k", 4: "∆", 5: "a", 6: "D", 7: "R", 8: "g", 9: "£",
        10: "‚", 11: "H", 12: ",", 13: "{", 14: "/", 15: "$", 16: "F", 17: "\"", 18: "?", 19: "~",
        20: "¥", 21: "n", 22: "(", 23: "&", 24: "`", 25: "K", 26: ":", 27: "À", 28: "d", 29: "T",
        33: "‘", 34: "W", 36: "’", 37: "S", 38: "w", 39: "c",
    ]
    public static let fKey: Character = "´", gKey: Character = "|"

    public static func table(_ c: Colour) -> [Int: Character] {
        switch c { case .primary: primary; case .gold: gold; case .blue: blue }
    }

    /// Legend text (as the 15C model and the decoder name it) -> (character, key code).
    static let lookup: [Colour: [String: (Character, Int)]] = {
        var m: [Colour: [String: (Character, Int)]] = [.primary: [:], .gold: [:], .blue: [:]]
        for k in CalculatorModel.hp15c.keys {
            func add(_ col: Colour, _ names: [String?]) {
                guard let ch = table(col)[k.code] else { return }
                for case let n? in names where !n.isEmpty { m[col]![n] = (ch, k.code) }
            }
            add(.primary, [k.name, k.face])
            add(.gold, [k.f]); add(.blue, [k.g])
        }
        // spellings the decoder uses besides the key legends
        let extraPrimary: [String: Int] = ["e^x": 1, "10^x": 2, "y^x": 3, "1/x": 4, "x<>y": 23, "x≷y": 23,
                                           "⬅": 24, "←": 24, "·": 37, ".": 37, "-": 29, "*": 19, "/": 9]
        for (n, c) in extraPrimary { if let ch = primary[c] { m[.primary]![n] = (ch, c) } }
        let extraGold: [String: Int] = ["∫": 19, "∫ʸₓ": 19, "∫xy": 19, "CLEAR": 21, "Σ": 21, "RAN #": 25, "x≷": 16,
                                        "Re≷Im": 29, "Re<>Im": 29, "x<>": 16]
        for (n, c) in extraGold { if let ch = gold[c] { m[.gold]![n] = (ch, c) } }
        let extraBlue: [String: Int] = ["LSTx": 25, "LST x": 25, "CLx": 24, "CL x": 24, "x̄": 36, "x≤y": 9, "x=0": 19]
        for (n, c) in extraBlue { if let ch = blue[c] { m[.blue]![n] = (ch, c) } }
        return m
    }()

    /// The key-cap glyphs for a 15C program line: the shift key, the function in its colour,
    /// then the arguments; each with the text it stands for. nil when a part has no glyph.
    public static func glyphs(for l: ProgramLine) -> [(Character, String)]? {
        var out: [(Character, String)] = []
        var tokens = l.mnemonic.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return nil }
        let first: Colour
        switch l.prefix {
        case "f": out.append((fKey, "f")); first = .gold
        case "g": out.append((gKey, "g")); first = .blue
        default: first = .primary
        }
        let head = tokens.removeFirst()
        guard let h = find(head, prefer: [first, .gold, .primary, .blue]) else { return nil }
        out.append(h)
        for t in tokens {
            if t == "f" { out.append((fKey, "f")); continue }
            if t == "g" { out.append((gKey, "g")); continue }
            if let g = find(t, prefer: [.gold, .primary, .blue]) { out.append(g); continue }
            // ".5", "25", ".1": one key per character
            var parts: [(Character, String)] = []
            for c in t {
                guard let g = find(String(c), prefer: [.primary, .gold]) else { return nil }
                parts.append(g)
            }
            out += parts
        }
        return out
    }

    static func find(_ name: String, prefer: [Colour]) -> (Character, String)? {
        var cands = [name]
        if name.hasSuffix("?"), name != "F?" { cands.append(String(name.dropLast())) }
        for n in cands {
            for c in prefer { if let (ch, _) = lookup[c]?[n] { return (ch, name) } }
        }
        return nil
    }
}
