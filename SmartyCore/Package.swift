// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SmartyCore",
    platforms: [.iOS(.v18), .macOS(.v26)],
    products: [
        .library(name: "SmartyCore", targets: ["SmartyCore"]),
        .library(name: "SmartyTestSupport", targets: ["SmartyTestSupport"]),
        .executable(name: "smarty-fixtures", targets: ["smarty-fixtures"]),
        .executable(name: "smarty-voice-lines", targets: ["smarty-voice-lines"]),
    ],
    targets: [
        .target(name: "SmartyCore"),
        .target(name: "SmartyTestSupport", dependencies: ["SmartyCore"]),
        .target(name: "FixtureTools", dependencies: ["SmartyCore"]),
        .executableTarget(name: "smarty-fixtures", dependencies: ["SmartyCore", "FixtureTools"]),
        .executableTarget(name: "smarty-voice-lines", dependencies: ["SmartyCore"]),
        .testTarget(name: "SmartyCoreTests", dependencies: ["SmartyCore"]),
        .testTarget(name: "SmartyTestSupportTests", dependencies: ["SmartyCore", "SmartyTestSupport"]),
        .testTarget(name: "FixtureToolsTests", dependencies: ["SmartyCore", "FixtureTools"]),
        .testTarget(name: "SensingBenchmarkTests", dependencies: ["SmartyCore"]),
        .testTarget(name: "LinkTests", dependencies: ["SmartyCore", "SmartyTestSupport"]),
        .testTarget(name: "GameEngineTests", dependencies: ["SmartyCore"]),
        .testTarget(name: "AITests", dependencies: ["SmartyCore"]),
    ]
)
