// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VoltaicVelocity",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(
            name: "VoltaicVelocity",
            targets: ["VoltaicVelocityApp"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/mchakravarty/CodeEditorView.git", .exact("6.0.0-rc.0")),
        .package(url: "https://github.com/kevinhermawan/OllamaKit.git", .exact("6.0.0-rc.0"))
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
