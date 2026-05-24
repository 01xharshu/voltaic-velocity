import asyncio
import json
import logging
import os
import subprocess
import aiofiles
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
import litellm
import urllib.request
import re

# Set litellm to not drop params to support diverse models
litellm.drop_params = True

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

MEMORY_FILE = "conversation_history.jsonl"

async def append_to_memory(prompt: str, response: str):
    async with aiofiles.open(MEMORY_FILE, mode='a', encoding='utf-8') as f:
        entry = {"prompt": prompt, "response": response}
        await f.write(json.dumps(entry) + "\n")

async def load_recent_memory(limit: int = 5) -> list:
    if not os.path.exists(MEMORY_FILE):
        return []
    try:
        async with aiofiles.open(MEMORY_FILE, mode='r', encoding='utf-8') as f:
            lines = await f.readlines()
            recent = []
            for line in lines[-limit:]:
                if line.strip():
                    try:
                        data = json.loads(line)
                        recent.append({"role": "user", "content": data["prompt"]})
                        recent.append({"role": "assistant", "content": data["response"]})
                    except Exception:
                        pass
            return recent
    except Exception as e:
        logger.error(f"Error loading memory: {e}")
        return []

app = FastAPI(title="Volt Velocity Agent Server")

# System Prompts
SYSTEM_PROMPT = """You are Volt Velocity's Elite 2026 Python Agentic System.

# 2026 Expertise & Self-Evaluation System
Before taking action or returning code, you MUST evaluate against these criteria:
A. Modernity & Best Practices: Use the latest Apple Silicon & Python concurrency optimizations. Use Clean Architecture & MVVM.
B. Production Excellence: Ensure code is clean, readable, robustly error-handled, performant, and maintainable.
C. Enhancement Layer: Can this be more elegant? Proactively upgrade implementations to the highest professional standard.

If any area scores below excellent, upgrade it before execution.

# Bulletproof File Operations
You have tools to read, edit (via block replace), and rewrite files. ALWAYS read a file first, then edit.
After writing, you are expected to verify your changes.
IMPORTANT: You MUST use the native tool calling API to execute these tools. DO NOT output raw JSON blocks or write tool calls manually in your text response.

# Response Format
Keep your text response concise and fast. You do not need to write an essay. Structure your text response with the following markdown headers ONLY if applicable:

## Plan
(Briefly explain what you will do)

## Actions Executed
(Brief summary of files changed or commands run)
"""

def fetch_and_categorize_models():
    """Dynamically fetch local Ollama models and intelligently categorize them."""
    try:
        req = urllib.request.urlopen("http://127.0.0.1:11434/api/tags")
        data = json.loads(req.read())
        models = [m["name"] for m in data.get("models", [])]
    except Exception as e:
        logger.error(f"Failed to fetch models from Ollama: {e}")
        models = ["qwen2.5-coder:7b", "llama3.1:8b"]  # Safe fallback
    
    categorized = {
        "coder": [],
        "reasoning": [],
        "general": []
    }
    
    # Pre-process models by name
    for m in models:
        m_lower = m.lower()
        full_name = f"ollama/{m}"
        
        # Coder detection
        if any(kw in m_lower for kw in ["coder", "starcoder", "deepseek"]):
            categorized["coder"].append(full_name)
            
        # Reasoning detection (large models or specialized reasoning)
        if any(kw in m_lower for kw in ["r1", "qwq", "14b", "24b", "32b", "70b"]):
            categorized["reasoning"].append(full_name)
            
        # General (all models are technically general, but we'll put versatile ones here)
        categorized["general"].append(full_name)

    # Sort logic to maximize efficiency and tool-calling reliability:
    # Qwen2.5-Coder natively supports OpenAI-style tool calling flawlessly.
    # Llama 3.1/3.2 models often hallucinate raw JSON instead of using the API natively.
    
    # Coders: Prefer fast Qwen 7b, then Qwen 14b.
    categorized["coder"].sort(key=lambda x: 0 if "qwen" in x and "7b" in x else (1 if "qwen" in x else 2))
    
    # Reasoning: Prefer heavy models, but Qwen is still more reliable for tool calling.
    categorized["reasoning"].sort(key=lambda x: 0 if "qwen" in x and "14b" in x else (1 if "qwen" in x else 2))
    
    # General: Strictly prefer Qwen over Llama to prevent raw JSON hallucinations.
    categorized["general"].sort(key=lambda x: 0 if "qwen" in x else 1)
    
    # If a category is somehow empty, fallback to whatever general has
    for k in categorized:
        if not categorized[k]:
            categorized[k] = categorized["general"]
            
    logger.info(f"Dynamically mapped models: {categorized}")
    return categorized

