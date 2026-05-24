---
name: mlx-inference
description: How to load, run, and stream tokens from Apple MLX models on M4 Mac with 16GB RAM. Use this skill when the task involves mlx_lm, model loading, quantized models, Apple Silicon inference, or fixing MLX-related crashes. Triggers for: "MLX not working", "model won't load", "slow inference", "memory error in MLX", "add MLX support".
---

# MLX Inference on M4 (16 GB)

## Quick Setup

```bash
pip install mlx-lm>=0.19.0 mlx>=0.18.0
```

## Model Selection for 16GB

| Task      | Model                                           | VRAM  | Speed (tok/s) |
|-----------|-------------------------------------------------|-------|---------------|
| Coding    | `mlx-community/Qwen2.5-Coder-7B-Instruct-4bit` | ~4.5G | ~80 t/s       |
| Reasoning | `mlx-community/phi-4-4bit`                      | ~8G   | ~40 t/s       |
| Fast/tiny | `mlx-community/Qwen2.5-Coder-1.5B-Instruct-4bit`| ~1.5G | ~180 t/s      |

**Never load Coder + Reasoning simultaneously.**

## Correct Streaming Pattern

```python
import mlx_lm

model, tokenizer = mlx_lm.load("mlx-community/Qwen2.5-Coder-7B-Instruct-4bit")

# Streaming — use stream_generate, not generate()
for token in mlx_lm.stream_generate(model, tokenizer, prompt="...", max_tokens=2048):
    print(token.text, end="", flush=True)
```

## Async Bridge (critical — mlx_lm is blocking)

```python
import asyncio
from concurrent.futures import ThreadPoolExecutor

_executor = ThreadPoolExecutor(max_workers=1)

async def stream_mlx(prompt: str):
    loop = asyncio.get_running_loop()
    queue = asyncio.Queue()

    def producer():
        for tok in mlx_lm.stream_generate(model, tokenizer, prompt=prompt, max_tokens=2048):
            loop.call_soon_threadsafe(queue.put_nowait, tok.text)
        loop.call_soon_threadsafe(queue.put_nowait, None)

    loop.run_in_executor(_executor, producer)
    while (chunk := await queue.get()) is not None:
        yield chunk
```

## Memory Cleanup Between Model Swaps

```python
import gc
import mlx.core as mx

def unload_model():
    global model, tokenizer
    del model, tokenizer
    model = tokenizer = None
    gc.collect()
    mx.metal.clear_cache()
```

## Common Fixes

| Symptom | Fix |
|---------|-----|
| `ImportError: mlx_lm` | `pip install mlx-lm` |
| Model download hangs | Set `HF_HUB_ENABLE_HF_TRANSFER=1` |
| OOM during load | Use 4-bit variant, call `clear_cache()` first |
| Garbled output | Apply chat template: `tokenizer.apply_chat_template(messages, ...)` |
| Slow first token | Normal — compilation; subsequent tokens fast |

## Chat Template (Qwen2.5)

```python
messages = [
    {"role": "system", "content": system_prompt},
    {"role": "user", "content": user_prompt},
]
formatted = tokenizer.apply_chat_template(
    messages, tokenize=False, add_generation_prompt=True
)
```
