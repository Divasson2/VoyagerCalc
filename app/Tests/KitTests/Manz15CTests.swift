// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// 0.7.2: Torsten Manz HP-15C Simulator program files (.15c / .txt): reading, writing, keys to press.
// The round trip over the simulator's 100 example programs runs when MANZ_PROGRAMS points at their folder
// (they are not part of this repository); the other tests use small inline files.

import XCTest
#if canImport(VoyagerKit)
@testable import VoyagerKit
#endif

final class Manz15CTests: XCTestCase {

    static let sample = """
    # ------------------------------------------------------------------------------
    # HEWLETT·PACKARD 15C Simulator program
    # Created with version 4.6.00
    # ------------------------------------------------------------------------------
    #T:Mother's Kitchen
    #D:First line
    #D:Second line
    #L-1:Can area
    #R0:Radius
    #R13:Point three
    #RI:Index
    #F8:Complex
    # ------------------------------------------------------------------------------

       000 {             } 
       001 {    42 21 11 } f LBL A
       002 {       44  0 } STO 0
       003 {       44 .3 } STO .3
       004 {    44 24  u } STO (i)
       005 {    43 30  5 } g TEST x=y
       006 {          48 } .
       007 {           7 } 7
       008 {       22 ,1 } GTO ,1
       009 {    45 16 11 } RCL MATRIX A
       010 {       43 32 } g RTN

    # ------------------------------------------------------------------------------
    """

    func testParsesStepsAndNotes() throws {
        let p = try Manz15CProgram.parse(Self.sample)
        XCTAssertEqual(p.title, "Mother's Kitchen")
        XCTAssertEqual(p.description, "First line\nSecond line")
        XCTAssertEqual(p.steps.count, 10)
        XCTAssertEqual(p.steps[0].tokens, [.key(42), .key(21), .key(11)])
        XCTAssertEqual(p.steps[2].tokens, [.key(44), .dot(3)])
        XCTAssertEqual(p.steps[3].tokens, [.key(44), .key(24), .user])
        XCTAssertEqual(p.steps[7].tokens, [.key(22), .dot(1)])
        XCTAssertEqual(p.steps[3].mnemonic, "STO (i)")
        XCTAssertEqual(p.steps[4].mnemonic, "g TEST x=y")
        XCTAssertEqual(p.labelNotes.map(\.key), ["L-1", "R0", "R13", "RI", "F8"])
    }

    func testNotesGoToTheProgramDocument() throws {
        let p = try Manz15CProgram.parse(Self.sample)
        var d = ProgramDocument()
        p.apply(to: &d)
        XCTAssertEqual(d.title, "Mother's Kitchen")
        XCTAssertEqual(d.labels["A"], "Can area")
        XCTAssertEqual(d.registers["R0"]?.meaning, "Radius")
        XCTAssertEqual(d.registers["R.3"]?.meaning, "Point three")
        XCTAssertEqual(d.registers["I"]?.meaning, "Index")
        XCTAssertEqual(d.flags["8"], "Complex")
        XCTAssertEqual(Manz15CProgram.notes(from: d).map(\.key), ["L-1", "R0", "R13", "RI", "F8"])
    }

    func testExportLayout() throws {
        let p = try Manz15CProgram.parse(Self.sample)
        let data = p.fileData()
        XCTAssertEqual([UInt8](data.prefix(4)), [0xFF, 0xFE, 0x23, 0x00])
        let text = String(data: data.dropFirst(2), encoding: .utf16LittleEndian)!
        let lines = text.components(separatedBy: "\r\n")
        XCTAssertEqual(lines[0], "# " + String(repeating: "-", count: 78))
        XCTAssertEqual(lines[1], "# HEWLETT·PACKARD 15C Simulator program")
        XCTAssertTrue(lines.contains("   000 {             } "))
        XCTAssertTrue(lines.contains("   001 {    42 21 11 } f LBL A"))
        XCTAssertTrue(lines.contains("   002 {       44  0 } STO 0"))
        XCTAssertTrue(lines.contains("   003 {       44 .3 } STO .3"))
        XCTAssertTrue(lines.contains("   004 {    44 24  u } STO (i)"))
        XCTAssertTrue(lines.contains("   006 {          48 } ."))
        XCTAssertEqual(lines.last, "# " + String(repeating: "-", count: 78))
        XCTAssertFalse(text.hasSuffix("\r\n"))
        XCTAssertEqual(try Manz15CProgram.read(data), p)
    }

    func testEncodings() throws {
        let body = "{ 42 21 11 }\n{ 2 }\n#T:Café\n"
        let utf8 = Data(body.utf8)
        XCTAssertEqual(try Manz15CProgram.read(utf8).title, "Café")
        XCTAssertEqual(try Manz15CProgram.read(Data([0xEF, 0xBB, 0xBF]) + utf8).steps.count, 2)
        let cp = body.data(using: .windowsCP1252)!
        XCTAssertEqual(try Manz15CProgram.read(cp).title, "Café")
        let u16 = Data([0xFF, 0xFE]) + body.data(using: .utf16LittleEndian)!
        XCTAssertEqual(try Manz15CProgram.read(u16).steps.map(\.keycodeText), ["42 21 11", " 2"])
    }

    func testOldPointKeycodeAndBareBraces() throws {
        let p = try Manz15CProgram.parse("{45 48 3}\n{48}\n{1}")
        XCTAssertEqual(p.steps.map(\.tokens), [[.key(45), .dot(3)], [.key(48)], [.key(1)]])
    }

