import Foundation
import OllamaKit

public struct AnyDecodable: Decodable {
    public let value: Any
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) { value = string }
        else if let int = try? container.decode(Int.self) { value = int }
        else if let double = try? container.decode(Double.self) { value = double }
        else if let bool = try? container.decode(Bool.self) { value = bool }
        else if let array = try? container.decode([AnyDecodable].self) { value = array.map { $0.value } }
        else if let dict = try? container.decode([String: AnyDecodable].self) { value = dict.mapValues { $0.value } }
        else { value = "" }
    }
}

public struct StreamChatResponse: Decodable {
    public struct Message: Decodable {
        public struct ToolCall: Decodable {
            public struct Function: Decodable {
                public let name: String?
                public let arguments: [String: Any]?
                
                enum CodingKeys: String, CodingKey {
                    case name, arguments
                }
                
                public init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    name = try container.decodeIfPresent(String.self, forKey: .name)
                    if let argsData = try container.decodeIfPresent([String: AnyDecodable].self, forKey: .arguments) {
                        arguments = argsData.mapValues { $0.value }
                    } else {
                        arguments = nil
                    }
                }
            }
            public let function: Function?
        }
        
        public let role: String?
        public let content: String?
        public let tool_calls: [ToolCall]?
    }
    public let model: String?
    public let message: Message?
    public let done: Bool
}

actor OllamaService: AIServiceProtocol {
    private let client = OllamaKit()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 86400 // 24 hours timeout
        config.timeoutIntervalForResource = 86400
        return URLSession(configuration: config)
    }()

    func streamChat(model: String, messages: [OKChatRequestData.Message], tools: [OKJSONValue]? = nil) -> AsyncThrowingStream<StreamChatResponse, Error> {
        let requestData = OKChatRequestData(model: model, messages: messages, tools: tools)
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let url = URL(string: "http://127.0.0.1:11434/api/chat") else {
                        throw URLError(.badURL)
                    }
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.timeoutInterval = 86400 // 24 hours timeout
                    var requestDict = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(requestData)) as? [String: Any] ?? [:]
                    requestDict["stream"] = true
                    
                    // Increase context window to handle large context lengths (128k supported by Qwen2.5)
                    requestDict["options"] = ["num_ctx": 131072]
                    
                    request.httpBody = try JSONSerialization.data(withJSONObject: requestDict)
                    
                    let (result, response) = try await session.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                        throw URLError(.badServerResponse)
                    }
                    
                    for try await line in result.lines {
                        guard let data = line.data(using: .utf8) else { continue }
                        do {
                            let chatResponse = try JSONDecoder().decode(StreamChatResponse.self, from: data)
                            continuation.yield(chatResponse)
                            if chatResponse.done {
                                break
                            }
                        } catch {
                            print("Ollama API stream decode error: \(error.localizedDescription) for line: \(line)")
                            continue
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func fetchModels() async throws -> [String] {
        let response = try await client.models()
        return response.models.map { $0.name }
    }

    func checkReachable() async -> Bool {
        do {
            _ = try await client.models()
            return true
        } catch {
            return false
        }
    }
}
