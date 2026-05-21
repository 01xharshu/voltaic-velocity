import Foundation
import CodeEditorView

struct OpenFile: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    var text: String
    var selection: CodeEditor.Position = CodeEditor.Position()
    var messages: Set<TextLocated<CodeEditor.Message>> = []

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
}

struct AgentStep: Identifiable {
    enum Status {
        case pending, running, success, warning, failure
    }

    let id = UUID()
    let title: String
    let details: String
    let status: Status
    var timestamp: Date = Date()
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
