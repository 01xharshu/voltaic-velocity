# Voltaic Velocity: Core Memory & Project Summary

## ⚡️ Project Overview
**Voltaic Velocity** is a blazing-fast, native macOS IDE built with Swift and SwiftUI, aiming to provide a fully agentic, multi-model AI coding experience.

## 🏗️ Architecture & Tooling
- **Platform**: macOS 15.0+ (Native SwiftUI Application)
- **Project Generation**: XcodeGen (`project.yml`)
- **Package Management**: Swift Package Manager (`Package.swift`)
- **Core Architecture**: MVVM
  - `ProjectViewModel`: Manages the workspace, indexing, and generating the dynamic Project Summary.
  - `AgentViewModel`: The orchestrator for the AI agent (Volt), maintaining prompt context, chat messages, and handling tool definitions.
  - `TerminalViewModel`: Executes bash/shell scripts in a local pseudo-terminal for tools like `build_project`.

## 📦 Key Dependencies
- **CodeEditorView** (v0.15.4): Native code editor with syntax highlighting.
- **OllamaKit** (v5.0.5): Connects to local LLMs via Ollama. 

## 🤖 Agentic Capabilities (Volt)
Volt operates under **True Autonomous Agent Mode**, combining capabilities of Cursor, Claude Code, and Antigravity.
- **Safety Diff Preview**: Uses Swift's native `CollectionDifference` to present a visual diff for any code change > 30 lines inside `SafetyDiffPreviewView.swift` before applying.
- **Build & Run Integration**: Tools include `build_project`, `run_project`, `get_build_errors`, and `create_branch` mapped directly into `AgentViewModel.swift`.
- **Advanced Reasoning**: Follows a strict loop: Deeply understand -> Explore & update summary -> Plan -> Execute -> Verify -> Refine.

## 📌 Rules & Heuristics
- Always produce complete, advanced, fully functional code (Zero placeholders).
- Do not require hand-holding from the user. Only ask for confirmation on major decisions.
- Maintain this `VOLT_MEMORY.md` file whenever making significant architectural changes.
