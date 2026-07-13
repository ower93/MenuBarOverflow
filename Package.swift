// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MenuBarOverflow",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "MenuBarOverflow", targets: ["MenuBarOverflow"]),
    ],
    targets: [
        .executableTarget(
            name: "MenuBarOverflow",
            path: "Sources/MenuBarOverflow",
            resources: [
                .copy("Resources"),
            ]
        ),
        .testTarget(
            name: "MenuBarOverflowTests",
            dependencies: ["MenuBarOverflow"],
            path: "Tests/MenuBarOverflowTests"
        ),
    ]
)
