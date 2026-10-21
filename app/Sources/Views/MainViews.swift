// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// MainViews.swift - the window's content and the menus' views (moved out of VoyagerCalcApp.swift in 0.6.7
// so the tests, which cannot contain the @main entry, can build and render the real ContentView).

import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

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
        if app.isStock {
            Divider()
            Text("HP's original firmware has no model switch")
        }
    }
}

#if os(macOS)
/// Calculator menu, real calculator over USB HID (f + ENTER + ON on the calculator first).
struct CalculatorLinkMenuItems: View {
    @ObservedObject var app: AppModel

    var body: some View {
        Button("Read from Calculator") { app.readFromCalculator() }
            .disabled(!app.isRunning || app.linkBusy || !app.hasMemoryFiles)
        Button("Write to Calculator…") { app.writeToCalculator() }
            .disabled(!app.isRunning || app.linkBusy || !app.hasMemoryFiles)
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
        ForEach(KeyChord.allCases.filter { $0.isAvailable(model: app.snapshot.model, family: app.family) }) { c in
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
        if app.isStock {
            Text("HP's original firmware: only the chords tried on it are listed")
        } else {
            Text("f-ENTER-ON: no USB in the app, the calculator just turns on")
        }
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
        #if os(macOS)
        .background(WindowChromeSetter())        // one title bar colour across the window (0.6.7)
        #endif
        .onAppear { app.launch() }
        .onOpenURL { url in app.memoryPicked(.success(url)) }   // a .16c opened from Files / AirDrop / Finder
        .fileImporter(isPresented: $app.showImporter,
                      allowedContentTypes: app.importTask == .memory ? MemoryFile.readableContentTypes
                        : app.importTask == .notes ? [.voyagerDoc, .json]
                        : [.data]) { result in
            switch app.importTask {
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

    /// The panel is only shown when the firmware has something to show (not with HP's original 12C firmware).
    private var inspectorShown: Binding<Bool> {
        Binding(get: { app.inspectorVisible }, set: { app.showInspector = $0 })
    }

    var body: some View {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            GeometryReader { geo in
                if !app.inspectorVisible {
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
            calculator.inspector(isPresented: inspectorShown) {
                InspectorView().inspectorColumnWidth(min: 260, ideal: 320, max: 520)
            }
        }
        #else
        calculator
            .background(WindowFitter(showInspector: app.inspectorVisible, aspect: app.faceAspect, app: app))   // the window keeps the calculator's shape
            .inspector(isPresented: inspectorShown) {
                // exactly 320 pt wide (0.6.9): with a draggable divider the window could not keep the calculator's shape
                InspectorView().inspectorColumnWidth(WindowFit.inspectorWidth)
            }
            .transaction(value: app.inspectorVisible) { $0.animation = nil }      // one change, no second animation fighting the window
        #endif
    }
}

/// Small menu in the corner (all platforms; the only menu on iPhone / iPad).
struct CalculatorMenu: View {
    @EnvironmentObject var app: AppModel
    @AppStorage(KeyHelp.defaultsKey) private var showKeyHelp = false

    var body: some View {
        Menu {
            Toggle("Registers & Program", isOn: $app.showInspector).disabled(!app.hasInspector)
            #if os(macOS)
            Toggle("Show Key Help", isOn: $showKeyHelp)
            Toggle("Click f/g Labels", isOn: $app.legendClicks)
            Toggle("Key Click Sound", isOn: $app.keyClickSound)
            Button("ON / OFF") { app.powerMenuAction(fromKeyboard: AppModel.menuActionIsFromKeyboard) }.keyboardShortcut(.escape, modifiers: [])
            #else
            Toggle("Click f/g Labels", isOn: $app.legendClicks)
            Toggle("Key Click Sound", isOn: $app.keyClickSound)
            Button("ON / OFF") { app.togglePower() }
            #endif
            Menu("Model") { ModelMenuItems(app: app) }
            Menu("Keys") { KeysMenuItems(app: app) }
            Divider()
            Button("Open Memory File…") { app.openMemory() }.disabled(!app.hasMemoryFiles)
            Button("Save Memory File…") { app.saveMemory() }.disabled(!app.hasMemoryFiles)
            if app.isStock { Text("HP's original 12C firmware: no memory files") }
            Menu("Program Documentation") {
                Button("Program Info…") { app.openProgramInfo() }
                Button("Open Program Notes…") { app.openNotes() }
                Button("Save Program Notes…") { app.saveNotes() }
                Button("Export PDF…") { app.exportPDF() }
                Button("Export Listing as Text…") { app.exportText() }
                Picker("Paper", selection: $app.paper) {
                    ForEach(PDFPaper.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            .disabled(!app.hasInspector)
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
