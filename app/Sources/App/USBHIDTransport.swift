// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// USBHIDTransport.swift - the calculator's USB HID connection through IOKit (macOS only).
// Same calls, order and timing as VoyagerInterface's HIDManager.swift (which reads Jose's
// calculator fine):
//   IOHIDManagerCreate -> SetDeviceMatching(VID 0x03F0, PID 0x1341) -> IOHIDManagerOpen ->
//   IOHIDManagerScheduleWithRunLoop -> IOHIDManagerCopyDevices -> IOHIDDeviceOpen(None);
//   IOHIDDeviceSetReport(Output, report ID 0, 64 bytes, command in byte 0); 100 ms;
//   IOHIDDeviceGetReport(Input, report ID 0, 64 bytes) polled every 10 ms.
// VoyagerInterface schedules on the main run loop; here the manager is scheduled on the
// current (USB queue) thread's run loop, and that run loop is run while waiting, so an
// input-report callback is also delivered. Reports come from GetReport like VoyagerInterface;
// if GetReport never gives anything but the callback does, the callback's reports are used.
// Every IOReturn and every report's bytes go to the USB log (USBLog).

#if os(macOS)
import Foundation
import IOKit
import IOKit.hid

/// ~/Library/Logs/VoyagerCalc-usb.log (sandboxed: inside the app's container,
/// ~/Library/Containers/com.josegonzalezdivasson.VoyagerCalc/Data/Library/Logs/).
enum USBLog {
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "usbLog") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "usbLog") }
    }
    static var url: URL {
        let lib = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        return lib.appendingPathComponent("Logs/VoyagerCalc-usb.log")
    }
    private static let lock = NSLock()
    private static let stamp: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"; return f
    }()

    static func write(_ line: @autoclosure () -> String) {
        guard enabled else { return }
        let text = stamp.string(from: Date()) + "  " + line() + "\n"
        lock.lock(); defer { lock.unlock() }
        let u = url
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let h = try? FileHandle(forWritingTo: u) {
            h.seekToEndOfFile(); h.write(Data(text.utf8)); try? h.close()
        } else {
            try? Data(text.utf8).write(to: u)
        }
    }

    static func code(_ r: IOReturn) -> String {
        let u = UInt32(bitPattern: r)
        let name: String
        switch r {
        case kIOReturnSuccess: name = "success"
        case kIOReturnNotPermitted: name = "not permitted"
        case kIOReturnNotPrivileged: name = "not privileged"
        case kIOReturnExclusiveAccess: name = "exclusive access"
        case kIOReturnNotFound: name = "not found"
        case kIOReturnTimeout: name = "timeout"
        case kIOReturnUnsupported: name = "unsupported"
        case kIOReturnNotResponding: name = "not responding"
        case kIOReturnNoDevice: name = "no device"
        case kIOReturnBadArgument: name = "bad argument"
        case kIOReturnNotOpen: name = "not open"
        case kIOReturnAborted: name = "aborted"
        case kIOReturnOverrun: name = "overrun"
        case kIOReturnUnderrun: name = "underrun"
        case kIOReturnError: name = "general error"
        default: name = "?"
        }
        return String(format: "0x%08X (%@)", u, name)
    }

    /// Bytes as hex; trailing zeros shortened.
    static func hex(_ b: ArraySlice<UInt8>) -> String {
        var a = Array(b); var zeros = 0
        while let l = a.last, l == 0, a.count > 1 { a.removeLast(); zeros += 1 }
        return a.map { String(format: "%02X", $0) }.joined(separator: " ") + (zeros > 0 ? " +\(zeros)×00" : "")
    }
}

