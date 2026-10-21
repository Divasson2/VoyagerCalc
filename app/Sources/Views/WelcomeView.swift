// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón

import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        ZStack {
            Color(rgb: 0x3B302A).ignoresSafeArea()
            VStack(spacing: 18) {
                Text("VoyagerCalc")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(Color(rgb: 0xE3A63A))
                Text("This app runs the firmware of your own CE calculator (12C, 15C or 16C, including multi-model builds), or HP's original 12C firmware with limits. No firmware comes with the app.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white.opacity(0.9))
                    .frame(maxWidth: 460)
                if app.isStarting {
                    ProgressView().tint(.white)
                    Text("Starting the calculator…").foregroundColor(.white.opacity(0.8))
                } else {
                    Button {
                        app.chooseFirmware()
                    } label: {
                        Label("Choose Firmware File…", systemImage: "cpu")
                            .font(.headline)
                            .padding(.horizontal, 18).padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(rgb: 0xB79A63))
                    Text("Pick the .bin file you flash to the calculator (about 112 KB). The app remembers it.")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(30)
        }
    }
}

struct AboutView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) private var dismiss

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("VoyagerCalc").font(.title.bold())
            Text("Version \(version)").foregroundColor(.secondary)
            Text("A calculator app that emulates the ARM chip of the CE calculators and runs the firmware file you supply.")
            if let fw = app.firmwareName {
                Text("Firmware: \(fw)\n\(app.firmwareInfo)" + (app.firmwareChecksum.map { "\nChecksum \($0)" } ?? "")).font(.callout).foregroundColor(.secondary)
            }
            if app.isStock {
                Divider()
                Text("HP's original 12C firmware").font(.callout.bold())
                Text(AppModel.stockLimits).font(.callout).foregroundColor(.secondary)
            }
            Divider()
            Text("Copyright © 2026 José González Divassón. MIT License.")
                .font(.callout)
            Text(DocFontStore.credit)
                .font(.callout).foregroundColor(.secondary)
            Text("Not affiliated with, endorsed by or sponsored by HP Inc. Model numbers are used only to say which firmware the app works with.")
                .font(.callout).foregroundColor(.secondary)
            HStack {
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(maxWidth: 440)
    }
}
