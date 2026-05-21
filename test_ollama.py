import requests
import json

payload = {
    "model": "qwen2.5-coder:7b",
    "messages": [
        {"role": "system", "content": "You are Voltaic Velocity... Tool names: create_file, etc."},
        {"role": "user", "content": "@hello.html make it a shopping website"}
    ],
    "tools": [
        {
            "type": "function",
            "function": {
                "name": "create_file",
                "description": "Create a project file and populate it with content.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "path": {"type": "string"},
                        "content": {"type": "string"}
                    },
                    "required": ["path", "content"]
                }
            }
        }
    ],
    "stream": False
}

r = requests.post("http://127.0.0.1:11434/api/chat", json=payload)
print(r.status_code)
print(r.text)
