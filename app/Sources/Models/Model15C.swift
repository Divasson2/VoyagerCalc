// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// 15C face (scientific). Laid out as data; built after the 16C.

import Foundation

extension CalculatorModel {
    public static let hp15c = CalculatorModel(
        id: 15, name: "15C", subtitle: "Scientific", fileExtension: "15c",
        keys: [
            KeySpec(0, "√x", f: "A", g: "x²", keys: [.char("q")]),
            KeySpec(1, "e^x", face: "eˣ", f: "B", g: "LN", keys: [.char("e")]),
            KeySpec(2, "10^x", face: "10ˣ", f: "C", g: "LOG", keys: [.char("w")]),
            KeySpec(3, "y^x", face: "yˣ", f: "D", g: "%", keys: [.char("y")]),
            KeySpec(4, "1/x", f: "E", g: "Δ%", keys: [.char("v")]),
            KeySpec(5, "CHS", f: "MATRIX", g: "ABS", keys: [.char("n"), .char("_")]),
            KeySpec(6, "7", f: "FIX", g: "DEG", keys: [.char("7")]),
            KeySpec(7, "8", f: "SCI", g: "RAD", keys: [.char("8")]),
            KeySpec(8, "9", f: "ENG", g: "GRD", keys: [.char("9")]),
            KeySpec(9, "÷", f: "SOLVE", g: "x≤y", keys: [.char("/")]),

            KeySpec(10, "SST", f: "LBL", g: "BST", keys: [.special(.rightArrow)]),
            KeySpec(11, "GTO", f: "HYP", g: "HYP⁻¹", keys: [.char("t")]),
            KeySpec(12, "SIN", f: "DIM", g: "SIN⁻¹", keys: [.char("i")]),
            KeySpec(13, "COS", f: "(i)", g: "COS⁻¹", keys: [.char("o")]),
            KeySpec(14, "TAN", f: "I", g: "TAN⁻¹", keys: [.char("p")]),
            KeySpec(15, "EEX", f: "RESULT", g: "π", keys: [.char("k")]),
            KeySpec(16, "4", f: "x≷", g: "SF", keys: [.char("4")]),
            KeySpec(17, "5", f: "DSE", g: "CF", keys: [.char("5")]),
            KeySpec(18, "6", f: "ISG", g: "F?", keys: [.char("6")]),
            KeySpec(19, "×", f: "∫ʸₓ", g: "x=0", keys: [.char("*"), .char("x")]),

            KeySpec(20, "R/S", f: "PSE", g: "P/R", keys: [.char("r")]),
            KeySpec(21, "GSB", f: "Σ", g: "RTN", keys: [.char("u")]),
            KeySpec(22, "R↓", f: "PRGM", g: "R↑", keys: [.special(.downArrow)]),
            KeySpec(23, "x<>y", face: "x≷y", f: "REG", g: "RND", keys: [.char("j")]),
            KeySpec(24, "←", face: "⬅", f: "PREFIX", g: "CLx", keys: [.special(.delete)]),
            KeySpec(25, "ENTER", f: "RAN#", g: "LSTx", keys: [.special(.returnKey), .char("=")], style: .enter),
            KeySpec(26, "1", f: "→R", g: "→P", keys: [.char("1")]),
            KeySpec(27, "2", f: "→H.MS", g: "→H", keys: [.char("2")]),
            KeySpec(28, "3", f: "→RAD", g: "→DEG", keys: [.char("3")]),
            KeySpec(29, "−", f: "Re≷Im", g: "TEST", keys: [.char("-")]),

            KeySpec(30, "ON", keys: [.special(.escape)], style: .on),
            KeySpec(31, "f", keys: [.special(.shift)], style: .fShift),
            KeySpec(32, "g", keys: [.special(.option)], style: .gShift),
            KeySpec(33, "STO", f: "FRAC", g: "INT", keys: [.char("s")]),
            KeySpec(34, "RCL", f: "USER", g: "MEM", keys: [.char("l")]),
            KeySpec(36, "0", f: "x!", g: "x̄", keys: [.char("0")]),
            KeySpec(37, ".", face: "·", f: "ŷ,r", g: "s", keys: [.char("."), .char(",")]),
            KeySpec(38, "Σ+", f: "L.R.", g: "Σ−", keys: [.char("z")]),
            KeySpec(39, "+", f: "Py,x", g: "Cy,x", keys: [.char("+")]),
        ],
        brackets: [LegendBracket(label: "CLEAR", fromCode: 21, toCode: 24)],
        annunciators: [
            Annunciator(label: "USER", bit: 4, cell: 1.2),
            Annunciator(label: "f", bit: 6, cell: 3.0),
            Annunciator(label: "g", bit: 9, cell: 4.0),
            Annunciator(label: "G", bit: 14, cell: 5.8),      // G + RAD = "GRAD"
            Annunciator(label: "RAD", bit: 16, cell: 6.2),
            Annunciator(label: "C", bit: 21, cell: 7.8),
            Annunciator(label: "PRGM", bit: 24, cell: 8.6),
        ],
        colors: .voyager(band: 0xA9A59C, lcd: ModelColors.greyLCD))
}
