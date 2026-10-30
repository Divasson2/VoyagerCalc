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
        #if os(macOS)
        // HP-15C Matrix Editor (0.7.1): its own window; keys typed there never reach the calculator (HardwareKeyboard)
        Window("HP-15C Matrix Editor", id: MatrixEditorView.windowID) {
            MatrixEditorView(editor: app.matrixEditor).environmentObject(app)
        }
        .defaultSize(width: 640, height: 540)
        // 0.7.4: View ▸ Show Calculator Back (⌘B), a separate resizable window that follows the model
        Window("Calculator Back", id: CalculatorBackView.windowID) {
            CalculatorBackView().environmentObject(app)
        }
        .defaultSize(width: 900, height: 560)
        #endif
    }
}

@MainActor
struct CalculatorCommands: Commands {
    @ObservedObject var app: AppModel
    @AppStorage(KeyHelp.defaultsKey) private var showKeyHelp = false
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some Commands {
        #if os(macOS)
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Paste Matrix…") { if app.prepareMatrixEditor(paste: true) { openWindow(id: MatrixEditorView.windowID) } }
                .keyboardShortcut("v", modifiers: [.command, .shift])
                .disabled(!app.isMatrixEditorAvailable)
        }
        #endif
        CommandGroup(replacing: .appInfo) {
            Button("About VoyagerCalc") { app.showAbout = true }
        }
        CommandGroup(replacing: .newItem) {
            Button("Open Memory File…") { app.openMemory() }
                .keyboardShortcut("o")
                .disabled(!app.isRunning || !app.hasMemoryFiles)
            Button("Save Memory File…") { app.saveMemory() }
                .keyboardShortcut("s")
                .disabled(!app.isRunning || !app.hasMemoryFiles)
            Divider()
            Button("Program Info…") { app.openProgramInfo() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(!app.isRunning || !app.hasInspector)
            Button("Open Program Notes…") { app.openNotes() }.disabled(!app.isRunning || !app.hasInspector)
            Button("Save Program Notes…") { app.saveNotes() }.disabled(!app.isRunning || !app.hasInspector)
            Button("Export Program Documentation (PDF)…") { app.exportPDF() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(!app.isRunning || !app.hasInspector)
            Button("Export Listing as Text…") { app.exportText() }.disabled(!app.isRunning || !app.hasInspector)
            #if os(macOS)
            // 0.7.2: HP-15C Simulator program files (Torsten Manz's .15c text format), HP-15C only
            Button("Import Program (.15c)…") { app.importManzProgram() }.disabled(!app.canUseManzFiles)
                .help("HP-15C only")
            Button("Export Program (.15c)…") { app.exportManzProgram() }.disabled(!app.canUseManzFiles)
                .help("HP-15C only")
            #endif
            Picker("PDF Paper Size", selection: $app.paper) {
                ForEach(PDFPaper.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Button("Clear Program Notes") { app.clearNotes() }.disabled(!app.isRunning || !app.hasInspector)
            Divider()
            if app.isStock {
                Text("HP's original 12C firmware: memory files and program notes are not available")
                Divider()
            }
            Button("Choose Firmware…") { app.chooseFirmware() }
        }
        CommandGroup(before: .toolbar) {
            Button(app.showInspector ? "Hide Registers & Program" : "Show Registers & Program") { app.showInspector.toggle() }
                .keyboardShortcut("i")
                .disabled(!app.isRunning || !app.hasInspector)
            #if os(macOS)
            Button("Show Calculator Back") { openWindow(id: CalculatorBackView.windowID) }
                .keyboardShortcut("b")
                .disabled(!app.canShowCalculatorBack)
                .help("HP-15C and HP-16C only")
            #endif
            Toggle("Show Key Help", isOn: $showKeyHelp)      // tooltip + shortcut bubble on hover; off by default
            Divider()
            Toggle("Click f/g Labels", isOn: $app.legendClicks)    // 0.7.1, on by default (as the Qt app)
            Toggle("Key Click Sound", isOn: $app.keyClickSound)    // 0.7.1, off by default
            Divider()
        }
        CommandMenu("Calculator") {
            Button("ON / OFF") { app.powerMenuAction(fromKeyboard: AppModel.menuActionIsFromKeyboard) }
                .keyboardShortcut(.escape, modifiers: [])      // shown at the right like ⌘C; the key itself is handled by the key router (see powerMenuAction)
                .disabled(!app.isRunning)
            Divider()
            Picker("Keyboard", selection: $app.skin) {
                ForEach(SkinChoice.allCases) { Text($0.title).tag($0) }
            }
            Picker("Face", selection: $app.faceStyle) {
                ForEach(FaceStyle.allCases) { Text($0.title).tag($0) }
            }
            #if os(macOS)
            Divider()
            Button("Matrix Editor…") { if app.prepareMatrixEditor() { openWindow(id: MatrixEditorView.windowID) } }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(!app.isMatrixEditorAvailable)
            #endif
            Divider()
            Button("Reset Calculator (clears memory)") { app.resetCalculator() }.disabled(!app.isRunning)
            if app.isStock {
                Text("HP's original 12C firmware: keys and display only (see About)")
            }
            #if os(macOS)
            Divider()
            Section("Real Calculator (USB)") { CalculatorLinkMenuItems(app: app) }
            #endif
        }
        CommandMenu("Model") { ModelMenuItems(app: app) }
        CommandMenu("Keys") { KeysMenuItems(app: app) }
    }
}
