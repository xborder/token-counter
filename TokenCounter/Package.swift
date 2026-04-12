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
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-testing.git", from: "0.10.0"),
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
            dependencies: [
                "TokenCounter",
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests",
            resources: [
                .process("Fixtures")
            ]
        )
    ]
)
