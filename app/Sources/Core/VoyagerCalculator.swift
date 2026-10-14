// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// VoyagerCalculator.swift - thin Swift wrapper around the C core (voyager_core.h).
// Not thread-safe: one owner thread (CalculatorEngine) uses it.

import Foundation
import VoyagerCore

public enum CalculatorError: Error, LocalizedError, Equatable {
    case firmware(String)
    case state(String)
    case fault(String)
    case argument(String)

    public var errorDescription: String? {
        switch self {
        case .firmware(let s): return s
        case .state(let s): return s
        case .fault(let s): return "The emulated chip stopped: \(s)"
        case .argument(let s): return s
        }
    }
}

/// What the LCD shows, as plain values (index 0 = leftmost digit).
public struct LCDState: Equatable, Sendable {
    public var segments: [UInt8] = Array(repeating: 0, count: 10)   // a=1 b=2 c=4 d=8 e=16 f=32 g=64
    public var dots: [Bool] = Array(repeating: false, count: 10)
    public var commas: [Bool] = Array(repeating: false, count: 10)
    public var minus = false
    /// Raw annunciator bits of the LCD memory (bit n = LCD bit n); model tables give names.
    public var annunciatorBits: UInt64 = 0
    public var text = ""

    public init() {}

    public static let blank = LCDState()

    /// Lit annunciator labels for a model.
    public func annunciators(for model: CalculatorModel) -> [Annunciator] {
        model.annunciators.filter { annunciatorBits >> UInt64($0.bit) & 1 == 1 }
    }
}

public enum CalculatorFamily: Int, Sendable {
    case none = 0, hp12c = 12, hp15c = 15, hp16c = 16, multi = 99
}

public final class VoyagerCalculator {
    private let handle: OpaquePointer
    /// The C core handle, for the read-only extensions in this module (Inspector.swift).
    var rawHandle: OpaquePointer { handle }

    public init() {
        guard let h = vc_create() else { fatalError("vc_create failed (out of memory)") }
        handle = h
    }
    deinit { vc_destroy(handle) }

    private var lastError: String { String(cString: vc_last_error(handle)) }

    private func check(_ r: Int32) throws {
        let v = Int(r)
        if v >= 0 { return }
        switch v {
        case Int(VC_ERR_FIRMWARE): throw CalculatorError.firmware(lastError)
        case Int(VC_ERR_STATE): throw CalculatorError.state(lastError)
        case Int(VC_ERR_FAULT): throw CalculatorError.fault(lastError)
        default: throw CalculatorError.argument(lastError)
        }
    }

    // MARK: firmware and engine

    public func loadFirmware(_ data: Data) throws {
        let r: Int32 = data.withUnsafeBytes { raw in
            vc_load_firmware(handle, raw.bindMemory(to: UInt8.self).baseAddress, raw.count)
        }
        try check(r)
    }

    public var family: CalculatorFamily { CalculatorFamily(rawValue: Int(vc_firmware_family(handle))) ?? .none }
    /// Active model: 12, 15 or 16. Follows the calculator's own model switch.
    public var model: Int { Int(vc_model(handle)) }
    /// 120, 150, 152 (15C long memory) or 160.
    public var variant: Int { Int(vc_model_variant(handle)) }
    public var firmwareInfo: String { String(cString: vc_firmware_info(handle)) }
    /// Calculator images in the firmware (120, 150, 152, 160), in the order of the calculator's
    /// own model menu; one for single-image firmware, empty without firmware.
    public var firmwareImages: [Int] {
        var v = [Int32](repeating: 0, count: 8)
        let n = Int(vc_firmware_images(handle, &v, 8))
        return n > 0 ? v.prefix(min(n, 8)).map(Int.init) : []
    }

    /// Start the whole-calculator engine (the calculator is off until ON).
    public func startWhole() throws { try check(vc_start(handle, Int32(VC_ENGINE_WHOLE), 0)) }

    public func setBattery(volts: Double) { _ = vc_set_battery(handle, volts) }

    // MARK: keys and time

    public func press(_ code: Int) { _ = vc_press_key(handle, Int32(code)) }
    public func release(_ code: Int) { _ = vc_release_key(handle, Int32(code)) }

    /// Advance simulated time (10 ms steps).
    public func run(ms: Int) throws { try check(vc_run_ms(handle, UInt32(max(10, ms)))) }

    /// Press, hold, release and let the calculator react (like a finger).
    public func tap(_ code: Int, holdMs: Int = 120, afterMs: Int = 600) throws {
        press(code); try run(ms: holdMs); release(code); try run(ms: afterMs)
    }

    public static func keyCode(model: Int, name: String) -> Int? {
        let k = Int(vc_key_code(Int32(model), name))
        return k >= 0 ? k : nil
    }

    // MARK: memory (2 KB VoyagerSave image)

    public static let memorySize = Int(VC_MEMORY_SIZE)

    public func saveMemory() throws -> Data {
        var buf = [UInt8](repeating: 0, count: Self.memorySize)
        try check(vc_save_memory(handle, &buf))
        return Data(buf)
    }

    public func loadMemory(_ data: Data) throws {
        guard data.count == Self.memorySize else {
            throw CalculatorError.argument("A memory file must be exactly \(Self.memorySize) bytes (this one is \(data.count)).")
        }
        let buf = [UInt8](data)
        try check(vc_load_memory(handle, buf))
    }

    // MARK: display

    public func lcd() -> LCDState {
        var d = vc_display()
        var out = LCDState()
        guard Int(vc_get_display_cells(handle, &d)) == Int(VC_OK) else { return out }
        withUnsafeBytes(of: d.seg) { out.segments = Array($0) }
        withUnsafeBytes(of: d.dot) { out.dots = $0.map { $0 != 0 } }
        withUnsafeBytes(of: d.comma) { out.commas = $0.map { $0 != 0 } }
        out.minus = d.minus != 0
        out.annunciatorBits = d.ann_bits
        var t = [CChar](repeating: 0, count: 48)
        _ = vc_display_text(&d, &t, t.count)
        out.text = String(cString: t)
        return out
    }

    public var displayText: String { lcd().text }

    public var stats: (arm: UInt64, nut: UInt64, simMs: UInt64, sleeps: UInt64) {
        var s = vc_stats()
        vc_get_stats(handle, &s)
        return (s.arm_instructions, s.nut_instructions, s.sim_ms, s.sleeps)
    }
}
