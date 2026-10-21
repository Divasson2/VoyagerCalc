// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// Pool15Views.swift - HP-15C inspector sections (0.6.0): the memory-pool bar with the g MEM line,
// and matrices A-E (size, RESULT badge, expandable value grid). Pure SwiftUI, so the snapshot
// tests can render them too.

import SwiftUI

enum PoolColors {
    static func color(_ k: Pool15.Kind) -> Color {
        switch k {
        case .workspace: return Color(rgb: 0xC77DCC)
        case .free: return Color.secondary.opacity(0.18)
        case .complex: return Color(rgb: 0xE07A5F)
        case .storage: return Color(rgb: 0x5AA9E6)
        case .matrix(let m): return [Color(rgb: 0xE3A33B), Color(rgb: 0xD4B04C), Color(rgb: 0xB9B957), Color(rgb: 0x9DBF62), Color(rgb: 0x7FBF73)][m]
        case .program: return Color(rgb: 0x4CBF6B)
        }
    }
}

/// One horizontal bar, proportional, in pool order (bottom of memory on the left).
struct PoolBar: View {
    let pool: Pool15
    var height: CGFloat = 14
    var body: some View {
        let segs = pool.segments
        let total = max(1, segs.map(\.count).reduce(0, +))
        GeometryReader { g in
            HStack(spacing: 1) {
                ForEach(segs) { s in
                    Rectangle().fill(PoolColors.color(s.kind))
                        .frame(width: max(2, (g.size.width - CGFloat(segs.count - 1)) * CGFloat(s.count) / CGFloat(total)))
                        .help(help(s))
                }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
    private func help(_ s: Pool15.Segment) -> String {
        var t = "\(s.label.isEmpty ? s.kind.title : s.label): \(s.count) register\(s.count == 1 ? "" : "s"), Nut \(String(format: "%02X", s.first))–\(String(format: "%02X", s.first + s.count - 1))"
        if s.kind == .workspace { t += " (freed at the next key)" }
        return t
    }
}

struct PoolSection: View {
    let pool: Pool15
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PoolBar(pool: pool)
            Text(pool.caption).font(.system(size: 11)).monospaced().foregroundStyle(.secondary)
            legend
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .fixedSize(horizontal: false, vertical: true)
    }
    private var legend: some View {
        let items = Dictionary(grouping: pool.segments, by: { s -> String in
            if case .matrix = s.kind { return "A–E" }
            return s.kind == .storage ? "R2…" : s.kind.title
        }).map { (name: $0.key, kind: $0.value[0].kind, n: $0.value.map(\.count).reduce(0, +), first: $0.value.map(\.first).min() ?? 0) }
          .sorted { $0.first < $1.first }
        return FlowRow(items.map { i in
            HStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 2).fill(PoolColors.color(i.kind)).frame(width: 9, height: 9)
                Text("\(i.name == "A–E" ? "matrices" : i.name) \(i.n)").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        })
    }
}

/// Simple wrapping row of small views (legend).
struct FlowRow<V: View>: View {
    let items: [V]
    init(_ items: [V]) { self.items = items }
    var body: some View {
        // at most three per line keeps it readable in the narrow sidebar
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(stride(from: 0, to: items.count, by: 3)), id: \.self) { i in
                HStack(spacing: 10) { ForEach(i..<min(items.count, i + 3), id: \.self) { items[$0] } }
            }
        }
    }
}

struct MatrixRow: View {
    let m: MatrixValue
    @State private var expanded = false
    @Environment(\.inspectorStatic) private var isStatic
    @Environment(\.colorScheme) private var scheme
    private var open: Bool { (expanded || isStatic) && !m.isEmpty && !m.values.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if !isStatic && !m.isEmpty {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 9)).foregroundStyle(.secondary).frame(width: 10)
                } else { Spacer().frame(width: 10) }
                Text(m.letter).font(.system(size: 12, weight: .semibold)).frame(width: 14, alignment: .leading)
                Text("\(m.rows)×\(m.cols)").monospaced()
                if !m.isEmpty {
                    Text("(\(m.rows * m.cols) regs, Nut \(String(format: "%02X", m.first))–\(String(format: "%02X", m.first + m.rows * m.cols - 1)))")
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer()
                if m.isResult { Tag("RESULT", color: InspectorColors.f(scheme)) }
            }
            .opacity(m.isEmpty ? 0.45 : 1)
            .contentShape(Rectangle())
            .onTapGesture { if !m.isEmpty { expanded.toggle() } }
            .contextMenu { if !m.isEmpty { Button("Copy Matrix \(m.letter) as TSV") { copy(m.tsv) } } }
            if open { grid }
        }
        .padding(.horizontal, 10).padding(.vertical, 3)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var grid: some View {
        let rows = min(m.rows, isStatic ? 4 : 99), cols = min(m.cols, 6)
        return VStack(alignment: .trailing, spacing: 1) {
            ForEach(1...max(1, rows), id: \.self) { r in
                HStack(spacing: 8) {
                    Text("\(r)").font(.system(size: 9)).foregroundStyle(.tertiary).frame(width: 14, alignment: .trailing)
                    ForEach(1...max(1, cols), id: \.self) { c in
                        Text(m.value(r, c)?.text ?? "").monospaced().font(.system(size: 11))
                            .lineLimit(1).minimumScaleFactor(0.5).frame(minWidth: 30, maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }
            if m.cols > cols || m.rows > rows {
                Text("\(m.rows)×\(m.cols): copy as TSV to see all").font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
        .padding(.leading, 24)
        .textSelection(.enabled)
    }
}
