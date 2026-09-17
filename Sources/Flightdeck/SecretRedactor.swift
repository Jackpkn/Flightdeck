import Foundation

/// High-performance, zero-leak secret scrubber for AI agent transcripts, tool calls,
/// and shell outputs before they are indexed, stored in SQLite, or displayed.
///
/// Designed to proactively prevent accidental leaks of API tokens, private keys,
/// and credentials into local databases or screen presentations.
public struct SecretRedactor: Sendable {

    public struct Rule: Sendable {
        public let name: String
        public let pattern: String
        let regex: NSRegularExpression

        public init(name: String, pattern: String, options: NSRegularExpression.Options = []) {
            self.name = name
            self.pattern = pattern
            // Precompile regex for zero-allocation reuse during high-throughput ingest
            self.regex = (try? NSRegularExpression(pattern: pattern, options: options)) ?? NSRegularExpression()
        }
    }

    public static let defaultRules: [Rule] = [
        // Anthropic API Keys (legacy and new formats)
        Rule(
            name: "Anthropic API Key",
            pattern: "sk-ant-(?:api03-)?[a-zA-Z0-9_\\-]{30,}"
        ),
        // OpenAI API Keys (project and legacy user keys)
        Rule(
            name: "OpenAI API Key",
            pattern: "sk-(?:proj-)?[a-zA-Z0-9_\\-]{32,}"
        ),
        // GitHub Tokens (Personal Access Token, OAuth, Fine-Grained PAT)
        Rule(
            name: "GitHub Token",
            pattern: "(?:ghp|gho|ghu|ghs|ghr)_[a-zA-Z0-9]{36,}|github_pat_[a-zA-Z0-9_\\-]{60,}"
        ),
        // AWS Access Key ID
        Rule(
            name: "AWS Access Key ID",
            pattern: "\\b(?:AKIA|ASIA|AROA)[0-9A-Z]{16}\\b"
        ),
        // Authorization Bearer Header Tokens
        Rule(
            name: "Authorization Bearer Token",
            pattern: "(?i)(?:bearer\\s+)[a-zA-Z0-9_\\-\\.]{25,}"
        ),
        // RSA / EC / OpenSSH Private Key blocks
        Rule(
            name: "Private Key Block",
            pattern: "-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----[\\s\\S]*?-----END (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----"
        ),
        // Generic high-entropy secret assignments (e.g. API_KEY=..., SECRET=...)
        Rule(
            name: "Generic Secret Assignment",
            pattern: "(?i)(?:api_key|secret_key|client_secret|auth_token|access_token|password)[\"']?\\s*[:=]\\s*[\"']?([a-zA-Z0-9_\\-]{24,})[\"']?"
        )
    ]

    private let rules: [Rule]

    public init(rules: [Rule] = SecretRedactor.defaultRules) {
        self.rules = rules
    }

    /// Default shared instance using standard rules
    public static let shared = SecretRedactor()

    /// Redacts all detected secrets in the input text with masked tokens.
    ///
    /// Preserves a short identifiable prefix and suffix where safe (e.g., `sk-ant-••••-1a2b`)
    /// so developers can confirm key rotation without exposing the secret itself.
    public func redact(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = text

        for rule in rules {
            let matches = rule.regex.matches(in: result, options: [], range: NSRange(location: 0, length: (result as NSString).length))
            // Iterate in reverse order so ranges remain valid as string lengths change
            for match in matches.reversed() {
                // If the regex has a capture group (like Generic Secret Assignment), mask group 1
                let targetRange = match.numberOfRanges > 1 && match.range(at: 1).location != NSNotFound
                    ? match.range(at: 1)
                    : match.range

                guard let swiftRange = Range(targetRange, in: result) else { continue }
                let secretValue = String(result[swiftRange])
                let masked = Self.mask(secretValue, ruleName: rule.name)
                result.replaceSubrange(swiftRange, with: masked)
            }
        }

        return result
    }

    /// Checks if the text contains any identifiable secrets.
    public func containsSecret(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return rules.contains { $0.regex.firstMatch(in: text, options: [], range: range) != nil }
    }

    /// Safely masks a secret string.
    public static func mask(_ secret: String, ruleName: String? = nil) -> String {
        if secret.hasPrefix("-----BEGIN") {
            return "[REDACTED PRIVATE KEY]"
        }

        if secret.lowercased().hasPrefix("bearer ") {
            let token = String(secret.dropFirst(7))
            return "Bearer " + mask(token)
        }

        let length = secret.count
        guard length > 8 else {
            return "••••••••"
        }

        // Determine prefix to keep based on common key formats
        var prefixLength = 0
        if secret.hasPrefix("sk-ant-api03-") {
            prefixLength = 13
        } else if secret.hasPrefix("sk-ant-") {
            prefixLength = 7
        } else if secret.hasPrefix("sk-proj-") {
            prefixLength = 8
        } else if secret.hasPrefix("sk-") {
            prefixLength = 3
        } else if secret.hasPrefix("github_pat_") {
            prefixLength = 11
        } else if secret.hasPrefix("ghp_") || secret.hasPrefix("gho_") {
            prefixLength = 4
        } else if length >= 20 {
            prefixLength = 4
        }

        let suffixLength = min(4, max(2, length - prefixLength - 6))
        guard prefixLength + suffixLength < length else {
            return String(secret.prefix(3)) + "••••••••"
        }

        let prefix = secret.prefix(prefixLength)
        let suffix = secret.suffix(suffixLength)
        return "\(prefix)••••••••\(suffix)"
    }
}
