// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MLXAudioSpike",
    platforms: [.macOS(.v15)],
    products: [
        .library(
            name: "MLXAudioSpike",
            targets: ["MLXAudioSpike"]
        ),
        .executable(
            name: "MLXAudioTest",
            targets: ["MLXAudioTest"]
        ),
    ],
    dependencies: [
        // MLX Swift - Apple's machine learning framework
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.21.0"),
        // MLX Audio Swift - Audio processing and STT for MLX
        .package(url: "https://github.com/Blaizzy/mlx-audio-swift", from: "0.1.0"),
    ],
    targets: [
        .target(
            name: "MLXAudioSpike",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXAudio", package: "mlx-audio-swift"),
            ]
        ),
        .executableTarget(
            name: "MLXAudioTest",
            dependencies: [
                "MLXAudioSpike",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXAudio", package: "mlx-audio-swift"),
            ]
        ),
    ]
)
