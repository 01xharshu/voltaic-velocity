# Voltaic Velocity

Voltaic Velocity is a native macOS SwiftUI IDE for Xcode 16+ targeting macOS 15+. It provides a VS Code-like project workspace with a file explorer, syntax highlighted editor, embedded terminal, and an Ollama-powered AI agent panel.

## Project Structure

- `Package.swift` — Swift package manifest with dependencies on `CodeEditorView` and `OllamaKit`
- `Sources/VoltaicVelocityApp/VoltaicVelocityApp.swift` — App entry and global environment setup
- `Sources/VoltaicVelocityApp/ContentView.swift` — Main split-view layout with sidebar, editor, terminal, and AI panel
- `Sources/VoltaicVelocityApp/Models/` — Workspace, editor, and chat data models
- `Sources/VoltaicVelocityApp/ViewModels/` — MVVM view models for project, editor, terminal, and AI agent behavior
- `Sources/VoltaicVelocityApp/Services/` — File system, terminal, and Ollama integration services
- `Sources/VoltaicVelocityApp/Views/` — SwiftUI views for the IDE shell, editor tabs, terminal, file explorer, chat, and timeline
- `Sources/VoltaicVelocityApp/Resources/Info.plist` — App metadata and macOS target information

## Setup

1. Install Ollama locally:
   ```bash
   brew install ollama
   ```
2. Pull the recommended coder model:
   ```bash
   ollama pull qwen2.5-coder
   ```
3. Open `Package.swift` in Xcode 16+.
4. Build and run the `VoltaicVelocity` target.
5. Use the sidebar to open a folder, edit files, and interact with the AI agent.

## Notes

- The app uses native file operations via `FileManager`.
- The embedded terminal runs commands inside the app process and captures output.
- The app includes Git repository support with status and diff preview commands.
- The command palette can show repository diffs, active file git diffs, and unsaved editor diffs.
- The AI panel streams responses from Ollama and supports simulated tool calling for file edits, terminal tasks, and git actions.
- The editor uses `CodeEditorView` for native syntax highlighting and line-based editing.
