// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// CalculatorLink.swift - the real calculator over USB HID (plan milestone M2): read and write
// the 2 KB Continuous Memory as VoyagerInterface's HIDManager.swift does, with timeouts.
// The protocol (ANALYSIS.md section 2, from the CE firmware's HID handler):
//   * 64-byte reports, VID 0x03F0, PID 0x1341, report ID 0. The calculator is a HID device only
//     after f + ENTER + ON (calculator off, hold f and ENTER, press ON).
//   * Output report whose first byte is >= 0x40: that byte is a command. 0xFE = send the 2,048
//     bytes at SRAM 0x20000018 (the memory image).
//   * Otherwise byte 0 is a length n and bytes 1...n go to the command queue. 'C' (0x43),
//     block, 32 bytes: copy them to 0x20000018 + block * 32. No checksum, no reply.
//   * The dump arrives as input reports [n, n bytes] with n < 64.
// Platform-neutral: the USB part is a CalculatorTransport (IOKit on the Mac, a fake in tests).

import Foundation

public protocol CalculatorTransport: AnyObject {
    /// Find and open the calculator. Throws LinkError.noDevice when it is not connected.
    func open() throws
    func close()
    /// Send one output report (CalculatorLink.reportSize bytes).
    func send(_ report: [UInt8]) throws
    /// One input report, or nil when none came within the timeout.
    func receive(timeout: TimeInterval) throws -> [UInt8]?
}

public enum LinkError: Error, LocalizedError, Equatable {
    case noDevice
    case accessDenied(Int32)
    case io(String)
    case timeout(received: Int)
    case badReport(length: Int)
    case wrongSize(Int)
    case mismatch(differences: Int, firstOffset: Int)

    public static let connectHint = "Connect the calculator by USB, turn it off, hold f and ENTER and press ON."

    public var errorDescription: String? {
        switch self {
        case .noDevice: return "No calculator found. " + Self.connectHint
        case .accessDenied(let r): return String(format: "macOS did not allow access to the calculator's USB connection (IOKit error 0x%08X).", UInt32(bitPattern: r))
        case .io(let s): return "USB error: \(s)"
        case .timeout(let n): return "The calculator stopped answering (\(n) of \(CalculatorLink.memorySize) bytes received). " + Self.connectHint
        case .badReport(let n): return "The calculator sent an unexpected USB report (length byte \(n))."
        case .wrongSize(let n): return "A calculator memory image is \(CalculatorLink.memorySize) bytes, not \(n)."
        case .mismatch(let d, let o): return String(format: "Read-back check failed: %d of %d bytes differ (first at offset 0x%03X).", d, CalculatorLink.memorySize, o)
        }
    }
}

public final class CalculatorLink {
    public static let vendorID = 0x03F0, productID = 0x1341
    public static let reportSize = 64, memorySize = 2048, blockSize = 32
    public static let dumpCommand: UInt8 = 0xFE, writeCommand = UInt8(ascii: "C")

    public let transport: CalculatorTransport
    /// Whole-dump timeout; the dump takes some 33 reports.
    public var readTimeout: TimeInterval = 3
    /// Pause after the dump command and between write reports (as VoyagerInterface).
    public var commandPause: TimeInterval = 0.1, packetPause: TimeInterval = 0.001
    public var writeAttempts = 3

    public init(transport: CalculatorTransport) { self.transport = transport }

    // MARK: framing

    /// [0xFE, 0, 0, ...]: send the memory.
    public static func dumpReport() -> [UInt8] {
        var r = [UInt8](repeating: 0, count: reportSize); r[0] = dumpCommand; return r
    }

    /// The 64 write reports: [34, 'C', block, 32 bytes, 0...].
    public static func writeReports(_ data: Data) throws -> [[UInt8]] {
        guard data.count == memorySize else { throw LinkError.wrongSize(data.count) }
        let bytes = [UInt8](data)
        return stride(from: 0, to: memorySize, by: blockSize).map { pos in
            var r = [UInt8](repeating: 0, count: reportSize)
            r[0] = UInt8(blockSize + 2); r[1] = writeCommand; r[2] = UInt8(pos / blockSize)
            r.replaceSubrange(3..<3 + blockSize, with: bytes[pos..<pos + blockSize])
            return r
        }
    }

    /// Add one input report [n, n bytes] to the dump. True when the dump is complete.
    public static func append(report r: [UInt8], to dump: inout Data) throws -> Bool {
        guard let n0 = r.first else { return dump.count == memorySize }
        let n = Int(n0)
        if n == 0 { return dump.count == memorySize }
        guard n < reportSize, n < r.count, dump.count + n <= memorySize else { throw LinkError.badReport(length: n) }
        dump.append(contentsOf: r[1...n])
        return dump.count == memorySize
    }

    public static func compare(_ a: Data, _ b: Data) -> (differences: Int, firstOffset: Int)? {
        let x = [UInt8](a), y = [UInt8](b)
        var n = 0, first = -1
        for i in 0..<max(x.count, y.count) where i >= x.count || i >= y.count || x[i] != y[i] {
            n += 1; if first < 0 { first = i }
        }
        return n == 0 ? nil : (n, first)
    }

    // MARK: operations (blocking: call them off the main thread)

