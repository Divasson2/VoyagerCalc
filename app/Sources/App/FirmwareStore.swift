// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// FirmwareStore.swift - the user's own firmware file, picked once and remembered.
// macOS: a security-scoped bookmark to the file where it is. iOS / iPadOS: a copy in the
// app's own container (Application Support). Firmware is never bundled with the app.

import Foundation

struct StoredFirmware {
    let name: String
    let data: Data
}

final class FirmwareStore {
    private let defaults = UserDefaults.standard
    private let bookmarkKey = "firmwareBookmark"
    private let nameKey = "firmwareName"

    private var copyDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Firmware", isDirectory: true)
    }

    var rememberedName: String? { defaults.string(forKey: nameKey) }

    /// Read the remembered firmware, if any.
    func load() -> StoredFirmware? {
        guard let name = rememberedName else { return nil }
        #if os(macOS)
        guard let bm = defaults.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bm, options: [.withSecurityScope],
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return nil }
        if stale, let fresh = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(fresh, forKey: bookmarkKey)
        }
        return StoredFirmware(name: name, data: data)
        #else
        guard let data = try? Data(contentsOf: copyDir.appendingPathComponent("firmware.bin")) else { return nil }
        return StoredFirmware(name: name, data: data)
        #endif
    }

    /// Read a file the user picked (fileImporter URL) without remembering it yet.
    func read(_ url: URL) throws -> StoredFirmware {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        return StoredFirmware(name: url.lastPathComponent, data: try Data(contentsOf: url))
    }

    /// Remember a picked file that the core accepted.
    func remember(_ url: URL, firmware: StoredFirmware) throws {
        #if os(macOS)
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        let bm = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(bm, forKey: bookmarkKey)
        #else
        try FileManager.default.createDirectory(at: copyDir, withIntermediateDirectories: true)
        var dest = copyDir.appendingPathComponent("firmware.bin")
        try firmware.data.write(to: dest, options: .atomic)
        var rv = URLResourceValues(); rv.isExcludedFromBackup = true
        try? dest.setResourceValues(rv)
        #endif
        defaults.set(firmware.name, forKey: nameKey)
    }

    func forget() {
        defaults.removeObject(forKey: bookmarkKey)
        defaults.removeObject(forKey: nameKey)
        #if !os(macOS)
        try? FileManager.default.removeItem(at: copyDir)
        #endif
    }
}

/// The calculator's continuous memory between launches (Application Support/State), one file
/// per firmware file (by its SHA-256), so each firmware comes back with its own memory and the
/// model last chosen on it. calculator.json is the last state of any firmware (older versions).
final class StateStore {
    private var dir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("State", isDirectory: true)
    }
    private var url: URL { dir.appendingPathComponent("calculator.json") }
    private func url(for id: String) -> URL { dir.appendingPathComponent("calculator-\(id.prefix(16)).json") }

    private func read(_ u: URL) -> SavedState? {
        guard let d = try? Data(contentsOf: u) else { return nil }
        return try? JSONDecoder().decode(SavedState.self, from: d)
    }

    /// The state saved for this firmware, or the last state (whatever firmware it belongs to).
    func load(firmwareID: String? = nil) -> SavedState? {
        if let id = firmwareID {
            if let s = read(url(for: id)), s.firmwareID == id { return s }
            if let s = read(url), s.firmwareID == id { return s }
            return nil
        }
        return read(url)
    }

    func save(_ s: SavedState) {
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let d = try JSONEncoder().encode(s)
            try d.write(to: url, options: .atomic)
            if !s.firmwareID.isEmpty { try d.write(to: url(for: s.firmwareID), options: .atomic) }
        } catch {
            NSLog("VoyagerCalc: could not save the calculator state: \(error)")
        }
    }

    /// Forget the state of this firmware (and the last state).
    func clear(firmwareID: String? = nil) {
        try? FileManager.default.removeItem(at: url)
        if let id = firmwareID { try? FileManager.default.removeItem(at: url(for: id)) }
    }
}
