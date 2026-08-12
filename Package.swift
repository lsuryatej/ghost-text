// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GhostText",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GhostTextCore", targets: ["GhostTextCore"]),
        .library(name: "GhostTextUI", targets: ["GhostTextUI"]),
        .library(name: "GhostTextInference", targets: ["GhostTextInference"]),
    ],
    targets: [
        // Pure logic. No AppKit behaviour, no AX, no event tap. Everything here
        // is unit-testable in seconds without launching the app.
        .target(name: "GhostTextCore"),

        // The ghost overlay panel. AppKit, but standalone and driveable from a
        // harness with hardcoded coordinates.
        .target(name: "GhostTextUI", dependencies: ["GhostTextCore"]),

        // MLX model loading and generation, behind an actor.
        .target(name: "GhostTextInference", dependencies: ["GhostTextCore"]),

        // Wires everything together: menu bar, event tap, AX geometry.
        .executableTarget(
            name: "GhostTextApp",
            dependencies: ["GhostTextCore", "GhostTextUI", "GhostTextInference"]
        ),

        // Latency harness. Runs the model with no GUI and no permissions.
        .executableTarget(name: "ghost-bench", dependencies: ["GhostTextInference", "GhostTextCore"]),

        // Draws the overlay at hardcoded coordinates so panel work needs no
        // event tap, no AX, and no model.
        .executableTarget(name: "ghost-panel-demo", dependencies: ["GhostTextUI", "GhostTextCore"]),

        .testTarget(name: "GhostTextCoreTests", dependencies: ["GhostTextCore"]),
    ]
)
