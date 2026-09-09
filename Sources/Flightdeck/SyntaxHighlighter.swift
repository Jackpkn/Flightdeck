import SwiftUI
import AppKit
import Foundation

/// Fast syntax highlighter for code preview overlays in Flightdeck.
/// Colors tokens according to the Cyberpunk HUD design system.
public enum SyntaxHighlighter {

    public enum Language: String, Sendable {
        case python
        case swift
        case javascript
        case json
        case yaml
        case shell
        case markdown
        case html
        case css
        case generic

        public static func detect(from url: URL) -> Language {
            switch url.pathExtension.lowercased() {
            case "py", "pyw", "python":
                return .python
            case "swift":
                return .swift
            case "js", "jsx", "ts", "tsx", "mjs", "cjs":
                return .javascript
            case "json", "jsonc", "ipynb":
                return .json
            case "yaml", "yml":
                return .yaml
            case "sh", "bash", "zsh", "command", "env":
                return .shell
            case "md", "markdown":
                return .markdown
            case "html", "htm", "xml", "svg":
                return .html
            case "css", "scss", "sass", "less":
                return .css
            default:
                return .generic
            }
        }
    }

    // Color palette matching Cockpit Cyberpunk theme
    public static let keywordColor = Color(hex: 0x00f0ff)       // Cyan (#00f0ff)
    public static let typeColor    = Color(hex: 0xb026ff)       // Cyberpunk Purple (#b026ff)
    public static let stringColor  = Color(hex: 0x39ff88)       // Neon Green (#39ff88)
    public static let numberColor  = Color(hex: 0xffb800)       // Amber / Gold (#ffb800)
    public static let commentColor = Color(hex: 0x64748b)       // Muted Slate (#64748b)
    public static let funcColor    = Color(hex: 0x38bdf8)       // Sky Blue (#38bdf8)
    public static let attrColor    = Color(hex: 0xf43f5e)       // Coral Red (#f43f5e)
    public static let defaultColor = Color(hex: 0xf0f2f5)       // Ink 1 (#f0f2f5)

    // Precompiled keyword sets
    private static let pythonKeywords: Set<String> = [
        "def", "class", "import", "from", "return", "if", "elif", "else",
        "for", "while", "in", "is", "not", "and", "or", "try", "except",
        "finally", "raise", "with", "as", "pass", "break", "continue",
        "lambda", "yield", "async", "await", "assert", "del", "global", "nonlocal"
    ]

    private static let pythonTypes: Set<String> = [
        "self", "cls", "None", "True", "False", "int", "float", "str",
        "bool", "list", "dict", "set", "tuple", "bytes", "object",
        "print", "len", "range", "enumerate", "sum", "min", "max",
        "open", "super", "isinstance", "type", "zip", "map", "filter",
        "any", "all", "sorted", "reversed"
    ]

    private static let swiftKeywords: Set<String> = [
        "func", "var", "let", "struct", "class", "enum", "actor", "extension",
        "protocol", "import", "guard", "if", "else", "switch", "case", "default",
        "for", "in", "while", "repeat", "return", "throw", "throws", "try",
        "await", "async", "public", "private", "fileprivate", "internal", "open",
        "static", "final", "mutating", "override", "weak", "unowned", "some", "any",
        "init", "deinit", "subscript", "typealias", "where", "defer", "catch", "break", "continue"
    ]

    private static let swiftTypes: Set<String> = [
        "self", "Self", "true", "false", "nil", "String", "Int", "Double",
        "Float", "Bool", "Array", "Dictionary", "Set", "Optional", "Result",
        "View", "Color", "Text", "Image", "VStack", "HStack", "ZStack",
        "State", "Binding", "Observable", "Published", "Environment"
    ]

    private static let jsKeywords: Set<String> = [
        "function", "const", "let", "var", "return", "if", "else", "for",
        "while", "switch", "case", "default", "import", "export", "from",
        "as", "class", "extends", "new", "this", "async", "await", "try",
        "catch", "finally", "throw", "typeof", "instanceof", "interface",
        "type", "enum", "namespace", "implements", "yield", "void", "delete"
    ]

    private static let jsTypes: Set<String> = [
        "true", "false", "null", "undefined", "NaN", "Infinity",
        "console", "window", "document", "process", "Promise", "Array",
        "Object", "String", "Number", "Boolean", "Map", "Set", "JSON"
    ]

    private static let shellKeywords: Set<String> = [
        "echo", "cd", "ls", "pwd", "cat", "grep", "find", "export",
        "source", "if", "then", "else", "elif", "fi", "for", "while",
        "do", "done", "case", "esac", "return", "exit", "local", "sudo",
        "mkdir", "rm", "cp", "mv", "chmod", "chown", "curl", "brew", "git"
    ]

