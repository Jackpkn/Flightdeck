// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Flightdeck",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Real SQLite persistence — app-activity time has to survive restarts
        // and accumulate across days, which is a job for SQL, not a JSON blob.
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "Flightdeck",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
            path: "Sources/Flightdeck",
            resources: [.copy("Resources/Fonts")]
        ),
        .testTarget(
            name: "FlightdeckTests",
            dependencies: ["Flightdeck"],
            path: "Tests/FlightdeckTests"
        ),
    ]
)
