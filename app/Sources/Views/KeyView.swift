// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// KeyView.swift - one key: gold f legend above (drawn by the keyboard), the cap with
// its label, and the blue g legend on the front face. Clickable / tappable: the key is
// held down for as long as the mouse button or finger is.

import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Latching keys down for chords (⌘-click / right-click on the Mac, long press on iOS).
struct KeyLatchHandlers: @unchecked Sendable {
    var toggle: (Int) -> Void = { _ in }
    var hold: (Int) -> Void = { _ in }
}
private struct LatchedKeysKey: EnvironmentKey { static let defaultValue: Set<Int> = [] }
private struct KeyLatchHandlersKey: EnvironmentKey { static let defaultValue = KeyLatchHandlers() }
extension EnvironmentValues {
    /// Keys latched down now (drawn with a gold outline).
    var latchedKeys: Set<Int> {
        get { self[LatchedKeysKey.self] }
        set { self[LatchedKeysKey.self] = newValue }
    }
    var keyLatch: KeyLatchHandlers {
        get { self[KeyLatchHandlersKey.self] }
        set { self[KeyLatchHandlersKey.self] = newValue }
    }
}

/// Press / release of one key by mouse or finger, held as long as the button or finger is.
/// Mac: ⌘-click or right-click (Hold Key Down) latches the key instead. iOS: holding a key
/// for 0.8 s latches it (a haptic tick), so it stays down when the finger lifts. A latched
/// key is let go by clicking it again or by pressing any other key (see KeyLatch).
struct KeyPressGesture: ViewModifier {
    let code: Int
    @Binding var touching: Bool
    /// Where the press started, in the view's own coordinates (for the key's legend zones).
    let onPress: (CGPoint) -> Void
    let onRelease: () -> Void
    @Environment(\.keyLatch) private var latch
    @State private var latchedByGesture = false
    @State private var holdTask: Task<Void, Never>?
    static let longPressSeconds = 0.8

    func body(content: Content) -> some View {
        content
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !touching else { return }
                        touching = true
                        latchedByGesture = false
                        #if os(macOS)
                        if NSEvent.modifierFlags.contains(.command) {
                            latchedByGesture = true
                            latch.toggle(code)
                            return
                        }
                        #endif
                        onPress(value.startLocation)
                        #if os(iOS)
                        holdTask?.cancel()
                        holdTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: UInt64(Self.longPressSeconds * 1e9))
                            guard !Task.isCancelled, touching, !latchedByGesture else { return }
                            latchedByGesture = true
                            latch.hold(code)
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }
                        #endif
                    }
                    .onEnded { _ in
                        touching = false
                        holdTask?.cancel(); holdTask = nil
                        if latchedByGesture { latchedByGesture = false; return }
                        onRelease()
                    }
            )
            #if os(macOS)
            .contextMenu {
                Button("Hold Key Down (Latch)") { latch.toggle(code) }
            }
            #endif
    }
}

struct KeyView: View {
    let key: KeySpec
    let colors: ModelColors
    let pressed: Bool
    let unit: CGFloat                 // font scale (key height)
    /// .face, or .gLabel for a press on the blue legend (the gold one is the keyboard's).
    let onPress: (KeyPart) -> Void
    let onRelease: () -> Void

    @State private var touching = false
    @State private var hovering = false
    @State private var hoverG = false
    @Environment(\.latchedKeys) private var latched

    private var capColor: Color {
        switch key.style {
        case .fShift: return Color(rgb: colors.fKey)
        case .gShift: return Color(rgb: colors.gKey)
        default: return Color(rgb: colors.keyCap)
        }
    }

