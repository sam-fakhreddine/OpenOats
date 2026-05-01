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
        // FluidAudio v0.14.3 - Audio processing and transcription backends
        // Includes Swift 6.2 concurrency fixes (v0.14.1+)
        // Revision: 00ea906c2089971bec767c4b4df38686aa7a9f9e
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.14.1"),
        
        // Sparkle v2.9.0 - Auto-updater framework
        // Revision: 21d8df80440b1ca3b65fa82e40782f1e5a9e6ba2
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0"),
        
        // WhisperKit for transcription
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
        
        // LaunchAtLogin Modern - Login item management
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
            exclude: ["Info.plist", "OpenOats.entitlements", "Assets", "Resources"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency=minimal")
            ]
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
            path: "Tests/OpenOatsTests",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency=minimal")
            ]
        ),
    ]
)
