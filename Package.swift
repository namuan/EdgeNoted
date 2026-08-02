// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "EdgeNoted",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "EdgeNoted",
            path: "EdgeNoted",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "EdgeNotedTests",
            dependencies: ["EdgeNoted"],
            path: "EdgeNotedTests",
        ),
    ]
)