    /// Read the calculator's 2 KB memory.
    public func readMemory() throws -> Data {
        try transport.open()
        defer { transport.close() }
        return try dump()
    }

    /// The part of the image that is the calculator's memory, from the CE firmware's RAM map
    /// (the same on C8C8 15.0 / 15.2 / 16C and E3E3 12C / 15.2 / 16C): the Nut CPU struct is at
    /// SRAM 0x20000020 (image 0x08..0x6F: registers, return stack, power state), its RAM at
    /// struct + 0x68 = image 0x70, 240 registers of 8 bytes up to 0x7EF. The 15C / 16C program
    /// grows down from the top, so lines 1, 2, ... are at 0x7EE, 0x7ED, ... (FinancePac: lines
    /// 1-14 are 0x7E0..0x7EF; a 16C keeps a pointer register at 0x7E0). After it, 0x7F0..0x7FF,
    /// a signature register and live counters (0x7FA / 0x7FB change between two reads).
    /// 'C' blocks are copied into the running calculator at once, so writing another CPU state
    /// there (the emulator's, saved while off) stops it mid-transfer (0.5.2 bug); 0.5.3 kept
    /// 0x7E0..0x7FF too and lost the program's first 14 lines (0.5.3 bug).
    public static let memoryRange = 0x70..<0x7F0

    /// HP-15C flag 8 (complex mode) is not in the Nut RAM: the firmware keeps it as a status bit
    /// of the Nut CPU, image byte 0x4C bit 3 (CPU struct + 0x2C), and rewrites the copy in S0A
    /// (byte 0xC4 bit 0) from it at the next key or power-on. Keeping the calculator's whole CPU
    /// state (as until 0.6.3) therefore dropped flag 8 while the 5 imaginary-stack registers
    /// stayed allocated (0.6.3 bug, docs/BUG-0.6.3-FLAG8-WRITE.md).
    public static let flag8Offset = 0x4C, flag8Mask: UInt8 = 0x08
    /// Flag 8 as the firmware sees it, from a 15C image.
    public static func flag8(_ image: Data) -> Bool { image.count > flag8Offset && [UInt8](image)[flag8Offset] & flag8Mask != 0 }

    /// What is sent: the calculator's own bytes outside memoryRange, the new image inside it.
    /// flag8 (HP-15C images only): also set or clear that one CPU status bit, nothing else of
    /// the CPU state.
    public static func merge(_ data: Data, into current: Data, flag8: Bool? = nil) -> Data {
        var out = [UInt8](current), d = [UInt8](data)
        out.replaceSubrange(memoryRange, with: d[memoryRange])
        if let f = flag8 {
            out[flag8Offset] = f ? out[flag8Offset] | flag8Mask : out[flag8Offset] & ~flag8Mask
            // keep the S0A copy consistent with it, as the firmware would
            out[0xC4] = f ? out[0xC4] | 1 : out[0xC4] & ~1
        }
        return Data(out)
    }

    /// Write a 2 KB memory image: read the calculator first, keep its live CPU state and
    /// trailer (merge), send only the 32-byte blocks that change, then read back and compare
    /// memoryRange. Rewrites up to writeAttempts times while the read-back is short or
    /// different; returns the read-back. flag8: see merge (pass it for HP-15C images).
    @discardableResult
    public func writeMemory(_ data: Data, flag8: Bool? = nil) throws -> Data {
        guard data.count == Self.memorySize else { throw LinkError.wrongSize(data.count) }
        try transport.open()
        defer { transport.close() }
        var current = try dump()
        let target = Self.merge(data, into: current, flag8: flag8)
        let reports = try Self.writeReports(target)
        var last: Error = LinkError.timeout(received: 0)
        for _ in 0..<max(1, writeAttempts) {
            let cur = [UInt8](current), tgt = [UInt8](target)
            for (b, r) in reports.enumerated() {
                let range = b * Self.blockSize..<(b + 1) * Self.blockSize
                if cur[range] == tgt[range] { continue }
                try transport.send(r)
                if packetPause > 0 { Thread.sleep(forTimeInterval: packetPause) }
            }
            do {
                let back = try dump()
                current = back
                if let d = Self.compare(back.subdata(in: Self.memoryRange), target.subdata(in: Self.memoryRange)) {
                    last = LinkError.mismatch(differences: d.differences, firstOffset: d.firstOffset + Self.memoryRange.lowerBound); continue
                }
                if let f = flag8, Self.flag8(back) != f {
                    last = LinkError.mismatch(differences: 1, firstOffset: Self.flag8Offset); continue
                }
                return back
            } catch let e as LinkError where e != .noDevice {
                last = e
            }
        }
        throw last
    }

    private func dump() throws -> Data {
        try transport.send(Self.dumpReport())
        if commandPause > 0 { Thread.sleep(forTimeInterval: commandPause) }
        var d = Data()
        let end = Date().addingTimeInterval(readTimeout)
        while Date() < end {
            guard let r = try transport.receive(timeout: min(0.25, max(0.01, end.timeIntervalSinceNow))) else { continue }
            if try Self.append(report: r, to: &d) { return d }
        }
        throw LinkError.timeout(received: d.count)
    }
}
