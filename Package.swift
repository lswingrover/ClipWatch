// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "ClipWatch",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ClipWatchCore", targets: ["ClipWatchCore"])
    ],
    targets: [
        // Pure-logic library — Foundation + SQLite3 + Network only.
        // No AppKit. Importable by CLI tools, MCP servers, or test harnesses.
        .target(
            name: "ClipWatchCore",
            path: "Sources/ClipWatchCore"
        ),
        // App executable — AppKit UI layer.
        .executableTarget(
            name: "ClipWatch",
            dependencies: ["ClipWatchCore"],
            path: "Sources/ClipWatch",
            linkerSettings: [.linkedFramework("LocalAuthentication")]
        ),
        .testTarget(
            name: "ClipWatchCoreTests",
            dependencies: ["ClipWatchCore"],
            path: "Tests/ClipWatchCoreTests"
        )
    ])