    private var faceColor: Color {
        switch key.style {
        case .fShift, .gShift: return Color(rgb: 0x1E1A17)
        default: return .white
        }
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let down = pressed || touching
            let frontH = KeyZones.drawnFrontHeight(keyHeight: h, unit: unit, isEnter: key.style == .enter)
            ZStack(alignment: .top) {
                // key body with front face
                RoundedRectangle(cornerRadius: w * 0.08, style: .continuous)
                    .fill(Color(rgb: colors.keyFront))
                    .shadow(color: .black.opacity(down ? 0.2 : 0.5), radius: down ? 0.5 : 1.5, y: down ? 0.5 : 1.5)
                // top face
                RoundedRectangle(cornerRadius: w * 0.07, style: .continuous)
                    .fill(LinearGradient(colors: [capColor.opacity(0.95), capColor], startPoint: .top, endPoint: .bottom))
                    .frame(height: h - frontH)
                    .overlay(
                        Text(key.face)
                            .font(.system(size: faceSize(h - frontH), weight: .semibold, design: .default))
                            .foregroundColor(faceColor)
                            .minimumScaleFactor(0.4)
                            .lineLimit(1)
                            .padding(.horizontal, w * 0.06)
                    )
                // g legend on the front face
                if !key.g.isEmpty {
                    Text(key.g)
                        .font(.system(size: unit * 0.22, weight: .medium))
                        .foregroundColor(Color(rgb: colors.gLegend))
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                        .frame(width: w * 0.96, height: frontH)
                        .offset(y: h - frontH)
                    if hoverG {
                        RoundedRectangle(cornerRadius: w * 0.06, style: .continuous)
                            .fill(Color(rgb: colors.gLegend).opacity(0.16))
                            .frame(width: w, height: frontH)
                            .offset(y: h - frontH)
                            .allowsHitTesting(false)
                    }
                }
                if hovering, !key.shortcuts.isEmpty {
                    Text(key.shortcutHint)
                        .font(.system(size: unit * 0.17, weight: .bold, design: .rounded))
                        .padding(.horizontal, 3).padding(.vertical, 1)
                        .background(Capsule().fill(Color.black.opacity(0.75)))
                        .foregroundColor(.white)
                        .offset(y: -unit * 0.12)
                        .allowsHitTesting(false)
                }
            }
            .offset(y: down ? h * 0.025 : 0)
            .brightness(down ? -0.08 : 0)
            .contentShape(Rectangle())
            .overlay {
                if latched.contains(key.code) || (key.style == .enter && latched.contains(25)) {
                    RoundedRectangle(cornerRadius: w * 0.08, style: .continuous)
                        .stroke(Color(rgb: 0xE3A63A), lineWidth: max(1.5, unit * 0.06))
                        .allowsHitTesting(false)
                }
            }
            .modifier(KeyPressGesture(code: key.code, touching: $touching,
                                      onPress: { p in onPress(!key.g.isEmpty && p.y >= h - frontH ? .gLabel : .face) },
                                      onRelease: onRelease))
            #if os(macOS)
            .onContinuousHover { phase in
                switch phase {
                case .active(let p): hovering = true; hoverG = !key.g.isEmpty && p.y >= h - frontH
                case .ended: hovering = false; hoverG = false
                }
            }
            #endif
        }
        .help(key.g.isEmpty ? key.shortcutHelp : key.shortcutHelp + " — blue legend: g \(key.g)")
        .accessibilityElement()
        .accessibilityLabel(Text(accessibilityName))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onPress(.face); onRelease() }
    }

    private func faceSize(_ capH: CGFloat) -> CGFloat {
        let base = min(capH * 0.48, unit * 0.40)
        return key.face.count > 3 ? base * 0.72 : base
    }

    private var accessibilityName: String {
        var parts = [key.face]
        if !key.f.isEmpty { parts.append("f \(key.f)") }
        if !key.g.isEmpty { parts.append("g \(key.g)") }
        return parts.joined(separator: ", ")
    }
}

/// The gold legend above a drawn key, clickable: f, then the key (0.5.5).
struct LegendArea: View {
    let key: KeySpec
    let colors: ModelColors
    let onPress: () -> Void
    let onRelease: () -> Void
    @State private var touching = false
    @State private var hovering = false

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .background {
                if hovering || touching {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color(rgb: colors.fLegend).opacity(touching ? 0.28 : 0.14))
                }
            }
            .modifier(KeyPressGesture(code: key.code, touching: $touching, onPress: { _ in onPress() }, onRelease: onRelease))
            #if os(macOS)
            .onHover { hovering = $0 }
            #endif
            .help("f \(key.f) — f, then \(key.face)")
            .accessibilityElement()
            .accessibilityLabel(Text("f \(key.f)"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onPress(); onRelease() }
    }
}
