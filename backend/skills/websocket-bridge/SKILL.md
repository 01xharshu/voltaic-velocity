---
name: websocket-bridge
description: How to correctly implement the WebSocket bridge between the Swift macOS client and the Python FastAPI backend in Voltaic Velocity. Use when fixing connection drops, message parsing errors, token streaming issues, or Swift WebSocket reconnect logic. Triggers for: "WebSocket disconnects", "tokens not appearing", "Swift not receiving", "connection refused", "ws bridge broken".
---

# WebSocket Bridge: Swift ↔ Python FastAPI

## Message Protocol

All messages are JSON. Both sides must agree on this schema:

### Client → Server
```json
{ "type": "prompt",  "content": "fix the auth bug", "task_hint": "coder" }
{ "type": "clear",   "content": "" }
{ "type": "cancel",  "content": "" }
```

### Server → Client (streamed)
```json
{ "type": "token",        "content": "Here" }
{ "type": "token",        "content": " is" }
{ "type": "tool_use",     "tool": "read_file", "args": {"path": "main.swift"} }
{ "type": "tool_result",  "tool": "read_file", "success": true, "output": "..." }
{ "type": "done",         "content": "" }
{ "type": "error",        "content": "Model failed: ..." }
```

## Python Server — Correct WebSocket Handler

```python
@app.websocket("/ws")
async def ws_endpoint(ws: WebSocket):
    await ws.accept()
    try:
        async for raw in ws.iter_text():          # <-- NOT receive_text() in a loop
            msg = json.loads(raw)
            await agent_loop.handle(msg, ws)
    except WebSocketDisconnect:
        pass
```

**DO NOT** use `await ws.receive_text()` in a `while True` loop — use `async for` to properly handle disconnect.

## Swift Client — Reliable WebSocket Actor

```swift
actor WebSocketClient {
    private var task: URLSessionWebSocketTask?
    private var continuation: AsyncStream<WSEvent>.Continuation?
    private let url = URL(string: "ws://127.0.0.1:8000/ws")!

    // Reconnect state
    private var reconnectAttempts = 0
    private let maxReconnectDelay: TimeInterval = 30

    var events: AsyncStream<WSEvent> {
        get async {
            let (stream, cont) = AsyncStream<WSEvent>.makeStream()
            self.continuation = cont
            Task { await self.connectWithRetry() }
            return stream
        }
    }

    private func connectWithRetry() async {
        while !Task.isCancelled {
            do {
                try await connect()
                reconnectAttempts = 0   // Reset on success
            } catch {
                reconnectAttempts += 1
                let delay = min(pow(2.0, Double(reconnectAttempts)), maxReconnectDelay)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    private func connect() async throws {
        let session = URLSession(configuration: .default)
        task = session.webSocketTask(with: url)
        task?.resume()

        // Start receive loop
        while let task = task {
            let message = try await task.receive()
            switch message {
            case .string(let text):
                if let event = parse(text) { continuation?.yield(event) }
            case .data(let data):
                if let text = String(data: data, encoding: .utf8),
                   let event = parse(text) { continuation?.yield(event) }
            @unknown default: break
            }
        }
    }

    func send(_ payload: [String: String]) async throws {
        let data = try JSONSerialization.data(withJSONObject: payload)
        let str = String(data: data, encoding: .utf8)!
        try await task?.send(.string(str))
    }

    private func parse(_ text: String) -> WSEvent? {
        guard let data = text.data(using: .utf8),
              let json = try? JSONDecoder().decode(WSMessage.self, from: data)
        else { return nil }
        switch json.type {
        case "token":       return .token(json.content ?? "")
        case "tool_use":    return .toolUse(json.tool ?? "", json.args ?? [:])
        case "tool_result": return .toolResult(json.output ?? "")
        case "done":        return .done
        case "error":       return .error(json.content ?? "")
        default:            return nil
        }
    }
}
```

## Common Failure Modes

| Symptom | Root Cause | Fix |
|---------|------------|-----|
| Swift never gets tokens | Python not streaming mid-WebSocket | Ensure `await ws.send_json()` inside loop, not after |
| Connection refused | Backend not running | Auto-launch backend process from Swift on app start |
| Message pile-up | Not awaiting send | All `ws.send_json()` must be `await`ed |
| Disconnect on large response | URLSession timeout | Set `timeoutInterval: 0` on URLSessionConfiguration |
| JSON parse error Swift-side | Extra whitespace/newlines | Always use `JSONDecoder` not manual parsing |

## Auto-Launch Backend from Swift

```swift
final class BackendLauncher {
    private var process: Process?

    func launch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "cd ~/VoltaicVelocity/backend && python -m uvicorn agent_server:app --host 127.0.0.1 --port 8000"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        self.process = process
    }

    func stop() { process?.terminate() }
}
```
