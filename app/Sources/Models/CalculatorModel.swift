// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// CalculatorModel.swift - everything that differs between the 12C, 15C and 16C faces,
// as data: key legends, key codes, keyboard shortcuts, colours, annunciators, file type.
// The key matrix is the same on all three (code = 10 * row + column, ON = 30, the tall
// ENTER key is code 25 and also covers 35).

import Foundation

public enum SpecialKey: String, Sendable, CaseIterable {
    case returnKey, delete, escape, shift, option, upArrow, downArrow, leftArrow, rightArrow, tab

    public var symbol: String {
        switch self {
        case .returnKey: return "⏎ Return"
        case .delete: return "⌫ Delete"
        case .escape: return "esc"
        case .shift: return "⇧ Shift"
        case .option: return "⌥ Option"
        case .upArrow: return "↑"
        case .downArrow: return "↓"
        case .leftArrow: return "←"
        case .rightArrow: return "→"
        case .tab: return "⇥ Tab"
        }
    }
}

public enum KeyShortcut: Hashable, Sendable {
    case char(Character)        // compared case-insensitively
    case special(SpecialKey)

    public var label: String {
        switch self {
        case .char(let c): return String(c).uppercased()
        case .special(let s): return s.symbol
        }
    }

    /// The compact form shown in the hover hint over a key (the tooltip keeps `label`).
    public var hintLabel: String {
        if case .special(.returnKey) = self { return "⏎" }
        return label
    }
}

public enum KeyStyle: Sendable { case normal, fShift, gShift, enter, on }

public struct KeySpec: Identifiable, Sendable {
    public let code: Int
    public let name: String          // name the core knows (vc_key_code)
    public let face: String          // printed on the key
    public let f: String             // gold legend above the key ("" = none)
    public let g: String             // blue legend on the key's front ("" = none)
    public let shortcuts: [KeyShortcut]
    public let style: KeyStyle
    public var id: Int { code }
    public var row: Int { code / 10 }
    public var column: Int { code % 10 }
    /// Rows covered (the ENTER key is two rows tall).
    public var rowSpan: Int { style == .enter ? 2 : 1 }

    public init(_ code: Int, _ name: String, face: String? = nil, f: String = "", g: String = "",
                keys: [KeyShortcut] = [], style: KeyStyle = .normal) {
        self.code = code; self.name = name; self.face = face ?? name; self.f = f; self.g = g
        self.shortcuts = keys; self.style = style
    }

    /// The text of the hover hint over the key.
    public var shortcutHint: String { shortcuts.map(\.hintLabel).joined(separator: " ") }

    public var shortcutHelp: String {
        shortcuts.isEmpty ? face : "\(face) — keyboard: " + shortcuts.map(\.label).joined(separator: " or ")
    }
}

/// A gold bracket printed above a group of keys (e.g. CLEAR over three keys).
public struct LegendBracket: Sendable {
    public let label: String
    public let fromCode: Int
    public let toCode: Int
}

public struct Annunciator: Sendable, Equatable {
    public let label: String
    public let bit: Int          // LCD memory bit (-1: not found in the LCD memory yet, never lit)
    public let cell: Double      // horizontal position, in digit cells from the left (0...10)

    /// Whether this annunciator's segment is set in the raw LCD bits.
    public func isLit(_ bits: UInt64) -> Bool { bit >= 0 && bit < 64 && bits >> UInt64(bit) & 1 == 1 }

    /// The Voyager LCD glass is the same part on the 12C, 15C and 16C: every annunciator is printed on it at a fixed
    /// place, and each one is visible only when the firmware lights its segment. So all models share one layout (the
    /// all-segments self test, ON + ×, then looks the same on every model, as on the real calculators). Same table as
    /// kVoyagerAnnunciators in the Qt app. RAD sits right after G (together "GRAD"). The low-battery "*" segment has
    /// not been found in the LCD memory yet (bit -1: drawn unlit, never lit).
    public static let voyager: [Annunciator] = [
        Annunciator(label: "*", bit: -1, cell: -0.05),
        Annunciator(label: "USER", bit: 4, cell: 0.75),
        Annunciator(label: "f", bit: 6, cell: 2.45),
        Annunciator(label: "g", bit: 9, cell: 3.15),
        Annunciator(label: "BEGIN", bit: 11, cell: 3.85),
        Annunciator(label: "G", bit: 14, cell: 5.35),
        Annunciator(label: "RAD", bit: 16, cell: 5.35),
        Annunciator(label: "D.MY", bit: 19, cell: 6.85),
        Annunciator(label: "C", bit: 21, cell: 8.0),
        Annunciator(label: "PRGM", bit: 24, cell: 8.55),
    ]
}

public struct ModelColors: Sendable {
    public let body: UInt32       // 0xRRGGBB
    public let bezel: UInt32
    public let band: UInt32       // the metal band behind the keyboard
    public let fLegend: UInt32
    public let gLegend: UInt32
    public let keyCap: UInt32
    public let keyFront: UInt32
    public let fKey: UInt32
    public let gKey: UInt32
    public let lcd: UInt32
    public let segment: UInt32
}

public struct CalculatorModel: Identifiable, Sendable {
    public let id: Int                // 12, 15, 16
    public let name: String           // "16C"
    public let subtitle: String       // neutral description
    public let fileExtension: String  // "bin16c" (0.6.9; the old .16c is still read)
    public let keys: [KeySpec]
    public let brackets: [LegendBracket]
    public let annunciators: [Annunciator]
    public let colors: ModelColors

    public func key(code: Int) -> KeySpec? { keys.first { $0.code == code || ($0.style == .enter && code == 35) } }

    /// Key for a hardware keyboard shortcut.
    public func key(for shortcut: KeyShortcut) -> KeySpec? {
        let wanted = shortcut.normalized
        return keys.first { $0.shortcuts.contains { $0.normalized == wanted } }
    }

    public static let all: [CalculatorModel] = [.hp16c, .hp15c, .hp12c]
    public static func with(id: Int) -> CalculatorModel { all.first { $0.id == id } ?? .hp16c }
}

extension KeyShortcut {
    var normalized: KeyShortcut {
        if case .char(let c) = self { return .char(Character(String(c).lowercased())) }
        return self
    }
}

/// The colours all three share: Voyager brown with a gold band.
extension ModelColors {
    /// The 12C keeps the green-tinted glass; the 15C / 16C use the neutral grey of the
    /// original machines (0.6.2, sampled from a photo of an old 15C).
    public static let greenLCD: UInt32 = 0xA9AE99
    /// 0.6.3: one flat grey, the same as the glass of the 15C / 16C photo faces (no gradient).
    public static let greyLCD: UInt32 = 0x898989
    static func voyager(band: UInt32, lcd: UInt32 = greenLCD) -> ModelColors {
        ModelColors(body: 0x3B302A, bezel: 0x2A221E, band: band, fLegend: 0xE3A63A, gLegend: 0x5DA9E8,
                    keyCap: 0x2B2725, keyFront: 0x45403C, fKey: 0xE3A63A, gKey: 0x5DA9E8,
                    lcd: lcd, segment: 0x22241E)
    }
}
