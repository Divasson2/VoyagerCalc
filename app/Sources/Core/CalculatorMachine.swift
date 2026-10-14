// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// CalculatorMachine.swift - the calculator as the app sees it: boot, restore a saved
// state, keys held by a finger, the calculator's own model switch. Synchronous and
// single-threaded (CalculatorEngine runs it on its own thread; tests call it directly).

import Foundation

public struct SavedState: Codable, Equatable, Sendable {
    public var memory: Data          // 2 KB VoyagerSave image
    public var variant: Int          // 120 / 150 / 152 / 160: which ROM was running
    public var firmwareID: String    // SHA-256 of the firmware file it belongs to
    public init(memory: Data, variant: Int, firmwareID: String) {
        self.memory = memory; self.variant = variant; self.firmwareID = firmwareID
    }
}

public final class CalculatorMachine {
    public let calc = VoyagerCalculator()
    public private(set) var family: CalculatorFamily = .none
    public private(set) var firmwareID = ""
    /// The firmware file (for trial loads of a memory image, see checkMemory).
    public private(set) var firmwareData = Data()
    /// Calculator images in the firmware (variants 120 / 150 / 152 / 160), menu order.
    public private(set) var images: [Int] = []
    /// Simulated time since start, ms.
    public private(set) var simMs: Int = 0

    /// A key touched by the user stays down at least this long in simulated time, so a
    /// quick click is seen by the firmware's 10 ms key scan and debounce.
    public var minimumHoldMs = 80

    private var downSince: [Int: Int] = [:]     // key -> simMs pressed
    private var pendingRelease: Set<Int> = []
    private var delayedRelease: [(at: Int, code: Int)] = []

    public init() {}

    // MARK: firmware

    public func loadFirmware(_ data: Data) throws {
        try calc.loadFirmware(data)
        family = calc.family
        firmwareID = SHA256Hex.of(data)
        firmwareData = data
        images = calc.firmwareImages
    }

    /// The firmware has more than one calculator image to choose from.
    public var canSwitchModel: Bool { images.count > 1 }

    public var model: Int { calc.model }
    public var variant: Int { calc.variant }

    // MARK: time

    public func run(ms: Int) throws {
        var left = ms
        while left > 0 {
            let step = min(left, 10)
            try calc.run(ms: step)
            simMs += step; left -= step
            if !delayedRelease.isEmpty {
                let due = delayedRelease.filter { $0.at <= simMs }
                delayedRelease.removeAll { $0.at <= simMs }
                for d in due { release(d.code) }
            }
            if !pendingRelease.isEmpty {
                for k in pendingRelease where simMs - (downSince[k] ?? 0) >= minimumHoldMs {
                    calc.release(k); pendingRelease.remove(k); downSince[k] = nil
                }
            }
        }
    }

    // MARK: keys

    public func press(_ code: Int) {
        if downSince[code] != nil && !pendingRelease.contains(code) { return }
        pendingRelease.remove(code)
        downSince[code] = simMs
        calc.press(code)
    }

    public func release(_ code: Int) {
        guard let t = downSince[code] else { return }
        if simMs - t >= minimumHoldMs { calc.release(code); downSince[code] = nil }
        else { pendingRelease.insert(code) }
    }

    /// Release keys a little later in simulated time (keys latched for a chord are let go
    /// after the key that completes the chord, as fingers would).
    public func release(_ codes: [Int], afterMs: Int) {
        for k in codes { delayedRelease.append((simMs + max(0, afterMs), k)) }
    }

    public func releaseAll() {
        for k in downSince.keys { calc.release(k) }
        downSince = [:]; pendingRelease = []; delayedRelease = []
    }

    /// Keys held down now (by the user, not by the machine's own sequences).
    public var keysDown: Set<Int> { Set(downSince.keys) }

    public func tap(_ code: Int) throws { try calc.tap(code); simMs += 720 }

    public static let keyON = 30, keyF = 31, keyG = 32, keyENTER = 25, keyBSP = 24

    /// Whether the f (31) or g (32) prefix is pending: its annunciator is lit.
    public func shiftPending(_ shift: Int) -> Bool {
        let label = shift == Self.keyF ? "f" : "g"
        return calc.lcd().annunciators(for: CalculatorModel.with(id: calc.model)).contains { $0.label == label }
    }

    /// A click on a key's gold (f) or blue (g) legend: the shift, then the key held down
    /// (released by the normal release). When that shift is already pending it is not pressed
    /// again (no f f); a pending other shift is replaced by pressing this one, as on the
    /// calculator (f then g = g), so the program records exactly "shift key".
    public func pressShifted(_ shift: Int, _ code: Int) throws {
        if !shiftPending(shift) {
            press(shift); try run(ms: max(minimumHoldMs, 100))
            release(shift); try run(ms: 150)
        }
        press(code)
    }

