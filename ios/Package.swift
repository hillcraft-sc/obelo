// swift-tools-version:6.2
import PackageDescription

// Runs the unit tests for the code in Shared without Xcode or a scheme: `cd ios && swift test`.
// The apps are built by Xcode from project.yml; this package exists only for the tests.
let package = Package(
    name: "ObeloShared",
    platforms: [.macOS(.v26)],
    targets: [
        .target(
            name: "ObeloShared",
            path: "Shared",
            swiftSettings: [.defaultIsolation(MainActor.self), .enableUpcomingFeature("NonisolatedNonsendingByDefault")]
        ),
        .testTarget(
            name: "ObeloSharedTests",
            dependencies: ["ObeloShared"],
            path: "Tests/Shared",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
