// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "BrrainzTools",
    platforms: [
        .macOS("27.0"),
    ],
    products: [
        .executable(
            name: "brrainztools",
            targets: ["BrrainzTools"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "BrrainzTools"
        ),
        .testTarget(
            name: "BrrainzToolsTests",
            dependencies: ["BrrainzTools"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
