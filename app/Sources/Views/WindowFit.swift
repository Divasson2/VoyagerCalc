// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// WindowFit.swift - the window always has the calculator's shape (0.6.9).
//
// Since 0.6.5 opening Registers & Program makes the window wider by the flyout's width instead of squeezing the calculator.
// 0.6.5 did this with a stored "width added" delta and an animated setFrame running at the same time as SwiftUI's own flyout
// animation. That was bouncy (the calculator shrank while the window was still growing) and could lose the delta (zoomed window,
// two quick toggles, a manual resize, a smaller screen), which left black pillars after closing the flyout.
//
// 0.6.9: no stored delta and no animation fight. One rule, applied by plain arithmetic:
//     content width = calculator height x face aspect  +  (flyout shown ? 320 : 0)
// * The flyout column is exactly 320 pt wide (inspectorColumnWidth(min = ideal = max)).
// * Toggling the flyout moves the window to that rule IMMEDIATELY (no animation, in the same call that changes the state, before
//   SwiftUI lays out), so the calculator never changes size and nothing bounces.
// * While the user drags a window edge the delegate (windowWillResize) returns a size that obeys the rule, so pillar- or
//   letterboxing cannot appear; zoom (green button) gets a standard frame that obeys it too. Full screen cannot follow the
//   rule; there the surround has the calculator's dark background colour.
// * An idempotent check (WindowFitter.updateNSView, at launch, after a face / model change, after a screen change) repairs
//   any window that is not in shape, e.g. a frame restored from an older version.
// grow / shrink (the 0.6.5 delta functions) are kept only because their tests exist; the app no longer uses them.

import SwiftUI
#if os(macOS)
import AppKit
#endif

enum WindowFit {
    /// Width the inspector column opens with (`inspectorColumnWidth(ideal:)`).
    static let inspectorWidth: CGFloat = 320

    /// Smallest calculator height of the window (the content's minimum height, as in ContentView's frame).
    static let minCalculatorHeight: CGFloat = 300

    /// The shape rule on content sizes: the content size nearest to `proposed` that has the calculator's `aspect`
    /// (plus the 320 pt flyout column when `flyout`), not smaller than the minimum and not larger than `maxContent`.
    /// `current` (the content size now) decides which edge the user is dragging: the one that changed more, relatively, leads.
    static func fitContent(proposed: CGSize, current: CGSize, aspect: CGFloat, flyout: Bool, maxContent: CGSize) -> CGSize {
        let extra = flyout ? inspectorWidth : 0
        let a = max(aspect, 0.1)
        let relW = abs(proposed.width - current.width) / max(current.width, 1)
        let relH = abs(proposed.height - current.height) / max(current.height, 1)
        var h = relW > relH ? (proposed.width - extra) / a : proposed.height
        // the screen: shrink the leading height until both sides fit
        let maxH = min(maxContent.height, (maxContent.width - extra) / a)
        h = max(min(h, maxH), min(minCalculatorHeight, maxH))
        return CGSize(width: (h * a + extra).rounded(), height: h.rounded())
    }

    /// The frame with `extra` more width, growing to the right and kept inside `visible` (shifted left
    /// when needed, narrower only when the screen is too small). Returns the frame and the width really added.
    static func grow(_ f: CGRect, by extra: CGFloat, in visible: CGRect) -> (frame: CGRect, added: CGFloat) {
        var r = f
        let room = max(visible.width, f.width)            // never shrink a window that is already wider
        r.size.width = min(f.width + extra, room)
        if r.maxX > visible.maxX { r.origin.x = max(visible.minX, visible.maxX - r.width) }
        return (r, r.width - f.width)
    }

    /// The frame after giving back `added` points of width (not below `minWidth`), left edge kept.
    static func shrink(_ f: CGRect, by added: CGFloat, minWidth: CGFloat) -> CGRect {
        var r = f
        r.size.width = max(min(minWidth, f.width), f.width - added)
        return r
    }
}


extension WindowFit {
    /// The frame of a window with this content shape: the content height is kept (the window grows / shrinks to the right, the top
    /// edge stays), clamped so that it fits `visible`; the frame is moved left / down when it would run off the screen.
    static func shapedFrame(_ frame: CGRect, titleBarHeight: CGFloat, aspect: CGFloat, flyout: Bool, visible: CGRect) -> CGRect {
        let content = CGSize(width: frame.width, height: max(frame.height - titleBarHeight, 1))
        let maxContent = CGSize(width: visible.width, height: max(visible.height - titleBarHeight, 1))
        let c = fitContent(proposed: content, current: content,
                           aspect: aspect, flyout: flyout, maxContent: maxContent)       // nothing changed relatively: the height leads
        var r = CGRect(x: frame.minX, y: frame.maxY - (c.height + titleBarHeight), width: c.width, height: c.height + titleBarHeight)
        if r.maxX > visible.maxX { r.origin.x = max(visible.minX, visible.maxX - r.width) }
        if r.minY < visible.minY { r.origin.y = visible.minY }
        return r
    }
}

#if os(macOS)
/// Window delegate in front of SwiftUI's own: enforces the shape while resizing / zooming and forwards everything else.
final class WindowShapeDelegate: NSObject {
    weak var original: NSWindowDelegate?
    /// Current aspect and flyout state (set by WindowFitter whenever SwiftUI updates).
    var aspect: CGFloat = 1.62
    var flyout = false

