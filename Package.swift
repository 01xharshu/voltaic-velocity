// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VoltaicVelocity",
    platforms: [
        .macOS("15")
    ],
    products: [
        .executable(
            name: "VoltaicVelocity",
            targets: ["VoltaicVelocityApp"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/mchakravarty/CodeEditorView.git", exact: "0.15.4"),
        .package(url: "https://github.com/kevinhermawan/OllamaKit.git", exact: "5.0.5"),
        .package(url: "https://github.com/ml-explore/mlx-swift.git", from: "0.20.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "VoltaicVelocityApp",
            dependencies: [
                .product(name: "CodeEditorView", package: "CodeEditorView"),
                .product(name: "OllamaKit", package: "OllamaKit"),
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXRandom", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXOptimizers", package: "mlx-swift"),
                .product(name: "MLXFFT", package: "mlx-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm")
            ],
            path: "Sources/VoltaicVelocityApp",
            resources: [
                .copy("Resources")
            ]
        )
    ]
)
