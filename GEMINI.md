# Voltaic Velocity — Antigravity Overrides

> Antigravity reads this alongside AGENTS.md. Rules here take precedence.
> Use this for Antigravity-specific behavior: model assignments, Manager view, artifact rules.

---

## Model Assignment (Manager View)

Assign models to agents by task in the Manager panel:

| Agent Task              | Model to Assign          | Why                                    |
|-------------------------|--------------------------|----------------------------------------|
| Swift / SwiftUI editing | Claude Sonnet 4.6        | Best Swift comprehension               |
| Python backend fixes    | Gemini 3.1 Pro           | 2M context — ingests whole backend     |
| Architecture planning   | Gemini 3.1 Pro           | Long-range reasoning across files      |
| Boilerplate / docs      | Gemini 3 Flash           | Fast, cheap, good enough               |
| MLX / ML code           | Claude Sonnet 4.6        | Strong Python + Apple Silicon knowledge|

> In Manager view: click the model pill on each agent card to reassign.

---

## Parallel Agent Strategy for This Project

Use Antigravity's Manager view to run agents in parallel where tasks are independent:

```
[Agent A: Sonnet 4.6]        [Agent B: Gemini Flash]
Fix MLXService.swift    ──── Write tests for OllamaService
         │                            │
         └────────── merge ───────────┘
                        │
              [Agent C: Gemini 3.1 Pro]
           Review diff + check architecture
```

**Good parallel splits for this codebase:**
- Swift frontend fixes ↔ Python backend fixes (fully independent)
- Writing tests ↔ writing implementation (independent)
- MLX service ↔ Ollama service (independent)

**Must be sequential:**
- Architecture plan → then implementation
- Backend tool executor fix → then WebSocket bridge fix
- Any git operation → wait for previous to finish

---

## Context Loading Strategy

Antigravity's 2M token context on Gemini 3.1 Pro means you can load the entire project.
For this codebase, always include:

1. `backend/agent_server.py` — the server entry
2. `backend/robust_agent_loop.py` — the most critical file
3. `VoltaicVelocity/Services/AIServiceProtocol.swift` — the interface contract
4. `VoltaicVelocity/ViewModels/AgentViewModel.swift` — the Swift bridge
5. The relevant `backend/skills/SKILL.md` for whatever you're fixing

When using Gemini Flash (smaller context), load only the files directly relevant to the task.

---

## Antigravity-Specific Behavior

- **Auto-approve** file edits that only touch `backend/` Python files — these are safe.
- **Require confirmation** before any edit to `AIServiceProtocol.swift` — breaking this breaks everything.
- **Require confirmation** before any `git reset` or force push.
- Do not generate `.cursorrules` — this project uses `AGENTS.md` + `GEMINI.md`.
- When generating Swift code, always target **macOS 15+** — do not add iOS compatibility shims.
- When generating Python code, use **Python 3.11+** syntax — no `Optional[X]`, use `X | None`.

---

## Backend Skills — Tell the Agent

When fixing something in `backend/`, always tell the Antigravity agent:

> "Read `backend/skills/<relevant-skill>/SKILL.md` before writing any code."

| You're fixing...              | Skills file to cite                          |
|-------------------------------|----------------------------------------------|
| MLX not loading / OOM         | `backend/skills/mlx-inference/SKILL.md`      |
| Ollama routing / model picker | `backend/skills/ollama-routing/SKILL.md`     |
| WebSocket tokens not showing  | `backend/skills/websocket-bridge/SKILL.md`   |
| Xcode build / entitlements    | `backend/skills/xcode-project-setup/SKILL.md`|