    /// Hold several keys, then ON, as on the calculator (e.g. g-ENTER-ON).
    public func chordWithON(_ keys: [Int]) throws {
        for k in keys { calc.press(k) }
        try run(ms: 100)
        calc.press(Self.keyON); try run(ms: 300)
        calc.release(Self.keyON); try run(ms: 200)
        for k in keys { calc.release(k) }
        try run(ms: 800)
    }

    private var isBlank: Bool { calc.lcd().text.allSatisfy { $0 == " " } }

    /// Turn the calculator off. A message on screen ("Pr Error", f MEM...) eats an ON, so
    /// press ON until the display is blank. (A blank display is taken as "off"; a running
    /// program also shows a blank display, and ON stops it first.)
    public func powerOff() throws {
        for _ in 0..<3 where !isBlank { try tap(Self.keyON); try run(ms: 500) }
    }

    public func powerOn() throws {
        for _ in 0..<2 where isBlank { try tap(Self.keyON); try run(ms: 1000) }
    }

    // MARK: boot / restore

    /// Reset the chip and turn the calculator on. With a saved state of the same firmware,
    /// select the ROM it was saved from (multi firmware) and put the memory back.
    /// Returns a note for the user when the saved state could not be used.
    @discardableResult
    public func boot(restoring saved: SavedState?) throws -> String? {
        try calc.startWhole()
        simMs = 0; downSince = [:]; pendingRelease = []; delayedRelease = []
        try tap(Self.keyON); try run(ms: 1500)
        var note: String?
        if let s = saved {
            if s.firmwareID != firmwareID {
                note = "The saved calculator memory belongs to another firmware; starting with a cleared memory."
            } else {
                if s.variant != variant { try switchVariant(to: s.variant) }
                if s.variant == variant {
                    try putMemory(s.memory)
                    return nil
                }
                note = "Could not switch the firmware back to the model the memory was saved from."
            }
        }
        try clearPrError()             // after a cold start
        return note
    }

    /// Load a 2 KB memory image into the running calculator and let the firmware take it
    /// (it is checked when the calculator turns on).
    public func putMemory(_ data: Data) throws {
        try powerOn()
        try calc.loadMemory(data)
        try powerOff()
        try powerOn()
    }

    /// The 2 KB memory image as a VoyagerSave dump would give it. The firmware keeps the
    /// working registers in the CPU while it is on and writes them back when it turns off,
    /// so the calculator is turned off for the copy (and back on when `turnBackOn`).
    public func memory(turnBackOn: Bool = true) throws -> Data {
        let wasOn = !isBlank
        try powerOff()
        let d = try calc.saveMemory()
        if wasOn && turnBackOn { try powerOn() }
        return d
    }

    /// What a memory image would do on this firmware, found by loading it into a scratch
    /// calculator with the same firmware and model, as on the calculator: in while it is off,
    /// then ON. The firmware checks the image at ON: another model's memory gives Pr Error, or
    /// (15C firmware with a 16C image) a silent cold start; garbage gives nothing at all.
    /// Images saved while the calculator was on (every dump read over USB, e.g. Jose's
    /// FinancePac) need two ONs: the first one turns that calculator off. So ON is pressed up
    /// to three times until the display shows something, and then the memory itself is
    /// compared: if the firmware kept the registers / program area unchanged, it fits.
    public enum MemoryCheck: Equatable, Sendable {
        case fits(display: String)
        case rejected                          // Pr Error
        case changed(bytes: Int)               // started, but cleared / rewrote part of the memory
        case unreadable                        // nothing on the display after three ONs
        case wrongSize(Int)
        /// Starts and keeps its memory, but g MEM gives Error 10: the image uses more registers
        /// than this model has (an HP-15C (15.2) "double memory" image on the 15.0 HP-15C).
        case needsMoreMemory
        public var fits: Bool { if case .fits = self { return true }; return false }
    }

    /// The part of the image compared: the Nut RAM (registers, program, flags). The first
    /// 0x100 bytes (wrapper header, CPU registers, status registers) and the trailer from
    /// 0x7F0 change at power cycles. 0x7E0..0x7EF is the top of the program (lines 1-14).
    public static let memoryCompareRange = 0x100..<0x7F0

    public static func checkMemory(_ mem: Data, firmware: Data, variant: Int) -> MemoryCheck {
        guard mem.count == VoyagerCalculator.memorySize else { return .wrongSize(mem.count) }
        let m = CalculatorMachine()
        do {
            try m.loadFirmware(firmware)
            try m.boot(restoring: nil)
            if m.variant != variant { try m.switchModel(to: variant) }
            try m.powerOff()
            try m.calc.loadMemory(mem)
            var shown = ""
            for _ in 0..<3 {
                try m.tap(keyON); try m.run(ms: 1500)
                let t = m.displayText
                if t.contains("Error") && t.contains("Pr") { return .rejected }
                if !t.allSatisfy({ $0 == " " }) { shown = t; break }
                if m.calc.inspect()?.running == true { shown = "running"; break }
            }
            if shown.isEmpty { return .unreadable }
            try m.powerOff()
            let after = try m.calc.saveMemory()
            let a = [UInt8](mem), b = [UInt8](after)
            let changed = memoryCompareRange.filter { a[$0] != b[$0] }.count
            if changed > 0 { return .changed(bytes: changed) }
            if variant == 150 || variant == 152, shown != "running" {
                try m.powerOn()
                if try m.memoryStatus().contains("Error 10") { return .needsMoreMemory }
            }
            return .fits(display: shown.trimmingCharacters(in: .whitespaces))
        } catch {
            return .unreadable
        }
    }

