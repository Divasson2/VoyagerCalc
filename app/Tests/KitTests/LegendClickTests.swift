// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// 0.5.5: clicking a key's gold (f) legend sends f + key, its blue (g) legend g + key.
// Hit zones per photo face, the drawn zones, and the program line recorded by LBL + A.

import Foundation
import XCTest
#if canImport(VoyagerKit)
@testable import VoyagerKit
#endif

final class LegendClickTests: XCTestCase {
    private let models: [CalculatorModel] = [.hp12c, .hp15c, .hp16c]
    private func inside(_ r: CGRect, _ a: CGRect) -> Bool {       // (corelibs' CGRect.contains(CGRect) is unreliable)
        let e = 1e-9
        return r.minX >= a.minX - e && r.maxX <= a.maxX + e && r.minY >= a.minY - e && r.maxY <= a.maxY + e
    }

    func testPhotoZonesPerFace() throws {
        for m in models {
            let face = try XCTUnwrap(m.photoFace, m.name)
            var all: [(Int, KeyPart, CGRect)] = []
            for k in m.keys {
                let z = try XCTUnwrap(face.zones(k), "\(m.name) \(k.code)")
                let cap = try XCTUnwrap(face.keyRect(k.code)), area = try XCTUnwrap(face.hitRect(k.code))
                XCTAssertEqual(z.f == nil, k.f.isEmpty, "\(m.name) \(k.face): gold zone only with a gold legend")
                XCTAssertEqual(z.g == nil, k.g.isEmpty, "\(m.name) \(k.face): blue zone only with a blue legend")
                for p in KeyPart.allCases { if let r = z.rect(p) {
                    XCTAssertTrue(inside(r, area), "\(m.name) \(k.face) \(p) inside the key's area \(r) \(area)")
                    all.append((k.code, p, r))
                } }
                // probes: just above the cap = gold, upper cap (main legend) = face, bottom of the cap = blue
                let x = cap.midX
                let above = CGPoint(x: x, y: cap.minY - (cap.minY - area.minY) / 2)
                let main = CGPoint(x: x, y: cap.minY + cap.height * 0.3)
                let blue = CGPoint(x: x, y: cap.maxY - (face.keys[24]?.height ?? cap.height) * 0.12)
                if !k.f.isEmpty { XCTAssertEqual(face.part(at: above, model: m).map { "\($0.code) \($0.part)" }, "\(k.code) fLabel", "\(m.name) \(k.face)") }
                XCTAssertEqual(face.part(at: main, model: m).map { "\($0.code) \($0.part)" }, "\(k.code) face", "\(m.name) \(k.face)")
                if !k.g.isEmpty { XCTAssertEqual(face.part(at: blue, model: m).map { "\($0.code) \($0.part)" }, "\(k.code) gLabel", "\(m.name) \(k.face)") }
            }
            // no two zones overlap, also between neighbouring keys
            for i in all.indices { for j in all.indices where j > i {
                let o = all[i].2.intersection(all[j].2)
                XCTAssertTrue(o.isNull || o.width * o.height < 1e-9, "\(m.name): \(all[i].0) \(all[i].1) overlaps \(all[j].0) \(all[j].1)")
            } }
            // the main legend of every key keeps a face zone at least half the cap high
            for k in m.keys where k.style != .enter {
                let z = face.zones(k)!, cap = face.keyRect(k.code)!
                XCTAssertGreaterThan(z.face.intersection(cap).height, cap.height * 0.5, "\(m.name) \(k.face)")
            }
        }
    }

    /// The tall ENTER key: gold zone above it (12C PREFIX, 15C RAN#, 16C WINDOW) and blue LSTx zone.
    func testEnterHasGoldAndBlueZones() throws {
        for m in models {
            let face = try XCTUnwrap(m.photoFace), k = try XCTUnwrap(m.key(code: 25))
            let z = try XCTUnwrap(face.zones(k)), cap = try XCTUnwrap(face.keyRect(25))
            let f = try XCTUnwrap(z.f, "\(m.name) ENTER gold zone"), g = try XCTUnwrap(z.g, "\(m.name) ENTER blue zone")
            XCTAssertEqual(f.maxY, cap.minY, accuracy: 1e-9)
            XCTAssertGreaterThan(f.height, cap.height * 0.15)
            XCTAssertEqual(face.part(at: CGPoint(x: f.midX, y: f.midY), model: m)?.part, .fLabel, m.name)
            XCTAssertEqual(face.part(at: CGPoint(x: f.midX, y: f.midY), model: m)?.code, 25, m.name)
            XCTAssertEqual(face.part(at: CGPoint(x: g.midX, y: g.midY), model: m)?.part, .gLabel, m.name)
            for code in [35] { XCTAssertEqual(face.part(at: CGPoint(x: cap.midX, y: cap.midY + cap.height * 0.3), model: m)?.code, 25, "\(m.name) \(code)") }
        }
    }

