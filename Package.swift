// swift-tools-version:5.9
// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// Swift package for the non-UI parts (C core + Swift wrapper + model data) so they can be
// built and tested anywhere Swift runs, including Linux. The apps are built from
// app/VoyagerCalc.xcodeproj.

import PackageDescription

let package = Package(
    name: "VoyagerCalc",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "VoyagerKit", targets: ["VoyagerKit"])],
    targets: [
        .target(name: "VoyagerCore", path: "core",
                exclude: ["tools", "tests", "build", "Makefile", "README.md", "PROGRESS.md"],
                sources: ["src"], publicHeadersPath: "include",
                cSettings: [.unsafeFlags(["-O2"])]),
        .target(name: "VoyagerKit", dependencies: ["VoyagerCore"], path: "app/Sources",
                exclude: ["App", "Views"], sources: ["Core", "Models"]),
        .testTarget(name: "VoyagerKitTests", dependencies: ["VoyagerKit"], path: "app/Tests/KitTests"),
    ],
    swiftLanguageVersions: [.v5]
)
