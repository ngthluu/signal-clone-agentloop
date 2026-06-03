// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ChatApp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "ChatApp",
            targets: ["ChatApp"]
        )
    ],
    targets: [
        .executableTarget(
            name: "ChatApp"
        ),
        .testTarget(
            name: "ChatAppTests",
            dependencies: ["ChatApp"]
        )
    ]
)
