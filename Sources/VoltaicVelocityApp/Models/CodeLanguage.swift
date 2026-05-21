import Foundation
import LanguageSupport

enum CodeLanguage {
    static func configuration(for fileExtension: String) -> LanguageConfiguration {
        switch fileExtension.lowercased() {
        case "swift": return .swift
        case "py": return .python
        case "js", "jsx", "ts", "tsx": return .javascript
        case "json", "yaml", "yml", "plist": return .json
        default: return .plainText
        }
    }
}

extension LanguageConfiguration {
    static let plainText = LanguageConfiguration(
        name: "PlainText",
        supportsSquareBrackets: true,
        supportsCurlyBrackets: true,
        caseInsensitiveReservedIdentifiers: false,
        indentationSensitiveScoping: false,
        stringRegex: nil,
        characterRegex: nil,
        numberRegex: /(?:0x[0-9A-Fa-f]+|[0-9]+(?:\.[0-9]+)?)/,
        singleLineComment: nil,
        nestedComment: nil,
        identifierRegex: /[A-Za-z_][A-Za-z0-9_]*/,
        operatorRegex: /[+\-*/%=<>!&|^~?]+/,
        reservedIdentifiers: [],
        reservedOperators: []
    )

    static let swift = LanguageConfiguration(
        name: "Swift",
        supportsSquareBrackets: true,
        supportsCurlyBrackets: true,
        caseInsensitiveReservedIdentifiers: false,
        indentationSensitiveScoping: false,
        stringRegex: /"(?:\\.|[^"\\])*"/,
        characterRegex: /'(?:\\.|[^'\\])'/,
        numberRegex: /(?:0x[0-9A-Fa-f]+|[0-9]+(?:\.[0-9]+)?)/,
        singleLineComment: "//",
        nestedComment: ("/*", "*/"),
        identifierRegex: /[A-Za-z_][A-Za-z0-9_]*/,
        operatorRegex: /[+\-*/%=<>!&|^~?]+/,
        reservedIdentifiers: [
            "let", "var", "func", "struct", "class", "enum", "protocol", "extension", "import",
            "if", "else", "for", "while", "return", "switch", "case", "default", "break", "continue",
            "guard", "defer", "async", "await", "throws", "try", "catch", "operator", "static"
        ],
        reservedOperators: []
    )

    static let python = LanguageConfiguration(
        name: "Python",
        supportsSquareBrackets: true,
        supportsCurlyBrackets: false,
        caseInsensitiveReservedIdentifiers: false,
        indentationSensitiveScoping: true,
        stringRegex: /("""(?:.|\n)*?"""|'''(?:.|\n)*?'''|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')/,
        characterRegex: nil,
        numberRegex: /(?:0x[0-9A-Fa-f]+|[0-9]+(?:\.[0-9]+)?)/,
        singleLineComment: "#",
        nestedComment: nil,
        identifierRegex: /[A-Za-z_][A-Za-z0-9_]*/,
        operatorRegex: /[+\-*/%=<>!&|^~?]+/,
        reservedIdentifiers: [
            "def", "class", "import", "from", "as", "if", "elif", "else", "for", "while", "return", "try", "except", "finally",
            "with", "lambda", "pass", "break", "continue", "yield", "async", "await", "global", "nonlocal", "assert", "del", "raise"
        ],
        reservedOperators: []
    )

    static let javascript = LanguageConfiguration(
        name: "JavaScript",
        supportsSquareBrackets: true,
        supportsCurlyBrackets: true,
        caseInsensitiveReservedIdentifiers: false,
        indentationSensitiveScoping: false,
        stringRegex: /("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`)/,
        characterRegex: nil,
        numberRegex: /(?:0x[0-9A-Fa-f]+|[0-9]+(?:\.[0-9]+)?)/,
        singleLineComment: "//",
        nestedComment: ("/*", "*/"),
        identifierRegex: /[A-Za-z_\$][A-Za-z0-9_\$]*/,
        operatorRegex: /[+\-*/%=<>!&|^~?]+/,
        reservedIdentifiers: [
            "function", "const", "let", "var", "class", "import", "export", "default", "if", "else", "for", "while", "switch", "case", "break", "continue", "return", "try", "catch", "finally", "await", "async", "new", "this", "super"
        ],
        reservedOperators: []
    )

    static let json = LanguageConfiguration(
        name: "JSON",
        supportsSquareBrackets: true,
        supportsCurlyBrackets: true,
        caseInsensitiveReservedIdentifiers: false,
        indentationSensitiveScoping: false,
        stringRegex: /"(?:\\.|[^"\\])*"/,
        characterRegex: nil,
        numberRegex: /(?:-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)/,
        singleLineComment: nil,
        nestedComment: nil,
        identifierRegex: /[A-Za-z_][A-Za-z0-9_]*/,
        operatorRegex: /[+\-*/%=<>!&|^~?]+/,
        reservedIdentifiers: [],
        reservedOperators: []
    )
}
