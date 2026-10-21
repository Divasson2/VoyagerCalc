// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// 0.6.5 (d): repeating an export offers the file name chosen last time.

import Foundation
import XCTest
#if canImport(VoyagerKit)
@testable import VoyagerKit
#endif

final class ExportNamesTests: XCTestCase {
    func testDefaultUntilSomethingWasSaved() {
        let m = ExportNameMemory()
        XCTAssertEqual(m.name(for: "text", default: "Program listing"), "Program listing")
    }

    func testRepeatPrefillsTheLastNameWithoutExtension() {
        var m = ExportNameMemory()
        m.remember("text", url: URL(fileURLWithPath: "/Users/x/Desktop/Miller Rabin 16C.txt"))
        XCTAssertEqual(m.name(for: "text", default: "Untitled listing"), "Miller Rabin 16C")
    }

    func testKindsAreIndependent() {
        var m = ExportNameMemory()
        m.remember("text", url: URL(fileURLWithPath: "/tmp/listing.txt"))
        m.remember("pdf", url: URL(fileURLWithPath: "/tmp/doc.pdf"))
        XCTAssertEqual(m.name(for: "text", default: "d"), "listing")
        XCTAssertEqual(m.name(for: "pdf", default: "d"), "doc")
        XCTAssertEqual(m.name(for: "notes", default: "d"), "d")
        XCTAssertEqual(m.name(for: "memory", default: "d"), "d")
    }

    func testLatestWinsAndForgetAllResets() {
        var m = ExportNameMemory()
        m.remember("text", url: URL(fileURLWithPath: "/tmp/one.txt"))
        m.remember("text", url: URL(fileURLWithPath: "/tmp/two.txt"))
        XCTAssertEqual(m.name(for: "text", default: "d"), "two")
        m.forgetAll()
        XCTAssertTrue(m.isEmpty)
        XCTAssertEqual(m.name(for: "text", default: "d"), "d")
    }

    func testNamesWithDotsKeepTheirBase() {
        var m = ExportNameMemory()
        m.remember("text", url: URL(fileURLWithPath: "/tmp/Finance v1.2 listing.txt"))
        XCTAssertEqual(m.name(for: "text", default: "d"), "Finance v1.2 listing")
    }
}
