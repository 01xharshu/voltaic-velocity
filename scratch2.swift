import Foundation

extension String {
    func strippingANSI() -> String {
        return self.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[a-zA-Z]", with: "", options: .regularExpression)
    }
    func applyingBackspaces() -> String {
        var result = ""
        for char in self {
            if char == "\u{08}" || char == "\u{7F}" {
                if !result.isEmpty {
                    result.removeLast()
                }
            } else {
                result.append(char)
            }
        }
        return result
    }
}

let test = "hello\u{1B}[?2004hworld\u{08} \u{08}!"
print(test.strippingANSI().applyingBackspaces())
