import Testing
import Foundation
import SwiftUI
@testable import Flightdeck

@Suite struct SyntaxHighlighterTests {

    @Test func languageDetection() {
        #expect(SyntaxHighlighter.Language.detect(from: URL(fileURLWithPath: "main.py")) == .python)
        #expect(SyntaxHighlighter.Language.detect(from: URL(fileURLWithPath: "App.swift")) == .swift)
        #expect(SyntaxHighlighter.Language.detect(from: URL(fileURLWithPath: "script.ts")) == .javascript)
        #expect(SyntaxHighlighter.Language.detect(from: URL(fileURLWithPath: "config.json")) == .json)
        #expect(SyntaxHighlighter.Language.detect(from: URL(fileURLWithPath: "deploy.yml")) == .yaml)
        #expect(SyntaxHighlighter.Language.detect(from: URL(fileURLWithPath: "build.sh")) == .shell)
        #expect(SyntaxHighlighter.Language.detect(from: URL(fileURLWithPath: "notes.md")) == .markdown)
    }

    @Test func pythonHighlighting() {
        let line = "def calculate_total(items): # compute sum"
        let attr = SyntaxHighlighter.highlight(line: line, language: .python)

        // Ensure string representation has preserved text
        #expect(String(attr.characters) == line)
    }

    @Test func jsonHighlighting() {
        let line = "\"status\": \"success\","
        let attr = SyntaxHighlighter.highlight(line: line, language: .json)
        #expect(String(attr.characters) == line)
    }

    @Test func emptyLineHandling() {
        let attr = SyntaxHighlighter.highlight(line: "", language: .python)
        #expect(!String(attr.characters).isEmpty)
    }
}
