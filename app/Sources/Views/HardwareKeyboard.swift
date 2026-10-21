// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// HardwareKeyboard.swift - feeds the Mac / iPad keyboard to HardwareKeyRouter.

import SwiftUI

#if os(macOS)
import AppKit

/// Installs a local key monitor while the calculator is on screen.
@MainActor
struct HardwareKeyboardModifier: ViewModifier {
    let router: HardwareKeyRouter
    @State private var monitor: Any?
    /// The calculator's own window (0.7.1 key-focus fix: keys typed in another window, such as the Matrix Editor, stay there).
    @State private var home = WindowBox()

    func body(content: Content) -> some View {
        content
            .background(WindowReader(box: home).frame(width: 0, height: 0))
            .onAppear { install() }
            .onDisappear { remove() }
    }

    private func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { event in
            // leave menu shortcuts and text fields (sheets, dialogs) alone
            if event.modifierFlags.contains(.command) { return event }
            // another window has the keyboard (0.7.1): only key-ups still reach the router, so a key held while the
            // focus moved is let go
            if event.type != .keyUp, keyEventIsForOtherWindow(event.window, home: home.window) { return event }
            if let w = event.window, w.attachedSheet != nil || w.firstResponder is NSTextView || w.isSheet {
                return event
            }
            let consumed = MainActor.assumeIsolated { handle(event) }
            return consumed ? nil : event
        }
    }

    private func remove() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        router.releaseAll()
    }

    @MainActor
    private func handle(_ e: NSEvent) -> Bool {
        switch e.type {
        case .flagsChanged:
            switch e.keyCode {
            case 56, 60: router.modifier(.shift, down: e.modifierFlags.contains(.shift))
            case 58, 61: router.modifier(.option, down: e.modifierFlags.contains(.option))
            default: break
            }
            return false
        case .keyDown:
            guard let s = shortcut(e) else { return false }
            return router.keyDown(id: Int(e.keyCode), shortcut: s, isRepeat: e.isARepeat)
        case .keyUp:
            return router.keyUp(id: Int(e.keyCode))
        default:
            return false
        }
    }

    private func shortcut(_ e: NSEvent) -> KeyShortcut? {
        switch e.keyCode {
        case 36, 76: return .special(.returnKey)
        case 51, 117: return .special(.delete)
        case 53: return .special(.escape)
        case 48: return .special(.tab)
        case 123: return .special(.leftArrow)
        case 124: return .special(.rightArrow)
        case 125: return .special(.downArrow)
        case 126: return .special(.upArrow)
        default: break
        }
        // Option changes characters (Option-7 = ¶): use the key without Option, but keep Shift (* + _ %)
        let chars = e.modifierFlags.contains(.option) ? e.charactersIgnoringModifiers : e.characters
        guard let c = chars?.first else { return nil }
        return .char(c)
    }
}

/// A weak reference to the window a view is in, filled by WindowReader.
final class WindowBox {
    weak var window: NSWindow?
}

/// Reports the NSWindow the view is placed in.
struct WindowReader: NSViewRepresentable {
    let box: WindowBox
    func makeNSView(context: Context) -> NSView {
        let v = Reader(); v.box = box; return v
    }
    func updateNSView(_ v: NSView, context: Context) { (v as? Reader)?.box = box; box.window = v.window ?? box.window }
    final class Reader: NSView {
        var box: WindowBox?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if let w = window { box?.window = w } }
    }
}

/// Is this key event aimed at another window than `home` (tests)?
func keyEventIsForOtherWindow(_ eventWindow: NSWindow?, home: NSWindow?) -> Bool {
    guard let home else { return false }
    return eventWindow !== home
}

#else
import UIKit

/// A hidden first responder that receives hardware keyboard presses (iPad / iPhone).
@MainActor
struct HardwareKeyboardModifier: ViewModifier {
    let router: HardwareKeyRouter

    func body(content: Content) -> some View {
        content.background(KeyCaptureRepresentable(router: router).frame(width: 0, height: 0))
    }
}

@MainActor
private struct KeyCaptureRepresentable: UIViewControllerRepresentable {
    let router: HardwareKeyRouter
    func makeUIViewController(context: Context) -> KeyCaptureController {
        let c = KeyCaptureController(); c.router = router; return c
    }
    func updateUIViewController(_ c: KeyCaptureController, context: Context) { c.router = router }
}

final class KeyCaptureController: UIViewController {
    var router: HardwareKeyRouter?

    override var canBecomeFirstResponder: Bool { true }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); becomeFirstResponder() }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unused = Set<UIPress>()
        for p in presses {
            guard let key = p.key, let router else { unused.insert(p); continue }
            switch key.keyCode {
            case .keyboardLeftShift, .keyboardRightShift: router.modifier(.shift, down: true)
            case .keyboardLeftAlt, .keyboardRightAlt: router.modifier(.option, down: true)
            default:
                if key.modifierFlags.contains(.command) { unused.insert(p); continue }
                if let s = shortcut(key), router.keyDown(id: key.keyCode.rawValue, shortcut: s, isRepeat: false) { continue }
                unused.insert(p)
            }
        }
        if !unused.isEmpty { super.pressesBegan(unused, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unused = Set<UIPress>()
        for p in presses {
            guard let key = p.key, let router else { unused.insert(p); continue }
            switch key.keyCode {
            case .keyboardLeftShift, .keyboardRightShift: router.modifier(.shift, down: false)
            case .keyboardLeftAlt, .keyboardRightAlt: router.modifier(.option, down: false)
            default: if !router.keyUp(id: key.keyCode.rawValue) { unused.insert(p) }
            }
        }
        if !unused.isEmpty { super.pressesEnded(unused, with: event) }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        router?.releaseAll()
        super.pressesCancelled(presses, with: event)
    }

    private func shortcut(_ key: UIKey) -> KeyShortcut? {
        switch key.keyCode {
        case .keyboardReturnOrEnter, .keypadEnter: return .special(.returnKey)
        case .keyboardDeleteOrBackspace, .keyboardDeleteForward: return .special(.delete)
        case .keyboardEscape: return .special(.escape)
        case .keyboardTab: return .special(.tab)
        case .keyboardLeftArrow: return .special(.leftArrow)
        case .keyboardRightArrow: return .special(.rightArrow)
        case .keyboardDownArrow: return .special(.downArrow)
        case .keyboardUpArrow: return .special(.upArrow)
        default: break
        }
        let chars = key.modifierFlags.contains(.alternate) ? key.charactersIgnoringModifiers : key.characters
        guard let c = chars.first else { return nil }
        return .char(c)
    }
}
#endif

extension View {
    func hardwareKeyboard(_ router: HardwareKeyRouter) -> some View { modifier(HardwareKeyboardModifier(router: router)) }
}
