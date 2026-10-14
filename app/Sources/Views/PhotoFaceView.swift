// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// PhotoFaceView.swift - the calculator as a product photo (PhotoFace): the photo with its
// LCD glass emptied, the live display drawn over the glass, and an invisible click / tap
// area over every key (PhotoFace.hitRect). A pressed key sinks: the cap is drawn again
// shifted down a little and darkened, over a shadow where it was.

import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Loads the face PNGs shipped in the app bundle (Resources/Faces), cached. Callable from
/// any context (views, tests); the cache is behind a lock.
enum FaceImages {
    #if os(macOS)
    typealias PlatformImage = NSImage
    #else
    typealias PlatformImage = UIImage
    #endif

    private final class Cache: @unchecked Sendable {
        let lock = NSLock()
        var images: [String: PlatformImage] = [:]
    }
    private static let cache = Cache()

    static func image(_ name: String) -> Image? {
        cache.lock.lock(); defer { cache.lock.unlock() }
        if let img = cache.images[name] { return wrap(img) }
        // main bundle (the app), then any loaded bundle (the unit-test bundle for snapshots)
        let bundles = [Bundle.main] + Bundle.allBundles + Bundle.allFrameworks
        for b in bundles {
            if let url = b.url(forResource: name, withExtension: "png") ?? b.url(forResource: name, withExtension: "png", subdirectory: "Faces"),
               let img = PlatformImage(contentsOfFile: url.path) {
                cache.images[name] = img
                return wrap(img)
            }
        }
        return nil
    }

    private static func wrap(_ img: PlatformImage) -> Image {
        #if os(macOS)
        return Image(nsImage: img)
        #else
        return Image(uiImage: img)
        #endif
    }
}

struct PhotoCalculatorFace: View {
    let model: CalculatorModel
    let face: PhotoFace
    let lcd: LCDState
    let pressed: Set<Int>
    var turbo = false
    var press: (Int) -> Void = { _ in }
    var release: (Int) -> Void = { _ in }
    /// A press on a key's gold / blue legend (nil: the key alone).
    var pressPart: ((Int, KeyPart) -> Void)? = nil

