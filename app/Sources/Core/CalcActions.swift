// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// CalcActions.swift - the inspector's context-menu commands as calculator keystrokes (port of the Qt
// CalcActions): "GTO nnn" on a program line, and RCL / STO / STO+−×÷ / RCL+−×÷ / x≷ on a register.
// Every item is executed by tapping the same keys a user would press, so it behaves exactly like the
// keyed sequence: in program mode a register item is keyed into the program as an instruction, and GTO
// (a non-programmable positioning in PRGM mode) only moves the pointer. Nothing runs while a program runs.

import Foundation

public struct CalcAction: Equatable, Sendable {
    public var title: String
    public var keys: [Int] = []
    public var enabled = false
    public var separatorBefore = false
}

public enum CalcActions {
    static let digit = [36, 26, 27, 28, 16, 17, 18, 6, 7, 8]
    static let dot = 37, sto = 33, rcl = 34, f = 31, g = 32, gtoKey = 11, rdn = 22, bsp = 24, chs = 5
    static let opKeys = [39, 29, 19, 9]                 // + − × ÷
    static let opNames = ["+", "−", "×", "÷"]
    static let i15 = 14, i16 = 21                       // 15C TAN = (I), 16C SST = (I): no f needed after STO / RCL
    static let xSwap15 = 16                             // 15C f 4 = x≷
    static let xSwapI16 = 11                            // 16C f GTO = x≷I

    static func isStackRow(_ n: String) -> Bool { ["X", "Y", "Z", "T", "LAST X"].contains(n) }

    /// 15C: GTO CHS nnn; 16C: GTO . nnn; 12C: g GTO nn (run mode) or g GTO . nn (program mode).
    public static func gtoKeys(model: Int, programMode: Bool, line: Int, lines: Int) -> [Int] {
        guard line >= 0, line <= lines else { return [] }
        if model == 12 {
            guard line <= 99 else { return [] }
            return [g, rdn] + (programMode ? [dot] : []) + [digit[line / 10], digit[line % 10]]
        }
        guard model == 15 || model == 16, line <= 999 else { return [] }
        return [gtoKey, model == 15 ? chs : dot, digit[line / 100], digit[line / 10 % 10], digit[line % 10]]
    }

    public static func gto(_ s: InspectorSnapshot, line: Int) -> CalcAction {
        let keys = s.running ? [] : gtoKeys(model: s.model, programMode: s.programMode, line: line, lines: s.lines)
        let label = s.model == 12 ? String(format: "%02d", line) : String(format: "%03d", line)
        return CalcAction(title: "GTO \(label)", keys: keys, enabled: !keys.isEmpty)
    }

    /// The keys that address a register after STO / RCL: R0..R9, R.0..R.9 (16C also A..F), I, 12C n i PV PMT FV.
    public static func addressKeys(model: Int, name: String) -> [Int] {
        if name == "I" { return model == 15 ? [i15] : model == 16 ? [i16] : [] }
        if model == 12, let i = ["n", "i", "PV", "PMT", "FV"].firstIndex(of: name) { return [i] }
        guard name.hasPrefix("R"), name.count >= 2 else { return [] }
        var rest = Substring(name.dropFirst())
        var k: [Int] = []
        if rest.hasPrefix(".") { k.append(dot); rest = rest.dropFirst() }
        guard rest.count == 1, let c = rest.first else { return [] }      // R20.. (15C) / R32.. (16C): only through (i)
        if let d = c.wholeNumberValue, c.isASCII, d < 10 { k.append(digit[d]); return k }
        if model == 16, let a = "ABCDEF".firstIndex(of: c) { k.append("ABCDEF".distance(from: "ABCDEF".startIndex, to: a)); return k }
        return []
    }

    public static func registerMenu(_ s: InspectorSnapshot, name: String) -> [CalcAction] {
        let model = s.model
        let addr = isStackRow(name) ? [] : addressKeys(model: model, name: name)
        let ok = !addr.isEmpty && !s.running
        let fin = model == 12 && !name.hasPrefix("R")
        var m: [CalcAction] = []
        func add(_ t: String, _ pre: [Int], _ valid: Bool, _ sep: Bool = false) {
            let on = ok && valid
            m.append(CalcAction(title: t, keys: on ? pre + addr : [], enabled: on, separatorBefore: sep))
        }
        add("RCL \(name)", [rcl], true)
        add("STO \(name)", [sto], true)
        // register arithmetic: 15C STO and RCL with + − × ÷ (registers and I); 12C STO only, R0..R4; 16C none
        let arith12 = model == 12 && !fin && addr.count == 1 && digit[0...4].contains(addr[0])
        if model != 16 {
            for i in 0..<4 { add("STO\(opNames[i]) \(name)", [sto, opKeys[i]], model == 15 || arith12, i == 0) }
        }
        if model == 15 {
            for i in 0..<4 { add("RCL\(opNames[i]) \(name)", [rcl, opKeys[i]], true, i == 0) }
            add("x≷ \(name)", [f, xSwap15], true, true)
        } else if model == 16 {
            // the 16C exchanges X only with I (x≷I) or the register I points at (x≷(i))
            let on = ok && name == "I"
            m.append(CalcAction(title: "x≷ I", keys: on ? [f, xSwapI16] : [], enabled: on, separatorBefore: true))
        }
        return m
    }
}

extension CalculatorMachine {
    /// Key a CalcAction: let held keys go, turn the calculator on, clear an Error display, tap each key.
    public func perform(keys: [Int]) throws {
        guard !keys.isEmpty else { return }
        releaseAll()
        try powerOn()
        if displayText.contains("rror") { try calc.tap(Self.keyBSP, holdMs: 80, afterMs: 220) }
        for k in keys { try calc.tap(k, holdMs: 80, afterMs: 220) }
        try run(ms: 400)
    }
}
