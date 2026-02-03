// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Hisohiso",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Hisohiso", targets: ["Hisohiso"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.9.0"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.7.9")
    ],
    targets: [
        .executableTarget(
            name: "Hisohiso",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "FluidAudio", package: "FluidAudio")
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
