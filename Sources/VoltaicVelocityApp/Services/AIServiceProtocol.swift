import Foundation
import OllamaKit

public protocol AIServiceProtocol: Actor {
    func streamChat(model: String, messages: [OKChatRequestData.Message], tools: [OKJSONValue]?) -> AsyncThrowingStream<StreamChatResponse, Error>
    func fetchModels() async throws -> [String]
    func checkReachable() async -> Bool
}
