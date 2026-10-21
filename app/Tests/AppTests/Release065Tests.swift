// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// 0.6.5: flyout contrast (WCAG), comma tail, window growth arithmetic, firmware-less snapshots.
// Pictures go to $VC_SCREENS_DIR (before/after sheets for the comma and the flyout colours).

#if os(macOS)
import AppKit
import SwiftUI
import XCTest

@MainActor
final class Release065Tests: XCTestCase {
    // MARK: WCAG contrast of the flyout colours (c)

    private func lum(_ h: UInt32) -> Double {
        func ch(_ v: UInt32) -> Double { let c = Double(v) / 255; return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * ch(h >> 16 & 255) + 0.7152 * ch(h >> 8 & 255) + 0.0722 * ch(h & 255)
    }
    private func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (x, y) = (lum(a), lum(b)); return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    func testLegendColoursReachAA() {
        typealias C = InspectorColors
        for (name, fg, bg) in [
            ("f on light panel", C.fLight, C.panelLight), ("g on light panel", C.gLight, C.panelLight),
            ("running on light panel", C.runningLight, C.panelLight),
            ("f on white", C.fLight, 0xFFFFFF), ("g on white", C.gLight, 0xFFFFFF),
            ("f on light band", C.fLight, 0xD3F1D3), ("g on light band", C.gLight, 0xD3F1D3),
            ("f on running light band", C.fLight, 0xB4E5B4), ("g on running light band", C.gLight, 0xB4E5B4),
            ("f on dark panel", C.fDark, C.panelDark), ("g on dark panel", C.gDark, C.panelDark),
            ("running on dark panel", C.runningDark, C.panelDark),
        ] as [(String, UInt32, UInt32)] {
            let r = contrast(fg, bg)
            print(String(format: "contrast %@: %.2f", name, r))
            XCTAssertGreaterThanOrEqual(r, 4.5, name)
        }
        // the old light-mode colours were the problem (kept here as the measured "before")
        XCTAssertLessThan(contrast(0xE3A33B, C.panelLight), 3)
        XCTAssertLessThan(contrast(0x5AA9E6, C.panelLight), 3)
        // the panel stays a light grey in the light appearance
        XCTAssertGreaterThan(lum(C.panelLight), 0.75)
        XCTAssertLessThan(lum(C.panelLight), lum(0xFFFFFF))
        XCTAssertEqual(C.panelLight, 0xECECEC)
    }

    // MARK: comma tail (e)

    func testCommaTailShape() {
        let dot = CGRect(x: 100, y: 50, width: 10, height: 10)
        let tail = LCDView.commaTail(dot: dot)
        let b = tail.boundingRect
        let d = dot.width
        // thin: about one dot wide at most (the old wedge was 1.3 D wide, 1.6 D long)
        XCTAssertLessThan(b.width, 1.1 * d)
        XCTAssertEqual(b.minY, dot.minY + 1.06 * d, accuracy: 0.01)          // starts below the dot: a hair of gap
        XCTAssertGreaterThan(b.minY, dot.maxY)
        XCTAssertEqual(b.maxY, dot.minY + 1.86 * d, accuracy: 0.01)          // ends 0.86 D below the dot
        // slants down-left: the lowest point is left of the top's centre
        let pts = LCDView.commaTailPoints
        let topCentre = (pts[0].x + pts[1].x) / 2
        let tip = pts.max(by: { $0.y < $1.y })!
        XCTAssertLessThan(tip.x, topCentre - 0.2)
        // narrowing: wider at the top than just above the tip
        XCTAssertGreaterThan(pts[1].x - pts[0].x, 0.7)
        XCTAssertLessThan(pts[3].x - pts[5].x, 0.4)
        // the dot itself is unchanged: tail never overlaps the dot rectangle
        XCTAssertFalse(b.intersects(dot))
    }

    // MARK: window growth (b)

    func testWindowGrowsToTheRightAndGivesTheWidthBack() {
        let screen = CGRect(x: 0, y: 0, width: 1600, height: 900)
        let w = CGRect(x: 100, y: 100, width: 900, height: 560)
        let (g, added) = WindowFit.grow(w, by: 320, in: screen)
        XCTAssertEqual(g.width, 1220); XCTAssertEqual(g.minX, 100); XCTAssertEqual(added, 320)
        XCTAssertEqual(g.height, w.height)
        let back = WindowFit.shrink(g, by: added, minWidth: 480)
        XCTAssertEqual(back, w)
    }

    func testWindowGrowthIsShiftedOrLimitedByTheScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let (g, added) = WindowFit.grow(CGRect(x: 800, y: 0, width: 600, height: 500), by: 320, in: screen)
        XCTAssertEqual(g.maxX, 1440); XCTAssertEqual(g.width, 920); XCTAssertEqual(added, 320)        // shifted left
        let small = CGRect(x: 0, y: 0, width: 1000, height: 700)
        let (g2, added2) = WindowFit.grow(CGRect(x: 0, y: 0, width: 900, height: 500), by: 320, in: small)
        XCTAssertEqual(g2.width, 1000); XCTAssertEqual(added2, 100)                                    // limited
        let (g3, added3) = WindowFit.grow(CGRect(x: 0, y: 0, width: 1200, height: 500), by: 320, in: small)
        XCTAssertEqual(g3.width, 1200); XCTAssertEqual(added3, 0)                                      // already wider than the screen
        XCTAssertEqual(WindowFit.shrink(CGRect(x: 0, y: 0, width: 500, height: 300), by: 320, minWidth: 480).width, 480)
    }

