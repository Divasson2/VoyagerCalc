// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// ExportNames.swift - the file name last used for each kind of export (0.6.5), so that repeating
// "Export Listing as Text…" (or the PDF, the notes, the memory file) offers the name the user chose
// last time instead of the generic default. Kept for the session; forgotten when another memory
// file is opened (a different document).

import Foundation

struct ExportNameMemory: Equatable {
    private var names: [String: String] = [:]
    private var endings: [String: String] = [:]      // 0.6.9: the ending typed last time (memory files: .bin15c is only the default)

    /// The name to offer: the one used last time for this kind, else the computed default.
    func name(for kind: String, default fallback: String) -> String {
        names[kind].flatMap { $0.isEmpty ? nil : $0 } ?? fallback
    }

    /// Remember the file the user saved (the extension is dropped: the panel adds its own).
    mutating func remember(_ kind: String, url: URL) {
        let base = url.deletingPathExtension().lastPathComponent
        if !base.isEmpty { names[kind] = base }
        let ext = url.pathExtension
        if ext.isEmpty { endings[kind] = nil } else { endings[kind] = ext }
    }

    /// The ending the user saved with last time for this kind, if any.
    func ending(for kind: String) -> String? { endings[kind] }

    mutating func forgetAll() { names.removeAll(); endings.removeAll() }
    var isEmpty: Bool { names.isEmpty }
}
