// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// DocFontStore.swift - the user's own HP 15C fonts for the documentation PDF (0.5.7):
// HP15CSimulatorDisplay.ttf (seven-segment display) and HP15CSimulatorKeys.ttf (key caps).
// They are never bundled. Looked for, in order:
//   1. what the user chose with "Use HP 15C Fonts…" (a folder or a font file; macOS keeps a
//      security-scoped bookmark, so the sandboxed app can read it after relaunch; iOS copies
//      the chosen fonts into the app's own container),
//   2. ~/Firmware/Fonts (the real home folder; readable by the no-sandbox build, and by the
//      sandboxed build only once that folder was chosen in step 1).
// Each font is read from its file (never looked up by family name: both original fonts are called
// "HP15C Simulator Font"). Fonts not found: the standard PDF fonts are used.

import Foundation
#if canImport(Darwin)
import Darwin
#endif

struct DocFonts {
    var keys: TrueTypeFont?
    var display: TrueTypeFont?
    var source = ""
    var any: Bool { keys != nil || display != nil }
    /// A fresh set per document (it records which glyphs that document draws).
    func pdfSet() -> PDFFontSet { PDFFontSet(keys: keys, display: display) }
    var summary: String {
        switch (keys != nil, display != nil) {
        case (true, true): "HP 15C key and display fonts"
        case (true, false): "HP 15C key font (no display font)"
        case (false, true): "HP 15C display font (no key font)"
        default: "standard fonts"
        }
    }
}

final class DocFontStore: @unchecked Sendable {   // UserDefaults and file reads only
    static let keysFile = "HP15CSimulatorKeys.ttf", displayFile = "HP15CSimulatorDisplay.ttf"
    private let defaults = UserDefaults.standard
    private let folderKey = "docFontFolderBookmark", keysKey = "docFontKeysBookmark", displayKey = "docFontDisplayBookmark"

    /// The real home folder (in the sandbox, NSHomeDirectory is the container).
    static var realHome: URL {
        #if os(macOS)
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        #endif
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }
    static var defaultFolder: URL { realHome.appendingPathComponent("Firmware/Fonts", isDirectory: true) }

    private var copyDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Fonts", isDirectory: true)
    }

    func load() -> DocFonts {
        var f = DocFonts()
        func take(_ data: Data?, _ from: String) {
            guard let data, let t = try? TrueTypeFont(data: data) else { return }
            switch Self.role(t) {
            case .keys: if f.keys == nil { f.keys = t; f.source = from }
            case .display: if f.display == nil { f.display = t; if f.source.isEmpty { f.source = from } }
            case nil: break
            }
        }
        #if os(macOS)
        if let dir = resolve(folderKey) {
            withAccess(dir) {
                take(try? Data(contentsOf: dir.appendingPathComponent(Self.keysFile)), dir.path)
                take(try? Data(contentsOf: dir.appendingPathComponent(Self.displayFile)), dir.path)
            }
        }
        for k in [keysKey, displayKey] {
            if let u = resolve(k) { withAccess(u) { take(try? Data(contentsOf: u), u.path) } }
        }
        #else
        take(try? Data(contentsOf: copyDir.appendingPathComponent(Self.keysFile)), "app container")
        take(try? Data(contentsOf: copyDir.appendingPathComponent(Self.displayFile)), "app container")
        #endif
        let d = Self.defaultFolder
        if f.keys == nil { take(try? Data(contentsOf: d.appendingPathComponent(Self.keysFile)), d.path) }
        if f.display == nil { take(try? Data(contentsOf: d.appendingPathComponent(Self.displayFile)), d.path) }
        return f
    }

    enum Role { case keys, display }
    /// Which font this is, by its glyphs (the key-cap font draws "¤" as the √x key; the display
    /// font draws no "¤" but has the seven-segment digits), not by its family name.
    static func role(_ t: TrueTypeFont) -> Role? {
        if t.has("¤"), t.has("´"), t.has("|") { return .keys }
        if t.has("8"), t.has(","), t.has("-") { return .display }
        return nil
    }

    /// "Use HP 15C Fonts…": a folder holding the two files, or one font file.
    func remember(_ url: URL) throws -> DocFonts {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        #if os(macOS)
        let bm = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                      includingResourceValuesForKeys: nil, relativeTo: nil)
        if isDir.boolValue {
            defaults.set(bm, forKey: folderKey)
        } else {
            let t = try TrueTypeFont(data: Data(contentsOf: url))
            guard let r = Self.role(t) else { throw CocoaError(.fileReadCorruptFile) }
            defaults.set(bm, forKey: r == .keys ? keysKey : displayKey)
        }
        #else
        try FileManager.default.createDirectory(at: copyDir, withIntermediateDirectories: true)
        let files = isDir.boolValue
            ? [url.appendingPathComponent(Self.keysFile), url.appendingPathComponent(Self.displayFile)] : [url]
        for u in files {
            guard let data = try? Data(contentsOf: u), let t = try? TrueTypeFont(data: data), let r = Self.role(t) else { continue }
            try data.write(to: copyDir.appendingPathComponent(r == .keys ? Self.keysFile : Self.displayFile))
        }
        #endif
        return load()
    }

    func forget() {
        for k in [folderKey, keysKey, displayKey] { defaults.removeObject(forKey: k) }
        try? FileManager.default.removeItem(at: copyDir)
    }

    #if os(macOS)
    private func resolve(_ key: String) -> URL? {
        guard let bm = defaults.data(forKey: key) else { return nil }
        var stale = false
        guard let u = try? URL(resolvingBookmarkData: bm, options: [.withSecurityScope], relativeTo: nil,
                               bookmarkDataIsStale: &stale) else { return nil }
        if stale {
            let ok = u.startAccessingSecurityScopedResource()
            if let fresh = try? u.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                               includingResourceValuesForKeys: nil, relativeTo: nil) {
                defaults.set(fresh, forKey: key)
            }
            if ok { u.stopAccessingSecurityScopedResource() }
        }
        return u
    }
    @discardableResult
    private func withAccess<T>(_ u: URL, _ body: () -> T) -> T? {
        let ok = u.startAccessingSecurityScopedResource()
        defer { if ok { u.stopAccessingSecurityScopedResource() } }
        return body()
    }
    #endif
}
