//
//  DocxMathOMML.swift
//  Beardy2
//
//  Converts a practical LaTeX subset to Office Math Markup (OMML) for Word.
//

import Foundation

enum DocxMathOMML {
    /// Parses `$...$` segments inside plain text into alternating text / math runs.
    static func splitInlineMath(_ text: String) -> [InlineSegment] {
        var segments: [InlineSegment] = []
        var index = text.startIndex
        var buffer = ""

        func flushText() {
            guard !buffer.isEmpty else { return }
            segments.append(.text(buffer))
            buffer = ""
        }

        while index < text.endIndex {
            if text[index] == "$" {
                let next = text.index(after: index)
                if next < text.endIndex, text[next] == "$" {
                    flushText()
                    segments.append(.text("$$"))
                    index = text.index(after: next)
                    continue
                }
                flushText()
                index = text.index(after: index)
                var latex = ""
                var escaped = false
                while index < text.endIndex {
                    let ch = text[index]
                    if escaped {
                        latex.append(ch)
                        escaped = false
                    } else if ch == "\\" {
                        latex.append(ch)
                        escaped = true
                    } else if ch == "$" {
                        break
                    } else {
                        latex.append(ch)
                    }
                    index = text.index(after: index)
                }
                if index < text.endIndex, text[index] == "$" {
                    segments.append(.math(latex.trimmingCharacters(in: .whitespacesAndNewlines)))
                    index = text.index(after: index)
                } else {
                    buffer += "$" + latex
                }
                continue
            }
            buffer.append(text[index])
            index = text.index(after: index)
        }
        flushText()
        return segments
    }

    static func isDisplayMathBlock(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("$$"), trimmed.hasSuffix("$$"), trimmed.count > 4 else { return nil }
        return String(trimmed.dropFirst(2).dropLast(2))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func omml(for latex: String, display: Bool) -> String? {
        var parser = LatexOMMLParser(latex: latex.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let body = parser.parse() else { return nil }
        if display {
            return "<m:oMathPara><m:oMath>\(body)</m:oMath></m:oMathPara>"
        }
        return "<m:oMath>\(body)</m:oMath>"
    }

    enum InlineSegment {
        case text(String)
        case math(String)
    }
}

// MARK: - LaTeX → OMML (subset)

private struct LatexOMMLParser {
    let latex: String
    private(set) var index: String.Index

    init(latex: String) {
        self.latex = latex
        self.index = latex.startIndex
    }

    mutating func parse() -> String? {
        skipSpaces()
        guard index < latex.endIndex else { return nil }
        let content = parseExpression()
        skipSpaces()
        guard index == latex.endIndex, let content else { return nil }
        return content
    }

    private mutating func parseExpression() -> String? {
        var parts: [String] = []
        while index < latex.endIndex {
            skipSpaces()
            if index >= latex.endIndex { break }
            if latex[index] == "}" || latex[index] == "]" || latex[index] == ")" { break }
            if let part = parseAtom() {
                parts.append(part)
            } else {
                return nil
            }
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined()
    }

    private mutating func parseAtom() -> String? {
        skipSpaces()
        guard index < latex.endIndex else { return nil }

        if latex[index] == "\\" {
            return parseCommand()
        }
        if latex[index] == "{" {
            index = latex.index(after: index)
            guard let inner = parseExpression() else { return nil }
            guard match("}") else { return nil }
            return applyScripts(to: inner)
        }
        if latex[index] == "(" {
            index = latex.index(after: index)
            guard let inner = parseExpression(), match(")") else { return nil }
            let grouped = run("(") + inner + run(")")
            return applyScripts(to: grouped)
        }
        if latex[index] == "[" {
            index = latex.index(after: index)
            guard let inner = parseExpression(), match("]") else { return nil }
            let grouped = run("[") + inner + run("]")
            return applyScripts(to: grouped)
        }
        if latex[index] == "^" || latex[index] == "_" {
            return nil
        }

        let ch = latex[index]
        index = latex.index(after: index)
        let base = run(String(ch))
        return applyScripts(to: base)
    }

    private mutating func parseCommand() -> String? {
        index = latex.index(after: index)
        var name = ""
        while index < latex.endIndex, latex[index].isLetter {
            name.append(latex[index])
            index = latex.index(after: index)
        }
        switch name {
        case "frac":
            guard match("{"), let num = parseExpression(), match("}"), match("{"), let den = parseExpression(), match("}") else { return nil }
            let base = "<m:f><m:num>\(num)</m:num><m:den>\(den)</m:den></m:f>"
            return applyScripts(to: base)
        case "sum":
            return parseNaryOperator(char: "∑")
        case "int":
            return parseNaryOperator(char: "∫")
        case "cdot", "times":
            return run(name == "cdot" ? "·" : "×")
        case "leq": return run("≤")
        case "geq": return run("≥")
        case "neq": return run("≠")
        case "infty": return run("∞")
        case "alpha": return run("α")
        case "beta": return run("β")
        case "pi": return run("π")
        case "left", "right", " ":
            skipSpaces()
            return parseAtom()
        default:
            if name.isEmpty { return nil }
            return run("\\\(name)")
        }
    }

    private mutating func parseNaryOperator(char: String) -> String? {
        var sub = emptyScript
        var sup = emptyScript
        skipSpaces()
        if index < latex.endIndex, latex[index] == "_" {
            index = latex.index(after: index)
            sub = parseScriptValue() ?? emptyScript
        }
        skipSpaces()
        if index < latex.endIndex, latex[index] == "^" {
            index = latex.index(after: index)
            sup = parseScriptValue() ?? emptyScript
        }
        return """
        <m:nary><m:naryPr><m:chr m:val="\(char)"/><m:limLoc m:val="undOvr"/></m:naryPr>\
        <m:sub>\(sub)</m:sub><m:sup>\(sup)</m:sup><m:e>\(emptyScript)</m:e></m:nary>
        """
    }

    private var emptyScript: String {
        "<m:r><m:t xml:space=\"preserve\"> </m:t></m:r>"
    }

    private mutating func applyScripts(to base: String) -> String {
        guard !base.contains("<m:nary>") else { return base }
        var result = base
        while index < latex.endIndex {
            skipSpaces()
            if latex[index] == "^" {
                index = latex.index(after: index)
                guard let sup = parseScriptValue() else { break }
                result = "<m:sSup><m:e>\(result)</m:e><m:sup>\(sup)</m:sup></m:sSup>"
            } else if latex[index] == "_" {
                index = latex.index(after: index)
                guard let sub = parseScriptValue() else { break }
                result = "<m:sSub><m:e>\(result)</m:e><m:sub>\(sub)</m:sub></m:sSub>"
            } else {
                break
            }
        }
        return result
    }

    private mutating func parseScriptValue() -> String? {
        skipSpaces()
        if index < latex.endIndex, latex[index] == "{" {
            index = latex.index(after: index)
            guard let inner = parseExpression(), match("}") else { return nil }
            return inner
        }
        guard index < latex.endIndex else { return nil }
        let ch = latex[index]
        index = latex.index(after: index)
        return run(String(ch))
    }

    private mutating func skipSpaces() {
        while index < latex.endIndex, latex[index].isWhitespace {
            index = latex.index(after: index)
        }
    }

    private mutating func match(_ token: String) -> Bool {
        skipSpaces()
        guard latex[index...].hasPrefix(token) else { return false }
        index = latex.index(index, offsetBy: token.count)
        return true
    }

    private func run(_ text: String) -> String {
        "<m:r><m:t xml:space=\"preserve\">\(xmlEscape(text))</m:t></m:r>"
    }

    private func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
