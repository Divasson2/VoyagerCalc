// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// InspectorView.swift - registers and program listing, read-only, updated live (at most 10
// times a second, CalculatorEngine). Mac: inspector sidebar (View > Show Registers & Program,
// ⌘I). iPad: inspector column. iPhone: a panel under (portrait) or beside (landscape) the
// calculator, so the keys stay usable while stepping through a program with SST.

import SwiftUI
#if os(macOS)
import AppKit
#endif

enum InspectorPane: String, CaseIterable, Identifiable {
    case both, registers, program
    var id: String { rawValue }
    var title: String {
        switch self { case .both: return "Both"; case .registers: return "Registers"; case .program: return "Program" }
    }
}

/// Snapshot tests render without scroll views and AppKit / UIKit controls (ImageRenderer
/// draws only pure SwiftUI): fixed rows around the program pointer, no picker.
private struct InspectorStaticKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var inspectorStatic: Bool {
        get { self[InspectorStaticKey.self] }
        set { self[InspectorStaticKey.self] = newValue }
    }
}

enum InspectorColors {
    static let f = Color(rgb: 0xE3A33B)          // gold f legends
    static let g = Color(rgb: 0x5AA9E6)          // blue g legends
    static let changed = Color(rgb: 0xF2C14E)
    static let pointer = Color.accentColor
    static let running = Color(rgb: 0x4CBF6B)

    /// The program pointer: a soft green band behind the current line, a little stronger while
    /// a program runs. Light appearance: light green under dark text; dark appearance: a muted
    /// green under light text (a light band there would glare and wash out the text).
    static func pointerBand(_ scheme: ColorScheme, running: Bool) -> Color {
        scheme == .dark ? Color(rgb: running ? 0x3A7D4A : 0x2E5E3A) : Color(rgb: running ? 0xB4E5B4 : 0xD3F1D3)
    }
    /// f / g legend colours readable on the band.
    static func fOnBand(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(rgb: 0xF2C060) : Color(rgb: 0x9A620A) }
    static func gOnBand(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(rgb: 0x8CC8F5) : Color(rgb: 0x1C639E) }
}

struct InspectorView: View {
    @EnvironmentObject var app: AppModel
    @AppStorage("inspectorPane") private var pane: InspectorPane = .both
    var compact = false                          // iPhone panel: smaller header
    @Environment(\.inspectorStatic) private var isStatic
    @State private var draft = ""

    /// Step comments of the program notes, by step (0.5.6).
    private var comments: [Int: String] {
        Dictionary(app.programDoc.comments.filter { !$0.orphaned }.map { ($0.step, $0.text) }, uniquingKeysWith: { a, _ in a })
    }
    private func edit(_ step: Int) { draft = app.comment(at: step); app.editingCommentStep = step }
    private func program(_ s: InspectorSnapshot) -> ProgramPanel {
        ProgramPanel(s: s, comments: comments, onEdit: edit)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let s = app.inspection {
                InspectorHeader(s: s, compact: compact)
                if !isStatic {
                    Picker("Show", selection: $pane) {
                        ForEach(InspectorPane.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(.horizontal, 10).padding(.bottom, 6)
                }
                Divider()
                switch isStatic ? .both : pane {
                case .both:
                    RegistersPanel(s: s).frame(minHeight: 0, maxHeight: .infinity)
                    Divider()
                    program(s).frame(minHeight: 0, maxHeight: .infinity)
                case .registers: RegistersPanel(s: s).frame(minHeight: 0, maxHeight: .infinity)
                case .program: program(s).frame(minHeight: 0, maxHeight: .infinity)
                }
            } else {
                ContentUnavailableView("Nothing to inspect", systemImage: "memorychip",
                                       description: Text(app.isRunning ? "The calculator is switching models." : "Choose a firmware file first."))
            }
        }
        .font(.system(size: 12))
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
        .clipped()
        .alert(app.editingCommentStep.map { "Comment for step \(String(format: app.inspection?.model == 12 ? "%02d" : "%03d", $0))" } ?? "",
               isPresented: Binding(get: { app.editingCommentStep != nil }, set: { if !$0 { app.editingCommentStep = nil } })) {
            TextField("Comment", text: $draft)
            Button("Save") { if let st = app.editingCommentStep { app.setComment(draft, at: st) }; app.editingCommentStep = nil }
            Button("Remove", role: .destructive) { if let st = app.editingCommentStep { app.setComment("", at: st) }; app.editingCommentStep = nil }
            Button("Cancel", role: .cancel) { app.editingCommentStep = nil }
        } message: {
            Text("Shown in the listing and the exported documentation. It stays with this step when lines are inserted or deleted.")
        }
    }
}

/// Model, modes, flags, run state and program line.
struct InspectorHeader: View {
    let s: InspectorSnapshot
    var compact = false

