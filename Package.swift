// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ClaudeQuotaIsland",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "ClaudeQuotaIslandCore",
            targets: ["ClaudeQuotaIslandCore"]
        ),
        .executable(
            name: "ClaudeQuotaIslandApp",
            targets: ["ClaudeQuotaIslandApp"]
        ),
        .executable(
            name: "ClaudeQuotaIslandChecks",
            targets: ["ClaudeQuotaIslandChecks"]
        ),
    ],
    targets: [
        .target(name: "ClaudeQuotaIslandCore"),
        .executableTarget(
            name: "ClaudeQuotaIslandApp",
            dependencies: ["ClaudeQuotaIslandCore"]
        ),
        .executableTarget(
            name: "ClaudeQuotaIslandChecks",
            dependencies: ["ClaudeQuotaIslandCore"]
        ),
    ]
)