final class USBHIDTransport: CalculatorTransport {
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var runLoop: CFRunLoop?
    private var inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: CalculatorLink.reportSize)
    private var callbackReports: [[UInt8]] = []
    private var getReportWorked = false
    private var getReportFailures = 0, lastGetReportError: IOReturn = kIOReturnSuccess
    private var loggedEmpty = false

    func open() throws {
        close()
        USBLog.write("---- open (thread \(Thread.isMainThread ? "main" : "USB queue"), sandboxed: \(ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil))")
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching = [kIOHIDVendorIDKey as String: NSNumber(value: CalculatorLink.vendorID),
                        kIOHIDProductIDKey as String: NSNumber(value: CalculatorLink.productID)] as CFDictionary
        IOHIDManagerSetDeviceMatching(m, matching)
        let r = IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone))
        USBLog.write("IOHIDManagerOpen -> \(USBLog.code(r))")
        let rl = CFRunLoopGetCurrent()!
        IOHIDManagerScheduleWithRunLoop(m, rl, CFRunLoopMode.defaultMode.rawValue)
        runLoop = rl
        manager = m
        let set = IOHIDManagerCopyDevices(m) as? Set<IOHIDDevice> ?? []
        USBLog.write("IOHIDManagerCopyDevices -> \(set.count) device(s)")
        guard let d = set.first else {
            close()
            if r != kIOReturnSuccess && r != kIOReturnNotFound { throw LinkError.accessDenied(r) }
            throw LinkError.noDevice
        }
        func prop(_ k: String) -> String { IOHIDDeviceGetProperty(d, k as CFString).map { "\($0)" } ?? "-" }
        USBLog.write("device: \(prop(kIOHIDProductKey)) / \(prop(kIOHIDManufacturerKey)), usage page \(prop(kIOHIDPrimaryUsagePageKey)) usage \(prop(kIOHIDPrimaryUsageKey)), max input \(prop(kIOHIDMaxInputReportSizeKey)), max output \(prop(kIOHIDMaxOutputReportSizeKey)), max feature \(prop(kIOHIDMaxFeatureReportSizeKey)), transport \(prop(kIOHIDTransportKey))")
        let e = IOHIDDeviceOpen(d, IOOptionBits(kIOHIDOptionsTypeNone))
        USBLog.write("IOHIDDeviceOpen(None) -> \(USBLog.code(e))")
        guard e == kIOReturnSuccess else { close(); throw LinkError.accessDenied(e) }
        device = d
        callbackReports = []; getReportWorked = false; getReportFailures = 0; loggedEmpty = false
        let me = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(d, inputBuffer, CalculatorLink.reportSize, { ctx, result, _, _, _, report, length in
            guard let ctx else { return }
            let t = Unmanaged<USBHIDTransport>.fromOpaque(ctx).takeUnretainedValue()
            let bytes = Array(UnsafeBufferPointer(start: report, count: length))
            USBLog.write("input callback \(USBLog.code(result)) len \(length): \(USBLog.hex(bytes[...]))")
            t.callbackReports.append(bytes)
        }, me)
    }

    func close() {
        if let d = device {
            IOHIDDeviceRegisterInputReportCallback(d, inputBuffer, CalculatorLink.reportSize, nil, nil)
            USBLog.write("IOHIDDeviceClose -> \(USBLog.code(IOHIDDeviceClose(d, IOOptionBits(kIOHIDOptionsTypeNone))))")
        }
        if let m = manager {
            if let rl = runLoop { IOHIDManagerUnscheduleFromRunLoop(m, rl, CFRunLoopMode.defaultMode.rawValue) }
            IOHIDManagerClose(m, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        if getReportFailures > 0 {
            USBLog.write("GetReport failed \(getReportFailures) times, last \(USBLog.code(lastGetReportError))")
            getReportFailures = 0
        }
        device = nil; manager = nil; runLoop = nil
    }

    func send(_ report: [UInt8]) throws {
        guard let d = device else { throw LinkError.noDevice }
        let e = report.withUnsafeBufferPointer { p in
            IOHIDDeviceSetReport(d, kIOHIDReportTypeOutput, 0, p.baseAddress!, p.count)
        }
        USBLog.write("SetReport(Output, id 0, \(report.count)) -> \(USBLog.code(e)): \(USBLog.hex(report[...]))")
        if e != kIOReturnSuccess { throw LinkError.io(String(format: "sending a report failed (0x%08X); the calculator may have left USB mode", UInt32(bitPattern: e))) }
    }

    /// Let the HID run loop sources (input-report callback) run for a moment.
    private func spin(_ seconds: TimeInterval) {
        if runLoop != nil { _ = CFRunLoopRunInMode(CFRunLoopMode.defaultMode, seconds, true) }
        else { Thread.sleep(forTimeInterval: seconds) }
    }

    func receive(timeout: TimeInterval) throws -> [UInt8]? {
        guard let d = device else { throw LinkError.noDevice }
        let end = Date().addingTimeInterval(timeout)
        var buf = [UInt8](repeating: 0, count: CalculatorLink.reportSize)
        repeat {
            if !getReportWorked, !callbackReports.isEmpty { return callbackReports.removeFirst() }
            var len = CFIndex(buf.count)
            let e = buf.withUnsafeMutableBufferPointer { p in
                IOHIDDeviceGetReport(d, kIOHIDReportTypeInput, 0, p.baseAddress!, &len)
            }
            if e == kIOReturnSuccess && len > 0 && buf[0] == 0 {
                if !loggedEmpty { USBLog.write("GetReport(Input) -> success, empty report (length byte 0)"); loggedEmpty = true }
            } else if e == kIOReturnSuccess && len > 0 {
                if !getReportWorked { USBLog.write("GetReport(Input, id 0) works; using it (as VoyagerInterface)") }
                getReportWorked = true
                callbackReports = []
                USBLog.write("GetReport(Input) len \(len): \(USBLog.hex(buf[0..<len]))")
                return Array(buf[0..<len])
            }
            if e != kIOReturnSuccess {
                if getReportFailures == 0 || e != lastGetReportError { USBLog.write("GetReport(Input, id 0) -> \(USBLog.code(e)) len \(len)") }
                getReportFailures += 1; lastGetReportError = e
            }
            spin(0.01)
        } while Date() < end
        return nil
    }

    deinit { close(); inputBuffer.deallocate() }
}
#endif
