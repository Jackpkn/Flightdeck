import Foundation
import Testing
@testable import Flightdeck

@Suite("Secret Redactor")
struct SecretRedactorTests {

    @Test("Redacts Anthropic API keys preserving prefix and suffix")
    func redactsAnthropicKeys() {
        let key = "sk-ant-api03-abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890"
        let input = "export ANTHROPIC_API_KEY=\(key)"
        let redacted = SecretRedactor.shared.redact(input)

        #expect(!redacted.contains(key))
        #expect(redacted.contains("sk-ant-api03-••••••••"))
        #expect(SecretRedactor.shared.containsSecret(input))
    }

    @Test("Redacts OpenAI project and legacy keys")
    func redactsOpenAIKeys() {
        let projKey = "sk-proj-1234567890abcdef1234567890abcdef12345678"
        let input = "curl https://api.openai.com -H 'Authorization: Bearer \(projKey)'"
        let redacted = SecretRedactor.shared.redact(input)

        #expect(!redacted.contains(projKey))
        #expect(SecretRedactor.shared.containsSecret(input))
    }

    @Test("Redacts GitHub personal access tokens")
    func redactsGitHubPATs() {
        let token = "ghp_1234567890abcdef1234567890abcdef1234"
        let input = "git clone https://\(token)@github.com/org/repo.git"
        let redacted = SecretRedactor.shared.redact(input)

        #expect(!redacted.contains(token))
        #expect(redacted.contains("ghp_••••••••"))
    }

    @Test("Redacts AWS Access Key IDs")
    func redactsAWSAccessKeys() {
        let awsKey = "AKIAIOSFODNN7EXAMPLE"
        let input = "AWS_ACCESS_KEY_ID=\(awsKey)"
        let redacted = SecretRedactor.shared.redact(input)

        #expect(!redacted.contains(awsKey))
        #expect(redacted.contains("AKIA••••••••MPLE"))
    }

    @Test("Redacts full Private Key blocks")
    func redactsPrivateKeyBlocks() {
        let privateKey = """
        -----BEGIN RSA PRIVATE KEY-----
        MIIEowIBAAKCAQEA0Y1+abcdefghijklmnopqrstuvwxyz1234567890
        -----END RSA PRIVATE KEY-----
        """
        let input = "Server config with key:\n\(privateKey)\nDone."
        let redacted = SecretRedactor.shared.redact(input)

        #expect(!redacted.contains("MIIEowIBAAKCAQEA0Y1+"))
        #expect(redacted.contains("[REDACTED PRIVATE KEY]"))
    }

    @Test("Preserves regular code, URLs, and paths without false positives")
    func preservesNormalCode() {
        let regularCode = """
        import Foundation
        let url = URL(string: "https://flightdeck-app.netlify.app/forensics")!
        let path = "/Users/pawankumar/Projects/Flightdeck/Sources/Flightdeck/CLI.swift"
        let count = 42
        """
        let redacted = SecretRedactor.shared.redact(regularCode)
        #expect(redacted == regularCode)
        #expect(!SecretRedactor.shared.containsSecret(regularCode))
    }
}
