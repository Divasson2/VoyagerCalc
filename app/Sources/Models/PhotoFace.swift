// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// PhotoFace.swift - a calculator face made from a product photo (art/faces/, built by
// art/tools/make_faces.py): the image names, the LCD glass window and every key cap's
// rectangle, all as fractions of the image (origin top-left), so the app can draw the live
// display over the empty glass and hit-test clicks / taps against the real keys.
// The numbers themselves are generated into PhotoFaceGeometry.swift.

import Foundation

public struct PhotoFace: Sendable {
    /// Face with the photo's own LCD contents (reference only, not shipped in the app).
    public let imageName: String
    /// Face with the LCD glass emptied; the app draws the live display over it.
    public let emptyLCDImageName: String
    public let pixelSize: CGSize
    /// The LCD glass window.
    public let lcd: CGRect
    /// Key caps by key code (the tall ENTER is code 25; 35 maps to it).
    public let keys: [Int: CGRect]
    /// Key pitch (centre to centre), measured from the caps.
    public let pitch: CGSize

    public init(imageName: String, emptyLCDImageName: String, pixelSize: CGSize, lcd: CGRect, keys: [Int: CGRect]) {
        self.imageName = imageName; self.emptyLCDImageName = emptyLCDImageName
        self.pixelSize = pixelSize; self.lcd = lcd; self.keys = keys
        func median(_ v: [CGFloat]) -> CGFloat { let s = v.sorted(); return s.isEmpty ? 0 : s[s.count / 2] }
        var dx: [CGFloat] = [], dy: [CGFloat] = []
        for (code, r) in keys where code != 25 {
            if let right = keys[code + 1], code % 10 != 9, code + 1 != 25 { dx.append(right.midX - r.midX) }
            if let below = keys[code + 10], code + 10 != 25, code + 10 != 35 { dy.append(below.minY - r.minY) }
        }
        pitch = CGSize(width: median(dx), height: median(dy))
    }

    /// Width / height of the image.
    public var aspect: CGFloat { pixelSize.width / pixelSize.height }

    public func keyRect(_ code: Int) -> CGRect? { keys[code == 35 ? 25 : code] }

    /// The area that answers a click / tap for a key: the cap grown half-way into the gaps
    /// beside it, and upwards over its gold legend (about two thirds of the gap above) -
    /// like pressing a real key slightly off-centre. Neighbouring areas meet but never overlap.
    public func hitRect(_ code: Int) -> CGRect? {
        let c = code == 35 ? 25 : code
        guard let r = keys[c] else { return nil }
        func at(_ n: Int) -> CGRect? {
            guard n >= 0, n < 40 else { return nil }
            let m = n == 35 ? 25 : n
            return m == c ? nil : keys[m]
        }
        let col = c % 10
        let gapX = max(0, pitch.width - r.width)
        let capH = keys[24]?.height ?? r.height
        let gapY = max(0, pitch.height - capH)
        let up = 0.68                                   // share of the vertical gap above a key
        let left = col > 0 ? at(c - 1).map { ($0.maxX + r.minX) / 2 } ?? r.minX - gapX / 2 : r.minX - gapX / 2
        let right = col < 9 ? at(c + 1).map { (r.maxX + $0.minX) / 2 } ?? r.maxX + gapX / 2 : r.maxX + gapX / 2
        let top = at(c - 10).map { $0.maxY + (r.minY - $0.maxY) * (1 - up) } ?? r.minY - gapY * up
        let bottom = at(c + 10).map { r.maxY + ($0.minY - r.maxY) * (1 - up) }
            ?? at(c + 20).map { r.maxY + ($0.minY - r.maxY) * (1 - up) }   // ENTER spans two rows
            ?? r.maxY + gapY * (1 - up)
        return CGRect(x: max(0, left), y: max(0, top), width: min(1, right) - max(0, left), height: min(1, bottom) - max(0, top))
    }

    /// Key code at a point given as fractions of the image (nil between the keys' areas).
    public func key(at p: CGPoint) -> Int? {
        if let hit = keys.first(where: { $0.value.contains(p) }) { return hit.key }
        return keys.keys.sorted().first { hitRect($0)?.contains(p) == true }
    }
}

extension CalculatorModel {
    /// The photo face for this model, if there is one.
    public var photoFace: PhotoFace? {
        switch id {
        case 12: return .hp12c
        case 15: return .hp15c
        case 16: return .hp16c
        default: return nil
        }
    }
}
