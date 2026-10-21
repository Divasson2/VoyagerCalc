// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// KeyClickSound.swift - the key click of View ▸ Key Click Sound (0.7.1): the same synthesised, soft, deep click as the
// Qt app (KeyClick.cpp, sample for sample): 50 ms, a 170 Hz -> 85 Hz "thock" with a low-passed noise attack.

import Foundation

public enum KeyClickSound {
    public static let rate = 44100

    /// The click as 16-bit mono samples at `rate` (pure function, unit-tested).
    public static func samples(rate: Int = KeyClickSound.rate) -> [Int16] {
        let len = 0.050
        let n = Int(Double(rate) * len)
        var out = [Int16](repeating: 0, count: n)
        var phase = 0.0
        var noise: UInt32 = 0x1234567
        var lp = 0.0
        for i in 0..<n {
            let t = Double(i) / Double(rate)
            let f = 85.0 + 85.0 * exp(-t / 0.012)                                   // 170 Hz falling to 85 Hz
            phase += 2 * Double.pi * f / Double(rate)
            let body = sin(phase) * exp(-t / 0.014) * (1 - exp(-t / 0.0006))
            noise = noise &* 1664525 &+ 1013904223
            let white = (Double(noise >> 8) / Double(1 << 24)) * 2 - 1
            lp += (white - lp) * 0.18                                                // soft (low-passed) attack
            let tick = lp * exp(-t / 0.0015) * 0.9
            var v = 0.62 * body + 0.30 * tick
            if i > n - rate / 200 { v *= Double(n - i) / Double(rate / 200) }       // 5 ms fade-out
            out[i] = Int16((min(1.0, max(-1.0, v)) * 32000).rounded())
        }
        return out
    }

    /// The click as a complete RIFF/WAVE file.
    public static func wav() -> Data {
        let s = samples()
        let data = UInt32(s.count * 2)
        var w = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { w.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { w.append(contentsOf: $0) } }
        w.append(contentsOf: Array("RIFF".utf8)); u32(36 + data); w.append(contentsOf: Array("WAVE".utf8))
        w.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate * 2)); u16(2); u16(16)
        w.append(contentsOf: Array("data".utf8)); u32(data)
        for x in s { u16(UInt16(bitPattern: x)) }
        return w
    }
}