# Initialize models dynamically on startup
MODELS = fetch_and_categorize_models()

def get_best_available_model(task_type: str = "coder") -> list:
    """Returns the list of available models for the given task type"""
    if task_type not in MODELS:
        task_type = "general"
    
    return MODELS.get(task_type, MODELS["general"])

# Model priority for auto-fallback
MODEL_PRIORITY = ["coder", "reasoning", "general"]



def determine_task_type(prompt: str) -> str:
    prompt_lower = prompt.lower()
    if any(kw in prompt_lower for kw in ["code", "refactor", "bug", "implement", "fix", "function", "swift", "python"]):
        return "coder"
    elif any(kw in prompt_lower for kw in ["plan", "analyze", "architect", "why", "reason", "evaluate"]):
        return "reasoning"
    return "general"

# Tools Definitions
tools = [
    {
        "type": "function",
        "function": {
            "name": "read_file",
            "description": "Read the contents of a file.",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Absolute path to the file"}
                },
                "required": ["path"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "rewrite_file",
            "description": "Completely rewrite a file with new content. Creates a backup automatically.",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string"},
                    "content": {"type": "string"}
                },
                "required": ["path", "content"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "edit_file_block",
            "description": "Semantically replace a block of text in a file. Creates a backup automatically.",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string"},
                    "old_content": {"type": "string", "description": "Exact text block to replace. Must match exactly."},
                    "new_content": {"type": "string", "description": "The new text block."}
                },
                "required": ["path", "old_content", "new_content"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "run_command",
            "description": "Run a shell command on the host.",
            "parameters": {
                "type": "object",
                "properties": {
                    "command": {"type": "string"}
                },
                "required": ["command"]
            }
        }
    }
]

async def execute_tool(name: str, arguments: dict) -> str:
    if name == "read_file":
        path = arguments.get("path")
        try:
            async with aiofiles.open(path, 'r', encoding='utf-8') as f:
                content = await f.read()
                return f"File content of {path}:\n\n{content}"
        except Exception as e:
            return f"Error reading file: {str(e)}"
            
    elif name == "edit_file_block":
        path = arguments.get("path")
        old_content = arguments.get("old_content")
        new_content = arguments.get("new_content")
        try:
            if os.path.exists(path):
                import shutil
                shutil.copy2(path, path + ".bak")
            async with aiofiles.open(path, 'r', encoding='utf-8') as f:
                content = await f.read()
            if old_content not in content:
                return f"Error: old_content not found in {path}"
            content = content.replace(old_content, new_content, 1)
            async with aiofiles.open(path, 'w', encoding='utf-8') as f:
                await f.write(content)
            
            # Post-write verify
            async with aiofiles.open(path, 'r', encoding='utf-8') as f:
                verified_content = await f.read()
            if new_content in verified_content:
                return f"Successfully edited {path} (Backup saved to {path}.bak)"
            else:
                return f"Error: Edit applied but new_content not found in verification read for {path}"
        except Exception as e:
            return f"Error editing file: {str(e)}"
            
    elif name == "rewrite_file":
        path = arguments.get("path")
        content = arguments.get("content")
        try:
            if os.path.exists(path):
                import shutil
                shutil.copy2(path, path + ".bak")
            async with aiofiles.open(path, 'w', encoding='utf-8') as f:
                await f.write(content)
            return f"Successfully rewrote {path} (Backup saved to {path}.bak)"
        except Exception as e:
            return f"Error writing file: {str(e)}"
            
    elif name == "run_command":
        cmd = arguments.get("command")
        try:
            result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=30)
            return f"Command Exit Code: {result.returncode}\nStdout: {result.stdout}\nStderr: {result.stderr}"
        except Exception as e:
            return f"Command failed: {str(e)}"
            
    return f"Unknown tool: {name}"

