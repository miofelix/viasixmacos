// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "ViaSix",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ViaSixCore", targets: ["ViaSixCore"]),
        .executable(name: "ViaSix", targets: ["ViaSixApp"])
    ],
    targets: [
        .target(
            name: "ViaSixCore",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "ViaSixApp",
            dependencies: ["ViaSixCore"]
        ),
        .testTarget(
            name: "ViaSixCoreTests",
            dependencies: ["ViaSixCore"]
        )
    ]
)
