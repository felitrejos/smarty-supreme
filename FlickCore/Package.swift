// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FlickCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "FlickCore", targets: ["FlickCore"]),
        .library(name: "FlickTestSupport", targets: ["FlickTestSupport"]),
    ],
    targets: [
        .target(name: "FlickCore"),
        .target(name: "FlickTestSupport", dependencies: ["FlickCore"]),
        .testTarget(name: "FlickCoreTests", dependencies: ["FlickCore"]),
        .testTarget(name: "FlickTestSupportTests", dependencies: ["FlickCore", "FlickTestSupport"]),
    ]
)
