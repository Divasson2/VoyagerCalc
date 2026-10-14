// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// 16C face (programmer's calculator). Legends follow the key functions of the firmware.

import Foundation

extension CalculatorModel {
    public static let hp16c = CalculatorModel(
        id: 16, name: "16C", subtitle: "Programmer", fileExtension: "16c",
        keys: [
            KeySpec(0, "A", f: "SL", g: "LJ", keys: [.char("a")]),
            KeySpec(1, "B", f: "SR", g: "ASR", keys: [.char("b")]),
            KeySpec(2, "C", f: "RL", g: "RLC", keys: [.char("c")]),
            KeySpec(3, "D", f: "RR", g: "RRC", keys: [.char("d")]),
            KeySpec(4, "E", f: "RLn", g: "RLCn", keys: [.char("e")]),
            KeySpec(5, "F", f: "RRn", g: "RRCn", keys: [.char("f")]),
            KeySpec(6, "7", f: "MASKL", g: "#B", keys: [.char("7")]),
            KeySpec(7, "8", f: "MASKR", g: "ABS", keys: [.char("8")]),
            KeySpec(8, "9", f: "RMD", g: "DBLR", keys: [.char("9")]),
            KeySpec(9, "/", face: "÷", f: "XOR", g: "DBL÷", keys: [.char("/")]),

            KeySpec(10, "GSB", f: "x≷(i)", g: "RTN", keys: [.char("u")]),
            KeySpec(11, "GTO", f: "x≷I", g: "LBL", keys: [.char("t")]),
            KeySpec(12, "HEX", f: "HEX", g: "DSZ", keys: [.char("h")]),
            KeySpec(13, "DEC", f: "DEC", g: "ISZ", keys: [.char("k")]),
            KeySpec(14, "OCT", f: "OCT", g: "√x", keys: [.char("o")]),
            KeySpec(15, "BIN", f: "BIN", g: "1/x", keys: [.char("i")]),
            KeySpec(16, "4", f: "SB", g: "SF", keys: [.char("4")]),
            KeySpec(17, "5", f: "CB", g: "CF", keys: [.char("5")]),
            KeySpec(18, "6", f: "B?", g: "F?", keys: [.char("6")]),
            KeySpec(19, "*", face: "×", f: "AND", g: "DBL×", keys: [.char("*"), .char("x")]),

            KeySpec(20, "R/S", f: "(i)", g: "P/R", keys: [.char("r")]),
            KeySpec(21, "SST", f: "I", g: "BST", keys: [.special(.rightArrow)]),
            KeySpec(22, "RDN", face: "R↓", f: "PRGM", g: "R↑", keys: [.special(.downArrow)]),
            KeySpec(23, "x<>y", face: "x≷y", f: "REG", g: "PSE", keys: [.char("w")]),
            KeySpec(24, "BSP", face: "⬅", f: "PREFIX", g: "CLx", keys: [.special(.delete)]),
            KeySpec(25, "ENTER", face: "ENTER", f: "WINDOW", g: "LSTx", keys: [.special(.returnKey), .char("=")], style: .enter),
            KeySpec(26, "1", f: "1'S", g: "x≤y", keys: [.char("1")]),
            KeySpec(27, "2", f: "2'S", g: "x<0", keys: [.char("2")]),
            KeySpec(28, "3", f: "UNSGN", g: "x>y", keys: [.char("3")]),
            KeySpec(29, "-", face: "−", f: "NOT", g: "x>0", keys: [.char("-")]),

            KeySpec(30, "ON", keys: [.special(.escape)], style: .on),
            KeySpec(31, "f", keys: [.special(.shift)], style: .fShift),
            KeySpec(32, "g", keys: [.special(.option)], style: .gShift),
            KeySpec(33, "STO", f: "WSIZE", g: "<", keys: [.char("s")]),
            KeySpec(34, "RCL", f: "FLOAT", g: ">", keys: [.char("l")]),
            KeySpec(36, "0", f: "MEM", g: "x≠y", keys: [.char("0")]),
            KeySpec(37, ".", face: "·", f: "STATUS", g: "x≠0", keys: [.char("."), .char(",")]),
            KeySpec(38, "CHS", f: "EEX", g: "x=y", keys: [.char("n"), .char("_")]),
            KeySpec(39, "+", f: "OR", g: "x=0", keys: [.char("+")]),
        ],
        brackets: [LegendBracket(label: "SHOW", fromCode: 12, toCode: 15),
                   LegendBracket(label: "CLEAR", fromCode: 22, toCode: 24)],
        annunciators: [
            Annunciator(label: "f", bit: 6, cell: 3.0),
            Annunciator(label: "g", bit: 9, cell: 4.0),
            Annunciator(label: "C", bit: 21, cell: 7.6),
            Annunciator(label: "G", bit: 14, cell: 6.3),
            Annunciator(label: "PRGM", bit: 24, cell: 8.6),
        ],
        colors: .voyager(band: 0xB79A63, lcd: ModelColors.greyLCD))
}