    func testDrawnZones() {
        let spec = CalculatorModel.hp15c.key(code: 10)!          // SST: f LBL, g BST
        let legend = CGRect(x: 0, y: 0, width: 50, height: 10), key = CGRect(x: 5, y: 10, width: 40, height: 24)
        let z = KeyZones.drawn(legend: legend, key: key, unit: 24, spec: spec)
        XCTAssertEqual(z.f, CGRect(x: 0, y: 0, width: 50, height: 10))
        XCTAssertEqual(z.g, CGRect(x: 5, y: 34 - 24 * 0.30, width: 40, height: 24 * 0.30))
        XCTAssertEqual(z.part(at: CGPoint(x: 25, y: 5)), .fLabel)
        XCTAssertEqual(z.part(at: CGPoint(x: 25, y: 15)), .face)
        XCTAssertEqual(z.part(at: CGPoint(x: 25, y: 32)), .gLabel)
        let on = KeyZones.drawn(legend: legend, key: key, unit: 24, spec: CalculatorModel.hp15c.key(code: 30)!)
        XCTAssertNil(on.f); XCTAssertNil(on.g); XCTAssertEqual(on.face, key)
        XCTAssertEqual(spec.shift(for: .fLabel), 31); XCTAssertEqual(spec.shift(for: .gLabel), 32)
        XCTAssertNil(spec.shift(for: .face))
        XCTAssertNil(CalculatorModel.hp15c.key(code: 31)!.shift(for: .fLabel), "the f key has no legend")
    }

    // MARK: the recorded program line

    private func machine(_ data: Data?, variant: Int? = nil) throws -> CalculatorMachine {
        guard let data else { throw XCTSkip("no firmware") }
        let m = CalculatorMachine(); try m.loadFirmware(data); try m.boot(restoring: nil)
        if let v = variant, m.variant != v { try m.switchModel(to: v) }
        return m
    }
    private func click(_ m: CalculatorMachine, _ code: Int, shift: Int? = nil) throws {
        if let s = shift { try m.pressShifted(s, code) } else { m.press(code) }
        try m.run(ms: 150); m.release(code); try m.run(ms: 500)
    }
    private func current(_ m: CalculatorMachine) -> String {
        guard let s = m.calc.inspect(), let l = s.program.first(where: { $0.line == s.line }) else { return "-" }
        return "\(l.keys) \(l.fullMnemonic)"
    }
    /// Enter PRGM by its blue legend (g P/R on R/S, 15C / 16C), clear, then LBL + A.
    private func lblA(_ m: CalculatorMachine, lbl: (code: Int, shift: Int), a: Int) throws -> [String] {
        try click(m, 20, shift: 32)                            // g P/R
        XCTAssertTrue(m.calc.inspect()?.programMode == true, "PRGM mode")
        try click(m, lbl.code, shift: lbl.shift)               // the LBL legend
        try click(m, a)                                        // A
        let first = current(m)
        // pending shifts: f already pending -> no f f; the other shift pending -> replaced
        try click(m, lbl.shift == 31 ? 31 : 32)                // press the shift key itself first
        try click(m, lbl.code, shift: lbl.shift); try click(m, a)
        let second = current(m)
        try click(m, lbl.shift == 31 ? 32 : 31)                // the other shift pending
        try click(m, lbl.code, shift: lbl.shift); try click(m, a)
        return [first, second, current(m)]
    }

    func testLBLAOn15C() throws {
        let m = try machine(Fixtures.hp15c3ROM, variant: 150)
        let lines = try lblA(m, lbl: (10, 31), a: 0)           // f LBL (gold over SST), √x = A
        XCTAssertEqual(lines, Array(repeating: "42,21,11 f LBL A", count: 3), "\(lines)")
    }

    func testLBLAOn16C() throws {
        let m = try machine(Fixtures.firmware16Ext)
        let lines = try lblA(m, lbl: (11, 32), a: 0)           // g LBL (blue on GTO), A
        XCTAssertEqual(lines, Array(repeating: "43,22, A g LBL A", count: 3), "\(lines)")
    }
}
