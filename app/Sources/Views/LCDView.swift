// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// LCDView.swift - draws the display from the LCD segments the firmware lit: ten
// seven-segment digits with points and commas, a minus sign, and the annunciators.

import SwiftUI

struct LCDView: View {
    let lcd: LCDState
    let model: CalculatorModel
    /// Segments only, no glass: drawn over the empty LCD glass of a photo face.
    var overPhoto = false

    var body: some View {
        Canvas { ctx, size in
            draw(&ctx, size)
        }
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(LinearGradient(colors: [Color(rgb: model.colors.lcd), Color(rgb: model.colors.lcd).opacity(model.colors.lcd == ModelColors.greyLCD ? 1 : 0.85)],
                                     startPoint: .top, endPoint: .bottom))
                .opacity(overPhoto ? 0 : 1)
        )
        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(Color.black.opacity(overPhoto ? 0 : 0.35), lineWidth: 1))
        .accessibilityElement()
        .accessibilityLabel(Text("Display"))
        .accessibilityValue(Text(lcd.text.trimmingCharacters(in: .whitespaces)))
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let ink = overPhoto ? Color(rgb: 0x101410, opacity: 0.92) : Color(rgb: model.colors.segment)
        let faint = Color(rgb: model.colors.segment, opacity: overPhoto ? 0.025 : 0.045)
        // 11 cells: sign + 10 digits; digits use the upper 72 %, annunciators the rest.
        // Over a photo the digits take the size and place they have on the real glass
        // (measured on the shop photos: 22 % to 61 % of the glass height, the last digit
        // ending at 95 % of its width).
        let cellW = size.width / 11.2
        let digitH = size.height * (overPhoto ? 0.39 : 0.62)
        let top = size.height * (overPhoto ? 0.22 : 0.10)
        let left = cellW * (overPhoto ? -0.13 : 0.35)
        for i in 0..<10 {
            let x = left + CGFloat(i + 1) * cellW
            let rect = CGRect(x: x + cellW * 0.14, y: top, width: cellW * 0.62, height: digitH)
            // unlit segments, very faint, like a real LCD
            for s in 0..<7 { ctx.fill(segment(s, in: rect), with: .color(faint)) }
            let bits = i < lcd.segments.count ? lcd.segments[i] : 0
            for s in 0..<7 where bits >> s & 1 == 1 { ctx.fill(segment(s, in: rect), with: .color(ink)) }
            let dotSize = cellW * 0.13
            let dot = CGRect(x: rect.maxX + cellW * 0.06, y: rect.maxY - dotSize, width: dotSize, height: dotSize)
            if i < lcd.dots.count, lcd.dots[i] || (i < lcd.commas.count && lcd.commas[i]) {
                ctx.fill(Path(dot), with: .color(ink))
            }
            if i < lcd.commas.count, lcd.commas[i] {
                let tail = LCDView.commaTail(dot: dot)
                ctx.fill(tail, with: .color(ink))
            }
        }
        // minus sign in the sign cell
        let signRect = CGRect(x: left + cellW * 0.15, y: top, width: cellW * 0.62, height: digitH)
        let minus = segment(6, in: signRect)
        ctx.fill(minus, with: .color(lcd.minus ? ink : faint))

        // annunciators: one fixed layout for every model (the glass is the same part); each lights only with its segment.
        // The font shrinks until no label runs into the next one.
        let annY = top + digitH + size.height * 0.08
        let anns = model.annunciators
        var fontSize = max(6, size.height * 0.15)
        var xs = [CGFloat](repeating: 0, count: anns.count)
        func label(_ a: Annunciator, _ color: Color) -> Text {
            Text(a.label).font(.system(size: fontSize, weight: .semibold, design: .rounded)).foregroundColor(color)
        }
        for _ in 0..<12 {
            var fits = true
            for (i, a) in anns.enumerated() {
                xs[i] = left + CGFloat(a.cell + 1) * cellW
                guard i > 0 else { continue }
                let prev = ctx.resolve(label(anns[i - 1], ink)).measure(in: size).width
                if a.label == "RAD", anns[i - 1].label == "G" { xs[i] = xs[i - 1] + prev }
                else if xs[i] < xs[i - 1] + prev + cellW * 0.08 { fits = false }
            }
            if fits || fontSize <= 4 { break }
            fontSize = max(4, fontSize * 0.92)
        }
        for (i, a) in anns.enumerated() {
            ctx.draw(label(a, a.isLit(lcd.annunciatorBits) ? ink : faint), at: CGPoint(x: xs[i], y: annY), anchor: .topLeading)
        }
    }

    /// Tail of a comma (0.6.5), measured on a photo of the real glass: thin, slanting down-left, separated
    /// from the dot by a hair, narrowing from about 0.78 dot widths at the top to a point at the bottom,
    /// ending 0.86 dot heights below the dot. Points are in dot units (D = dot width), origin at the dot's
    /// top-left corner, y down; the dot itself is drawn separately and unchanged.
    static let commaTailPoints: [(x: CGFloat, y: CGFloat)] = [
        (-0.10, 1.06), (0.66, 1.06), (0.12, 1.68), (-0.08, 1.86), (-0.30, 1.84), (-0.34, 1.66),
    ]
    static func commaTail(dot: CGRect) -> Path {
        let d = dot.width
        var path = Path()
        for (i, pt) in commaTailPoints.enumerated() {
            let p = CGPoint(x: dot.minX + pt.x * d, y: dot.minY + pt.y * d)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }

    /// Path of segment s (0 = a ... 6 = g) in a digit box, slanted like the Voyager LCD.
    private func segment(_ s: Int, in r: CGRect) -> Path {
        let t = r.width * 0.17            // stroke thickness
        let g = t * 0.18                  // gap between segments
        let w = r.width, h = r.height, mid = h / 2
        let slant: CGFloat = 0.10         // x shift per unit of height (italic)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: r.minX + x + (h - y) * slant, y: r.minY + y)
        }
        var path = Path()
        func horizontal(_ y: CGFloat) {
            path.move(to: p(t / 2 + g, y))
            path.addLine(to: p(t + g, y - t / 2))
            path.addLine(to: p(w - t - g, y - t / 2))
            path.addLine(to: p(w - t / 2 - g, y))
            path.addLine(to: p(w - t - g, y + t / 2))
            path.addLine(to: p(t + g, y + t / 2))
            path.closeSubpath()
        }
        func vertical(_ x: CGFloat, _ y0: CGFloat, _ y1: CGFloat) {
            path.move(to: p(x, y0 + g))
            path.addLine(to: p(x + t / 2, y0 + t / 2 + g))
            path.addLine(to: p(x + t / 2, y1 - t / 2 - g))
            path.addLine(to: p(x, y1 - g))
            path.addLine(to: p(x - t / 2, y1 - t / 2 - g))
            path.addLine(to: p(x - t / 2, y0 + t / 2 + g))
            path.closeSubpath()
        }
        switch s {
        case 0: horizontal(t / 2)
        case 1: vertical(w - t / 2, t / 2, mid)
        case 2: vertical(w - t / 2, mid, h - t / 2)
        case 3: horizontal(h - t / 2)
        case 4: vertical(t / 2, mid, h - t / 2)
        case 5: vertical(t / 2, t / 2, mid)
        default: horizontal(mid)
        }
        return path
    }
}
