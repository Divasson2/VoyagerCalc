// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// VoyagerCalcApp.swift - app entry: one window (Mac) / full screen (iOS), menus.

import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

@main
struct VoyagerCalcApp: App {
    @StateObject private var app = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(app)
                #if os(macOS)
                .frame(minWidth: 480, minHeight: 300)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    app.saveStateNow()
                }
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 900, height: 560)
        .windowResizability(.contentMinSize)
        #endif
        .onChange(of: scenePhase) { _, phase in
            #if os(iOS)
            if phase == .background { app.saveStateNow() }
            if phase == .active { app.resumeAfterBackground() }
            #endif
        }
        .commands { CalculatorCommands(app: app) }
    }
}

@MainActor
struct CalculatorCommands: Commands {
    @ObservedObject var app: AppModel

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About VoyagerCalc") { app.showAbout = true }
        }
        CommandGroup(replacing: .newItem) {
            Button("Open Memory File…") { app.openMemory() }
                .keyboardShortcut("o")
                .disabled(!app.isRunning)
            Button("Save Memory File…") { app.saveMemory() }
                .keyboardShortcut("s")
                .disabled(!app.isRunning)
            Divider()
            Button("Program Info…") { app.openProgramInfo() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(!app.isRunning)
            Button("Open Program Notes…") { app.openNotes() }.disabled(!app.isRunning)
            Button("Save Program Notes…") { app.saveNotes() }.disabled(!app.isRunning)
            Button("Export Program Documentation (PDF)…") { app.exportPDF() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(!app.isRunning)
            Button("Export Listing as Text…") { app.exportText() }.disabled(!app.isRunning)
            Picker("PDF Paper Size", selection: $app.paper) {
                ForEach(PDFPaper.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Button("Clear Program Notes") { app.clearNotes() }.disabled(!app.isRunning)
            Menu("PDF Fonts") {
                Text("Using: \(app.docFonts.summary)")
                Button("Use HP 15C Fonts…") { app.chooseDocFonts() }
                Button("Forget HP 15C Fonts") { app.forgetDocFonts() }
            }
            Divider()
            Button("Choose Firmware…") { app.chooseFirmware() }
        }
        CommandGroup(before: .toolbar) {
            Button(app.showInspector ? "Hide Registers & Program" : "Show Registers & Program") { app.showInspector.toggle() }
                .keyboardShortcut("i")
                .disabled(!app.isRunning)
            Divider()
        }
        CommandMenu("Calculator") {
            Toggle("Turbo", isOn: $app.turbo).keyboardShortcut("t")
            Button("ON / OFF") { app.togglePower() }.disabled(!app.isRunning)
            Divider()
            Picker("Keyboard", selection: $app.skin) {
                ForEach(SkinChoice.allCases) { Text($0.title).tag($0) }
            }
            Picker("Face", selection: $app.faceStyle) {
                ForEach(FaceStyle.allCases) { Text($0.title).tag($0) }
            }
            Divider()
            Button("Reset Calculator (clears memory)") { app.resetCalculator() }.disabled(!app.isRunning)
            #if os(macOS)
            Divider()
            Section("Real Calculator (USB)") { CalculatorLinkMenuItems(app: app) }
            #endif
        }
        CommandMenu("Model") { ModelMenuItems(app: app) }
        CommandMenu("Keys") { KeysMenuItems(app: app) }
    }
}

/// Model menu: the calculator images in the firmware, the running one checked. Choosing one
/// runs the calculator's own switch (after a confirmation). Single-image firmware: one
/// greyed item.
struct ModelMenuItems: View {
    @ObservedObject var app: AppModel

    var body: some View {
        if app.images.isEmpty {
            Text("No firmware").foregroundColor(.secondary)
        }
        ForEach(app.images, id: \.self) { v in
            Toggle(CalculatorMachine.variantName(v), isOn: Binding(
                get: { app.isRunning && app.runningVariant == v },
                set: { _ in app.chooseModel(v) }))
                .disabled(!app.canSwitchModel)
        }
        if app.images.count > 1 {
            Divider()
            Text(app.isSwitchingModel ? "Switching…" : "Switching clears the calculator's memory")
        }
    }
}

#if os(macOS)
/// Calculator menu, real calculator over USB HID (f + ENTER + ON on the calculator first).
struct CalculatorLinkMenuItems: View {
    @ObservedObject var app: AppModel

    var body: some View {
        Button("Read from Calculator") { app.readFromCalculator() }
            .disabled(!app.isRunning || app.linkBusy)
        Button("Write to Calculator…") { app.writeToCalculator() }
            .disabled(!app.isRunning || app.linkBusy)
        Button("Save Calculator Memory to File…") { app.saveCalculatorMemoryToFile() }
            .disabled(app.linkBusy)
        Text(app.linkStatus ?? "USB: calculator off, hold f + ENTER, press ON")
        Toggle("Log USB Traffic", isOn: Binding(get: { USBLog.enabled }, set: { USBLog.enabled = $0 }))
        Button("Show USB Log in Finder") {
            if !FileManager.default.fileExists(atPath: USBLog.url.path) { USBLog.write("(log started)") }
            NSWorkspace.shared.activateFileViewerSelecting([USBLog.url])
        }
    }
}
#endif

/// Keys menu: the documented chords with ON, and letting go of latched keys.
struct KeysMenuItems: View {
    @ObservedObject var app: AppModel

    var body: some View {
        ForEach(KeyChord.allCases.filter { $0.isAvailable(model: app.snapshot.model) }) { c in
            Button(c.menuTitle + (c.needsConfirmation ? "…" : "")) { app.perform(c) }
                .disabled(!app.isRunning || app.isSwitchingModel)
                .help(c.explanation)
        }
        Divider()
        Button("Release Held Keys") { app.releaseLatchedKeys() }
            .disabled(app.latchedKeys.isEmpty)
        #if os(macOS)
        Text("Hold a key down: ⌘-click or right-click it")
        #else
        Text("Hold a key down: long-press it")
        #endif
        Text("f-ENTER-ON: no USB in the app, the calculator just turns on")
    }
}

struct ContentView: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        Group {
            if app.isRunning {
                CalculatorWithInspector()
                #if os(iOS)
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
                #endif
            } else {
                WelcomeView()
            }
        }
        .onAppear { app.launch() }
        .onOpenURL { url in app.memoryPicked(.success(url)) }   // a .16c opened from Files / AirDrop / Finder
        .fileImporter(isPresented: $app.showImporter,
                      allowedContentTypes: app.importTask == .memory ? MemoryFile.readableContentTypes
                        : app.importTask == .notes ? [.voyagerDoc, .json]
                        : app.importTask == .fonts ? [.folder, .font] : [.data]) { result in
            switch app.importTask {
            case .fonts: app.docFontsPicked(result)
            case .memory: app.memoryPicked(result)
            case .notes: app.notesPicked(result)
            case .firmware: app.firmwarePicked(result)
            }
        }
        .fileExporter(isPresented: Binding(get: { app.exportDocument != nil }, set: { if !$0 { app.exporterClosed() } }),
                      document: app.exportDocument, contentType: app.exportType,
                      defaultFilename: app.exportFilename) { result in
            app.exportFinished(result)
        }
        .confirmationDialog(app.pendingAction?.title ?? "", isPresented: Binding(
            get: { app.pendingAction != nil }, set: { if !$0 { app.pendingAction = nil } }),
            titleVisibility: .visible, presenting: app.pendingAction) { a in
            Button("Save Backup First…") { app.backupThenConfirm(a) }
            Button(a.confirmTitle, role: .destructive) { app.confirm(a) }
            Button("Cancel", role: .cancel) { app.pendingAction = nil }
        } message: { a in
            Text(a.message)
        }
        .alert("VoyagerCalc", isPresented: Binding(get: { app.errorMessage != nil }, set: { if !$0 { app.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(app.errorMessage ?? "")
        }
        .alert("Note", isPresented: Binding(get: { app.notice != nil }, set: { if !$0 { app.notice = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(app.notice ?? "")
        }
        .sheet(isPresented: $app.showAbout) { AboutView().environmentObject(app) }
        .sheet(isPresented: $app.showProgramInfo) { ProgramInfoView().environmentObject(app) }
        #if os(macOS)
        .alert(app.pendingWrite?.title ?? "", isPresented: Binding(
            get: { app.pendingWrite != nil }, set: { if !$0 { app.pendingWrite = nil } }),
            presenting: app.pendingWrite) { w in
            Button(w.matches ? "Write to Calculator" : "Write Anyway", role: .destructive) { app.confirmWrite(w) }
            Button("Cancel", role: .cancel) { app.pendingWrite = nil }
        } message: { w in
            Text(w.message)
        }
        .overlay(alignment: .bottom) {
            if let s = app.linkStatus {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(s)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 16)
            }
        }
        #endif
    }
}

/// The calculator, and the registers / program inspector when it is shown.
/// Mac and iPad: SwiftUI's inspector column on the right. iPhone: the inspector would be a
/// sheet over the keys, so it is a panel under the calculator (portrait) or beside it
/// (landscape) instead; the keys stay usable for SST / R/S while watching the listing.
struct CalculatorWithInspector: View {
    @EnvironmentObject var app: AppModel

    private var calculator: some View {
        ZStack(alignment: .topTrailing) {
            CalculatorView()
                .hardwareKeyboard(app.keyRouter)
                #if os(macOS)
                .aspectRatio(app.faceAspect, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                #endif
            CalculatorMenu()
                .padding(10)
        }
        .background(Color(rgb: 0x1C1714).ignoresSafeArea())
    }

    var body: some View {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            GeometryReader { geo in
                if !app.showInspector {
                    calculator
                } else if geo.size.height > geo.size.width {
                    VStack(spacing: 0) {
                        calculator.frame(height: geo.size.height * 0.58)
                        InspectorView(compact: true).frame(maxHeight: .infinity).background(.background)
                    }
                } else {
                    HStack(spacing: 0) {
                        calculator
                        InspectorView(compact: true).frame(width: min(340, geo.size.width * 0.4)).background(.background)
                    }
                }
            }
        } else {
            calculator.inspector(isPresented: $app.showInspector) {
                InspectorView().inspectorColumnWidth(min: 260, ideal: 320, max: 520)
            }
        }
        #else
        calculator.inspector(isPresented: $app.showInspector) {
            InspectorView().inspectorColumnWidth(min: 260, ideal: 320, max: 520)
        }
        #endif
    }
}

/// Small menu in the corner (all platforms; the only menu on iPhone / iPad).
struct CalculatorMenu: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        Menu {
            Toggle("Turbo", isOn: $app.turbo)
            Toggle("Registers & Program", isOn: $app.showInspector)
            Button("ON / OFF") { app.togglePower() }
            Menu("Model") { ModelMenuItems(app: app) }
            Menu("Keys") { KeysMenuItems(app: app) }
            Divider()
            Button("Open Memory File…") { app.openMemory() }
            Button("Save Memory File…") { app.saveMemory() }
            Menu("Program Documentation") {
                Button("Program Info…") { app.openProgramInfo() }
                Button("Open Program Notes…") { app.openNotes() }
                Button("Save Program Notes…") { app.saveNotes() }
                Button("Export PDF…") { app.exportPDF() }
                Button("Export Listing as Text…") { app.exportText() }
                Picker("Paper", selection: $app.paper) {
                    ForEach(PDFPaper.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Button("Use HP 15C Fonts…") { app.chooseDocFonts() }
            }
            Divider()
            Picker("Keyboard", selection: $app.skin) {
                ForEach(SkinChoice.allCases) { Text($0.title).tag($0) }
            }
            Picker("Face", selection: $app.faceStyle) {
                ForEach(FaceStyle.allCases) { Text($0.title).tag($0) }
            }
            Button("Choose Firmware…") { app.chooseFirmware() }
            Button("Reset Calculator…", role: .destructive) { app.resetCalculator() }
            Divider()
            Button("About VoyagerCalc") { app.showAbout = true }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Color(rgb: 0xB79A63))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(Text("Calculator menu"))
    }
}
