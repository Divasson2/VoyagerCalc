// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// CalculatorBackView.swift - View ▸ Show Calculator Back (⌘B): a separate, resizable window with a photograph of
// the back of the current calculator (HP-15C and HP-16C; photographs by Warren Young). It follows model changes;
// for the HP-12C there is no back picture and the window says so (the menu item is disabled then).

import SwiftUI

struct CalculatorBackView: View {
    static let windowID = "calculatorBack"
    @EnvironmentObject var app: AppModel

    static func imageName(model: Int) -> String? {
        model == 15 ? "back_15c" : model == 16 ? "back_16c" : nil
    }
    static func title(model: Int) -> String { model == 15 || model == 16 ? "HP-\(model)C Back" : "Calculator Back" }

    var body: some View {
        let model = app.snapshot.model
        ZStack {
            Color(rgb: 0x1E1E1E)
            if app.isRunning, let name = Self.imageName(model: model), let img = FaceImages.image(name) {
                img.resizable().interpolation(.high).aspectRatio(contentMode: .fit).padding(8)
                    .accessibilityLabel("Back of the HP-\(model)C")
            } else {
                Text("The back picture is available for the HP-15C and HP-16C.").foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 320, minHeight: 200)
        .navigationTitle(Self.title(model: model))
    }
}
