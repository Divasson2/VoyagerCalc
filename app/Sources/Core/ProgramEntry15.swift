// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// ProgramEntry15.swift - key a program into the emulated HP-15C (0.7.2, File ▸ Import Program (.15c)…): program
// mode, CLEAR PRGM, then every step's keys as a person would press them, so the calculator's own firmware encodes and
// stores the program (and allocates its memory). Registers and matrices are kept. Each step is checked as it goes in
// (the program grows by one line, no Error); at the end the listing is compared with the file. On any problem the
// memory from before the import is put back.

import Foundation

public struct ProgramEntryReport: Equatable, Sendable {
    public var steps = 0
    /// Steps whose keycodes in the calculator differ from the file (step number, file, calculator).
    public var mismatches: [(step: Int, file: String, calculator: String)] = []
    public static func == (a: Self, b: Self) -> Bool { a.steps == b.steps && a.mismatches.count == b.mismatches.count }
}

public enum ProgramEntryError: Error, LocalizedError, Equatable {
    case notA15C
    case running
    case noProgramMode
    case doesNotFit(steps: Int, bytesFree: Int)
    case memoryFull(step: Int, keycodes: String)
    case stepRejected(step: Int, keycodes: String, display: String)
    public var errorDescription: String? {
        switch self {
        case .notA15C: return "Program files from the HP-15C Simulator can only be imported into the HP-15C. Switch the model to the 15C first."
        case .running: return "The calculator is running a program. Stop it (R/S) and import again."
        case .noProgramMode: return "The calculator did not go into program mode (g P/R). Clear any message on its display and try again."
        case .doesNotFit(let n, let free):
            return "The program has \(n) steps, but the calculator has room for at most \(free) (free memory, 7 bytes per register). Free registers or matrices (DIM (i), MATRIX 0) or use the 15C (15.2) mode, then import again."
        case .memoryFull(let n, let k):
            return "The calculator ran out of memory (Error 4) at step \(String(format: "%03d", n)) {\(k)}. Free registers or matrices (DIM (i), MATRIX 0) or use the 15C (15.2) mode, then import again. The calculator's memory is as before the import."
        case .stepRejected(let n, let k, let d):
            return "The calculator did not take step \(String(format: "%03d", n)) {\(k)} (display: “\(d.trimmingCharacters(in: .whitespaces))”). The calculator's memory is as before the import."
        }
    }
}

extension CalculatorMachine {
    private func lit(_ label: String) -> Bool {
        calc.lcd().annunciators(for: CalculatorModel.with(id: calc.model)).contains { $0.label == label }
    }
    private func key(_ code: Int) throws { try calc.tap(code, holdMs: 80, afterMs: 220) }

    /// Type `steps` into the HP-15C's program memory (replacing the program there). Runs on the engine thread.
    public func enterProgram15(_ steps: [HP15CStep]) throws -> ProgramEntryReport {
        guard calc.model == 15 else { throw ProgramEntryError.notA15C }
        let keys = steps.map { HP15CKeyEntry.keys(for: $0) }
        if let bad = keys.firstIndex(where: { $0 == nil }) {
            throw ProgramEntryError.stepRejected(step: bad + 1, keycodes: steps[bad].keycodeText, display: "")
        }
        try powerOn()
        if let s = calc.inspect(includeProgram: false, maxRegisters: 0), s.running { throw ProgramEntryError.running }
        if let pool = calc.inspect(includeProgram: false, maxRegisters: 0)?.pool {
            let bytes = (pool.free + pool.programRegisters) * 7
            if steps.count > bytes { throw ProgramEntryError.doesNotFit(steps: steps.count, bytesFree: bytes) }
        }
        let before = try memory(turnBackOn: true)      // consistent image (the firmware writes its working registers back at OFF)
        do {
            return try enter(steps, keys.map { $0! })
        } catch {
            try? putMemory(before)
            throw error
        }
    }

    private func enter(_ steps: [HP15CStep], _ keys: [[Int]]) throws -> ProgramEntryReport {
        let F = HP15CKeyEntry.keyF, G = HP15CKeyEntry.keyG
        // a message on the display (Error n, Pr Error) takes the first key: clear it with ←
        if calc.lcd().text.contains("rror") { try key(MachineKeys.backspace) }
        if !lit("PRGM") { try key(G); try key(MachineKeys.runStop) }        // g P/R
        guard lit("PRGM") else { throw ProgramEntryError.noProgramMode }
        try key(F); try key(MachineKeys.rollDown)                           // f CLEAR PRGM (program mode: clears program memory)
        let userAtStart = lit("USER")
        var user = userAtStart
        func setUser(_ on: Bool) throws {
            if user != on { try key(F); try key(HP15CKeyEntry.keyRCL); user = on }     // f USER
        }
        var lines = calc.inspect(includeProgram: false, maxRegisters: 0)?.lines ?? 0
        for (i, step) in steps.enumerated() {
            try setUser(step.isUser)
            for k in keys[i] { try key(k) }
            let text = calc.lcd().text
            let now = calc.inspect(includeProgram: false, maxRegisters: 0)?.lines ?? lines
            if text.contains("rror") {
                try? key(MachineKeys.backspace)
                if text.contains("4") { throw ProgramEntryError.memoryFull(step: i + 1, keycodes: step.keycodeText) }
                throw ProgramEntryError.stepRejected(step: i + 1, keycodes: step.keycodeText, display: text)
            }
            guard now == lines + 1 else {
                throw ProgramEntryError.stepRejected(step: i + 1, keycodes: step.keycodeText, display: text)
            }
            lines = now
        }
        try setUser(userAtStart)
        try key(G); try key(MachineKeys.runStop)                            // g P/R: back to run mode
        // compare the calculator's listing with the file
        var report = ProgramEntryReport(steps: steps.count)
        let listing = calc.inspect()?.program ?? []
        for (i, step) in steps.enumerated() {
            let got = i < listing.count ? listing[i].keys : ""
            if HP15CKeycodes.parseDisplay(got) != step.plainTokens {
                report.mismatches.append((i + 1, step.keycodeText, got))
            }
        }
        return report
    }
}

/// Face key indexes used to drive the 15C (same as the app's model data, see Model15C.swift).
enum MachineKeys {
    static let runStop = 20, rollDown = 22, backspace = 24
}