    func testErrorsNameTheLine() {
        XCTAssertThrowsError(try Manz15CProgram.parse("{ 42 21 11 }\n{ 42 21 99 }")) {
            XCTAssertEqual($0 as? Manz15CProgram.ReadError, .unknownStep(line: 2, keycodes: "42 21 99"))
        }
        XCTAssertThrowsError(try Manz15CProgram.parse("{ 2 }\nhello")) {
            XCTAssertEqual($0 as? Manz15CProgram.ReadError, .invalidLine(line: 2, text: "hello"))
        }
        XCTAssertThrowsError(try Manz15CProgram.parse("{ 22 16 }"))          // GTO CHS: not programmable
        XCTAssertThrowsError(try Manz15CProgram.parse("{ 43 31 }"))          // P/R
        XCTAssertThrowsError(try Manz15CProgram.parse("{ 44 0 u }"))         // u only on A..E and (i)
        let big = (0..<1000).map { _ in "{ 1 }" }.joined(separator: "\n")
        XCTAssertThrowsError(try Manz15CProgram.parse(big)) { XCTAssertEqual($0 as? Manz15CProgram.ReadError, .tooManySteps(1000)) }
    }

    func testKeysToPress() throws {
        func keys(_ s: String) -> [Int]? { HP15CKeyEntry.keys(for: HP15CStep(HP15CKeycodes.parseManz(s)!)) }
        XCTAssertEqual(keys("42 21 11"), [31, 10, 0])            // f LBL A
        XCTAssertEqual(keys("44 .3"), [33, 37, 28])              // STO . 3
        XCTAssertEqual(keys("45 16 11"), [34, 31, 5, 0])         // RCL f MATRIX A
        XCTAssertEqual(keys("44 36"), [33, 31, 25])              // STO f RAN#
        XCTAssertEqual(keys("43 30 0"), [32, 29, 36])            // g TEST 0
        XCTAssertEqual(keys("44 24 u"), [33, 13])                // STO (i), typed in USER mode
        XCTAssertEqual(keys("49"), [38])
        XCTAssertEqual(keys("40"), [39])
        XCTAssertEqual(keys("9"), [8])
    }

    func testListingKeysFromTheCalculator() throws {
        let s = try Manz15CProgram.steps(fromListing: ["42,21,11", "44 .3", "45,10, .5", "43,30, 0", "6", "44 24"])
        XCTAssertEqual(s.map(\.keycodeText), ["42 21 11", "44 .3", "45 10 .5", "43 30  0", " 6", "44 24"])
        let imported = [HP15CStep([.key(44), .key(24), .user])]
        XCTAssertEqual(try Manz15CProgram.steps(fromListing: ["44 24"], imported: imported), imported)
    }

    /// Every example program of the simulator: read, write, read again; the keycodes must match the original file.
    func testRoundTripOfSimulatorExamples() throws {
        guard let dir = ProcessInfo.processInfo.environment["MANZ_PROGRAMS"] else { throw XCTSkip("MANZ_PROGRAMS not set") }
        let report = try Self.roundTrip(folder: URL(fileURLWithPath: dir))
        print("Manz round trip: \(report.passed)/\(report.total) passed")
        for f in report.failures { print("  FAIL \(f)") }
        XCTAssertGreaterThan(report.total, 0)
        XCTAssertEqual(report.failures, [])
    }

    static func roundTrip(folder: URL) throws -> (total: Int, passed: Int, failures: [String]) {
        let fm = FileManager.default
        var files: [URL] = []
        if let e = fm.enumerator(at: folder, includingPropertiesForKeys: nil) {
            for case let u as URL in e where ["15c", "txt"].contains(u.pathExtension.lowercased()) { files.append(u) }
        }
        var failures: [String] = []
        for f in files.sorted(by: { $0.path < $1.path }) {
            let name = f.lastPathComponent
            do {
                let data = try Data(contentsOf: f)
                let p = try Manz15CProgram.read(data)
                // the original keycodes, straight from the text between the braces (whitespace-normalised)
                let text = Manz15CProgram.decodeText(data)!
                var original: [String] = []
                for line in text.split(whereSeparator: \.isNewline) {
                    let l = line.trimmingCharacters(in: .whitespaces)
                    guard !l.hasPrefix("#"), let o = l.firstIndex(of: "{"), let c = l.lastIndex(of: "}") else { continue }
                    let k = l[l.index(after: o)..<c].split(separator: " ").joined(separator: " ").replacingOccurrences(of: ",", with: ".")
                    if !k.isEmpty { original.append(k) }
                }
                let out = p.fileData()
                let again = try Manz15CProgram.read(out)
                let written = again.steps.map { $0.keycodeText.split(separator: " ").joined(separator: " ") }
                var problems: [String] = []
                if written != original { problems.append("keycodes differ") }
                if again != p { problems.append("re-read differs") }
                if let bad = p.steps.firstIndex(where: { HP15CKeyEntry.keys(for: $0) == nil }) { problems.append("no keys for step \(bad + 1)") }
                // the step lines must also be byte-identical to the original file's, apart from "," for the point
                let origLines = text.split(whereSeparator: \.isNewline).map(String.init).filter { $0.contains("{") && !$0.hasPrefix("#") }
                let newLines = String(data: out.dropFirst(2), encoding: .utf16LittleEndian)!.components(separatedBy: "\r\n").filter { $0.contains("{") && !$0.hasPrefix("#") }
                if origLines.map({ String($0.prefix(while: { $0 != "}" })).replacingOccurrences(of: ",", with: ".") })
                    != newLines.map({ String($0.prefix(while: { $0 != "}" })) }) { problems.append("step layout differs") }
                if !problems.isEmpty { failures.append("\(name): " + problems.joined(separator: ", ")) }
            } catch {
                failures.append("\(name): \((error as? LocalizedError)?.errorDescription ?? "\(error)")")
            }
        }
        return (files.count, files.count - failures.count, failures)
    }
}
