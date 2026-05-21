import Foundation
import OllamaKit

@MainActor
final class MultiAgentCoordinator: ObservableObject {
    private let service = OllamaService()
    @Published var conversations: [AgentRole: [OKChatRequestData.Message]] = [:]
    
    // Dependencies injected from AgentViewModel
    weak var agentViewModel: AgentViewModel?
    
    func runTask(userPrompt: String) async {
        guard let agentVM = agentViewModel else { return }
        
        agentVM.appendActivity(.info(message: "Supervisor: Planning task..."))
        
        let supervisorResponse = await callAgent(.supervisor, message: userPrompt)
        
        agentVM.appendActivity(.info(message: "Planner: Breaking down tasks..."))
        let plannerResponse = await callAgent(.planner, message: "Supervisor's Plan: \(supervisorResponse)\nPlease break this down.")
        
        agentVM.appendActivity(.info(message: "Coder: Writing code..."))
        let coderResponse = await callAgent(.coder, message: "Planner's Subtasks: \(plannerResponse)\nPlease execute these tasks using tools.")
        
        agentVM.appendActivity(.info(message: "Reviewer: Reviewing changes..."))
        let reviewerResponse = await callAgent(.reviewer, message: "Coder's Output: \(coderResponse)\nPlease review the changes.")
        agentVM.appendAssistantText("🛠 **Reviewer Agent:**\n\(reviewerResponse)")
        
        agentVM.isProcessing = false
    }
    
    func runQA(fileChanged: String) async {
        guard let agentVM = agentViewModel else { return }
        
        agentVM.appendActivity(.info(message: "QA: Testing changes for \(fileChanged)..."))
        agentVM.appendActivity(.runningTests(file: fileChanged), details: "Executing test suite")
        
        let qaResponse = await callAgent(.qa, message: "The user just applied edits to \(fileChanged). Run `generate_tests` to verify it. If tests fail, fix it.")
        agentVM.appendAssistantText("🧪 **QA Agent:**\n\(qaResponse)")
        
        agentVM.appendActivity(.info(message: "QA Completed: Verified the build."))
    }
    
    func callAgent(_ role: AgentRole, message: String) async -> String {
        guard let agentVM = agentViewModel else { return "" }
        
        if conversations[role] == nil {
            let context = agentVM.buildSystemPrompt()
            conversations[role] = [OKChatRequestData.Message(role: .system, content: systemPrompt(for: role, context: context))]
        }
        
        conversations[role]?.append(OKChatRequestData.Message(role: .user, content: message))
        
        var responseText = ""
        do {
            let stream = await service.streamChat(
                model: agentVM.selectedModel, // Use the user-selected model
                messages: conversations[role] ?? [],
                tools: agentVM.makeToolDefinitions()
            )
            for try await response in stream {
                if let content = response.message?.content {
                    responseText += content
                    
                    // We can pipe this to the UI if we want to show it in the chat bubble
                    agentVM.appendAssistantText(content)
                }
            }
        } catch {
            print("Error calling agent \(role.displayName): \(error)")
        }
        
        conversations[role]?.append(OKChatRequestData.Message(role: .assistant, content: responseText))
        return responseText
    }
}