    private var modelName: String { s.model == 15 && s.variant == 152 ? "HP-15C (15.2)" : "HP-\(s.model)C" }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(modelName).font(.system(size: 13, weight: .semibold))
                if s.extendedMemory { Tag("ext. memory", color: .secondary) }
                if s.isComplex { Tag("Complex", color: Color(rgb: 0xE07A5F)) }
                Spacer()
                if s.running { Tag("RUNNING", color: InspectorColors.running) }
                else if s.programMode { Tag("PRGM", color: InspectorColors.f) }
            }
            HStack(spacing: 8) {
                if !s.modeSummary.isEmpty { Text(s.modeSummary).monospaced() }
                if s.model != 12 {
                    Text("flags " + (s.setFlags.isEmpty ? "–" : s.setFlags.map(flagName).joined(separator: " ")))
                        .help(flagHelp)
                }
                Spacer()
                if s.hasProgram { Text(String(format: "line %03d / %03d", s.line, s.lines)).monospaced() }
            }
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 10).padding(.top, compact ? 6 : 10).padding(.bottom, 6)
        .fixedSize(horizontal: false, vertical: true)
        .layoutPriority(1)
    }

    private func flagName(_ n: Int) -> String {
        if s.model == 16 && n == 4 { return "4(C)" }
        if s.model == 16 && n == 5 { return "5(G)" }
        if s.model == 15 && n == 8 { return "8(C)" }
        if s.model == 15 && n == 9 { return "9" }
        return "\(n)"
    }
    private var flagHelp: String {
        s.model == 16 ? "Flags set. 3: show leading zeros, 4: carry (C), 5: out of range (G)."
                      : "Flags set. 8: complex mode, 9: overflow (blinking display)."
    }
}

struct Tag: View {
    let text: String; let color: Color
    init(_ text: String, color: Color) { self.text = text; self.color = color }
    var body: some View {
        Text(text).font(.system(size: 10, weight: .bold)).padding(.horizontal, 5).padding(.vertical, 1)
            .foregroundStyle(color).overlay(RoundedRectangle(cornerRadius: 3).stroke(color.opacity(0.7)))
    }
}

// MARK: registers

struct RegistersPanel: View {
    let s: InspectorSnapshot
    @AppStorage("inspectorHideZeros") private var hideZeros = false
    @Environment(\.inspectorStatic) private var isStatic

    private var shown: [RegisterValue] { hideZeros ? s.registers.filter { $0.stored != 0 } : s.registers }

    var body: some View {
        if isStatic {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: s.model == 12 ? "Stack and financial registers" : "Stack")
                ForEach(s.stack) { row($0) }
                if let p = s.pool {
                    SectionHeader(title: "Memory")
                    PoolSection(pool: p)
                    SectionHeader(title: "Matrices")
                    ForEach(s.matrices) { MatrixRow(m: $0) }
                }
                SectionHeader(title: "Storage registers (\(s.registerCount))")
                ForEach(s.registers.prefix(8)) { RegisterRow(value: $0, base: s.base) }
                Spacer(minLength: 0)
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
            .clipped()
        } else {
            scrolling
        }
    }

    /// Stack rows: the imaginary part in complex mode, matrix descriptors by name.
    private func row(_ v: RegisterValue) -> RegisterRow {
        RegisterRow(value: v, base: s.base, imaginary: s.imaginary(of: v.name), descriptor: s.descriptorText(v))
    }

    private var scrolling: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(s.stack) { row($0) }
                } header: { SectionHeader(title: s.model == 12 ? "Stack and financial registers" : "Stack") }
                if let p = s.pool {
                    Section { PoolSection(pool: p) } header: { SectionHeader(title: "Memory") }
                    Section { ForEach(s.matrices) { MatrixRow(m: $0) } } header: { SectionHeader(title: "Matrices") }
                }
                Section {
                    ForEach(shown) { RegisterRow(value: $0, base: s.base) }
                    if shown.isEmpty { Text("All registers are zero.").foregroundStyle(.secondary).padding(10) }
                } header: {
                    SectionHeader(title: "Storage registers (\(s.registerCount))") {
                        Toggle("Non-zero only", isOn: $hideZeros).toggleStyle(.button).controlSize(.mini).font(.system(size: 10))
                    }
                }
            }
        }
    }
}

struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            Spacer()
            trailing
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(.bar)
        .fixedSize(horizontal: false, vertical: true)
    }
}
extension SectionHeader where Trailing == EmptyView {
    init(title: String) { self.title = title; self.trailing = EmptyView() }
}

struct RegisterRow: View {
    let value: RegisterValue
    let base: Int
    var imaginary: RegisterValue? = nil      // 15C complex mode
    var descriptor: String? = nil           // "matrix A (2×3)"
    @State private var flash = false

