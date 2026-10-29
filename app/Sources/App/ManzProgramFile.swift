// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// ManzProgramFile.swift - File ▸ Import Program (.15c)… and Export Program (.15c)… (0.7.2): HP-15C programs in the
// text format of Torsten Manz's HP-15C Simulator (see Core/Manz15CProgram.swift). HP-15C only; the menu items are
// disabled with an explanation on the 16C and 12C. Import keys the program in (Core/ProgramEntry15.swift) and takes the
// file's title, description and label / register / flag notes into the program notes (Program Info, PDF).

import Foundation
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

extension UTType {
    /// ".15c" of the HP-15C Simulator (not claimed by the app, see Info.plist; a dynamic type is enough for the panels).
    static let manz15c = UTType(filenameExtension: "15c") ?? .plainText
}

extension AppModel {
    /// Import / export of simulator program files works on a running HP-15C with the inspector (CE firmware).
    var canUseManzFiles: Bool {
        isRunning && hasInspector && hasMemoryFiles && snapshot.model == 15 && !isSwitchingModel && !isImportingProgram
    }

    /// Why the items are greyed out, for the menu (nil when they work).
    var manzFilesUnavailableReason: String? {
        guard isRunning else { return nil }
        if isStock { return nil }                                         // the stock-firmware line already explains it
        if snapshot.model != 15 { return "Program files (.15c) are for the HP-15C: switch the model to the 15C to import or export them" }
        return nil
    }

    #if os(macOS)
    /// File ▸ Import Program (.15c)…
    func importManzProgram() {
        guard snapshot.model == 15 else { errorMessage = ProgramEntryError.notA15C.errorDescription; return }
        guard canUseManzFiles else { return }
        let panel = NSOpenPanel()
        panel.title = "Import HP-15C Program"
        panel.message = "A program file of the HP-15C Simulator (.15c or .txt). It replaces the program in the calculator; registers and matrices are kept."
        panel.allowedContentTypes = [.manz15c, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        let done: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            MainActor.assumeIsolated {
                guard response == .OK, let url = panel.url else { return }
                self?.manzFilePicked(url)
            }
        }
        if let w = NSApp.keyWindow ?? NSApp.mainWindow { panel.beginSheetModal(for: w, completionHandler: done) }
        else { panel.begin(completionHandler: done) }
    }

    func manzFilePicked(_ url: URL) {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        let program: Manz15CProgram
        do {
            program = try Manz15CProgram.read(try Data(contentsOf: url))
        } catch let e as Manz15CProgram.ReadError {
            errorMessage = "“\(url.lastPathComponent)” cannot be imported. " + (e.errorDescription ?? "")
            return
        } catch {
            errorMessage = "“\(url.lastPathComponent)” cannot be read: \(error.localizedDescription)"
            return
        }
        guard !program.steps.isEmpty else { errorMessage = "“\(url.lastPathComponent)” has no program steps."; return }
        let alert = NSAlert()
        alert.messageText = "Import “\(url.lastPathComponent)”?"
        let name = program.title.isEmpty ? "" : " (\(program.title))"
        alert.informativeText = "The program\(name) has \(program.steps.count) steps. It replaces the program in the calculator and its notes; registers, matrices and settings are kept. The steps are keyed in as on the calculator, which can take a little while."
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        enterManzProgram(program, fileName: url.lastPathComponent)
    }
    #endif

    /// Key `program` into the calculator, then take its notes.
    func enterManzProgram(_ program: Manz15CProgram, fileName: String) {
        guard let e = engine else { return }
        isImportingProgram = true
        e.send(.perform { m in
            let r = Result { try m.enterProgram15(program.steps) }
            DispatchQueue.main.async { MainActor.assumeIsolated { [weak self] in self?.manzProgramEntered(r, program, fileName) } }
        })
    }

    private func manzProgramEntered(_ r: Result<ProgramEntryReport, Error>, _ program: Manz15CProgram, _ fileName: String) {
        isImportingProgram = false
        switch r {
        case .failure(let e):
            errorMessage = "“\(fileName)” was not imported. " + ((e as? LocalizedError)?.errorDescription ?? "\(e)")
        case .success(let report):
            var doc = ProgramDocument()
            program.apply(to: &doc)
            if doc.title.isEmpty { doc.title = (fileName as NSString).deletingPathExtension }
            programDoc = doc
            programDocURL = nil
            memoryFileName = nil
            lastProgramKeys = []
            exportNames.forgetAll()
            importedManzProgram = program
            if persistState { saveStateNow(turnBackOn: true) }
            if report.mismatches.isEmpty {
                notice = "Imported “\(fileName)”: \(report.steps) steps."
            } else {
                let list = report.mismatches.prefix(5).map { String(format: "%03d", $0.step) + " {\($0.file)} → {\($0.calculator)}" }
                errorMessage = "“\(fileName)” was keyed in, but \(report.mismatches.count) step\(report.mismatches.count == 1 ? "" : "s") in the calculator differ from the file: "
                    + list.joined(separator: "; ") + (report.mismatches.count > 5 ? "; …" : "") + ". Please check the program."
            }
        }
    }

    /// The program in the calculator as a simulator file, with the program notes.
    func manzProgramForExport(_ s: InspectorSnapshot) throws -> Manz15CProgram {
        var p = Manz15CProgram()
        let doc = programDoc
        p.title = doc.title.isEmpty ? (memoryFileName.map { ($0 as NSString).deletingPathExtension } ?? "") : doc.title
        p.description = doc.description
        p.labelNotes = Manz15CProgram.notes(from: doc, keeping: importedManzProgram?.labelNotes ?? [])
        p.steps = try Manz15CProgram.steps(fromListing: s.hasProgram ? s.program.map(\.keys) : [],
                                           imported: importedManzProgram?.steps)
        return p
    }

    #if os(macOS)
    /// File ▸ Export Program (.15c)…
    func exportManzProgram() {
        guard snapshot.model == 15 else { errorMessage = ProgramEntryError.notA15C.errorDescription; return }
        guard canUseManzFiles else { return }
        fetchProgram { [weak self] s in
            guard let self, let s else { return }
            let program: Manz15CProgram
            do { program = try self.manzProgramForExport(s) }
            catch { self.errorMessage = "The program cannot be written as a .15c file: " + ((error as? LocalizedError)?.errorDescription ?? "\(error)"); return }
            guard !program.steps.isEmpty else { self.errorMessage = "There is no program in the calculator to export."; return }
            let data = program.fileData()
            let panel = NSSavePanel()
            panel.title = "Export HP-15C Program"
            panel.message = "A program file for the HP-15C Simulator (UTF-16 text). Keep the ending “.15c”."
            let base = program.title.isEmpty ? "Program" : program.title
            panel.nameFieldStringValue = base.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-") + ".15c"
            panel.allowedContentTypes = [.manz15c]
            panel.allowsOtherFileTypes = true
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false
            let done: (NSApplication.ModalResponse) -> Void = { [weak self] response in
                MainActor.assumeIsolated {
                    guard response == .OK, let url = panel.url else { return }
                    do {
                        try data.write(to: url, options: .atomic)
                        self?.notice = "Exported \(program.steps.count) steps to “\(url.lastPathComponent)”."
                    } catch {
                        self?.errorMessage = "“\(url.lastPathComponent)” could not be written: \(error.localizedDescription)"
                    }
                }
            }
            if let w = NSApp.keyWindow ?? NSApp.mainWindow { panel.beginSheetModal(for: w, completionHandler: done) }
            else { panel.begin(completionHandler: done) }
        }
    }
    #endif
}
