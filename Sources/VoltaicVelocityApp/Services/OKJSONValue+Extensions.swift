import Foundation
import OllamaKit

extension OKJSONValue {
    func stringValue() -> String? {
        switch self {
        case .string(let value): return value
        case .integer(let value): return String(value)
        case .number(let value): return String(value)
        case .boolean(let value): return String(value)
        default: return nil
        }
    }

    func objectValue() -> [String: OKJSONValue]? {
        guard case let .object(object) = self else { return nil }
        return object
    }

    func arrayValue() -> [OKJSONValue]? {
        guard case let .array(array) = self else { return nil }
        return array
    }

    func prettyPrinted() -> String {
        switch self {
        case .string(let value): return value
        case .integer(let value): return String(value)
        case .number(let value): return String(value)
        case .boolean(let value): return String(value)
        case .array(let values): return values.map { $0.prettyPrinted() }.joined(separator: ", ")
        case .object(let object):
            return object.map { "\($0): \($1.prettyPrinted())" }.sorted().joined(separator: ", ")
        }
    }
}
