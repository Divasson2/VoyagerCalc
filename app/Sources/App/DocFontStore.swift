// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// DocFontStore.swift - the two HP 15C Simulator fonts of the documentation PDF:
// HP15CSimulatorDisplay.ttf (seven-segment display) and HP15CSimulatorKeys.ttf (key caps).
// Since 0.6.7 they are part of the app: both files sit in the app bundle (Contents/Resources on the
// Mac, the bundle folder on iOS), and the PDF always uses them; there is nothing to choose.
// Credit: the key-cap font was designed by Eric Rechlin, the seven-segment display font by Torsten Manz
// ("HP15C Simulator Font (c) 2005 Torsten Manz, Freeware"). Jose confirmed both may be redistributed. The
// fonts are renamed copies (name table only; the copyright fields are kept as they were) and the credit is
// in About, the README and art/fonts/README.md.
// Each font is read from its file (never looked up by family name) and embedded as a subset in the PDF.
// Fonts missing from the bundle (not expected): the standard PDF fonts are used, as before.

import Foundation

struct DocFonts {
    var keys: TrueTypeFont?
    var display: TrueTypeFont?
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

final class DocFontStore: @unchecked Sendable {   // file reads only
    static let keysFile = "HP15CSimulatorKeys.ttf", displayFile = "HP15CSimulatorDisplay.ttf"

    /// The credit shown in About (and kept in the README and art/fonts/README.md): Manz's freeware copyright notice stays with the display font.
    static let credit = "Documentation PDF fonts, included with the app: key-cap font by Eric Rechlin; seven-segment display font by Torsten Manz (HP15C Simulator Font © 2005 Torsten Manz, Freeware). The font files are renamed copies (name table only) that keep their copyright notices. HP-15C and HP-16C calculator photographs by Warren Young."

    /// The bundles searched: the one holding this code (the app, or the test bundle in tests), then the main bundle.
    private static var bundles: [Bundle] { [Bundle(for: DocFontStore.self), Bundle.main] }

    /// The file inside the app bundle (Resources/ or Resources/Fonts/), nil if it is not there.
    static func bundledURL(_ file: String) -> URL? {
        let name = (file as NSString).deletingPathExtension, ext = (file as NSString).pathExtension
        for b in bundles {
            if let u = b.url(forResource: name, withExtension: ext) { return u }
            if let u = b.url(forResource: name, withExtension: ext, subdirectory: "Fonts") { return u }
        }
        return nil
    }

    /// Both fonts from the bundle (read again at every call; they are small).
    func load() -> DocFonts {
        var f = DocFonts()
        func read(_ file: String) -> TrueTypeFont? {
            guard let u = Self.bundledURL(file), let data = try? Data(contentsOf: u) else { return nil }
            return try? TrueTypeFont(data: data)
        }
        if let t = read(Self.keysFile), Self.role(t) == .keys { f.keys = t }
        if let t = read(Self.displayFile), Self.role(t) == .display { f.display = t }
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
}
