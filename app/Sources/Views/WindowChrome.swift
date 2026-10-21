// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// WindowChrome.swift - the Mac window's title bar keeps one colour across the whole width (0.6.7).
//
// The bug (0.6.6 and before): SwiftUI windows let the content run under a translucent title bar. The
// calculator's dark background and the Registers & Program flyout's light grey column both ran under it,
// so the bar took the colour of whatever was behind it: dark over the calculator, light grey over the flyout.
// The fix: the title bar is the standard opaque one and the content starts below it (no full-size content
// view), so nothing shows through and the bar has the window's own title bar colour from edge to edge, with
// or without the flyout, in the light and the dark appearance. Public AppKit API only. It is applied when
// the content gets its window and again when the window becomes key or leaves full screen (in case SwiftUI
// restores its own style).
// Checked by a render of the real ContentView in a never-shown NSWindow (Release067Tests).

import SwiftUI
#if os(macOS)
import AppKit

enum WindowChrome {
    /// Tests switch it off to render the 0.6.6 behaviour for comparison.
    nonisolated(unsafe) static var enabled = true

    @MainActor static func apply(to w: NSWindow) {
        guard enabled else { return }
        if w.titlebarAppearsTransparent { w.titlebarAppearsTransparent = false }
        if w.styleMask.contains(.fullSizeContentView) { w.styleMask.remove(.fullSizeContentView) }
    }
}

/// Put in the content's background: applies WindowChrome to the window the content is in.
struct WindowChromeSetter: NSViewRepresentable {
    final class Tracker: NSView {
        private var observers: [NSObjectProtocol] = []
        deinit { observers.forEach(NotificationCenter.default.removeObserver) }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver); observers = []
            guard let w = window else { return }
            DispatchQueue.main.async { WindowChrome.apply(to: w) }
            for n in [NSWindow.didBecomeKeyNotification, NSWindow.didExitFullScreenNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: n, object: w, queue: .main) { [weak w] _ in
                    MainActor.assumeIsolated { if let w { WindowChrome.apply(to: w) } }
                })
            }
        }
    }
    func makeNSView(context: Context) -> NSView { Tracker(frame: .zero) }
    func updateNSView(_ view: NSView, context: Context) {}
}
#endif