class TokenBuffer:
    def __init__(self, websocket: WebSocket):
        self.ws = websocket
        self.buffer = ""
        self.is_suppressing = False
        self.suppress_stack = 0
        
    async def process_token(self, token: str):
        self.buffer += token
        
        # Simple heuristic to suppress <tool_call>... or { ... } blocks from UI
        # We look backwards to see if there's an unmatched { or <tool_call>
        if "<tool_call>" in self.buffer and "</tool_call>" not in self.buffer:
            self.is_suppressing = True
        elif "{" in self.buffer and self.buffer.count("{") > self.buffer.count("}"):
            self.is_suppressing = True
        else:
            self.is_suppressing = False
            
        if not self.is_suppressing:
            # Output buffer and clear
            # Only output text if it doesn't contain the raw tags
            out = self.buffer.replace("<tool_call>", "").replace("</tool_call>", "")
            if out.strip() != "":
                await self.ws.send_text(json.dumps({"type": "token", "text": out}))
            self.buffer = ""

async def worker_agent_task(task_desc: str, websocket: WebSocket):
    model_list = get_best_available_model("coder")
    model = model_list[0] if model_list else "ollama/qwen2.5-coder:7b"
    
    await websocket.send_text(json.dumps({"type": "status", "message": f"Worker thread started using {model}..."}))
    
    messages = [
        {"role": "system", "content": SYSTEM_PROMPT + "\nYou are a fast Worker Agent. Execute the given task perfectly using your tools. Do not output text, just run the necessary tool calls."},
        {"role": "user", "content": task_desc}
    ]
    
    try:
        from litellm import acompletion
        response = await acompletion(
            model=model,
            messages=messages,
            tools=tools,
            tool_choice="auto"
        )
        
        message = response.choices[0].message
        if hasattr(message, 'tool_calls') and message.tool_calls:
            for tc in message.tool_calls:
                await websocket.send_text(json.dumps({"type": "tool_start", "name": tc.function.name}))
                args_str = tc.function.arguments
                await websocket.send_text(json.dumps({"type": "tool_stream", "name": tc.function.name, "chunk": args_str}))
                try:
                    args = json.loads(args_str)
                except:
                    args = {}
                result = await execute_tool(tc.function.name, args)
                await websocket.send_text(json.dumps({"type": "tool_finish", "name": tc.function.name, "result": result}))
        
        await websocket.send_text(json.dumps({"type": "status", "message": "Worker thread finished."}))
    except Exception as e:
        logger.error(f"Worker task failed: {e}")
        await websocket.send_text(json.dumps({"type": "error", "message": f"Worker task failed: {str(e)}"}))

