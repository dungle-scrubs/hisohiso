// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Hisohiso",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Hisohiso", targets: ["Hisohiso"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.9.0")
    ],
    targets: [
        .executableTarget(
            name: "Hisohiso",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit")
            ],
            path: "Sources/Hisohiso",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "HisohisoTests",
            dependencies: ["Hisohiso"],
            path: "Tests/HisohisoTests"
        )
    ]
)
