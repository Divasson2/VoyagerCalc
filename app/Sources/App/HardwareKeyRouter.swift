// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// HardwareKeyRouter.swift - turns Mac / iPad hardware keyboard events into calculator keys.
// Shift tapped on its own = f, Option tapped on its own = g (Shift still types * + _ %
// as usual). Option + key = g, then the key. Each physical key holds its calculator key
// down while it is held, so chords work.

import Foundation

@MainActor
final class HardwareKeyRouter {
    enum Modifier { case shift, option }

    var model: () -> CalculatorModel = { .hp16c }
    var press: (Int) -> Void = { _ in }
    /// Shift (31 / 32) then key, like clicking the key's legend (no doubled or stacked shift).
    var pressShifted: (Int, Int) -> Void = { _, _ in }
    var release: (Int) -> Void = { _ in }

    private var held: [Int: Int] = [:]          // physical key id -> calculator code
    private var lone: [Modifier: Bool] = [:]    // modifier went down with no other key yet
    private var optionDown = false

    /// Returns true when the key was used by the calculator.
    func keyDown(id: Int, shortcut: KeyShortcut, isRepeat: Bool) -> Bool {
        lone[.shift] = false; lone[.option] = false
        let m = model()
        guard let key = m.key(for: shortcut), key.style != .fShift, key.style != .gShift else { return false }
        if isRepeat || held[id] != nil { return true }
        held[id] = key.code
        if optionDown, !key.g.isEmpty, let g = m.keys.first(where: { $0.style == .gShift }) {
            pressShifted(g.code, key.code)          // Option + key = its blue legend, as a click on it
        } else {
            press(key.code)
        }
        return true
    }

    func keyUp(id: Int) -> Bool {
        guard let code = held.removeValue(forKey: id) else { return false }
        release(code)
        return true
    }

    func modifier(_ mod: Modifier, down: Bool) {
        if mod == .option { optionDown = down }
        if down { lone[mod] = true; return }
        guard lone[mod] == true else { return }
        lone[mod] = false
        let style: KeyStyle = mod == .shift ? .fShift : .gShift
        if let k = model().keys.first(where: { $0.style == style }) { press(k.code); release(k.code) }
    }

    func releaseAll() {
        for code in held.values { release(code) }
        held = [:]
    }
}