    /// Highlights a single line of source code into an `AttributedString`.
    public static func highlight(line: String, language: Language) -> AttributedString {
        if line.isEmpty {
            return AttributedString(" ")
        }

        var attributed = AttributedString(line)
        attributed.foregroundColor = defaultColor

        switch language {
        case .json:
            highlightJSON(line: line, attributed: &attributed)
        case .python:
            highlightTokens(
                line: line,
                attributed: &attributed,
                commentPrefix: "#",
                keywords: pythonKeywords,
                types: pythonTypes
            )
        case .swift:
            highlightTokens(
                line: line,
                attributed: &attributed,
                commentPrefix: "//",
                keywords: swiftKeywords,
                types: swiftTypes
            )
        case .javascript:
            highlightTokens(
                line: line,
                attributed: &attributed,
                commentPrefix: "//",
                keywords: jsKeywords,
                types: jsTypes
            )
        case .shell:
            highlightTokens(
                line: line,
                attributed: &attributed,
                commentPrefix: "#",
                keywords: shellKeywords,
                types: ["true", "false", "PATH", "HOME", "USER"]
            )
        case .yaml:
            highlightYAML(line: line, attributed: &attributed)
        default:
            highlightTokens(
                line: line,
                attributed: &attributed,
                commentPrefix: "//",
                keywords: swiftKeywords,
                types: ["true", "false", "nil", "null"]
            )
        }

        return attributed
    }

    // MARK: - Token Highlighting

    private static func highlightTokens(
        line: String,
        attributed: inout AttributedString,
        commentPrefix: String,
        keywords: Set<String>,
        types: Set<String>
    ) {
        // 1. Strings: "...", '...', f"...", `...`
        highlightRegex(pattern: #"f?\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`"#, in: line, attributed: &attributed, color: stringColor)

        // 2. Python decorators / Swift attributes: @...
        highlightRegex(pattern: #"@[A-Za-z_][A-Za-z0-9_]*"#, in: line, attributed: &attributed, color: attrColor)

        // 3. Numbers: hex, float, integer
        highlightRegex(pattern: #"\b(0x[0-9a-fA-F]+|\d+\.?\d*)\b"#, in: line, attributed: &attributed, color: numberColor)

        // 4. Words: Keywords, Types, Function definitions / calls
        let wordRegex = try? NSRegularExpression(pattern: #"\b[A-Za-z_][A-Za-z0-9_]*\b"#)
        if let matches = wordRegex?.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
            for match in matches {
                guard let range = Range(match.range, in: line) else { continue }
                let word = String(line[range])

                if keywords.contains(word) {
                    if let attrRange = Range(match.range, in: attributed) {
                        attributed[attrRange].foregroundColor = keywordColor
                    }
                } else if types.contains(word) {
                    if let attrRange = Range(match.range, in: attributed) {
                        attributed[attrRange].foregroundColor = typeColor
                    }
                } else {
                    // Check if followed by "(" -> function call/def
                    let afterIdx = range.upperBound
                    if afterIdx < line.endIndex && line[afterIdx] == "(" {
                        if let attrRange = Range(match.range, in: attributed) {
                            attributed[attrRange].foregroundColor = funcColor
                        }
                    }
                }
            }
        }

        // 5. Comments: Overwrites anything inside the comment portion
        if let commentIndex = line.range(of: commentPrefix) {
            let commentRange = commentIndex.lowerBound..<line.endIndex
            let nsRange = NSRange(commentRange, in: line)
            if let attrRange = Range(nsRange, in: attributed) {
                attributed[attrRange].foregroundColor = commentColor
            }
        }
    }

    // MARK: - JSON Highlighting

    private static func highlightJSON(line: String, attributed: inout AttributedString) {
        // String keys: "key":
        highlightRegex(pattern: #"\".*?\"\s*(?=:)"#, in: line, attributed: &attributed, color: keywordColor)
        // String values: : "value"
        highlightRegex(pattern: #"(?<=:)\s*\".*?\""#, in: line, attributed: &attributed, color: stringColor)
        // Numbers
        highlightRegex(pattern: #"\b\d+(\.\d+)?\b"#, in: line, attributed: &attributed, color: numberColor)
        // Booleans and null
        highlightRegex(pattern: #"\b(true|false|null)\b"#, in: line, attributed: &attributed, color: typeColor)
    }

    // MARK: - YAML Highlighting

    private static func highlightYAML(line: String, attributed: inout AttributedString) {
        // Comments
        if let commentIdx = line.range(of: "#") {
            let nsRange = NSRange(commentIdx.lowerBound..<line.endIndex, in: line)
            if let attrRange = Range(nsRange, in: attributed) {
                attributed[attrRange].foregroundColor = commentColor
            }
        }
        // Keys: key:
        highlightRegex(pattern: #"^[ \t]*[A-Za-z0-9_\-]+(?=:)"#, in: line, attributed: &attributed, color: keywordColor)
        // Strings
        highlightRegex(pattern: #"\".*?\"|'.*?'"#, in: line, attributed: &attributed, color: stringColor)
        // Numbers
        highlightRegex(pattern: #"\b\d+(\.\d+)?\b"#, in: line, attributed: &attributed, color: numberColor)
        // Booleans
        highlightRegex(pattern: #"\b(true|false|yes|no|on|off)\b"#, in: line, attributed: &attributed, color: typeColor)
    }

    // MARK: - Regex Helper

    private static func highlightRegex(pattern: String, in line: String, attributed: inout AttributedString, color: Color) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let matches = regex.matches(in: line, range: NSRange(line.startIndex..., in: line))
        for match in matches {
            if let attrRange = Range(match.range, in: attributed) {
                attributed[attrRange].foregroundColor = color
            }
        }
    }
}
