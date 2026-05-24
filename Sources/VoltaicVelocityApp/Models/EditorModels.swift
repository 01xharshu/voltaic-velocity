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

struct ChatMessage: Identifiable, Codable {
    enum Role: String, Codable {
        case system, assistant, user
    }

    var id: UUID = UUID()
    let role: Role
    var text: String
    var date = Date()
    var activities: [AgentActivity] = []
    var totalWorkTime: TimeInterval = 0
    var filesChanged: [FileChange] = []
}

struct FileChange: Identifiable, Codable {
    var id: UUID = UUID()
    let name: String
    var added: Int
    var removed: Int
}

struct AgentActivity: Identifiable, Codable {
    enum Kind: Codable {
        case thinking(duration: TimeInterval)
        case searching(query: String, results: Int)
        case analyzing(file: String, lines: String)
        case editing(file: String, added: Int, removed: Int)
        case created(file: String)
        case deleted(file: String)
        case ranCommand(command: String)
        case completed
        case error(message: String)
        case warning(message: String)
        case info(message: String)
        case askingUser(question: String)
        case searchingWeb(query: String)
        case runningTests(file: String)
        case profiling(command: String)
    }
    var id: UUID = UUID()
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
    case qa
    
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
        You are the Supervisor Agent in Volt Velocity.
        Your job is to understand the user request, create a high-level plan, and delegate tasks to the correct specialized agents.
        Available agents: Planner, Researcher, Coder, Reviewer.
        Always respond with clear delegation instructions using the `delegate_task` tool.
        """
        
    case .planner:
        basePrompt = """
        You are the Planner Agent. Break down tasks into clear, sequential subtasks.
        Always start with <plan> block using the standard Volt Velocity format.
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
        You are the Reviewer Agent. Verify code for logic, style, and security.
        Provide constructive feedback.
        """
        
    case .qa:
        basePrompt = """
        You are the Quality Assurance (QA) Agent. Your responsibility is to analyze test results and code coverage.
        If tests fail, use your tools to analyze the failure, modify the code to fix the bug, and re-run tests using `generate_tests`.
        You ensure all code modifications are robust before they are presented to the user.
        """
    }
    
    return """
    \(basePrompt)
    
    Current Context:
    \(context)
    """
}

public struct DiffLine: Identifiable {
    public let id = UUID()
    public let content: String
    public let type: DiffType
    
    public enum DiffType {
        case unchanged, added, removed
    }
}

public class AgentDiffUtility {
    public static func computeDiff(oldText: String?, newText: String) -> [DiffLine] {
        guard let oldText = oldText, !oldText.isEmpty else {
            return newText.components(separatedBy: .newlines).map {
                DiffLine(content: $0, type: .added)
            }
        }
        
        let oldLines = oldText.components(separatedBy: .newlines)
        let newLines = newText.components(separatedBy: .newlines)
        
        let diff = newLines.difference(from: oldLines)
        
        var result: [DiffLine] = []
        var removes: [Int: String] = [:]
        var inserts: [Int: String] = [:]
        
        for change in diff {
            switch change {
            case let .remove(offset, element, _):
                removes[offset] = element
            case let .insert(offset, element, _):
                inserts[offset] = element
            }
        }
        
        var o = 0
        var n = 0
        
        while o < oldLines.count || n < newLines.count {
            if let removed = removes[o] {
                result.append(DiffLine(content: removed, type: .removed))
                o += 1
                continue
            }
            if let inserted = inserts[n] {
                result.append(DiffLine(content: inserted, type: .added))
                n += 1
                continue
            }
            if o < oldLines.count && n < newLines.count {
                result.append(DiffLine(content: oldLines[o], type: .unchanged))
                o += 1
                n += 1
            } else if o < oldLines.count {
                o += 1
            } else if n < newLines.count {
                n += 1
            }
        }
        
        var contextResult: [DiffLine] = []
        let contextLines = 3
        
        for i in 0..<result.count {
            if result[i].type != .unchanged {
                contextResult.append(result[i])
            } else {
                let start = max(0, i - contextLines)
                let end = min(result.count - 1, i + contextLines)
                
                var hasChangeNearby = false
                for j in start...end {
                    if result[j].type != .unchanged {
                        hasChangeNearby = true
                        break
                    }
                }
                
                if hasChangeNearby {
                    contextResult.append(result[i])
                } else if contextResult.last?.content != "..." {
                    contextResult.append(DiffLine(content: "...", type: .unchanged))
                }
            }
        }
        
        return contextResult
    }
}