    // MARK: pictures

    private func render<V: View>(_ view: V, width: CGFloat, height: CGFloat, name: String, scale: CGFloat = 2) throws {
        let r = ImageRenderer(content: view.frame(width: width, height: height))
        r.scale = scale
        guard let cg = r.cgImage else { return XCTFail("render failed: \(name)") }
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
        let env = ProcessInfo.processInfo.environment["VC_SCREENS_DIR"]
        let dir = env.map { URL(fileURLWithPath: $0) } ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("VoyagerCalcScreens")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try png.write(to: dir.appendingPathComponent(name))
    }

    private struct OldTail: View {
        var body: some View {
            Canvas { ctx, size in
                let d = size.width * 0.22
                let dot = CGRect(x: size.width * 0.5, y: size.height * 0.25, width: d, height: d)
                ctx.fill(Path(dot), with: .color(.black))
                var tail = Path()                                    // the 0.6.4 wedge
                tail.move(to: CGPoint(x: dot.maxX, y: dot.maxY))
                tail.addLine(to: CGPoint(x: dot.maxX - d * 0.2, y: dot.maxY + d * 1.6))
                tail.addLine(to: CGPoint(x: dot.minX - d * 0.5, y: dot.maxY + d * 1.6))
                tail.addLine(to: CGPoint(x: dot.minX, y: dot.maxY))
                tail.closeSubpath()
                ctx.fill(tail, with: .color(.black))
            }
        }
    }
    private struct NewTail: View {
        var body: some View {
            Canvas { ctx, size in
                let d = size.width * 0.22
                let dot = CGRect(x: size.width * 0.5, y: size.height * 0.25, width: d, height: d)
                ctx.fill(Path(dot), with: .color(.black))
                ctx.fill(LCDView.commaTail(dot: dot), with: .color(.black))
            }
        }
    }

    func testRenderCommaBeforeAfter() throws {
        let digitBits: [Character: UInt8] = ["0": 63, "1": 6, "3": 79, "6": 125]
        var l = LCDState()
        // "36,10": 3 at cell 6, 6 at cell 7 with a comma, 1 at 8, 0 at 9
        for (i, c) in zip(6..<10, "3610") { l.segments[i] = digitBits[c] ?? 0 }
        l.commas[7] = true
        let sheet = HStack(spacing: 0) {
            VStack(spacing: 2) { Text("0.6.4").font(.caption); OldTail().frame(width: 240, height: 200) }
            VStack(spacing: 2) { Text("0.6.5").font(.caption); NewTail().frame(width: 240, height: 200) }
            VStack(spacing: 2) {
                Text("in the display").font(.caption)
                LCDView(lcd: l, model: .hp16c).frame(width: 330, height: 90)
                    .background(Color(rgb: 0x898989))
            }
        }
        .padding(10).background(Color.white)
        try render(sheet, width: 840, height: 240, name: "lcd-comma-0.6.5-after.png", scale: 3)
    }

    /// The flyout in the light appearance with the new legend colours (the "before" is the 0.6.4 render).
    func testRenderFlyoutLegendSwatches() throws {
        func row(_ name: String, _ light: UInt32, _ old: UInt32, _ bg: UInt32) -> some View {
            HStack(spacing: 8) {
                Text("0.6.4").font(.system(size: 10)).foregroundColor(.gray).frame(width: 40, alignment: .leading)
                Text(name).font(.system(size: 13, weight: .semibold)).foregroundColor(Color(rgb: old)).frame(width: 30)
                Text("0.6.5").font(.system(size: 10)).foregroundColor(.gray).frame(width: 40, alignment: .leading)
                Text(name).font(.system(size: 13, weight: .semibold)).foregroundColor(Color(rgb: light)).frame(width: 30)
            }
            .padding(6).background(Color(rgb: bg))
        }
        let v = VStack(spacing: 0) {
            row("f", InspectorColors.fLight, 0xE3A33B, InspectorColors.panelLight)
            row("g", InspectorColors.gLight, 0x5AA9E6, InspectorColors.panelLight)
        }
        try render(v, width: 220, height: 80, name: "flyout-legend-swatches-light.png", scale: 4)
    }
}
#endif
