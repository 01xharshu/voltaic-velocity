---
name: xcode-project-setup
description: How to correctly set up the Xcode project for Voltaic Velocity, including Swift Package Manager dependencies, entitlements, Info.plist keys, and build settings for macOS 15+. Use when adding packages, fixing build errors, configuring code signing, or setting up MLX/SwiftTreeSitter dependencies. Triggers for: "build fails", "package not found", "missing entitlement", "Xcode setup", "SPM dependency".
---

# Xcode Project Setup — Voltaic Velocity

## Required Swift Packages (Package.swift or Xcode SPM)

```swift
dependencies: [
    // MLX for Apple Silicon inference
    .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.18.0"),
    .package(url: "https://github.com/ml-explore/mlx-swift-examples", branch: "main"),

    // Syntax highlighting
    .package(url: "https://github.com/ChimeHQ/SwiftTreeSitter", from: "0.8.0"),
    .package(url: "https://github.com/nickel-lang/tree-sitter-swift", from: "0.1.0"),

    // Git operations (optional — alternative to CLI)
    .package(url: "https://github.com/swiftlang/swift-package-manager", from: "5.10.0"),
]

targets: [
    .target(
        name: "VoltaicVelocity",
        dependencies: [
            .product(name: "MLX", package: "mlx-swift"),
            .product(name: "MLXLLM", package: "mlx-swift-examples"),
            .product(name: "MLXLMCommon", package: "mlx-swift-examples"),
            .product(name: "SwiftTreeSitter", package: "SwiftTreeSitter"),
        ]
    )
]
```

## Required Entitlements (`VoltaicVelocity.entitlements`)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Required for PTY terminal emulator -->
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <!-- Required for file system access (IDE needs this) -->
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <!-- Required for running shell commands -->
    <key>com.apple.security.inherit</key>
    <true/>
    <!-- Required for WebSocket to localhost backend -->
    <key>com.apple.security.network.client</key>
    <true/>
    <!-- Required for Ollama on localhost -->
    <key>com.apple.security.network.server</key>
    <false/>
</dict>
</plist>
```

> ⚠️ **App Sandbox must be OFF** for a native IDE. You cannot fork processes or access arbitrary files with the sandbox enabled.

## Info.plist Keys

```xml
<!-- Allow outbound connections to localhost -->
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsLocalNetworking</key>
    <true/>
</dict>

<!-- Required for file open dialogs -->
<key>NSDocumentsFolderUsageDescription</key>
<string>Voltaic Velocity needs access to open and edit your code projects.</string>
```

## Build Settings

| Setting | Value |
|---------|-------|
| `SWIFT_VERSION` | `5.10` |
| `MACOSX_DEPLOYMENT_TARGET` | `15.0` |
| `ENABLE_APP_SANDBOX` | `NO` |
| `CODE_SIGN_STYLE` | `Automatic` |
| `SWIFT_STRICT_CONCURRENCY` | `complete` |
| `OTHER_SWIFT_FLAGS` | `-enable-actor-data-race-checks` |

## Common Build Errors

| Error | Fix |
|-------|-----|
| `MLX: No such module` | Add `mlx-swift` package, ensure target links it |
| `Sandbox: denied file-read` | Disable App Sandbox in entitlements |
| `async let` warning | Set `SWIFT_STRICT_CONCURRENCY=complete` |
| PTY fork fails | Confirm sandbox is OFF, check entitlements |
| WebSocket to localhost fails | Add `NSAllowsLocalNetworking` to Info.plist |
| `@MainActor` isolation errors | Annotate all ViewModels with `@MainActor` |

## Project Structure Template

```
VoltaicVelocity.xcodeproj
VoltaicVelocity/
├── App/
│   └── VoltaicVelocityApp.swift     (@main, injects @EnvironmentObject)
├── ViewModels/
│   ├── AgentViewModel.swift
│   ├── EditorViewModel.swift
│   ├── ProjectViewModel.swift
│   ├── TerminalManagerViewModel.swift
│   ├── TerminalViewModel.swift
│   └── GitViewModel.swift
├── Views/
│   ├── ContentView.swift
│   ├── EditorView.swift
│   ├── ProjectView.swift
│   ├── TerminalView.swift
│   ├── AgentChatView.swift
│   └── SettingsView.swift
├── Services/
│   ├── AIServiceProtocol.swift
│   ├── MLXService.swift
│   └── OllamaService.swift
├── MultiAgentCoordinator/
│   └── MultiAgentCoordinator.swift
├── Networking/
│   └── WebSocketClient.swift
├── Models/
│   ├── ChatMessage.swift
│   ├── WorkspaceFile.swift
│   └── GitFileStatus.swift
└── Resources/
    ├── VoltaicVelocity.entitlements
    └── Info.plist
```
