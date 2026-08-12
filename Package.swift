// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GhostText",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GhostTextCore", targets: ["GhostTextCore"]),
        .library(name: "GhostTextUI", targets: ["GhostTextUI"]),
    ],
    targets: [
        // Pure logic. No AppKit behaviour, no AX, no event tap. Everything here
        // is unit-testable in seconds without launching the app.
        .target(name: "GhostTextCore"),

        // The ghost overlay panel. AppKit, but standalone and driveable from a
        // test harness with hardcoded coordinates.
        .target(name: "GhostTextUI", dependencies: ["GhostTextCore"]),

        // Wires everything together: menu bar, event tap, AX geometry.
        .executableTarget(name: "GhostTextApp", dependencies: ["GhostTextCore", "GhostTextUI"]),

        .testTarget(name: "GhostTextCoreTests", dependencies: ["GhostTextCore"]),
    ]
)
