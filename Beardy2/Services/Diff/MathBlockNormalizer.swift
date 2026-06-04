import Foundation

enum MathBlockNormalizer {

    static func displayLatex(from source: String) -> String {
        let inner = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if inner.hasPrefix("$$"), inner.hasSuffix("$$"), inner.count > 4 {
            return String(inner.dropFirst(2).dropLast(2))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return inner
    }

    static func normalizedDisplayLatex(from source: String) -> String {
        displayLatex(from: source)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func equivalentDisplayMath(_ a: String, _ b: String) -> Bool {
        normalizedDisplayLatex(from: a) == normalizedDisplayLatex(from: b)
    }
}
