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
        .library(
            name: "ViaSixMihomoConfig",
            targets: ["ViaSixMihomoConfig"]
        ),
        .library(
            name: "ViaSixPrivilegedProtocol",
            targets: ["ViaSixPrivilegedProtocol"]
        ),
        .library(
            name: "ViaSixTunHelperSupport",
            targets: ["ViaSixTunHelperSupport"]
        ),
        .executable(name: "ViaSix", targets: ["ViaSixApp"]),
        .executable(name: "ViaSixTunHelper", targets: ["ViaSixTunHelper"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/jpsim/Yams.git",
            exact: "6.2.2"
        )
    ],
    targets: [
        .target(
            name: "ViaSixPrivilegedProtocol",
            linkerSettings: [
                .linkedFramework("Security")
            ]
        ),
        .target(
            name: "ViaSixMihomoConfig",
            dependencies: [
                .product(name: "Yams", package: "Yams")
            ]
        ),
        .target(
            name: "ViaSixCore",
            dependencies: ["ViaSixMihomoConfig"],
            resources: [
                .process("Resources")
            ]
        ),
        .target(
            name: "ViaSixTunHelperSupport",
            dependencies: ["ViaSixPrivilegedProtocol"],
            linkerSettings: [
                .linkedFramework("Security")
            ]
        ),
        .executableTarget(
            name: "ViaSixApp",
            dependencies: [
                "ViaSixCore",
                "ViaSixMihomoConfig",
                "ViaSixPrivilegedProtocol",
            ],
            linkerSettings: [
                .linkedFramework("ServiceManagement")
            ]
        ),
        .executableTarget(
            name: "ViaSixTunHelper",
            dependencies: [
                "ViaSixMihomoConfig",
                "ViaSixPrivilegedProtocol",
                "ViaSixTunHelperSupport",
            ]
        ),
        .testTarget(
            name: "ViaSixCoreTests",
            dependencies: ["ViaSixCore"]
        ),
        .testTarget(
            name: "ViaSixMihomoConfigTests",
            dependencies: ["ViaSixMihomoConfig"]
        ),
        .testTarget(
            name: "ViaSixAppTests",
            dependencies: [
                "ViaSixApp",
                "ViaSixCore",
                "ViaSixMihomoConfig",
                "ViaSixPrivilegedProtocol",
            ]
        ),
        .testTarget(
            name: "ViaSixPrivilegedProtocolTests",
            dependencies: ["ViaSixPrivilegedProtocol"]
        ),
        .testTarget(
            name: "ViaSixTunHelperSupportTests",
            dependencies: ["ViaSixTunHelperSupport"]
        ),
        .testTarget(
            name: "ViaSixTunHelperTests",
            dependencies: [
                "ViaSixMihomoConfig",
                "ViaSixPrivilegedProtocol",
                "ViaSixTunHelper",
                "ViaSixTunHelperSupport",
            ]
        ),
    ]
)
