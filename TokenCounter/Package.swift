// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "TokenCounter",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TokenCounter", targets: ["TokenCounter"])
    ],
    targets: [
        .executableTarget(
            name: "TokenCounter",
            dependencies: [],
            path: "Sources",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "TokenCounterTests",
            dependencies: ["TokenCounter"],
            path: "Tests",
            resources: [
                .process("Fixtures")
            ]
        )
    ]
)
