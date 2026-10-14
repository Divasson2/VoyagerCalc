// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// AppModel.swift - app state shared by the views and menus: firmware, the running
// calculator, turbo, keyboard skin, face style (photo / drawn), memory files.

import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum SkinChoice: String, CaseIterable, Identifiable {
    case automatic, hp16c, hp15c, hp12c
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: return "Automatic (from firmware)"
        case .hp16c: return "16C"
        case .hp15c: return "15C"
        case .hp12c: return "12C"
        }
    }
    var model: CalculatorModel? {
        switch self {
        case .automatic: return nil
        case .hp16c: return .hp16c
        case .hp15c: return .hp15c
        case .hp12c: return .hp12c
        }
    }
}

/// How the calculator is drawn. Photo: the product photo with the live display drawn on
/// its empty LCD glass (landscape; iPhone portrait falls back to the stacked drawn face,
/// see CalculatorView). Drawn: our own vector drawing, every layout.
enum FaceStyle: String, CaseIterable, Identifiable {
    case photo, drawn
    var id: String { rawValue }
    var title: String { self == .photo ? "Photo" : "Drawn" }
}

enum FileTask { case firmware, memory, notes, fonts }

/// What the save panel is saving.
enum ExportKind { case memory, notes, pdf, text }

/// Something that clears the calculator's memory, waiting for the user's confirmation.
enum PendingAction: Equatable, Identifiable {
    case switchModel(Int)
    case memoryReset
    /// Load a checked 2 KB image (from a file or the real calculator) over the emulator's memory.
    case loadMemory(Data, source: String)
    /// The trial load did not look right; the user may still load it ("Load Anyway").
    case loadMemoryAnyway(Data, source: String, reason: String)
    /// The memory needs another image of this firmware (15.2 double memory): switch, then load.
    case switchThenLoad(Data, source: String, variant: Int, reason: String)
    var id: String {
        switch self {
        case .switchModel(let v): return "switch\(v)"
        case .memoryReset: return "reset"
        case .loadMemory(_, let src): return "load " + src
        case .loadMemoryAnyway(_, let src, _): return "load anyway " + src
        case .switchThenLoad(_, let src, let v, _): return "switch \(v) load " + src
        }
    }
    var title: String {
        switch self {
        case .switchModel(let v): return "Switch to the \(CalculatorMachine.variantName(v))?"
        case .memoryReset: return "Reset the calculator's memory?"
        case .loadMemory(_, let src): return "Load the memory from \(src)?"
        case .loadMemoryAnyway(_, let src, _): return "The memory from \(src) may not fit"
        case .switchThenLoad(_, let src, let v, _): return "The memory from \(src) is for the HP-\(CalculatorMachine.variantName(v))"
        }
    }
    var message: String {
        switch self {
        case .switchModel: return "Switching model clears the calculator's memory (programs, registers and settings), as on the calculator. You can save a backup first."
        case .memoryReset: return "ON + − clears all programs, registers and settings (Pr Error). You can save a backup first."
        case .loadMemory(_, let src): return "This replaces the emulator's memory (programs, registers and settings) with the one from \(src). You can save a backup of the emulator's memory first."
        case .loadMemoryAnyway(_, _, let reason): return reason + " You can load it anyway; save a backup of the emulator's memory first if you want to keep it."
        case .switchThenLoad(_, _, _, let reason): return reason
        }
    }
    var confirmTitle: String {
        switch self {
        case .memoryReset: return "Reset Memory"
        case .switchModel: return "Switch Model"
        case .loadMemory: return "Load Memory"
        case .loadMemoryAnyway: return "Load Anyway"
        case .switchThenLoad(_, _, let v, _): return "Switch to \(CalculatorMachine.variantName(v)) and Load"
        }
    }
}

