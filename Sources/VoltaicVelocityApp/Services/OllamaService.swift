import Foundation
import OllamaKit

actor OllamaService {
    private let client = OllamaKit()

    func streamChat(model: String, messages: [OKChatRequestData.Message], tools: [OKJSONValue]? = nil) -> AsyncThrowingStream<OKChatResponse, Error> {
        client.chat(data: OKChatRequestData(model: model, messages: messages, tools: tools))
    }
}