async def robust_agent_loop(prompt: str, websocket: WebSocket):
    task_type = determine_task_type(prompt)
    model_list = get_best_available_model("reasoning" if task_type == "reasoning" else "general")
    
    if not model_list:
        model_list = ["ollama/qwen2.5-coder:7b"]
        
    await websocket.send_text(json.dumps({"type": "status", "message": f"Master Reasoner: {model_list[0]}..."}))
    
    messages = [
        {"role": "system", "content": SYSTEM_PROMPT + "\nYou are the Master Reasoner. Break down the task. You can output <worker_task>instruction</worker_task> tags to spawn concurrent worker agents to execute specific tasks (like file creation or updates). Avoid writing raw code or JSON directly in your response; use workers or tools."}
    ]
    
    recent_history = await load_recent_memory(limit=5)
    messages.extend(recent_history)
    messages.append({"role": "user", "content": prompt})
    
    max_retries = 3
    final_full_response = ""
    token_buffer = TokenBuffer(websocket)
    
    for attempt in range(max_retries):
        model = model_list[attempt % len(model_list)]
        try:
            from litellm import acompletion
            response = await acompletion(
                model=model,
                messages=messages,
                tools=tools,
                tool_choice="auto",
                stream=True
            )
            
            tool_calls = []
            
            async for chunk in response:
                delta = chunk.choices[0].delta
                if hasattr(delta, 'content') and delta.content:
                    final_full_response += delta.content
                    await token_buffer.process_token(delta.content)
                    
                if hasattr(delta, 'tool_calls') and delta.tool_calls:
                    for tc in delta.tool_calls:
                        if len(tool_calls) <= tc.index:
                            tool_calls.append({"id": tc.id, "type": "function", "function": {"name": tc.function.name, "arguments": ""}})
                            await websocket.send_text(json.dumps({"type": "tool_start", "name": tc.function.name}))
                        if hasattr(tc.function, 'arguments') and tc.function.arguments:
                            tool_calls[tc.index]["function"]["arguments"] += tc.function.arguments
                            await websocket.send_text(json.dumps({"type": "tool_stream", "name": tool_calls[tc.index]["function"]["name"], "chunk": tc.function.arguments}))
                            
            if not tool_calls and "{" in final_full_response:
                try:
                    blocks = re.findall(r'\{[\s\S]*?\}', final_full_response) 
                    start_idx = final_full_response.find('{')
                    end_idx = final_full_response.rfind('}')
                    if start_idx != -1 and end_idx != -1 and end_idx > start_idx:
                        json_str = final_full_response[start_idx:end_idx+1]
                        try:
                            data = json.loads(json_str)
                            func_name = data.get("function_name") or data.get("name")
                            args = data.get("arguments") or data.get("parameters")
                            if func_name and args is not None:
                                args_str = json.dumps(args) if isinstance(args, dict) else str(args)
                                tool_calls.append({
                                    "id": "call_fallback",
                                    "type": "function",
                                    "function": {"name": func_name, "arguments": args_str}
                                })
                                await websocket.send_text(json.dumps({"type": "tool_start", "name": func_name}))
                                await websocket.send_text(json.dumps({"type": "tool_stream", "name": func_name, "chunk": "\n[Parsed from JSON text]"}))
                        except json.JSONDecodeError:
                            pass
                except Exception as e:
                    logger.error(f"Fallback parsing failed: {e}")
                            
            if tool_calls:
                await websocket.send_text(json.dumps({"type": "status", "message": f"Executing {len(tool_calls)} master tools..."}))
                for tc in tool_calls:
                    name = tc["function"]["name"]
                    try:
                        args = json.loads(tc["function"]["arguments"])
                    except:
                        args = {}
                    
                    result = await execute_tool(name, args)
                    messages.append({"role": "assistant", "tool_calls": [tc]})
                    messages.append({"role": "tool", "tool_call_id": tc["id"], "name": name, "content": result})
                    await websocket.send_text(json.dumps({"type": "tool_finish", "name": name, "result": result}))
                
                second_response = await acompletion(
                    model=model,
                    messages=messages,
                    stream=True
                )
                async for chunk in second_response:
                    delta = chunk.choices[0].delta
                    if hasattr(delta, 'content') and delta.content:
                        final_full_response += delta.content
                        await token_buffer.process_token(delta.content)
            
            worker_tasks = re.findall(r'<worker_task>(.*?)</worker_task>', final_full_response, re.DOTALL)
            if worker_tasks:
                await websocket.send_text(json.dumps({"type": "status", "message": f"Spawning {len(worker_tasks)} concurrent worker threads..."}))
                tasks = [worker_agent_task(desc, websocket) for desc in worker_tasks]
                await asyncio.gather(*tasks)

            await append_to_memory(prompt, final_full_response)
            break
            
        except Exception as e:
            logger.error(f"Attempt {attempt+1} failed with model {model}: {e}")
            await websocket.send_text(json.dumps({"type": "status", "message": f"Fallback: Model {model} failed. Retrying..."}))
            if attempt == max_retries - 1:
                await websocket.send_text(json.dumps({"type": "error", "message": f"All fallback attempts failed: {str(e)}"}))

    await websocket.send_text(json.dumps({"type": "done", "message": "Agent loop complete."}))

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    logger.info("SwiftUI Client connected")
    try:
        async for raw in websocket.iter_text():
            logger.info(f"Received from Swift: {raw}")
            try:
                request = json.loads(raw)
                prompt = request.get("prompt", "")
                await robust_agent_loop(prompt, websocket)
            except json.JSONDecodeError:
                await websocket.send_text(json.dumps({"error": "Invalid JSON format."}))
    except WebSocketDisconnect:
        logger.info("SwiftUI Client disconnected")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("agent_server:app", host="127.0.0.1", port=8000, reload=True)