#if os(macOS)
/// "Write to Calculator", after the calculator's own memory was read and backed up.
struct PendingWrite: Identifiable {
    let id = UUID()
    let memory: Data              // the emulator's memory, to be written
    let emulatorModel: String     // "HP-16C"
    let calculatorModels: [Int]   // variants the calculator's memory fits (empty: unknown)
    let backup: URL
    /// The emulator's memory only fits the 15C (15.2) mode (g MEM Error 10 on 15.0).
    var needs152 = false
    var calculatorModel: String? {
        calculatorModels.first.map { "HP-" + (CalculatorMachine.variantName($0).components(separatedBy: " (").first ?? "") }
    }
    var matches: Bool { calculatorModel == emulatorModel }
    var title: String { "Write to the \(calculatorModel ?? "calculator")?" }
    var message: String {
        var m: String
        if let c = calculatorModel {
            m = matches ? "The connected \(c) gets the emulator's \(emulatorModel) memory (programs, registers and settings)."
                : "The connected calculator holds an \(c) memory, but the emulator runs an \(emulatorModel). The calculator will most likely show Pr Error and clear its memory."
        } else {
            m = "The connected calculator's memory does not look like a memory this firmware knows. It gets the emulator's \(emulatorModel) memory."
        }
        if needs152 {
            m += " This memory uses the HP-15C (15.2) double memory: set the calculator to 15C (15.2) mode first (turn it off, hold g and ENTER, press ON, 4, then the key under 15.2), or it will show Error 10."
        }
        return m + " Its current memory was saved to “\(backup.lastPathComponent)” in \(backup.deletingLastPathComponent().path)."
    }
}
#endif

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot = EngineSnapshot()
    @Published private(set) var isRunning = false
    @Published private(set) var isStarting = false
    @Published private(set) var firmwareName: String?
    @Published private(set) var firmwareInfo = ""
    @Published private(set) var family: CalculatorFamily = .none
    @Published private(set) var pressedKeys: Set<Int> = []
    /// Keys latched down by ⌘-click / right-click (Mac) or a long press (iOS).
    @Published private(set) var latchedKeys: Set<Int> = []
    /// Calculator images in the firmware (120 / 150 / 152 / 160): the Model menu.
    @Published private(set) var images: [Int] = []
    @Published private(set) var isSwitchingModel = false
    /// Waiting for "Switching model clears the calculator's memory" to be confirmed.
    @Published var pendingAction: PendingAction?
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published var importTask: FileTask = .firmware
    /// The user's HP 15C fonts for the documentation PDF (0.5.7); never bundled.
    let docFontStore = DocFontStore()
    @Published var docFonts = DocFonts()
    @Published var showImporter = false
    @Published var exportDocument: MemoryFile?
    /// The save panel's file type and what it is for (memory file, notes, PDF, text).
    @Published var exportType: UTType = .voyager16c
    var exportKind: ExportKind = .memory

    // MARK: program documentation (0.5.6)
    /// The notes for the program in the calculator (sidecar .voyagerdoc), kept between launches.
    @Published var programDoc = ProgramDocument() {
        didSet { if programDoc != oldValue { storeProgramDoc() } }
    }
    /// Where the notes were last opened from / saved to.
    @Published var programDocURL: URL?
    @Published var showProgramInfo = false
    /// The program as of opening Program Info (for its label / register / flag tables).
    @Published var docLines: [ProgramLine] = []
    /// The step whose comment is being edited (double-click in the listing).
    @Published var editingCommentStep: Int?
    @Published var paper: PDFPaper = PDFPaper(rawValue: UserDefaults.standard.string(forKey: "pdfPaper") ?? "") ?? .a4 {
        didSet { UserDefaults.standard.set(paper.rawValue, forKey: "pdfPaper") }
    }
    /// The memory file last opened ("FinancePac.15c"): the document's title and file names.
    @Published var memoryFileName: String?
    /// Notes found next to a memory file being opened, used once it is loaded.
    var pendingSidecar: (doc: ProgramDocument, url: URL)?
    var lastProgramKeys: [String] = []
    var memoryFileNameCandidate: String?
    func exportNameOverrideForDocs(_ name: String) { exportNameOverride = name }
    @Published var showAbout = false
    #if os(macOS)
    /// What the USB link is doing ("Reading the calculator…"), nil when idle.
    @Published private(set) var linkStatus: String?
    @Published var pendingWrite: PendingWrite?
    private let linkQueue = DispatchQueue(label: "VoyagerCalc.usb", qos: .userInitiated)
    private var linkTicket = 0
    #endif
    /// File name offered by the save panel (the calculator's backup has its own).
    private var exportNameOverride: String?
    /// Registers and program panel (inspector). The engine only reads them while it is shown.
    @Published var showInspector = UserDefaults.standard.bool(forKey: "showInspector") {
        didSet { UserDefaults.standard.set(showInspector, forKey: "showInspector"); engine?.send(.setInspector(showInspector)) }
    }
    @Published var inspection: InspectorSnapshot?

    @Published var turbo = false {
        didSet { engine?.send(.setTurbo(turbo)) }
    }
    @Published var skin: SkinChoice = SkinChoice(rawValue: UserDefaults.standard.string(forKey: "skin") ?? "") ?? .automatic {
        didSet { UserDefaults.standard.set(skin.rawValue, forKey: "skin") }
    }

    @Published var faceStyle: FaceStyle = FaceStyle(rawValue: UserDefaults.standard.string(forKey: "faceStyle") ?? "") ?? .photo {
        didSet { UserDefaults.standard.set(faceStyle.rawValue, forKey: "faceStyle") }
    }

    let keyRouter = HardwareKeyRouter()
    private let firmwareStore = FirmwareStore()
    private let stateStore = StateStore()
    /// Keep the calculator memory between launches (off in tests).
    var persistState = true
    private(set) var engine: CalculatorEngine?
    private var latch = KeyLatch()
    private(set) var firmwareID = ""
    /// Run after the backup offered by the confirmation was saved.
    private var afterExport: PendingAction?

    init() {
        keyRouter.model = { [unowned self] in self.model }
        keyRouter.press = { [unowned self] in self.press($0) }
        keyRouter.pressShifted = { [unowned self] in self.press($1, part: $0 == CalculatorMachine.keyF ? .fLabel : .gLabel) }
        keyRouter.release = { [unowned self] in self.release($0) }
    }

    /// The face shown: follows the running ROM unless the user picked one.
    var model: CalculatorModel { skin.model ?? CalculatorModel.with(id: snapshot.model) }

    /// Width / height of the face being shown in landscape (Mac window aspect).
    var faceAspect: CGFloat {
        if faceStyle == .photo, let face = model.photoFace { return face.aspect }
        return 1.62
    }

    var familyDescription: String {
        switch family {
        case .multi: return "multi firmware (12C / 15C / 16C)"
        case .hp15c: return "15C firmware"
        case .hp16c: return "16C firmware"
        case .hp12c: return "12C firmware"
        case .none: return "no firmware"
        }
    }

    var exportFilename: String { exportNameOverride ?? "Calculator memory" }
    private var firmwareData = Data()

    // MARK: launch / firmware

    func launch() {
        guard engine == nil, !isStarting else { return }
        reloadDocFonts()
        if let fw = firmwareStore.load() { start(fw, restoring: stateStore.load(firmwareID: SHA256Hex.of(fw.data))) }
    }

    func chooseFirmware() { importTask = .firmware; showImporter = true }

    func firmwarePicked(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let e): errorMessage = e.localizedDescription
        case .success(let url):
            do {
                let fw = try firmwareStore.read(url)
                let probe = VoyagerCalculator()
                try probe.loadFirmware(fw.data)          // check before remembering
                try firmwareStore.remember(url, firmware: fw)
                saveStateNow()
                start(fw, restoring: stateStore.load(firmwareID: SHA256Hex.of(fw.data)))
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func start(_ fw: StoredFirmware, restoring saved: SavedState?) {
        stopEngine()
        isStarting = true
        let turboNow = turbo
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let machine = CalculatorMachine()
            let outcome: Result<String?, Error> = Result {
                try machine.loadFirmware(fw.data)
                return try machine.boot(restoring: saved)
            }
            DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated {
                guard let self else { return }
                self.isStarting = false
                switch outcome {
                case .failure(let e):
                    self.errorMessage = (e as? LocalizedError)?.errorDescription ?? e.localizedDescription
                case .success(let note):
                    self.notice = note
                    self.attach(machine, firmwareName: fw.name, turbo: turboNow)
                }
            } }
        }
    }

    /// Run a booted machine: engine thread, snapshots, inspector. (Also used by the tests.)
    func attach(_ machine: CalculatorMachine, firmwareName: String, turbo turboNow: Bool = false) {
        stopEngine()
        self.firmwareName = firmwareName
        firmwareInfo = machine.calc.firmwareInfo
        family = machine.family
        images = machine.images
        firmwareID = machine.firmwareID
        firmwareData = machine.firmwareData
        loadStoredProgramDoc()
        let e = CalculatorEngine(machine: machine)
        e.onSnapshot = { [weak self] s in self?.snapshot = s }
        e.onFault = { [weak self] msg in self?.errorMessage = msg }
        e.onInspector = { [weak self] s in self?.inspection = s; self?.programChanged(s) }
        e.send(.setInspector(showInspector))
        e.send(.setTurbo(turboNow))
        engine = e
        e.start()
        isRunning = true
    }

    func stopEngine() {
        engine?.stop()
        engine = nil
        isRunning = false
        pressedKeys = []
        latchedKeys = []; latch = KeyLatch()
        inspection = nil
    }

    /// Turn the calculator off and keep its memory for the next launch (blocking, short).
    func saveStateNow(turnBackOn: Bool = false) {
        guard let e = engine else { return }
        if let r = e.performAndWait(timeout: 3, { m in try? m.savedState(turnBackOn: turnBackOn) }), let s = r {
            if persistState { stateStore.save(s) }
        }
    }

    func resumeAfterBackground() {
        engine?.send(.perform { m in try? m.powerOn() })
    }

    // MARK: keys

    func press(_ code: Int) {
        guard engine != nil else { return }
        apply(latch.press(code))
    }

    func release(_ code: Int) {
        apply(latch.release(code))
    }

    /// A press on one part of a key: its gold legend = f then the key, its blue legend = g then
    /// the key, the cap = the key. Latched keys (a latched f or g too) are let go first; a
    /// pending shift is replaced, never doubled (CalculatorMachine.pressShifted).
    func press(_ code: Int, part: KeyPart) {
        guard engine != nil else { return }
        guard let k = model.key(code: code), let shift = k.shift(for: part) else { return press(code) }
        apply(latch.unlatchAll())
        pressedKeys.insert(shown(code))
        engine?.send(.pressShifted(shift: shift, code: code))
    }

    /// ⌘-click / right-click: latch the key down (highlighted), or let all latched keys go.
    func toggleLatch(_ code: Int) {
        guard engine != nil else { return }
        apply(latch.toggle(code))
    }

    /// iOS long press: the key the finger holds stays down when it lifts.
    func holdBecameLatch(_ code: Int) {
        apply(latch.holdBecameLatch(code))
    }

    func releaseLatchedKeys() { apply(latch.unlatchAll()) }

    private func shown(_ code: Int) -> Int { code == 35 ? 25 : code }

    private func apply(_ actions: [KeyLatch.Action]) {
        for a in actions {
            switch a {
            case .press(let k): pressedKeys.insert(shown(k)); engine?.send(.press(k))
            case .release(let k): pressedKeys.remove(shown(k)); engine?.send(.release(k))
            case .releaseLater(let ks):
                ks.forEach { pressedKeys.remove(shown($0)) }
                engine?.send(.releaseLater(ks, afterMs: KeyLatch.releaseDelayMs))
            }
        }
        latchedKeys = Set(latch.latched.map(shown))
    }

    func togglePower() {
        press(CalculatorMachine.keyON); release(CalculatorMachine.keyON)
    }

    /// g-ENTER-ON: the calculator's service menu (checksum, speed, model switch).
    func serviceMenu() { perform(.serviceMenu) }

    /// A Keys menu chord. ON + − asks first (it clears the memory).
    func perform(_ chord: KeyChord) {
        guard engine != nil else { return }
        if chord.needsConfirmation { pendingAction = .memoryReset; return }
        releaseLatchedKeys()
        engine?.send(.chord(chord))
    }

    // MARK: model chooser

    /// Variant running now (120 / 150 / 152 / 160).
    var runningVariant: Int { snapshot.variant }
    var canSwitchModel: Bool { images.count > 1 && isRunning && !isSwitchingModel }

    /// Model menu: ask first, because switching clears the memory.
    func chooseModel(_ v: Int) {
        guard canSwitchModel, images.contains(v) else { return }
        pendingAction = .switchModel(v)
    }

    /// The confirmation's "Save Backup First…": save a memory file, then go on.
    func backupThenConfirm(_ a: PendingAction) {
        pendingAction = nil
        afterExport = a
        saveMemory()
    }

    func confirm(_ a: PendingAction) {
        pendingAction = nil
        switch a {
        case .memoryReset:
            releaseLatchedKeys()
            engine?.send(.chord(.memoryReset))
        case .switchModel(let v):
            switchModel(to: v)
        case .loadMemory(let data, _), .loadMemoryAnyway(let data, _, _):
            engine?.send(.loadMemory(data) { [weak self] err in
                if let err { self?.errorMessage = (err as? LocalizedError)?.errorDescription ?? "\(err)" }
                else { self?.memoryLoaded() }
            })
        case .switchThenLoad(let data, _, let v, _):
            switchModel(to: v) { [weak self] in self?.confirm(.loadMemory(data, source: "")) }
        }
    }

    /// Run the calculator's own switch (off, g-ENTER-ON, 4, key under the label) and check it.
    /// The face, keys and inspector follow the new model as soon as the engine sees it.
    func switchModel(to v: Int, then next: (@MainActor () -> Void)? = nil) {
        guard let e = engine else { return }
        releaseLatchedKeys()
        isSwitchingModel = true
        if skin != .automatic { skin = .automatic }      // show the chosen model's own face
        e.send(.switchModel(v) { [weak self] r in
            guard let self else { return }
            self.isSwitchingModel = false
            switch r {
            case .success:
                if self.persistState { self.saveStateNow(turnBackOn: true) }   // remembered for this firmware
                next?()
            case .failure(let err):
                self.errorMessage = (err as? LocalizedError)?.errorDescription ?? "\(err)"
            }
        })
    }

    // MARK: memory files

    func openMemory() { importTask = .memory; showImporter = true }

    func memoryPicked(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let e): errorMessage = e.localizedDescription
        case .success(let url):
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                guard data.count == VoyagerCalculator.memorySize else {
                    errorMessage = "“\(url.lastPathComponent)” is not a calculator memory file (it must be exactly 2048 bytes)."
                    return
                }
                let ext = url.pathExtension.lowercased()
                findSidecar(for: url)
                let note = ["12c", "15c", "16c"].contains(ext) && ext != model.fileExtension
                    ? "“\(url.lastPathComponent)” was saved from a \(ext.uppercased()); the calculator now runs as a \(model.name)." : nil
                offerMemory(data, source: "“\(url.lastPathComponent)”", note: note)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// The firmware-layout check, then the confirmation with "Save Backup First…": a 2 KB image
    /// is tried in a scratch calculator on the same firmware and model first (the firmware
    /// checks it at ON and shows Pr Error when it is another model's memory or not valid).
    func offerMemory(_ data: Data, source: String, note: String? = nil) {
        let fw = firmwareData, v = runningVariant, imgs = images, name = "HP-" + model.name
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let verdict = CalculatorMachine.checkMemory(data, firmware: fw, variant: v)
            let fitsOther = verdict.fits ? [] : CalculatorMachine.identifyMemory(data, firmware: fw, among: imgs.filter { $0 != v })
            DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated {
                guard let self else { return }
                switch verdict {
                case .fits:
                    _ = note        // the check passed, so a file-name hint is moot (and two alerts would clash)
                    self.pendingAction = .loadMemory(data, source: source)
                case .needsMoreMemory:
                    let m = "It uses more registers than the \(name) mode this firmware is running has (g MEM gives Error 10, and DIM (i) cannot fix it). It is a memory from the HP-15C (15.2) double-memory mode."
                    if let o = fitsOther.first {
                        self.pendingAction = .switchThenLoad(data, source: source, variant: o, reason: m + " Switch the model first (this clears the emulator's memory), then load it.")
                    } else {
                        self.pendingAction = .loadMemoryAnyway(data, source: source, reason: m)
                    }
                case .wrongSize(let n):
                    self.errorMessage = "The memory from \(source) is \(n) bytes; a calculator memory is 2048 bytes. Nothing was loaded."
                case .rejected, .unreadable, .changed:
                    var m = "In a trial load on this firmware's \(name)"
                    switch verdict {
                    case .rejected: m += ", the calculator showed Pr Error with it (its memory would be cleared)."
                    case .changed(let n): m += ", the calculator started but changed \(n) bytes of the registers / program area (it may have cleared them)."
                    default: m += ", the calculator did not show anything after ON."
                    }
                    if let o = fitsOther.first { m += " It fits the HP-\(CalculatorMachine.variantName(o)): choose that in the Model menu, then try again." }
                    else { m += " It may be from another model or firmware." }
                    self.pendingAction = .loadMemoryAnyway(data, source: source, reason: m)
                }
            } }
        }
    }

    func saveMemory() {
        exportNameOverride = memoryFileName.map { ($0 as NSString).deletingPathExtension }
        exportKind = .memory; exportType = .memoryType(for: model)
        engine?.send(.saveState { [weak self] r in
            switch r {
            case .success(let s): self?.exportDocument = MemoryFile(data: s.memory)
            case .failure(let e): self?.errorMessage = (e as? LocalizedError)?.errorDescription ?? "\(e)"
            }
        })
    }

    func exportFinished(_ result: Result<URL, Error>) {
        exportDocument = nil
        exportNameOverride = nil
        let kind = exportKind; exportKind = .memory
        if kind != .memory {
            if case .failure(let e) = result { errorMessage = e.localizedDescription }
            if kind == .notes, case .success(let url) = result { programDocURL = url }
            return
        }
        let next = afterExport; afterExport = nil
        switch result {
        case .failure(let e): errorMessage = e.localizedDescription      // no backup: do not go on
        case .success: if let next { confirm(next) }
        }
    }

    /// The save panel closed. Without a completion (cancelled) the pending switch / reset is
    /// dropped: the user did not get the backup they asked for.
    func exporterClosed() {
        exportDocument = nil
        exportNameOverride = nil
        guard afterExport != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            MainActor.assumeIsolated { self?.afterExport = nil }
        }
    }

    #if os(macOS)
    // MARK: real calculator over USB (plan milestone M2)

    var linkBusy: Bool { linkStatus != nil }

    /// Run blocking USB work on the link queue, with a watchdog: the window never waits on it.
    private func usb<T>(_ status: String, timeout: TimeInterval = 25, _ work: @escaping (CalculatorLink) throws -> T,
                        done: @escaping @MainActor (Result<T, Error>) -> Void) {
        linkTicket += 1
        let ticket = linkTicket
        linkStatus = status
        USBLog.write("==== \(status) (VoyagerCalc \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "?"))")
        linkQueue.async {
            let r = Result { try work(CalculatorLink(transport: USBHIDTransport())) }
            switch r {
            case .success: USBLog.write("==== done")
            case .failure(let e): USBLog.write("==== failed: \((e as? LocalizedError)?.errorDescription ?? "\(e)")")
            }
            DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated {
                guard let self, self.linkTicket == ticket else { return }
                self.linkStatus = nil; done(r)
            } }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in MainActor.assumeIsolated {
            guard let self, self.linkTicket == ticket, self.linkStatus != nil else { return }
            self.linkTicket += 1; self.linkStatus = nil
            USBLog.write("==== watchdog: no answer from the USB queue after \(Int(timeout)) s")
            done(.failure(LinkError.timeout(received: 0)))
        } }
    }

    private func linkFailed(_ e: Error) {
        errorMessage = (e as? LocalizedError)?.errorDescription ?? "\(e)"
    }

    /// Calculator ▸ Read from Calculator: the 2 KB memory over USB, checked, then loaded after
    /// the same confirmation as opening a memory file.
    func readFromCalculator() {
        guard isRunning, !linkBusy else { return }
        usb("Reading the calculator's memory…", { try $0.readMemory() }) { [weak self] r in
            switch r {
            case .success(let d): self?.offerMemory(d, source: "the calculator")
            case .failure(let e): self?.linkFailed(e)
            }
        }
    }

    /// Calculator ▸ Save Calculator Memory to File…: read only.
    func saveCalculatorMemoryToFile() {
        guard !linkBusy else { return }
        usb("Reading the calculator's memory…", { try $0.readMemory() }) { [weak self] r in
            switch r {
            case .success(let d):
                self?.exportNameOverride = "Calculator memory " + Self.stamp()
                if let self { self.exportKind = .memory; self.exportType = .memoryType(for: self.model) }
                self?.exportDocument = MemoryFile(data: d)
            case .failure(let e): self?.linkFailed(e)
            }
        }
    }

    /// Calculator ▸ Write to Calculator…: read and back up the calculator's memory, then ask.
    func writeToCalculator() {
        guard isRunning, !linkBusy, let e = engine else { return }
        let fw = firmwareData, imgs = images.isEmpty ? [runningVariant] : images
        let emu = "HP-" + model.name
        linkStatus = "Reading the emulator's memory…"
        e.send(.saveState { [weak self] r in
            guard let self else { return }
            self.linkStatus = nil
            guard case .success(let s) = r else {
                if case .failure(let err) = r { self.linkFailed(err) }
                return
            }
            self.usb("Backing up the calculator's memory…", { link -> (URL, [Int], Bool) in
                let old = try link.readMemory()
                let fits = CalculatorMachine.identifyMemory(old, firmware: fw, among: imgs)
                let big = CalculatorMachine.needs152(s.memory, firmware: fw, among: imgs)
                return (try Self.saveBackup(old, variant: fits.first), fits, big)
            }) { [weak self] r in
                switch r {
                case .success(let (url, fits, big)):
                    self?.pendingWrite = PendingWrite(memory: s.memory, emulatorModel: emu, calculatorModels: fits, backup: url, needs152: big)
                case .failure(let e): self?.linkFailed(e)
                }
            }
        })
    }

    func confirmWrite(_ w: PendingWrite) {
        pendingWrite = nil
        usb("Writing to the calculator…", { link -> Data in
            let back = try link.writeMemory(w.memory, flag8: w.emulatorModel == "HP-15C" ? CalculatorLink.flag8(w.memory) : nil)
            Thread.sleep(forTimeInterval: 5)        // as VoyagerInterface: let the calculator settle (off the main thread)
            return back
        }) { [weak self] r in
            switch r {
            case .success:
                self?.notice = "Done: the \(w.emulatorModel) memory was written to the calculator, read back and compared: the registers and program memory match (the calculator kept its own USB-session state). Press ON on the calculator to leave USB mode, then ON again to use it."
            case .failure(let e):
                self?.errorMessage = ((e as? LocalizedError)?.errorDescription ?? "\(e)")
                    + " The calculator's previous memory is in “\(w.backup.lastPathComponent)”."
            }
        }
    }

    static func stamp(_ d: Date = Date()) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return f.string(from: d)
    }

    /// ~/Documents/VoyagerCalc Backups/<model> calculator <date>.<ext>. The real home folder
    /// (not the sandbox container); allowed by the home-relative-path entitlement. If that
    /// fails, the app's own Documents folder.
    nonisolated static func saveBackup(_ data: Data, variant: Int?) throws -> URL {
        let ext = variant.map { $0 == 120 ? "12c" : $0 == 160 ? "16c" : "15c" } ?? "bin"
        let name = (variant.map { "HP-" + (CalculatorMachine.variantName($0).components(separatedBy: " (").first ?? "") } ?? "Unknown") + " calculator "
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let file = name + f.string(from: Date()) + "." + ext
        var homes: [URL] = []
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir { homes.append(URL(fileURLWithPath: String(cString: dir))) }
        homes.append(FileManager.default.homeDirectoryForCurrentUser)
        var lastError: Error?
        for home in homes {
            let dir = home.appendingPathComponent("Documents/VoyagerCalc Backups", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let url = dir.appendingPathComponent(file)
                try data.write(to: url, options: .withoutOverwriting)
                return url
            } catch { lastError = error }
        }
        throw lastError ?? CocoaError(.fileWriteUnknown)
    }
    #endif

    /// Clear the calculator: forget the saved memory and cold-start.
    func resetCalculator() {
        stopEngine()
        stateStore.clear(firmwareID: firmwareID)
        if let fw = firmwareStore.load() { start(fw, restoring: nil) }
    }
}
