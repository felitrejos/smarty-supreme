// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FlickCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "FlickCore", targets: ["FlickCore"]),
        .library(name: "FlickTestSupport", targets: ["FlickTestSupport"]),
        .executable(name: "flick-fixtures", targets: ["flick-fixtures"]),
    ],
    targets: [
        .target(name: "FlickCore"),
        .target(name: "FlickTestSupport", dependencies: ["FlickCore"]),
        .target(name: "FixtureTools", dependencies: ["FlickCore"]),
        .executableTarget(name: "flick-fixtures", dependencies: ["FlickCore", "FixtureTools"]),
        .testTarget(name: "FlickCoreTests", dependencies: ["FlickCore"]),
        .testTarget(name: "FlickTestSupportTests", dependencies: ["FlickCore", "FlickTestSupport"]),
        .testTarget(name: "FixtureToolsTests", dependencies: ["FlickCore", "FixtureTools"]),
    ]
)
