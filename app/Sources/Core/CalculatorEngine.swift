// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// CalculatorEngine.swift - runs a CalculatorMachine on its own thread, in real time
// always in real time: 10 ms of calculator time per 10 ms of wall time (0.7.1: Turbo removed).
// The UI sends commands and gets display snapshots on the main queue.

import Foundation

public struct EngineSnapshot: Equatable, Sendable {
    public var lcd: LCDState = .blank
    public var model: Int = 16
    public var variant: Int = 160
    public var simMs: Int = 0
    public init() {}
}

public final class CalculatorEngine: @unchecked Sendable {
    public enum Command {
        case press(Int)
        /// A gold / blue legend click: shift (unless pending), then the key held down.
        case pressShifted(shift: Int, code: Int)
        case release(Int)
        case releaseAll
        /// Release keys `afterMs` of calculator time from now (the end of a latched chord).
        case releaseLater([Int], afterMs: Int)
        /// The model chooser: switch to a calculator image and report the variant running after.
        case switchModel(Int, @MainActor (Result<Int, Error>) -> Void)
        /// A documented chord with ON (Keys menu).
        case chord(KeyChord)
        case chordWithON([Int])
        case loadMemory(Data, @MainActor (Error?) -> Void)
        case saveState(@MainActor (Result<SavedState, Error>) -> Void)
        /// Publish InspectorSnapshots (registers, program) while true, at most 10 times a second.
        case setInspector(Bool)
        /// Run a closure on the engine thread with the machine (for blocking saves etc.).
        case perform((CalculatorMachine) -> Void)
        case stop
    }

    /// Called on the main queue whenever the display or the active model changes.
    public var onSnapshot: (@MainActor (EngineSnapshot) -> Void)?
    /// Called on the main queue with the registers and program when they change (inspector on).
    public var onInspector: (@MainActor (InspectorSnapshot?) -> Void)?
    /// Called on the main queue if the emulated chip stops with an error.
    public var onFault: (@MainActor (String) -> Void)?

    private let machine: CalculatorMachine
    private let lock = NSLock()
    private var queue: [Command] = []
    private var thread: Thread?
    private var running = false
    private var last = EngineSnapshot()
    private var inspector = false
    private var lastInspection: InspectorSnapshot?
    private var nextInspection: UInt64 = 0
    /// Minimum time between two inspector snapshots (10 Hz).
    public static let inspectorInterval: UInt64 = 100_000_000
    private let wake = DispatchSemaphore(value: 0)

    /// Takes a machine that already has firmware and has booted.
    public init(machine: CalculatorMachine) {
        self.machine = machine
    }

    public func start() {
        guard thread == nil else { return }
        running = true
        let t = Thread { [weak self] in self?.loop() }
        t.name = "VoyagerCalc engine"
        t.qualityOfService = .userInteractive
        thread = t
        t.start()
    }

    public func send(_ c: Command) {
        lock.lock(); queue.append(c); lock.unlock()
        wake.signal()
    }

    public func stop() { send(.stop) }

    /// Run `body` on the engine thread and wait for it (at most `timeout` seconds).
    /// Do not call it from the engine thread. Returns nil on timeout or if not running.
    public func performAndWait<T>(timeout: Double = 3, _ body: @escaping (CalculatorMachine) -> T) -> T? {
        guard thread != nil, running else { return nil }
        let done = DispatchSemaphore(value: 0)
        var result: T?
        send(.perform { m in result = body(m); done.signal() })
        return done.wait(timeout: .now() + timeout) == .success ? result : nil
    }

    public var isRunning: Bool { running }

    private func takeCommands() -> [Command] {
        lock.lock(); defer { lock.unlock() }
        let q = queue; queue = []; return q
    }

    private func apply(_ c: Command) -> Bool {
        do {
            switch c {
            case .press(let k): machine.press(k)
            case .pressShifted(let sh, let k): try machine.pressShifted(sh, k)
            case .release(let k): machine.release(k)
            case .releaseAll: machine.releaseAll()
            case .releaseLater(let ks, let ms): machine.release(ks, afterMs: ms)
            case .switchModel(let v, let done):
                let r = Result { try machine.switchModel(to: v); return machine.variant }
                publish()                                   // the face follows the new model now
                lastInspection = nil; inspect(force: true)  // and the inspector decodes it
                onMain { done(r) }
            case .chord(let c): try machine.perform(c); publish()
            case .chordWithON(let keys): try machine.chordWithON(keys)
            case .loadMemory(let d, let done):
                do { try machine.putMemory(d); onMain { done(nil) } }
                catch { onMain { done(error) } }
            case .saveState(let done):
                let r = Result { try machine.savedState() }
                onMain { done(r) }
            case .setInspector(let on): inspector = on; lastInspection = nil; inspect(force: true)
            case .perform(let body): body(machine)
            case .stop: return false
            }
        } catch {
            report(error)
        }
        return true
    }

    /// Run on the main thread, on the main actor.
    private func onMain(_ body: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async { MainActor.assumeIsolated { body() } }
    }

    private func report(_ error: Error) {
        let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        onMain { [weak self] in self?.onFault?(msg) }
    }

    private func publish() {
        var s = EngineSnapshot()
        s.lcd = machine.calc.lcd()
        s.model = machine.model
        s.variant = machine.variant
        s.simMs = machine.simMs
        if s.lcd != last.lcd || s.model != last.model || s.variant != last.variant {
            last = s
            onMain { [weak self] in self?.onSnapshot?(s) }
        }
        inspect()
    }

    /// Read the registers and program (read-only, does not touch the calculator's timing),
    /// throttled to inspectorInterval.
    private func inspect(force: Bool = false) {
        guard inspector else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        guard force || now >= nextInspection else { return }
        nextInspection = now + Self.inspectorInterval
        let s = machine.calc.inspect()
        if s != lastInspection || force {
            lastInspection = s
            onMain { [weak self] in self?.onInspector?(s) }
        }
    }

    private func loop() {
        let tick: UInt64 = 10_000_000                      // 10 ms in ns
        var next = DispatchTime.now().uptimeNanoseconds
        var failed = false
        publish()
        while running {
            for c in takeCommands() where !apply(c) { running = false }
            if !running { break }
            if failed { _ = wake.wait(timeout: .now() + .milliseconds(200)); continue }
            do {
                let now = DispatchTime.now().uptimeNanoseconds
                if now < next {
                    // wait for the next 10 ms slot; a command wakes us early to apply it
                    _ = wake.wait(timeout: DispatchTime(uptimeNanoseconds: next))
                    continue
                }
                if now - next > 250_000_000 { next = now }   // fell behind (e.g. Mac asleep): no catch-up race
                try machine.run(ms: 10)
                next += tick
            } catch {
                failed = true
                report(error)
            }
            publish()
        }
        machine.releaseAll()
    }
}
