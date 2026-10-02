// swift-tools-version: 5.9
import PackageDescription

// This package runs storage tests on a Mac without an iOS simulator.
// Open GoatMilk.xcodeproj to build the actual app.
let package = Package(
    name: "GoatMilkStorage",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "GoatMilkStorage", path: "GoatMilk",
                exclude: ["ContentView.swift", "GoatMilkApp.swift"],
                sources: ["Models.swift", "Database.swift"],
                linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "GoatMilkStorageTests", dependencies: ["GoatMilkStorage"], path: "Tests")
    ]
)
