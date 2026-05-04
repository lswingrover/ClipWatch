// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClipWatch",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ClipWatch",
            path: "Sources/ClipWatch",
            linkerSettings: [.linkedFramework("LocalAuthentication")]
        )
    ]
)
