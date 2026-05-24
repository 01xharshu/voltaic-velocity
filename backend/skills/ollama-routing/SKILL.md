---
name: ollama-routing
description: How to query Ollama, route prompts to the right model, and stream responses. Use when fixing Ollama connection issues, model discovery failures, or adding new model categories. Triggers for: "Ollama not found", "model not responding", "add new model", "routing broken", "task router".
---

# Ollama Multi-Model Routing

## Check What's Installed

```python
import httpx

async def get_installed_models() -> list[str]:
    async with httpx.AsyncClient(timeout=3.0) as client:
        r = await client.get("http://localhost:11434/api/tags")
        return [m["name"] for m in r.json().get("models", [])]
```

## Model Categories for Voltaic

```python
MODEL_CATEGORIES = {
    "coder": ["qwen2.5-coder:7b", "codellama:7b", "deepseek-coder:6.7b"],
    "reasoning": ["phi4:latest", "qwq:32b", "deepseek-r1:8b"],
    "general": ["llama3.2:3b", "qwen2.5:7b"],
}

def pick_model(installed: list[str], category: str) -> str | None:
    for candidate in MODEL_CATEGORIES.get(category, []):
        if any(candidate in m for m in installed):
            return candidate
    return None
```

## Streaming Generation

```python
import httpx, json
from typing import AsyncIterator

async def stream_ollama(model: str, prompt: str, system: str = "") -> AsyncIterator[str]:
    payload = {
        "model": model,
        "prompt": prompt,
        "system": system,
        "stream": True,
        "options": {
            "num_gpu": 99,       # Full GPU offload on M4
            "num_thread": 8,     # M4 has 10 cores; leave 2 for OS
            "num_predict": 2048,
            "temperature": 0.1,  # Low temp for coding tasks
        },
    }
    async with httpx.AsyncClient(timeout=120.0) as client:
        async with client.stream("POST", "http://localhost:11434/api/generate", json=payload) as r:
            r.raise_for_status()
            async for line in r.aiter_lines():
                if not line: continue
                data = json.loads(line)
                if tok := data.get("response"): yield tok
                if data.get("done"): break
```

## Graceful Fallback

```python
async def stream_with_fallback(prompt: str, task_type: str):
    """Try MLX first, fall back to Ollama, fall back to error message."""
    from mlx_service import MLXService
    from ollama_service import OllamaService

    if await MLXService.is_available():
        model = MLXService.DEFAULT_CODER if task_type == "coder" else MLXService.DEFAULT_REASONING
        async for chunk in MLXService.stream(model, prompt): yield chunk
        return

    if await OllamaService.is_available():
        installed = await get_installed_models()
        model = pick_model(installed, task_type) or "qwen2.5-coder:7b"
        async for chunk in stream_ollama(model, prompt): yield chunk
        return

    yield "⚠️ No inference backend available. Start Ollama (`ollama serve`) or install mlx-lm."
```

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `Connection refused :11434` | Run `ollama serve` |
| Model not found | `ollama pull qwen2.5-coder:7b` |
| Slow on M4 | Ensure `num_gpu: 99` in options |
| Out of memory | Use smaller model or 4-bit quant |
