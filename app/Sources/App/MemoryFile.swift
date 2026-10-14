// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// MemoryFile.swift - .16c / .15c / .12c memory files (the 2 KB VoyagerSave image); the same
// FileDocument also carries the program notes, PDF and text exports to the save panel.

import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let voyager16c = UTType(exportedAs: "com.josegonzalezdivasson.voyagercalc.memory16c", conformingTo: .data)
    static let voyager15c = UTType(exportedAs: "com.josegonzalezdivasson.voyagercalc.memory15c", conformingTo: .data)
    static let voyager12c = UTType(exportedAs: "com.josegonzalezdivasson.voyagercalc.memory12c", conformingTo: .data)

    /// VoyagerCalc program notes (the sidecar of a memory file), JSON.
    static let voyagerDoc = UTType(exportedAs: "com.josegonzalezdivasson.voyagercalc.programdoc", conformingTo: .json)

    static func memoryType(for model: CalculatorModel) -> UTType {
        switch model.id {
        case 12: return .voyager12c
        case 15: return .voyager15c
        default: return .voyager16c
        }
    }
}

struct MemoryFile: FileDocument {
    static var readableContentTypes: [UTType] { [.voyager16c, .voyager15c, .voyager12c, .data] }
    static var writableContentTypes: [UTType] { [.voyager16c, .voyager15c, .voyager12c, .voyagerDoc, .pdf, .plainText] }

    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let d = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        data = d
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
