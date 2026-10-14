// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// KeyChords.swift - key combinations that need several fingers: the documented chords with
// ON (Keys menu) and keys latched down by the user (⌘-click / right-click / long-press).

import Foundation

/// A key combination with ON: with the calculator off, hold the keys, press ON, let go.
/// All of them were tried on the firmware in the core (12C multi E3E3, 15C 3-ROM C8C8,
/// 16C B7B7); the key codes are positions, the same on the three models.
public enum KeyChord: String, CaseIterable, Identifiable, Sendable {
    case serviceMenu, usbMode, memoryReset, selfTest, selfTestLoop, keyboardTest, radixMark

    public var id: String { rawValue }

    /// Keys held with ON (row/column codes).
    public var keys: [Int] {
        switch self {
        case .serviceMenu: return [32, 25]      // g ENTER
        case .usbMode: return [31, 25]          // f ENTER
        case .memoryReset: return [29]          // −
        case .selfTest: return [19]             // ×
        case .selfTestLoop: return [39]         // +
        case .keyboardTest: return [9]          // ÷
        case .radixMark: return [37]            // .
        }
    }

    /// How the chord is written in the guides.
    public var chord: String {
        switch self {
        case .serviceMenu: return "g-ENTER-ON"
        case .usbMode: return "f-ENTER-ON"
        case .memoryReset: return "ON + −"
        case .selfTest: return "ON + ×"
        case .selfTestLoop: return "ON + +"
        case .keyboardTest: return "ON + ÷"
        case .radixMark: return "ON + ."
        }
    }

    public var title: String {
        switch self {
        case .serviceMenu: return "Service Menu"
        case .usbMode: return "USB Mode"
        case .memoryReset: return "Memory Reset"
        case .selfTest: return "Self-Test"
        case .selfTestLoop: return "Continuous Self-Test"
        case .keyboardTest: return "Keyboard Test"
        case .radixMark: return "Swap Decimal Point and Comma"
        }
    }

    public var menuTitle: String { "\(title) (\(chord))" }

    /// What it does, for help texts and the Keys menu.
    public var explanation: String {
        switch self {
        case .serviceMenu: return "Checksum (2), model (4), speed (5), key settings (6-8). ON leaves the menu."
        case .usbMode: return "On the calculator this waits for VoyagerSave over USB. There is no USB in the app: the calculator just turns on."
        case .memoryReset: return "Clears all programs, registers and settings (Pr Error)."
        case .selfTest: return "Runs the calculator's self-test and shows all segments when it passes."
        case .selfTestLoop: return "Repeats the self-test until you press a key."
        case .keyboardTest: return "Press every key in order, row by row; ON ends the test."
        case .radixMark: return "Switches the number display between 1,234.56 and 1.234,56."
        }
    }

    /// Asks before it runs (it clears the memory).
    public var needsConfirmation: Bool { self == .memoryReset }

    /// The 16C shows integers without a decimal point, so ON + . does nothing useful there.
    public func isAvailable(model: Int) -> Bool { self == .radixMark ? model != 16 : true }
}

/// Keys the user latched down to play a chord one key at a time. Pure logic: the app turns
/// the returned actions into presses and releases. A latched key stays down until it is
/// clicked again or another key is pressed and released; then all latched keys are let go,
/// a little after that key (so ON in g-ENTER-ON comes up before g and ENTER, as by hand).
public struct KeyLatch: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case press(Int)
        case release(Int)
        /// Release these a moment after the key that completed the chord.
        case releaseLater([Int])
    }

    public private(set) var latched: Set<Int> = []
    private var swallow: Set<Int> = []      // press/release of a latched key that unlatched it

    /// How long after the completing key the latched ones are let go (simulated ms).
    public static let releaseDelayMs = 200

    public init() {}

    public var isEmpty: Bool { latched.isEmpty }

    /// ⌘-click / right-click: latch the key down, or let everything go if it was latched.
    public mutating func toggle(_ k: Int) -> [Action] {
        if latched.contains(k) { return unlatchAll() }
        latched.insert(k)
        return [.press(k)]
    }

    /// Long-press: the key is already down (pressed by the touch) and now stays down.
    public mutating func holdBecameLatch(_ k: Int) -> [Action] {
        latched.insert(k)
        return []
    }

    /// Normal press of a key (click, tap, hardware key).
    public mutating func press(_ k: Int) -> [Action] {
        if latched.contains(k) {
            swallow.insert(k)
            return unlatchAll()
        }
        return [.press(k)]
    }

    /// Normal release.
    public mutating func release(_ k: Int) -> [Action] {
        if swallow.remove(k) != nil { return [] }
        if latched.contains(k) { return [] }            // the end of the long-press that latched it
        var a: [Action] = [.release(k)]
        if !latched.isEmpty { a.append(.releaseLater(latched.sorted())); latched = [] }
        return a
    }

    /// Let go of every latched key now.
    public mutating func unlatchAll() -> [Action] {
        let a = latched.sorted().map { Action.release($0) }
        latched = []
        return a
    }
}