    var body: some View {
        GeometryReader { geo in
            // fit the photo in the space, keeping its aspect, centred
            let scale = min(geo.size.width / face.aspect, geo.size.height)
            let size = CGSize(width: scale * face.aspect, height: scale)
            let origin = CGPoint(x: (geo.size.width - size.width) / 2, y: (geo.size.height - size.height) / 2)
            if let photo = FaceImages.image(face.emptyLCDImageName) {
                ZStack(alignment: .topLeading) {
                    photo.resizable().interpolation(.high)
                        .frame(width: size.width, height: size.height)
                    let l = rect(face.lcd, in: size)
                    LCDView(lcd: lcd, model: model, overPhoto: true)
                        .frame(width: l.width, height: l.height)
                        .offset(x: l.minX, y: l.minY)
                        .allowsHitTesting(false)
                    ForEach(model.keys.filter { pressed.contains($0.code) || ($0.style == .enter && pressed.contains(35)) }) { k in
                        if let r = face.keyRect(k.code) {
                            PressedKey(photo: photo, cap: rect(r, in: size), size: size)
                        }
                    }
                    ForEach(model.keys) { k in
                        if let h = face.hitRect(k.code) {
                            let r = rect(h, in: size)
                            // font scale = a normal (one-row) key's height, so the tall ENTER key's hint
                            // is not twice the size of the others
                            PhotoKeyArea(key: k, unit: rect(face.keyRect(k.style == .enter ? 24 : k.code)
                                                                 ?? face.keyRect(k.code) ?? h, in: size).height,
                                         zones: face.zones(k).map { local($0, area: r, in: size) },
                                         onPress: { part in
                                             if part != .face, let pp = pressPart { pp(k.code, part) } else { press(k.code) }
                                         },
                                         onRelease: { release(k.code) })
                                .frame(width: r.width, height: r.height)
                                .offset(x: r.minX, y: r.minY)
                        }
                    }
                    if turbo {
                        Text("TURBO")
                            .font(.system(size: max(7, size.height * 0.022), weight: .heavy, design: .rounded))
                            .foregroundColor(Color(rgb: 0xE3A63A))
                            .padding(.horizontal, 4)
                            .overlay(Capsule().stroke(Color(rgb: 0xE3A63A), lineWidth: 1))
                            .offset(x: l.minX, y: l.maxY + size.height * 0.012)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .offset(x: origin.x, y: origin.y)
            } else {
                // image missing from the bundle: fall back to the drawn face
                CalculatorFace(model: model, lcd: lcd, pressed: pressed, layout: .landscape, turbo: turbo,
                               press: press, release: release, pressPart: pressPart)
            }
        }
    }

    private func rect(_ r: CGRect, in size: CGSize) -> CGRect {
        CGRect(x: r.minX * size.width, y: r.minY * size.height, width: r.width * size.width, height: r.height * size.height)
    }

    /// Zones (fractions of the image) in the coordinates of the key's area view.
    private func local(_ z: KeyZones, area: CGRect, in size: CGSize) -> KeyZones {
        func l(_ r: CGRect) -> CGRect { rect(r, in: size).offsetBy(dx: -area.minX, dy: -area.minY) }
        return KeyZones(face: l(z.face), f: z.f.map(l), g: z.g.map(l))
    }
}

/// A pressed key: shadow where the cap was, the cap itself shifted down and darkened.
private struct PressedKey: View {
    let photo: Image
    let cap: CGRect
    let size: CGSize

    var body: some View {
        let dy = max(1, cap.height * 0.045)
        let corner = min(cap.width, cap.height) * 0.08
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(Color.black.opacity(0.55))
                .frame(width: cap.width, height: cap.height)
                .offset(x: cap.minX, y: cap.minY)
            photo.resizable().interpolation(.high)
                .frame(width: size.width, height: size.height)
                .offset(y: dy)
                .mask(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .frame(width: cap.width, height: cap.height - dy)
                        .offset(x: cap.minX, y: cap.minY + dy)
                }
                .brightness(-0.12)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// Invisible click / tap area of one key, held for as long as the button / finger is.
private struct PhotoKeyArea: View {
    let key: KeySpec
    let unit: CGFloat
    /// The key's gold / cap / blue zones, in this view's coordinates.
    var zones: KeyZones? = nil
    let onPress: (KeyPart) -> Void
    let onRelease: () -> Void

    @State private var touching = false
    @State private var hovering = false
    @State private var hoverPart: KeyPart?
    @Environment(\.latchedKeys) private var latched

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .overlay(alignment: .topLeading) {
                // a subtle highlight on the legend under the pointer
                if let p = hoverPart, p != .face, let r = zones?.rect(p) {
                    RoundedRectangle(cornerRadius: unit * 0.08, style: .continuous)
                        .fill((p == .fLabel ? Color(rgb: 0xE3A63A) : Color(rgb: 0x5DA9E8)).opacity(0.18))
                        .frame(width: r.width, height: r.height)
                        .offset(x: r.minX, y: r.minY)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .top) {
                // the keyboard shortcut, over the cap (not over the legends)
                if hovering, hoverPart == nil || hoverPart == .face, !key.shortcuts.isEmpty {
                    Text(key.shortcutHint)
                        .font(.system(size: max(8, unit * 0.2), weight: .bold, design: .rounded))
                        .padding(.horizontal, 3).padding(.vertical, 1)
                        .background(Capsule().fill(Color.black.opacity(0.75)))
                        .foregroundColor(.white)
                        .offset(y: zones?.face.minY ?? 0)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                if latched.contains(key.code) || (key.style == .enter && latched.contains(25)) {
                    RoundedRectangle(cornerRadius: unit * 0.12, style: .continuous)
                        .stroke(Color(rgb: 0xE3A63A), lineWidth: max(1.5, unit * 0.07))
                        .allowsHitTesting(false)
                }
            }
            .modifier(KeyPressGesture(code: key.code, touching: $touching,
                                      onPress: { p in onPress(zones?.part(at: p) ?? .face) }, onRelease: onRelease))
            #if os(macOS)
            .onContinuousHover { phase in
                switch phase {
                case .active(let p): hovering = true; hoverPart = zones?.part(at: p)
                case .ended: hovering = false; hoverPart = nil
                }
            }
            #endif
            .help(helpText)
            .accessibilityElement()
            .accessibilityLabel(Text(accessibilityName))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onPress(.face); onRelease() }
    }

    private var helpText: String {
        var t = key.shortcutHelp
        if !key.f.isEmpty { t += " — gold legend: f \(key.f)" }
        if !key.g.isEmpty { t += " — blue legend: g \(key.g)" }
        return t
    }

    private var accessibilityName: String {
        var parts = [key.face]
        if !key.f.isEmpty { parts.append("f \(key.f)") }
        if !key.g.isEmpty { parts.append("g \(key.g)") }
        return parts.joined(separator: ", ")
    }
}
