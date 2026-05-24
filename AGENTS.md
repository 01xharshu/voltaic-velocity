# Voltaic Velocity — Agent Rules

> This file is the cross-tool foundation. Commit it to your repo root.
> Antigravity reads this alongside GEMINI.md (GEMINI.md overrides on conflicts).

---

## Project Identity

Voltaic Velocity is a **native macOS IDE** built with SwiftUI + a Python FastAPI backend
that acts as a multi-agent AI orchestrator. You are the senior engineer on this codebase.
Every fix must be production-grade, idiomatic 2026 Swift/Python, and optimized for Apple Silicon M4.

**Hardware target**: MacBook Pro M4, 16 GB unified memory, macOS 15+.
All inference is **local only** — no cloud API keys in any production code path.

---

## Architecture

```
SwiftUI Client (macOS)
  AgentViewModel ──── AIServiceProtocol ──┬── MLXService
  ProjectViewModel                        └── OllamaService
  EditorViewModel
  TerminalManagerViewModel / TerminalViewModel
  GitViewModel
  MultiAgentCoordinator
        │
        │  WebSocket  ws://127.0.0.1:8000/ws
        ▼
Python Backend (FastAPI)
  agent_server.py → task_router.py → robust_agent_loop.py → tool_executor.py
  backend/skills/   ← agent reads these SKILL.md files at runtime
```

---

## Tech Stack

| Layer     | Technology                                      |
|-----------|-------------------------------------------------|
| Frontend  | Swift 5.10, SwiftUI, Combine, async/await       |
| Backend   | Python 3.11+, FastAPI, uvicorn, asyncio         |
| ML (primary) | MLX (`mlx-lm`) — runs on M4 GPU/ANE          |
| ML (fallback) | Ollama HTTP API at localhost:11434           |
| Terminal  | POSIX PTY (`posix_openpt`, fork/exec)           |
| Syntax    | SwiftTreeSitter + language grammars             |
| Git       | `git` CLI via async subprocess                  |

---

## M4 / 16 GB Memory Budget

| Component            | RAM    |
|----------------------|--------|
| macOS + IDE process  | ~4 GB  |
| MLX Coder model      | ~4.5 GB|
| MLX Reasoning model  | ~8 GB  |

**Critical rule**: Never load Coder + Reasoning models simultaneously.
Always `mx.metal.clear_cache()` + `gc.collect()` before swapping models.

### Model Assignments

| Task      | MLX (primary)                                   | Ollama (fallback)     |
|-----------|-------------------------------------------------|-----------------------|
| Coding    | `mlx-community/Qwen2.5-Coder-7B-Instruct-4bit` | `qwen2.5-coder:7b`    |
| Reasoning | `mlx-community/phi-4-4bit`                      | `phi4:latest`         |
| General   | `mlx-community/Qwen2.5-Coder-7B-Instruct-4bit` | `qwen2.5-coder:7b`    |

---

## Swift Coding Standards

- `@MainActor final class` for every ViewModel — no exceptions.
- `async/await` only — no `DispatchQueue` unless PTY forces it.
- `AIServiceProtocol` is the sole abstraction for all inference — never call MLX/Ollama from a View directly.
- Typed errors: `enum VoltaicError: LocalizedError` — never bare `print("error")`.
- `@Published private(set)` for state the ViewModel owns exclusively.
- Force-unwrap (`!`) is forbidden in production paths — use `guard let`.

## Python Coding Standards

- `from __future__ import annotations` at top of every file.
- Full type annotations on all functions and class attributes.
- `async def` for all FastAPI routes and I/O operations.
- `asyncio.create_subprocess_exec` only — never blocking `subprocess.run` in async context.
- `structlog` with JSON output — never bare `print()`.
- All tool calls use `ToolCall` dataclasses, not raw dicts.

---

## File Map

```
VoltaicVelocity/
├── App/VoltaicVelocityApp.swift
├── ViewModels/
│   ├── AgentViewModel.swift        ← bridge: UI ↔ AIServiceProtocol ↔ WebSocket
│   ├── EditorViewModel.swift
│   ├── ProjectViewModel.swift
│   ├── TerminalManagerViewModel.swift
│   ├── TerminalViewModel.swift
│   └── GitViewModel.swift
├── Services/
│   ├── AIServiceProtocol.swift     ← DO NOT break this interface
│   ├── MLXService.swift
│   └── OllamaService.swift
├── MultiAgentCoordinator/
│   └── MultiAgentCoordinator.swift
└── Networking/
    └── WebSocketClient.swift
backend/
├── agent_server.py
├── task_router.py
├── robust_agent_loop.py
├── tool_executor.py
├── mlx_service.py
├── ollama_service.py
└── skills/                         ← read these before fixing anything
```

---

## When Fixing Broken Code

1. Trace the full data path: UI event → ViewModel → Protocol → Service → WebSocket → Backend → Tool → Response → UI update.
2. Read the relevant `backend/skills/` SKILL.md before touching that area.
3. Never stub or TODO — write the complete working implementation.
4. Check WebSocket reconnect assumptions — the Swift client must handle disconnect and retry with exponential backoff.
5. Do not rewrite files wholesale if `edit_file_block` (targeted diff) is sufficient.

---

## Safety Rules

- Never write code that calls external APIs in production inference paths.
- Never commit secrets, API keys, or tokens.
- The `ENABLE_APP_SANDBOX` Xcode setting must be `NO` — the IDE needs PTY + arbitrary file access.
- Confirm with the user before any destructive git operation (reset, force push).
