// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Effortless",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey", from: "0.2.1"),
    ],
    targets: [
        .executableTarget(
            name: "Effortless",
            dependencies: ["HotKey"],
            path: "Sources/Effortless"
        ),
        .testTarget(
            name: "EffortlessTests",
            dependencies: ["Effortless"],
            path: "Tests/EffortlessTests"
        ),
    ]
)
