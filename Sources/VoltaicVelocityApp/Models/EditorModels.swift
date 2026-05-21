import Foundation
import CodeEditorView
import LanguageSupport

struct OpenFile: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    var text: String
    var selection: CodeEditor.Position = CodeEditor.Position()
    var messages: Set<TextLocated<Message>> = []

    var title: String {
        url.lastPathComponent
    }

    var language: LanguageConfiguration {
        CodeLanguage.configuration(for: url.pathExtension)
    }

    static func == (lhs: OpenFile, rhs: OpenFile) -> Bool {
        lhs.id == rhs.id
    }
}

struct ChatMessage: Identifiable {
    enum Role: String {
        case system, assistant, user
    }

    let id = UUID()
    let role: Role
    var text: String
    let date = Date()
    var activities: [AgentActivity] = []
    var totalWorkTime: TimeInterval = 0
    var filesChanged: [FileChange] = []
}

struct FileChange: Identifiable {
    let id = UUID()
    let name: String
    var added: Int
    var removed: Int
}

struct AgentActivity: Identifiable {
    enum Kind {
        case thinking(duration: TimeInterval)
        case searching(query: String, results: Int)
        case analyzing(file: String, lines: String)
        case editing(file: String, added: Int, removed: Int)
        case created(file: String)
        case deleted(file: String)
        case ranCommand(command: String)
        case completed
        case error(message: String)
        case info(message: String)
    }
    let id = UUID()
    let kind: Kind
    var details: String
    var timestamp: Date = Date()
}

struct AgentStep: Identifiable {
    enum Status {
        case pending, running, success, warning, failure
    }

    let id = UUID()
    var title: String
    var details: String
    var status: Status
    var timestamp: Date = Date()
    var fileURL: URL?
    var agentRole: AgentRole?
    var children: [AgentStep]?
}

struct PendingFileAction: Identifiable {
    enum ActionType {
        case create, edit
    }

    let id = UUID()
    let type: ActionType
    let fileURL: URL
    let existingText: String?
    let newText: String
    let summary: String
    let apply: () -> Void
}
import Foundation

enum AgentRole: String, CaseIterable, Codable, Identifiable {
    case supervisor
    case planner
    case coder
    case researcher
    case reviewer
    
    var id: String { self.rawValue }
    
    var displayName: String {
        self.rawValue.capitalized
    }
}

func systemPrompt(for role: AgentRole, context: String) -> String {
    let basePrompt: String
    switch role {
    case .supervisor:
        basePrompt = """
        You are the Supervisor Agent in Voltaic Velocity.
        Your job is to understand the user request, create a high-level plan, and delegate tasks to the correct specialized agents.
        Available agents: Planner, Researcher, Coder, Reviewer.
        Always respond with clear delegation instructions using the `delegate_task` tool.
        """
        
    case .planner:
        basePrompt = """
        You are the Planner Agent. Break down tasks into clear, sequential subtasks.
        Always start with <plan> block using the standard Voltaic Velocity format.
        Output a numbered list of actionable subtasks for other agents.
        """
        
    case .coder:
        basePrompt = """
        You are the Coder Agent powered by Qwen2.5-Coder.
        You ONLY write, edit, or refactor code. Use tools to read/write files.
        Respect existing style. Prefer small, safe changes.
        """
        
    case .researcher:
        basePrompt = """
        You are the Researcher Agent. Analyze the codebase using tools.
        Summarize relevant files, architecture, and patterns.
        Help other agents by providing accurate context.
        """
        
    case .reviewer:
        basePrompt = """
        You are the Reviewer & Tester Agent.
        Review code for bugs, style, security, and performance.
        Suggest and run tests via terminal tools.
        Be critical but constructive.
        """
    }
    
    return """
    \(basePrompt)
    
    Current Context:
    \(context)
    """
}
