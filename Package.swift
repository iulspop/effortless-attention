// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Effortless",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Effortless",
            path: "Sources/Effortless"
        ),
    ]
)
