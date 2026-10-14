// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// 12C face (financial). Laid out as data; built after the 16C.

import Foundation

extension CalculatorModel {
    public static let hp12c = CalculatorModel(
        id: 12, name: "12C", subtitle: "Financial", fileExtension: "12c",
        keys: [
            KeySpec(0, "n", f: "AMORT", g: "12×", keys: [.char("m")]),
            KeySpec(1, "i", f: "INT", g: "12÷", keys: [.char("i")]),
            KeySpec(2, "PV", f: "NPV", g: "CFo", keys: [.char("p")]),
            KeySpec(3, "PMT", f: "RND", g: "CFj", keys: [.char("j")]),
            KeySpec(4, "FV", f: "IRR", g: "Nj", keys: [.char("v")]),
            KeySpec(5, "CHS", g: "DATE", keys: [.char("n"), .char("_")]),
            KeySpec(6, "7", g: "BEG", keys: [.char("7")]),
            KeySpec(7, "8", g: "END", keys: [.char("8")]),
            KeySpec(8, "9", g: "MEM", keys: [.char("9")]),
            KeySpec(9, "÷", keys: [.char("/")]),

            KeySpec(10, "y^x", face: "yˣ", f: "PRICE", g: "√x", keys: [.char("y")]),
            KeySpec(11, "1/x", f: "YTM", g: "eˣ", keys: [.char("e")]),
            KeySpec(12, "%T", f: "SL", g: "LN", keys: [.char("t")]),
            KeySpec(13, "Δ%", f: "SOYD", g: "FRAC", keys: [.char("d")]),
            KeySpec(14, "%", f: "DB", g: "INTG", keys: [.char("%")]),
            KeySpec(15, "EEX", g: "ΔDYS", keys: [.char("k")]),
            KeySpec(16, "4", g: "D.MY", keys: [.char("4")]),
            KeySpec(17, "5", g: "M.DY", keys: [.char("5")]),
            KeySpec(18, "6", g: "x̄w", keys: [.char("6")]),
            KeySpec(19, "×", g: "x²", keys: [.char("*"), .char("x")]),

            KeySpec(20, "R/S", f: "P/R", g: "PSE", keys: [.char("r")]),
            KeySpec(21, "SST", f: "Σ", g: "BST", keys: [.special(.rightArrow)]),
            KeySpec(22, "R↓", f: "PRGM", g: "GTO", keys: [.special(.downArrow)]),
            KeySpec(23, "x<>y", face: "x≷y", f: "FIN", g: "x≤y", keys: [.char("w")]),
            KeySpec(24, "CLx", f: "REG", g: "x=0", keys: [.special(.delete)]),
            KeySpec(25, "ENTER", f: "PREFIX", g: "LSTx", keys: [.special(.returnKey), .char("=")], style: .enter),
            KeySpec(26, "1", g: "x̂,r", keys: [.char("1")]),
            KeySpec(27, "2", g: "ŷ,r", keys: [.char("2")]),
            KeySpec(28, "3", g: "n!", keys: [.char("3")]),
            KeySpec(29, "−", g: "←", keys: [.char("-")]),

            KeySpec(30, "ON", keys: [.special(.escape)], style: .on),
            KeySpec(31, "f", keys: [.special(.shift)], style: .fShift),
            KeySpec(32, "g", keys: [.special(.option)], style: .gShift),
            KeySpec(33, "STO", keys: [.char("s")]),
            KeySpec(34, "RCL", keys: [.char("l")]),
            KeySpec(36, "0", g: "x̄", keys: [.char("0")]),
            KeySpec(37, ".", face: "·", g: "s", keys: [.char("."), .char(",")]),
            KeySpec(38, "Σ+", g: "Σ−", keys: [.char("z")]),
            KeySpec(39, "+", keys: [.char("+")]),
        ],
        brackets: [LegendBracket(label: "CLEAR", fromCode: 21, toCode: 24)],
        annunciators: [
            Annunciator(label: "f", bit: 6, cell: 3.0),
            Annunciator(label: "g", bit: 9, cell: 4.0),
            Annunciator(label: "BEGIN", bit: 11, cell: 5.0),
            Annunciator(label: "D.MY", bit: 19, cell: 7.0),
            Annunciator(label: "PRGM", bit: 24, cell: 8.6),
        ],
        colors: .voyager(band: 0xC9A24E))
}
