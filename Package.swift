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
        .package(url: "https://github.com/kevinhermawan/OllamaKit.git", exact: "5.0.5")
    ],
    targets: [
        .executableTarget(
            name: "VoltaicVelocityApp",
            dependencies: [
                .product(name: "CodeEditorView", package: "CodeEditorView"),
                .product(name: "OllamaKit", package: "OllamaKit")
            ],
            path: "Sources/VoltaicVelocityApp",
            resources: [
                .copy("Resources")
            ]
        )
    ]
)