    /// The models (variants) of this firmware whose memory the image is; 15.0 and 15.2 share
    /// their memory, so a 15C image gives both.
    /// HP-15C g MEM ("dd uu pp-b"), read while RCL is held, on a scratch machine. The 15.0
    /// and 15.2 ROMs compute the free registers from their own memory size, so a 15.2 image
    /// that uses more than the 15.0's registers shows Error 10 there (and on a real 15C in 15.0).
    func memoryStatus() throws -> String {
        let rcl = 34
        try tap(Self.keyG)
        calc.press(rcl); try calc.run(ms: 400)
        let t = displayText
        calc.release(rcl); try calc.run(ms: 800)
        return t
    }

    /// True when the image only fits the HP-15C (15.2) double-memory mode: on the 15.0 it
    /// starts but g MEM gives Error 10. Firmware without a 15.0 image: false.
    public static func needs152(_ mem: Data, firmware: Data, among variants: [Int]) -> Bool {
        variants.contains(150) && variants.contains(152)
            && checkMemory(mem, firmware: firmware, variant: 150) == .needsMoreMemory
    }

    public static func identifyMemory(_ mem: Data, firmware: Data, among variants: [Int]) -> [Int] {
        variants.filter { checkMemory(mem, firmware: firmware, variant: $0).fits }
    }

    /// The raw image right now, without turning the calculator off.
    public func rawMemory() throws -> Data { try calc.saveMemory() }

    public func savedState(turnBackOn: Bool = true) throws -> SavedState {
        SavedState(memory: try memory(turnBackOn: turnBackOn), variant: variant, firmwareID: firmwareID)
    }

    /// Key under each label of the multi-ROM model menu ("12 15.2  16" / "15 15.2  16").
    public static func modelMenuKey(for variant: Int) -> Int? {
        switch variant {
        case 120, 150: return 1
        case 152: return 3
        case 160: return 5
        default: return nil
        }
    }

    public var displayText: String { calc.lcd().text }
    public var showsPrError: Bool { displayText.contains("Pr Error") }

    /// "Pr Error" (after a memory reset) goes away with any key; ← is harmless there.
    public func clearPrError() throws {
        if showsPrError { try tap(Self.keyBSP) }
    }

    /// Use the calculator's own model switch, as on the calculator: off, g-ENTER-ON (the
    /// service menu), 4 (the model menu: "12 15.2  16" on the 12C multi, "15 15.2  16" on
    /// the 15C 3-ROM builds), then the key under the label. The firmware restarts as that
    /// model, normally with a cleared memory ("Pr Error", cleared here with ←).
    public func switchVariant(to v: Int) throws {
        guard images.count > 1, images.contains(v), let k = Self.modelMenuKey(for: v) else { return }
        try powerOff()
        try chordWithON([Self.keyG, Self.keyENTER])
        try tap(16)                    // "4": model menu
        try tap(k); try run(ms: 2000)
        try clearPrError()
        try powerOn()
    }

    public enum SwitchError: Error, LocalizedError, Equatable {
        case notInFirmware(Int)
        case didNotSwitch(wanted: Int, running: Int)
        public var errorDescription: String? {
            switch self {
            case .notInFirmware(let v): return "This firmware has no \(Self.name(v)) image."
            case .didNotSwitch(let w, let r): return "The calculator did not switch to the \(Self.name(w)); it is running as the \(Self.name(r))."
            }
        }
        static func name(_ v: Int) -> String { CalculatorMachine.variantName(v) }
    }

    /// Menu title of a calculator image.
    public static func variantName(_ v: Int) -> String {
        switch v {
        case 120: return "12C"
        case 150: return "15C"
        case 152: return "15C (15.2)"
        case 160: return "16C"
        default: return "\(v)"
        }
    }

    /// The model chooser: switch and check that the calculator really runs the new image.
    public func switchModel(to v: Int) throws {
        guard images.contains(v), images.count > 1 else { throw SwitchError.notInFirmware(v) }
        releaseAll()
        try switchVariant(to: v)
        if variant != v { throw SwitchError.didNotSwitch(wanted: v, running: variant) }
    }

    /// A documented key combination with ON (off first, hold the keys, ON, let go).
    public func perform(_ chord: KeyChord) throws {
        releaseAll()
        try powerOff()
        try chordWithON(chord.keys)
    }
}
