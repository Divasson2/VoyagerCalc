// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// ProgramInfoView.swift - File ▸ Program Info… (0.5.6): the program notes that go into the
// exported documentation: title, author, description ("## Usage" starts a section, "- " a
// bullet), a note per label, a name and meaning per register, a note per flag. The tables
// list what the program uses (detected from the listing); comments per step are edited in the
// inspector's listing (double-click a line).

import SwiftUI

struct ProgramInfoView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) private var dismiss

    private var model: Int { app.inspection?.model ?? app.snapshot.model }
    private var analysis: ProgramAnalysis { ProgramAnalysis(lines: app.docLines, model: model) }
    private func steps(_ s: [Int]) -> String {
        let f = model == 12 ? "%02d" : "%03d"
        let shown = s.prefix(8).map { String(format: f, $0) }.joined(separator: ", ")
        return s.count > 8 ? shown + " …" : shown
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Program") {
                    TextField("Title", text: $app.programDoc.title)
                    TextField("Author", text: $app.programDoc.author, prompt: Text("optional"))
                    LabeledContent("Model", value: app.documentModelName)
                    LabeledContent("Steps", value: "\(app.docLines.count)")
                }
                Section {
                    TextEditor(text: $app.programDoc.description)
                        .font(.body)
                        .frame(minHeight: 120)
                } header: {
                    Text("Description")
                } footer: {
                    Text("What the program does and how to use it. A line starting with ## is a section heading (for example ## Usage); a line starting with - is a bullet.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                let a = analysis
                if !a.labels.isEmpty {
                    Section(model == 12 ? "Branch targets" : "Labels") {
                        ForEach(a.labels) { l in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(model == 12 && !l.isIndirect ? "line \(l.name)" : (l.isIndirect ? l.name : "LBL \(l.name)"))
                                        .bold().frame(width: 90, alignment: .leading)
                                    Text(where_(l)).font(.caption).foregroundStyle(l.defined.isEmpty && !l.isIndirect ? .red : .secondary)
                                }
                                TextField("Notes", text: Binding(get: { app.programDoc.labels[l.name] ?? "" },
                                                                 set: { app.programDoc.labels[l.name] = $0 }))
                            }
                        }
                    }
                }
                if !a.registers.isEmpty {
                    Section("Registers") {
                        ForEach(a.registers) { r in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(r.name).bold().frame(width: 90, alignment: .leading)
                                    Text(r.operations.joined(separator: ", ") + " — " + steps(r.steps)).font(.caption).foregroundStyle(.secondary)
                                }
                                HStack {
                                    TextField("Name", text: Binding(get: { app.programDoc.registers[r.name]?.name ?? "" },
                                                                    set: { app.programDoc.registers[r.name, default: RegisterNote()].name = $0 }))
                                        .frame(maxWidth: 160)
                                    TextField("Meaning", text: Binding(get: { app.programDoc.registers[r.name]?.meaning ?? "" },
                                                                       set: { app.programDoc.registers[r.name, default: RegisterNote()].meaning = $0 }))
                                }
                            }
                        }
                    }
                }
                if !a.flags.isEmpty {
                    Section("Flags") {
                        ForEach(a.flags) { f in
                            HStack(alignment: .firstTextBaseline) {
                                Text("Flag \(f.name)").bold().frame(width: 90, alignment: .leading)
                                TextField("Meaning", text: Binding(get: { app.programDoc.flags[f.name] ?? "" },
                                                                   set: { app.programDoc.flags[f.name] = $0 }))
                                Text(f.operations.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section {
                    Text("Comments per step: double-click a line in the inspector's program list. \(app.programDoc.comments.filter { !$0.orphaned }.count) step comment(s) so far.")
                        .font(.callout).foregroundStyle(.secondary)
                    let orphans = app.programDoc.orphanedComments
                    if !orphans.isEmpty {
                        ForEach(Array(orphans.enumerated()), id: \.offset) { _, c in
                            Text("was step \(String(format: "%03d", c.step)) (\(c.keys)): \(c.text)").font(.callout)
                        }
                        Button("Remove Comments That No Longer Match", role: .destructive) { app.removeOrphans() }
                    }
                } header: {
                    Text(app.programDoc.orphanedComments.isEmpty ? "Comments" : "Comments that no longer match a step")
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                if let u = app.programDocURL { Text(u.lastPathComponent).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                Spacer()
                Button("Save Notes…") { later { app.saveNotes() } }
                Button("Export PDF…") { later { app.exportPDF() } }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        #if os(macOS)
        .frame(minWidth: 600, idealWidth: 680, minHeight: 560, idealHeight: 720)
        #endif
    }

    private func where_(_ l: ProgramAnalysis.Label) -> String {
        let d = l.defined.isEmpty ? (l.isIndirect ? "computed in I" : "not defined") : "at " + steps(l.defined)
        let c = l.called.isEmpty ? "not called" : "called from " + steps(l.called) + " (" + l.callKinds.joined(separator: ", ") + ")"
        return d + " · " + c
    }

    /// Close the sheet, then open the save panel (it belongs to the main window).
    private func later(_ body: @escaping @MainActor () -> Void) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { MainActor.assumeIsolated { body() } }
    }
}
