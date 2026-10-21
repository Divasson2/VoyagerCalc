// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// VoyagerCalculator.swift - thin Swift wrapper around the C core (voyager_core.h).
// Not thread-safe: one owner thread (CalculatorEngine) uses it.

import Foundation
import VoyagerCore

public enum CalculatorError: Error, LocalizedError, Equatable {
    case firmware(String)
    /// Recognised but not available: an original-layout firmware that has not been verified, or a feature HP's original firmware
    /// does not offer (memory files). The text says so in plain words.
    case unsupported(String)
    case state(String)
    case fault(String)
    case argument(String)

    public var errorDescription: String? {
        switch self {
        case .firmware(let s): return s
        case .unsupported(let s): return s
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
        model.annunciators.filter { $0.isLit(annunciatorBits) }
    }
}

public enum CalculatorFamily: Int, Sendable {
    case none = 0, hp12c = 12, hp15c = 15, hp16c = 16, multi = 99
    /// HP's original firmware layout (the 2015 HP-12C): runs, with limits (see `FirmwareCapabilities`).
    case stock = 98
}

/// What a loaded firmware supports (0.6.6). HP's original 12C runs keyboard and display only: its RAM
/// layout differs from the CE builds, so the inspector, memory files and the model switch do not apply.
public struct FirmwareCapabilities: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let keysDisplay = FirmwareCapabilities(rawValue: 1 << 0)
    /// Registers & Program (stack, registers, program listing read from the Continuous Memory image).
    public static let inspect = FirmwareCapabilities(rawValue: 1 << 1)
    /// Memory files (VoyagerSave image): open, save, USB transfer, memory kept between launches.
    public static let memory = FirmwareCapabilities(rawValue: 1 << 2)
    /// The firmware reports which calculator runs, so the model follows its own switch.
    public static let modelSwitch = FirmwareCapabilities(rawValue: 1 << 3)
    public static let all: FirmwareCapabilities = [.keysDisplay, .inspect, .memory, .modelSwitch]
}

public final class VoyagerCalculator {
    private let handle: OpaquePointer
    /// The C core handle, for the read-only extensions in this module (Inspector.swift).
    var rawHandle: OpaquePointer { handle }

    public init() {
        guard let h = vc_create() else { fatalError("vc_create failed (out of memory)") }
        handle = h
        // 0.7.1: real 15C CE speed (the core default VC_IPC_REFERENCE 0.75 ran programs ~30 % fast at 4 MHz).
        vc_set_clock_ipc(h, VC_IPC_REAL)
    }
    deinit { vc_destroy(handle) }

    private var lastError: String { String(cString: vc_last_error(handle)) }

    private func check(_ r: Int32) throws {
        let v = Int(r)
        if v >= 0 { return }
        switch v {
        case Int(VC_ERR_FIRMWARE): throw CalculatorError.firmware(lastError)
        case Int(VC_ERR_UNSUPPORTED): throw CalculatorError.unsupported(lastError)
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
    /// What this firmware supports; empty without firmware.
    public var capabilities: FirmwareCapabilities { FirmwareCapabilities(rawValue: Int(vc_capabilities(handle))) }
    /// Diagnostics (tests): a 32-bit word of the emulated chip's memory.
    public func debugRead32(_ address: UInt32) -> UInt32 { vc_debug_read32(handle, address) }
    /// Active model: 12, 15 or 16. Follows the calculator's own model switch.
    public var model: Int { Int(vc_model(handle)) }
    /// 120, 150, 152 (15C long memory) or 160.
    public var variant: Int { Int(vc_model_variant(handle)) }
    public var firmwareInfo: String { String(cString: vc_firmware_info(handle)) }
    /// The checksum the calculator shows as XYXY ("C8C8"), nil when the image is too short.
    public var firmwareChecksum: String? {
        let v = Int(vc_firmware_checksum(handle))
        return v >= 0 ? String(format: "%02X%02X", v, v) : nil
    }
    /// Bytes dropped from the front of the file: 0x4000 when it was a full flash dump (bootloader first).
    public var firmwareBytesDropped: Int { Int(vc_firmware_stripped(handle)) }
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

    // MARK: 16C memory layouts (standard / extended B7B7 = E8E8 / early E3E3)

    /// Result of the structural pre-check of a memory image against the running firmware
    /// (vc_memory_precheck). A trial load cannot see a layout mismatch: the firmware accepts it
    /// and the registers just read wrong, so this runs first.
    public struct MemoryLayoutCheck: Equatable, Sendable {
        public enum Verdict: Int, Sendable { case ok = 0, warn = 1, convert = 2 }
        public var verdict: Verdict
        public var message: String
    }

    /// ARM instructions per CPU clock (vc_set_clock_ipc): the apps run at VC_IPC_REAL (0.577).
    public var clockIPC: Double { vc_clock_ipc(handle) }

    public func precheckMemory(_ data: Data) -> MemoryLayoutCheck? {
        guard data.count == Self.memorySize else { return nil }
        var chk = vc_memcheck()
        let buf = [UInt8](data)
        guard vc_memory_precheck(handle, buf, &chk) == Int32(VC_OK) else { return nil }
        let msg = withUnsafeBytes(of: chk.message) { raw in String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self) }
        return MemoryLayoutCheck(verdict: MemoryLayoutCheck.Verdict(rawValue: Int(chk.verdict)) ?? .ok, message: msg)
    }

    /// An image saved on the early extended-memory multi (E3E3: pool 8 bytes later) in the layout of
    /// B7B7 / E8E8, or nil when the image is not in the E3E3 layout.
    public static func convertE3E3Memory(_ data: Data) -> Data? {
        guard data.count == memorySize else { return nil }
        var buf = [UInt8](data)
        return vc_memory_convert_e3e3(&buf) == 1 ? Data(buf) : nil
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
