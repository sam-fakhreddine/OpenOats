// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "OpenOats",
    platforms: [.macOS(.v15)],
    products: [
        .library(
            name: "OpenOatsKit",
            targets: ["OpenOatsKit"]
        ),
        .executable(
            name: "OpenOats",
            targets: ["OpenOatsAppExecutable"]
        ),
        .executable(
            name: "Benchmark",
            targets: ["Benchmark"]
        ),
    ],
    dependencies: [
        // FluidAudio has made source-breaking API changes in patch releases.
        // Pin exactly so SwiftPM and Xcode smoke builds resolve the same SDK.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.13.5"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0"),
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
        .package(url: "https://github.com/sindresorhus/LaunchAtLogin-Modern", from: "1.1.0"),
        // MLX Audio for local GPU-accelerated transcription
        // Using compatible versions to resolve swift-transformers conflict
        // mlx-swift-lm 2.30.3 depends on mlx-swift 0.30.x (not swift-transformers 1.2.x)
        .package(url: "https://github.com/ml-explore/mlx-swift.git", exact: "0.30.6"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", exact: "2.30.3"),
        .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", exact: "0.1.0"),
    ],
    targets: [
        .target(
            name: "OpenOatsKit",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "LaunchAtLogin", package: "LaunchAtLogin-Modern"),
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXAudioSTT", package: "mlx-audio-swift"),
            ],
            path: "Sources/OpenOats",
            exclude: ["Info.plist", "OpenOats.entitlements", "Assets", "Resources"]
        ),
        .executableTarget(
            name: "OpenOatsAppExecutable",
            dependencies: ["OpenOatsKit"],
            path: "Sources/OpenOatsApp"
        ),
        .executableTarget(
            name: "Benchmark",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            path: "Sources/Benchmark"
        ),
        .testTarget(
            name: "OpenOatsTests",
            dependencies: ["OpenOatsKit"],
            path: "Tests/OpenOatsTests"
        ),
        .testTarget(
            name: "OpenOatsPerformanceTests",
            dependencies: ["OpenOatsKit"],
            path: "Tests/OpenOatsPerformanceTests"
        ),
    ]
)