    /// Binary in groups of four for reading; the other bases as the calculator shows them.
    private var shownText: String {
        if let descriptor { return descriptor }
        if let im = imaginary {
            let neg = im.text.hasPrefix("-")
            return "\(value.text) \(neg ? "−" : "+") \(neg ? String(im.text.dropFirst()) : im.text)i"
        }
        guard value.isInteger, base == 2, value.text.count > 8 else { return value.text }
        var out = ""
        for (i, ch) in value.text.reversed().enumerated() {
            if i > 0 && i % 4 == 0 { out.append(" ") }
            out.append(ch)
        }
        return String(out.reversed())
    }
    private var suffix: String {
        guard value.isInteger else { return "" }
        switch base { case 16: return "h"; case 8: return "o"; case 2: return "b"; default: return "d" }
    }
    private var help: String {
        value.isInteger ? "\(value.name) = \(value.decimal) (decimal)" : "\(value.name) = \(value.text)"
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(value.name).foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 0) {
                HStack(spacing: 3) {
                    Text(shownText).monospaced().lineLimit(1).minimumScaleFactor(0.5).textSelection(.enabled)
                    if !suffix.isEmpty { Text(suffix).foregroundStyle(.secondary).font(.system(size: 10)) }
                }
                if value.isInteger && base != 10 {
                    Text(value.decimal).font(.system(size: 10)).monospaced().foregroundStyle(.tertiary).lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 3)
        .fixedSize(horizontal: false, vertical: true)
        .background(InspectorColors.changed.opacity(flash ? 0.35 : 0))
        .contentShape(Rectangle())
        .help(help)
        .contextMenu {
            Button("Copy \(value.text)") { copy(value.text) }
            if value.isInteger { Button("Copy decimal \(value.decimal)") { copy(value.decimal) } }
        }
        .onChange(of: value.stored &+ (imaginary?.raw ?? 0)) { _, _ in
            flash = true
            withAnimation(.easeOut(duration: 1.2).delay(0.4)) { flash = false }
        }
        .accessibilityElement(children: .combine)
    }
}

func copy(_ s: String) {
    #if os(macOS)
    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s, forType: .string)
    #else
    UIPasteboard.general.string = s
    #endif
}

// MARK: program

struct ProgramPanel: View {
    let s: InspectorSnapshot
    var comments: [Int: String] = [:]
    var onEdit: (Int) -> Void = { _ in }
    @Environment(\.inspectorStatic) private var isStatic

    private var zero: String { s.model == 12 ? "00" : "000" }

    var body: some View {
        if isStatic && s.hasProgram {
            let first = max(0, s.line - 4)
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "Program (\(s.lines) lines)")
                if first == 0 { ProgramRow(label: zero, keys: "", mnemonic: "", prefix: "", current: s.line == 0, running: s.running) }
                ForEach(s.program.filter { $0.line >= max(1, first) && $0.line < first + 14 }) { p in
                    ProgramRow(label: p.number(model: s.model), keys: p.keys, mnemonic: p.mnemonic, prefix: p.prefix,
                               current: p.line == s.line, running: s.running, comment: comments[p.line] ?? "")
                }
                Spacer(minLength: 0)
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
            .clipped()
        } else if !s.hasProgram {
            ContentUnavailableView("No program listing", systemImage: "list.number",
                                   description: Text("This calculator image has no program memory the inspector can read."))
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            ProgramRow(label: zero, keys: "", mnemonic: "", prefix: "", current: s.line == 0, running: s.running).id(0)
                            ForEach(s.program) { p in
                                ProgramRow(label: p.number(model: s.model), keys: p.keys, mnemonic: p.mnemonic, prefix: p.prefix,
                                           current: p.line == s.line, running: s.running, comment: comments[p.line] ?? "")
                                    .contentShape(Rectangle())
                                    .onTapGesture(count: 2) { onEdit(p.line) }
                                    .contextMenu { Button(comments[p.line] == nil ? "Add Comment…" : "Edit Comment…") { onEdit(p.line) } }
                                    .id(p.line)
                            }
                        } header: { SectionHeader(title: "Program (\(s.lines) lines)") }
                    }
                }
                .onAppear { proxy.scrollTo(s.line, anchor: .center) }
                .onChange(of: s.line) { _, line in
                    if s.running { proxy.scrollTo(line, anchor: .center) }
                    else { withAnimation(.easeInOut(duration: 0.15)) { proxy.scrollTo(line, anchor: .center) } }
                }
            }
        }
    }
}

struct ProgramRow: View {
    let label: String, keys: String, mnemonic: String, prefix: String
    let current: Bool, running: Bool
    var comment = ""
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 6) {
            Text(label + "-").monospaced()
                .foregroundStyle(current ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            Text(keys).monospaced().frame(width: 86, alignment: .leading)
            if !prefix.isEmpty {
                Text(prefix).bold().foregroundStyle(prefixColor)
            }
            Text(mnemonic)
            if !comment.isEmpty {
                Text(comment).italic().foregroundStyle(.secondary).truncationMode(.tail)
                    .padding(.leading, 6).help(comment)
            }
            Spacer(minLength: 0)
        }
        .fontWeight(current ? .semibold : .regular)
        .lineLimit(1)
        .padding(.horizontal, 10).padding(.vertical, 2)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(current ? InspectorColors.pointerBand(scheme, running: running) : Color.clear)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(current ? .isSelected : [])
    }

    private var prefixColor: Color {
        if current { return prefix == "f" ? InspectorColors.fOnBand(scheme) : InspectorColors.gOnBand(scheme) }
        return prefix == "f" ? InspectorColors.f : InspectorColors.g
    }
}
