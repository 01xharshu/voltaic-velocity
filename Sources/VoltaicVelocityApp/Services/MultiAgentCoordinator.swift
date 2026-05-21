import Foundation
import OllamaKit

@MainActor
final class MultiAgentCoordinator: ObservableObject {
    private let ollama = OllamaKit()
    @Published var conversations: [AgentRole: [OKChatRequestData.Message]] = [:]
    
    // Dependencies injected from AgentViewModel
    weak var agentViewModel: AgentViewModel?
    
    func runTask(userPrompt: String) async {
        guard let agentVM = agentViewModel else { return }
        
        // 1. Initial Call to Supervisor
        agentVM.appendSystemStep(title: "Supervisor Agent", details: "Planning task...", status: .running, agentRole: .supervisor)
        
        let supervisorResponse = await callAgent(.supervisor, message: userPrompt)
        
        agentVM.appendSystemStep(title: "Supervisor Finished", details: "Delegating tasks...", status: .success, agentRole: .supervisor)
        
        // 2. We parse delegation. For MVP, we check if supervisor outputs tool calls or just parses text.
        // A simple fallback: just run planner, coder, reviewer sequentially if no specific JSON tool is found.
        // But let's look for "delegate_task" in the response, or execute it based on plan.
        
        // As a quick implementation, if we are here, we can just sequentially call Planner, Coder, Reviewer
        // in a real setup, we would parse JSON tool calls. 
        // For now, let's sequentially execute the pipeline on the user request to show Multi-Agent behavior:
        
        agentVM.appendSystemStep(title: "Planner Agent", details: "Breaking down tasks...", status: .running, agentRole: .planner)
        let plannerResponse = await callAgent(.planner, message: "Supervisor's Plan: \(supervisorResponse)\nPlease break this down.")
        agentVM.appendSystemStep(title: "Planner Finished", details: "Subtasks created.", status: .success, agentRole: .planner)
        
        agentVM.appendSystemStep(title: "Coder Agent", details: "Writing code...", status: .running, agentRole: .coder)
        let coderResponse = await callAgent(.coder, message: "Planner's Subtasks: \(plannerResponse)\nPlease execute these tasks using tools.")
        
        // The coder will likely use tools. AgentViewModel handles tool execution implicitly if we route tool calls back to it.
        // In a full implementation, `callAgent` would stream through AgentViewModel's parser to execute tools.
        
        agentVM.appendSystemStep(title: "Coder Finished", details: "Code modifications complete.", status: .success, agentRole: .coder)
        
        agentVM.appendSystemStep(title: "Reviewer Agent", details: "Reviewing changes...", status: .running, agentRole: .reviewer)
        let reviewerResponse = await callAgent(.reviewer, message: "Coder's Output: \(coderResponse)\nPlease review the changes.")
        agentVM.appendSystemStep(title: "Reviewer Finished", details: "Review complete.", status: .success, agentRole: .reviewer)
        
        agentVM.isProcessing = false
    }
    
    func callAgent(_ role: AgentRole, message: String) async -> String {
        guard let agentVM = agentViewModel else { return "" }
        
        if conversations[role] == nil {
            let context = agentVM.buildContextString()
            conversations[role] = [OKChatRequestData.Message(role: .system, content: systemPrompt(for: role, context: context))]
        }
        
        conversations[role]?.append(OKChatRequestData.Message(role: .user, content: message))
        
        var responseText = ""
        do {
            let stream = await ollama.streamChat(
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
