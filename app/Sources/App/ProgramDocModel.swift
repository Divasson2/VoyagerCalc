// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// ProgramDocModel.swift - program documentation in the app (0.5.6): the notes (title, author,
// description, label / register / flag notes, step comments) for the program in the calculator,
// their sidecar file next to the memory file (FinancePac.15c.voyagerdoc), comments following
// the program as lines are inserted or deleted, and File ▸ Export Program Documentation (PDF) /
// Export Listing as Text.
//
// The sandboxed app may only read files the user picked, so a sidecar next to an opened memory
// file is read when the system allows it (the no-sandbox build always can); otherwise File ▸
// Open Program Notes… opens it. The current notes are also kept per firmware between launches.

import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension AppModel {
    var docDefaultsKey: String { "programDoc." + (firmwareID.isEmpty ? "none" : String(firmwareID.prefix(16))) }

    func storeProgramDoc() {
        guard persistState else { return }
        if let d = try? programDoc.encoded() { UserDefaults.standard.set(d, forKey: docDefaultsKey) }
    }

    func loadStoredProgramDoc() {
        guard persistState else { return }
        if let d = UserDefaults.standard.data(forKey: docDefaultsKey), let doc = try? ProgramDocument.decode(d) {
            programDoc = doc
        }
    }

    /// The program changed (a line inserted or deleted, another memory loaded): comments follow it.
    func programChanged(_ s: InspectorSnapshot?) {
        guard let s, s.hasProgram, !s.program.isEmpty else { return }
        let keys = s.program.map(\.keys)
        guard keys != lastProgramKeys else { return }
        let first = lastProgramKeys.isEmpty
        lastProgramKeys = keys
        let stale = programDoc.comments.contains { c in s.program.first { $0.line == c.step }?.keys != c.keys }
        if !programDoc.comments.isEmpty, !first || stale {
            var d = programDoc; d.rematch(to: s.program)
            if d != programDoc { programDoc = d }
        }
    }

    // MARK: sidecar

    /// A memory file is being opened: read "<file>.voyagerdoc" next to it if the system lets us.
    func findSidecar(for url: URL) {
        memoryFileNameCandidate = url.lastPathComponent
        pendingSidecar = nil
        for side in MemoryFileNames.sidecarCandidates(for: url) {      // the name itself, then the other memory endings (0.6.9)
            if let d = try? Data(contentsOf: side), let doc = try? ProgramDocument.decode(d) {
                pendingSidecar = (doc, side); break
            }
        }
    }

    /// The memory from a file is in the calculator: take its notes if they were found.
    func memoryLoaded() {
        if let name = memoryFileNameCandidate { memoryFileName = name; exportNames.forgetAll() }
        memoryFileNameCandidate = nil
        lastProgramKeys = []
        if let s = pendingSidecar {
            programDoc = s.doc; programDocURL = s.url
        } else if programDoc.isEmpty, let name = memoryFileName {
            programDoc.title = (name as NSString).deletingPathExtension
        }
        pendingSidecar = nil
    }

    // MARK: the program, read on demand

    /// The current listing (also when the inspector is hidden), on the main actor.
    func fetchProgram(_ done: @escaping @MainActor (InspectorSnapshot?) -> Void) {
        guard hasInspector else { stockUnavailable("Program documentation"); return done(nil) }
        guard let e = engine else { return done(nil) }
        e.send(.perform { m in
            let s = m.calc.inspect()
            DispatchQueue.main.async { MainActor.assumeIsolated { done(s) } }
        })
    }

    var documentModelName: String {
        ProgramDocumentInfo.modelName(variant: snapshot.variant, model: snapshot.model)
    }

    func documentContent(_ s: InspectorSnapshot) -> ProgramDocumentContent {
        var doc = programDoc
        doc.model = documentModelName
        let info = ProgramDocumentInfo(modelName: documentModelName, firmware: firmwareName ?? "",
                                       memoryFile: memoryFileName ?? "", model: s.model)
        return ProgramDocumentContent(doc: doc, info: info, lines: s.hasProgram ? s.program : [], pool: s.pool, setFlags: s.setFlags)
    }

    // MARK: menu actions

    /// File ▸ Program Info…: title, author, description, label / register / flag notes.
    func openProgramInfo() {
        fetchProgram { [weak self] s in
            guard let self, let s else { return }
            self.docLines = s.hasProgram ? s.program : []
            var d = self.programDoc
            d.rematch(to: self.docLines)
            d.prefill(from: ProgramAnalysis(lines: self.docLines, model: s.model))
            if d.title.isEmpty, let n = self.memoryFileName { d.title = (n as NSString).deletingPathExtension }
            d.model = self.documentModelName
            self.programDoc = d
            self.showProgramInfo = true
        }
    }

    func openNotes() {
        guard hasInspector else { return stockUnavailable("Program notes") }
        importTask = .notes; showImporter = true
    }

    func notesPicked(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let e): errorMessage = e.localizedDescription
        case .success(let url):
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            do {
                var doc = try ProgramDocument.decode(try Data(contentsOf: url))
                programDocURL = url
                fetchProgram { [weak self] s in
                    guard let self else { return }
                    if let s, s.hasProgram, !s.program.isEmpty {
                        let r = doc.rematch(to: s.program)
                        if r.orphaned > 0 {
                            self.notice = "\(r.orphaned) comment\(r.orphaned == 1 ? "" : "s") in “\(url.lastPathComponent)” no longer match a step of the program in the calculator. They are kept and listed in Program Info."
                        }
                    }
                    self.lastProgramKeys = s?.program.map(\.keys) ?? []
                    self.programDoc = doc
                }
            } catch {
                errorMessage = "“\(url.lastPathComponent)” is not a VoyagerCalc program notes file."
            }
        }
    }

    private var baseName: String {
        if let n = memoryFileName { return n }
        return programDoc.title.isEmpty ? "Program" : programDoc.title
    }

    /// File ▸ Save Program Notes…: "<memory file>.voyagerdoc", to keep next to the memory file.
    func saveNotes() {
        guard hasInspector else { return stockUnavailable("Program notes") }
        do {
            let data = try programDoc.encoded()
            exportKind = .notes; exportType = .voyagerDoc
            exportNameOverrideForDocs(programDocURL.map { ($0.lastPathComponent as NSString).deletingPathExtension } ?? baseName)
            exportDocument = MemoryFile(data: data)
        } catch { errorMessage = error.localizedDescription }
    }

    /// File ▸ Export Program Documentation (PDF)…
    func exportPDF() {
        let paper = self.paper
        fetchProgram { [weak self] s in
            guard let self, let s else { return }
            let content = self.documentContent(s)
            let name = content.title + " documentation"
            let store = self.docFontStore
            DispatchQueue.global(qos: .userInitiated).async {
                let fonts = store.load()           // the two HP 15C Simulator fonts from the app bundle (0.6.7), always
                let data = ProgramDocumentPDF.render(content, paper: paper, fonts: fonts.pdfSet())
                DispatchQueue.main.async { MainActor.assumeIsolated {
                    self.exportKind = .pdf; self.exportType = .pdf
                    self.exportNameOverrideForDocs(name)
                    self.exportDocument = MemoryFile(data: data)
                } }
            }
        }
    }

    /// File ▸ Export Listing as Text…
    func exportText() {
        fetchProgram { [weak self] s in
            guard let self, let s else { return }
            let content = self.documentContent(s)
            self.exportKind = .text; self.exportType = .plainText
            self.exportNameOverrideForDocs(content.title + " listing")
            self.exportDocument = MemoryFile(data: Data(content.plainText().utf8))
        }
    }

    /// File ▸ Clear Program Notes: start empty notes (the sidecar file is not touched).
    func clearNotes() {
        programDoc = ProgramDocument()
        programDocURL = nil
    }

    /// A reset, a model switch or another firmware (0.6.9): nothing of the old program's notes is kept: all step comments, the orphans,
    /// title, author, description and the label / register / flag notes, the sidecar link, the stored copy for this firmware and the
    /// remembered memory file name.
    func clearAllNotes(forgetStored: Bool) {
        programDoc = ProgramDocument()
        programDocURL = nil
        pendingSidecar = nil
        memoryFileNameCandidate = nil
        memoryFileName = nil
        lastProgramKeys = []
        importedManzProgram = nil
        exportNames.forgetAll()
        if forgetStored, persistState { UserDefaults.standard.removeObject(forKey: docDefaultsKey) }
    }

    // MARK: comments

    func comment(at step: Int) -> String { programDoc.comment(at: step) ?? "" }

    func setComment(_ text: String, at step: Int) {
        let lines = inspection?.program ?? docLines
        var d = programDoc
        d.setComment(text, at: step, lines: lines)
        programDoc = d
    }

    func removeOrphans() {
        programDoc.comments.removeAll(where: \.orphaned)
    }
}
