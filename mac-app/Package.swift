// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ChatApp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "ChatAppCore",
            targets: ["ChatApp"]
        ),
        .executable(
            name: "ChatApp",
            targets: ["ChatAppRunner"]
        )
    ],
    targets: [
        .target(
            name: "ChatApp"
        ),
        .executableTarget(
            name: "ChatAppRunner",
            dependencies: ["ChatApp"]
        ),
        .testTarget(
            name: "ChatAppTests",
            dependencies: ["ChatApp"]
        )
    ]
)
