// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// CalculatorView.swift - the whole calculator. Two faces:
//  * Photo (default): the product photo with the live display drawn on its empty LCD glass
//    and the measured key rectangles as click / tap areas (PhotoFaceView.swift). Used in
//    landscape (Mac, iPad, iPhone held sideways).
//  * Drawn: our own drawing. Landscape: the usual 4 x 10 keyboard. Portrait (iPhone): the
//    left and right halves of the keyboard stacked, display on top.
// iPhone portrait always uses the stacked drawn face: the landscape photo would be too small
// to tap (or sideways if rotated), so turn the phone to get the photo.
// Everything scales with the window.

import SwiftUI

enum KeyboardLayout {
    case landscape, portrait

    var rows: Int { self == .landscape ? 4 : 8 }
    var columns: Int { self == .landscape ? 10 : 5 }

    /// Display row / column of a key.
    func place(_ k: KeySpec) -> (row: Int, col: Int) {
        switch self {
        case .landscape: return (k.row, k.column)
        case .portrait: return (k.row + (k.column >= 5 ? 4 : 0), k.column % 5)
        }
    }
}

struct KeyboardGeometry {
    let layout: KeyboardLayout
    let rect: CGRect

    var cellW: CGFloat { rect.width / CGFloat(layout.columns) }
    var rowH: CGFloat { rect.height / CGFloat(layout.rows) }
    var legendH: CGFloat { rowH * 0.27 }
    var keyH: CGFloat { rowH * 0.64 }
    var keyW: CGFloat { cellW * 0.80 }

    func legendRect(_ k: KeySpec) -> CGRect {
        let p = layout.place(k)
        return CGRect(x: rect.minX + CGFloat(p.col) * cellW, y: rect.minY + CGFloat(p.row) * rowH, width: cellW, height: legendH)
    }

    /// The key's gold legend / cap / blue legend zones (KeyZones.drawn).
    func zones(_ k: KeySpec) -> KeyZones {
        KeyZones.drawn(legend: legendRect(k), key: keyRect(k), unit: keyH, spec: k)
    }

    func keyRect(_ k: KeySpec) -> CGRect {
        let p = layout.place(k)
        let x = rect.minX + CGFloat(p.col) * cellW + (cellW - keyW) / 2
        let y = rect.minY + CGFloat(p.row) * rowH + legendH
        let h = k.rowSpan == 2 ? rowH + keyH : keyH
        return CGRect(x: x, y: y, width: keyW, height: h)
    }
}

struct CalculatorView: View {
    @EnvironmentObject var app: AppModel
    var forcedLayout: KeyboardLayout? = nil      // for snapshots