    init(original: NSWindowDelegate?) { self.original = original }

    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (original as AnyObject?)?.responds(to: aSelector) == true
    }
    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if (original as AnyObject?)?.responds(to: aSelector) == true { return original }
        return super.forwardingTarget(for: aSelector)
    }

    /// The size a drag of a window edge may produce (also used by the tests).
    @MainActor func shapedFrameSize(_ sender: NSWindow, proposed frameSize: NSSize) -> NSSize {
        guard !sender.styleMask.contains(.fullScreen) else { return frameSize }
        let cur = sender.contentRect(forFrameRect: sender.frame).size
        let proposed = sender.contentRect(forFrameRect: NSRect(origin: .zero, size: frameSize)).size
        let visible = (sender.screen ?? NSScreen.main)?.visibleFrame.size ?? CGSize(width: 4000, height: 3000)
        let titleBar = sender.frame.height - cur.height
        let c = WindowFit.fitContent(proposed: proposed, current: cur, aspect: aspect, flyout: flyout,
                                     maxContent: CGSize(width: visible.width, height: visible.height - titleBar))
        return sender.frameRect(forContentRect: NSRect(origin: .zero, size: c)).size
    }
}

extension WindowShapeDelegate: NSWindowDelegate {
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        MainActor.assumeIsolated {
            let size = original?.windowWillResize?(sender, to: frameSize) ?? frameSize
            return shapedFrameSize(sender, proposed: size)
        }
    }

    func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame: NSRect) -> NSRect {
        MainActor.assumeIsolated {
            let base = original?.windowWillUseStandardFrame?(window, defaultFrame: defaultFrame) ?? defaultFrame
            let titleBar = window.frame.height - window.contentRect(forFrameRect: window.frame).height
            return WindowFit.shapedFrame(base, titleBarHeight: titleBar, aspect: aspect, flyout: flyout, visible: base)
        }
    }
}

/// Put in the calculator's background: keeps the window in the calculator's shape (see the header of this file).
struct WindowFitter: NSViewRepresentable {
    let showInspector: Bool
    let aspect: CGFloat
    /// The model's hook: AppModel calls it just BEFORE showInspector changes (see AppModel.windowFitHook).
    let app: AppModel

    final class Tracker: NSView {
        var showInspector = false, aspect: CGFloat = 1.62
        var shape: WindowShapeDelegate?
        private var observers: [NSObjectProtocol] = []
        deinit { observers.forEach(NotificationCenter.default.removeObserver) }

        /// Install our delegate in front of the window's (once; again if SwiftUI put its own back).
        @MainActor func installDelegate() {
            guard let w = window else { return }
            if let d = w.delegate as? WindowShapeDelegate { shape = d }
            else {
                let d = WindowShapeDelegate(original: w.delegate)
                w.delegate = d
                shape = d
                objc_setAssociatedObject(w, &WindowFitter.key, d, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)      // the window only holds it weakly
            }
            shape?.aspect = aspect; shape?.flyout = showInspector
        }

        /// Move the window into shape for `flyout` now (no animation). Idempotent.
        @MainActor func snap(flyout: Bool) {
            guard let w = window, !w.styleMask.contains(.fullScreen), !w.inLiveResize else { return }
            let visible = (w.screen ?? NSScreen.main)?.visibleFrame ?? w.frame
            let titleBar = w.frame.height - w.contentRect(forFrameRect: w.frame).height
            let target = WindowFit.shapedFrame(w.frame, titleBarHeight: titleBar, aspect: aspect, flyout: flyout, visible: visible)
            if abs(target.width - w.frame.width) > 0.5 || abs(target.height - w.frame.height) > 0.5 || abs(target.minX - w.frame.minX) > 0.5 {
                w.setFrame(target, display: true, animate: false)
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver); observers = []
            guard let w = window else { return }
            DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.installDelegate(); self?.snap(flyout: self?.showInspector ?? false) } }
            let center = NotificationCenter.default
            for n in [NSWindow.didBecomeKeyNotification, NSWindow.didExitFullScreenNotification, NSWindow.didChangeScreenNotification, NSWindow.didEndLiveResizeNotification] {
                observers.append(center.addObserver(forName: n, object: w, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.installDelegate(); self?.snap(flyout: self?.showInspector ?? false) }
                })
            }
        }
    }
    nonisolated(unsafe) static var key = 0

    func makeNSView(context: Context) -> Tracker {
        let t = Tracker(frame: .zero)
        t.showInspector = showInspector; t.aspect = aspect
        return t
    }

    func updateNSView(_ t: Tracker, context: Context) {
        let changed = t.showInspector != showInspector || t.aspect != aspect
        t.showInspector = showInspector; t.aspect = aspect
        t.shape?.aspect = aspect; t.shape?.flyout = showInspector
        // The toggle itself was already applied by the hook before SwiftUI changed anything; this only repairs a window that
        // is not in shape (face / model change, state at launch, another path that changed the flyout).
        let tracker = t
        app.windowFitHook = { [weak tracker] flyout in tracker?.shape?.flyout = flyout; tracker?.snap(flyout: flyout) }
        if changed { DispatchQueue.main.async { MainActor.assumeIsolated { tracker.snap(flyout: tracker.showInspector) } } }
    }
}
#endif
