// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// KeyZones.swift - the three click / tap zones of a key (0.5.5):
//   * fLabel: the gold legend above the key       -> f, then the key
//   * face:   the key cap itself                  -> the key
//   * gLabel: the blue legend on the cap's front  -> g, then the key
// A key without a gold / blue legend has no such zone (that part belongs to the face).
// The zones of one key tile its hit area, and hit areas of neighbouring keys never overlap,
// so a point belongs to at most one (key, part).

import Foundation

public enum KeyPart: String, Sendable, CaseIterable { case face, fLabel, gLabel }

public struct KeyZones: Equatable, Sendable {
    public var face: CGRect
    public var f: CGRect?
    public var g: CGRect?

    public func rect(_ p: KeyPart) -> CGRect? {
        switch p { case .face: return face; case .fLabel: return f; case .gLabel: return g }
    }
    public func part(at p: CGPoint) -> KeyPart? {
        if let f, f.contains(p) { return .fLabel }
        if let g, g.contains(p) { return .gLabel }
        return face.contains(p) ? .face : nil
    }

    /// Split a key's whole area: the strip above `capTop` is the gold zone, the strip from
    /// `gTop` down is the blue zone (each only if the key has that legend).
    public static func split(area a: CGRect, capTop: CGFloat, gTop: CGFloat, hasF: Bool, hasG: Bool) -> KeyZones {
        let top = hasF ? min(max(capTop, a.minY), a.maxY) : a.minY
        let bottom = hasG ? max(min(gTop, a.maxY), top) : a.maxY
        return KeyZones(face: CGRect(x: a.minX, y: top, width: a.width, height: bottom - top),
                        f: hasF ? CGRect(x: a.minX, y: a.minY, width: a.width, height: top - a.minY) : nil,
                        g: hasG ? CGRect(x: a.minX, y: bottom, width: a.width, height: a.maxY - bottom) : nil)
    }
}

extension KeySpec {
    /// The shift key a part sends first (31 = f, 32 = g), or nil for the key alone.
    public func shift(for part: KeyPart) -> Int? {
        switch part {
        case .fLabel: return f.isEmpty ? nil : 31
        case .gLabel: return g.isEmpty ? nil : 32
        case .face: return nil
        }
    }
}

extension PhotoFace {
    /// Height of the blue-legend zone, as a fraction of a normal cap (measured on the photo).
    public var gZoneFraction: CGFloat { Self.gZoneFractions[imageName] ?? 0.36 }

    /// The zones of a key on the photo (fractions of the image): its hit area split at the
    /// cap's top edge (gold legend above it) and at the top of the blue legend on the cap's front.
    public func zones(_ k: KeySpec) -> KeyZones? {
        guard let area = hitRect(k.code), let cap = keyRect(k.code) else { return nil }
        let capH = keys[24]?.height ?? cap.height
        return KeyZones.split(area: area, capTop: cap.minY, gTop: cap.maxY - capH * gZoneFraction,
                              hasF: !k.f.isEmpty, hasG: !k.g.isEmpty)
    }

    /// The key and part under a point (fractions of the image).
    public func part(at p: CGPoint, model: CalculatorModel) -> (code: Int, part: KeyPart)? {
        guard let code = key(at: p), let k = model.key(code: code) else { return nil }
        return (k.code, zones(k)?.part(at: p) ?? .face)
    }
}

extension KeyZones {
    /// Height of the blue-legend front of a drawn key (KeyView draws it so).
    public static func drawnFrontHeight(keyHeight h: CGFloat, unit: CGFloat, isEnter: Bool) -> CGFloat {
        isEnter ? min(h * 0.16, unit * 0.30) : h * 0.30
    }

    /// The zones of a key on the drawn face: its gold legend strip above the key, the cap, and
    /// the cap's front with the blue legend.
    public static func drawn(legend: CGRect, key: CGRect, unit: CGFloat, spec: KeySpec) -> KeyZones {
        let front = drawnFrontHeight(keyHeight: key.height, unit: unit, isEnter: spec.style == .enter)
        let hasF = !spec.f.isEmpty
        let area = hasF ? CGRect(x: min(legend.minX, key.minX), y: legend.minY,
                                 width: max(legend.maxX, key.maxX) - min(legend.minX, key.minX),
                                 height: key.maxY - legend.minY) : key
        var z = split(area: area, capTop: key.minY, gTop: key.maxY - front, hasF: hasF, hasG: !spec.g.isEmpty)
        // the cap and its front keep the key's own width; the gold strip spans the legend cell
        z.face = CGRect(x: key.minX, y: z.face.minY, width: key.width, height: z.face.height)
        if let g = z.g { z.g = CGRect(x: key.minX, y: g.minY, width: key.width, height: g.height) }
        if let f = z.f { z.f = CGRect(x: legend.minX, y: f.minY, width: legend.width, height: f.height) }
        return z
    }
}
