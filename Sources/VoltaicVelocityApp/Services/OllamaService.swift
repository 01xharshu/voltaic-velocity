import Foundation
import OllamaKit

actor OllamaService {
    private let client = OllamaKit()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300 // 5 minutes timeout
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config)
    }()

    func streamChat(model: String, messages: [OKChatRequestData.Message], tools: [OKJSONValue]? = nil) -> AsyncThrowingStream<OKChatResponse, Error> {
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
                    request.timeoutInterval = 300 // Explicitly set timeout on the request object itself
                    request.httpBody = try JSONEncoder().encode(requestData)
                    
                    let (result, response) = try await session.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                        throw URLError(.badServerResponse)
                    }
                    
                    for try await line in result.lines {
                        guard let data = line.data(using: .utf8) else { continue }
                        do {
                            let chatResponse = try JSONDecoder().decode(OKChatResponse.self, from: data)
                            continuation.yield(chatResponse)
                            if chatResponse.done {
                                break
                            }
                        } catch {
                            // Some lines might be empty or invalid JSON, ignore and continue
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