    var body: some View {
        GeometryReader { geo in
            let layout = forcedLayout ?? (geo.size.width >= geo.size.height * 1.05 ? .landscape : .portrait)
            if app.faceStyle == .photo, layout == .landscape, let face = app.model.photoFace {
                PhotoCalculatorFace(model: app.model, face: face, lcd: app.snapshot.lcd, pressed: app.pressedKeys,
                                    press: { app.press($0) }, release: { app.release($0) },
                                    pressPart: { app.press($0, part: $1) })
                    .frame(width: geo.size.width, height: geo.size.height)
            } else {
                CalculatorFace(model: app.model, lcd: app.snapshot.lcd, pressed: app.pressedKeys,
                               layout: layout, variant: app.snapshot.variant,
                               press: { app.press($0) }, release: { app.release($0) },
                               pressPart: { app.press($0, part: $1) })
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .environment(\.latchedKeys, app.latchedKeys)
        .environment(\.keyLatch, KeyLatchHandlers(toggle: { app.toggleLatch($0) }, hold: { app.holdBecameLatch($0) }))
    }
}

/// The drawing itself, with no app state (also used for snapshots and previews).
struct CalculatorFace: View {
    let model: CalculatorModel
    let lcd: LCDState
    let pressed: Set<Int>
    let layout: KeyboardLayout
    var variant = 0
    var press: (Int) -> Void = { _ in }
    var release: (Int) -> Void = { _ in }
    /// A press on a key's gold / blue legend (nil: the key alone).
    var pressPart: ((Int, KeyPart) -> Void)? = nil

    private func press(_ code: Int, _ part: KeyPart) {
        if part != .face, let pp = pressPart { pp(code, part) } else { press(code) }
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let c = model.colors
            let pad = min(size.width, size.height) * 0.035
            let topH = layout == .landscape ? size.height * 0.30 : size.height * 0.235
            let kbRect = CGRect(x: pad * 1.4, y: topH + pad * 0.8,
                                width: size.width - pad * 2.8, height: size.height - topH - pad * 2.0)
            let kg = KeyboardGeometry(layout: layout, rect: kbRect)
            let unit = kg.keyH

            ZStack(alignment: .topLeading) {
                // body
                RoundedRectangle(cornerRadius: pad * 1.2, style: .continuous)
                    .fill(LinearGradient(colors: [Color(rgb: c.body).opacity(0.92), Color(rgb: c.body)],
                                         startPoint: .top, endPoint: .bottom))
                // display bezel
                bezel(size: size, topH: topH, pad: pad)
                // keyboard frame (the metal band)
                RoundedRectangle(cornerRadius: pad * 0.5, style: .continuous)
                    .stroke(Color(rgb: c.band), lineWidth: max(2, pad * 0.22))
                    .frame(width: kbRect.width + pad * 0.9, height: kbRect.height + pad * 0.7)
                    .offset(x: kbRect.minX - pad * 0.45, y: kbRect.minY - pad * 0.35)
                // f legends and brackets
                legends(kg)
                // keys
                ForEach(model.keys) { k in
                    let r = kg.keyRect(k)
                    KeyView(key: k, colors: c, pressed: pressed.contains(k.code), unit: unit,
                            onPress: { press(k.code, $0) }, onRelease: { release(k.code) })
                        .frame(width: r.width, height: r.height)
                        .offset(x: r.minX, y: r.minY)
                }
            }
        }
    }

    @ViewBuilder
    private func bezel(size: CGSize, topH: CGFloat, pad: CGFloat) -> some View {
        let c = model.colors
        let lcdW = layout == .landscape ? size.width * 0.52 : size.width - pad * 4
        let lcdH = layout == .landscape ? topH * 0.48 : min(topH * 0.48, lcdW * 0.22)
        let lcdX = layout == .landscape ? size.width * 0.14 : pad * 2
        let lcdY = (topH - lcdH) / 2 + pad * 0.3
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: pad * 0.6, style: .continuous)
                .fill(Color(rgb: c.bezel))
                .frame(width: lcdW + pad * 1.6, height: lcdH + pad * 1.4)
                .offset(x: lcdX - pad * 0.8, y: lcdY - pad * 0.7)
            LCDView(lcd: lcd, model: model)
                .frame(width: lcdW, height: lcdH)
                .offset(x: lcdX, y: lcdY)
            // model name, neutral branding
            VStack(alignment: .trailing, spacing: 2) {
                Text(model.name)
                    .font(.system(size: max(10, topH * (layout == .landscape ? 0.20 : 0.13)), weight: .bold, design: .rounded))
                    .foregroundColor(Color(rgb: c.band))
                Text(model.subtitle.uppercased())
                    .font(.system(size: max(7, topH * (layout == .landscape ? 0.075 : 0.05)), weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(Color(rgb: c.band).opacity(0.8))
            }
            .frame(width: layout == .landscape ? size.width * 0.22 : size.width * 0.5, alignment: .trailing)
            .offset(x: layout == .landscape ? size.width * 0.73 : size.width * 0.5 - pad * 2,
                    y: layout == .landscape ? lcdY : lcdY + lcdH + pad * 0.9)
        }
    }

    @ViewBuilder
    private func legends(_ kg: KeyboardGeometry) -> some View {
        let c = model.colors
        let fontSize = max(6, kg.legendH * 0.50)
        let inBracket = Set(model.brackets.flatMap { b in model.keys.filter { $0.code >= b.fromCode && $0.code <= b.toCode }.map(\.code) })
        ZStack(alignment: .topLeading) {
            ForEach(model.keys.filter { !$0.f.isEmpty }) { k in
                let r = kg.legendRect(k)
                Text(k.f)
                    .font(.system(size: inBracket.contains(k.code) ? fontSize * 0.85 : fontSize, weight: .semibold))
                    .foregroundColor(Color(rgb: c.fLegend))
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .frame(width: r.width * 0.96, height: r.height * (inBracket.contains(k.code) ? 0.55 : 1))
                    .offset(x: r.minX + r.width * 0.02, y: r.minY + (inBracket.contains(k.code) ? r.height * 0.45 : 0))
            }
            // the gold legends are clickable: f, then the key
            ForEach(model.keys.filter { !$0.f.isEmpty }) { k in
                if let r = kg.zones(k).f {
                    LegendArea(key: k, colors: c, onPress: { press(k.code, .fLabel) }, onRelease: { release(k.code) })
                        .frame(width: r.width, height: r.height)
                        .offset(x: r.minX, y: r.minY)
                }
            }
            ForEach(Array(bracketSegments(kg).enumerated()), id: \.offset) { _, seg in
                BracketShape()
                    .stroke(Color(rgb: c.fLegend), lineWidth: 1)
                    .frame(width: seg.rect.width, height: seg.rect.height)
                    .offset(x: seg.rect.minX, y: seg.rect.minY)
                    .allowsHitTesting(false)
                Text(seg.label)
                    .font(.system(size: fontSize * 0.8, weight: .bold))
                    .foregroundColor(Color(rgb: c.fLegend))
                    .padding(.horizontal, 3)
                    .background(Color(rgb: c.body))
                    .frame(width: seg.rect.width, height: seg.rect.height * 0.9)
                    .offset(x: seg.rect.minX, y: seg.rect.minY - seg.rect.height * 0.45)
                    .allowsHitTesting(false)
            }
        }
    }

    private struct Segment { let label: String; let rect: CGRect }

    /// Brackets split into one piece per display row.
    private func bracketSegments(_ kg: KeyboardGeometry) -> [Segment] {
        var out: [Segment] = []
        for b in model.brackets {
            let ks = model.keys.filter { $0.code >= b.fromCode && $0.code <= b.toCode }
            let rows = Dictionary(grouping: ks) { kg.layout.place($0).row }
            for (_, group) in rows.sorted(by: { $0.key < $1.key }) {
                let rects = group.map { kg.legendRect($0) }
                guard let minX = rects.map(\.minX).min(), let maxX = rects.map(\.maxX).max(), let y = rects.first?.minY else { continue }
                let h = kg.legendH * 0.40
                out.append(Segment(label: b.label, rect: CGRect(x: minX + kg.cellW * 0.12, y: y + kg.legendH * 0.22,
                                                                width: maxX - minX - kg.cellW * 0.24, height: h)))
            }
        }
        return out
    }
}

/// ┌──── ────┐ shape (open in the middle for the label, which is drawn over it).
struct BracketShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        return p
    }
}
