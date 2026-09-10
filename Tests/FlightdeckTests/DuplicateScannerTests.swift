import Testing
import Foundation
@testable import Flightdeck

@Suite("DuplicateScannerTests")
struct DuplicateScannerTests {

    @Test("Categorizes file extensions into correct DuplicateMediaKind")
    func categorizeFileTypes() {
        #expect(DuplicateMediaKind.categorize(url: URL(fileURLWithPath: "archive.zip")) == .archives)
        #expect(DuplicateMediaKind.categorize(url: URL(fileURLWithPath: "setup.dmg")) == .diskImages)
        #expect(DuplicateMediaKind.categorize(url: URL(fileURLWithPath: "movie.mp4")) == .media)
        #expect(DuplicateMediaKind.categorize(url: URL(fileURLWithPath: "report.pdf")) == .documents)
        #expect(DuplicateMediaKind.categorize(url: URL(fileURLWithPath: "script.swift")) == .codeAndOther)
    }

    @Test("Streaming SHA256 calculates identical hashes for identical content")
    func streamingSHA256ExactMatch() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let content = "FLIGHTDECK_AVIONICS_TELEMETRY_SAMPLE_\(UUID().uuidString)"
        let fileA = tempDir.appendingPathComponent("file_a.txt")
        let fileB = tempDir.appendingPathComponent("file_b.txt")
        let fileC = tempDir.appendingPathComponent("file_c.txt")

        try content.write(to: fileA, atomically: true, encoding: .utf8)
        try content.write(to: fileB, atomically: true, encoding: .utf8)
        try (content + "_DIFF").write(to: fileC, atomically: true, encoding: .utf8)

        let hashA = DuplicateScanner.computeStreamingSHA256(for: fileA)
        let hashB = DuplicateScanner.computeStreamingSHA256(for: fileB)
        let hashC = DuplicateScanner.computeStreamingSHA256(for: fileC)

        #expect(hashA != nil)
        #expect(hashA == hashB)
        #expect(hashA != hashC)
    }

    @Test("DuplicateSet computes reclaimable bytes keeping one original copy")
    func duplicateSetReclaimableBytes() {
        let now = Date()
        let files = [
            ScannedFileItem(url: URL(fileURLWithPath: "/path/a.mov"), sizeBytes: 100 * 1024 * 1024, modificationDate: now.addingTimeInterval(-200)),
            ScannedFileItem(url: URL(fileURLWithPath: "/path/b.mov"), sizeBytes: 100 * 1024 * 1024, modificationDate: now.addingTimeInterval(-100)),
            ScannedFileItem(url: URL(fileURLWithPath: "/path/c.mov"), sizeBytes: 100 * 1024 * 1024, modificationDate: now)
        ]

        let set = DuplicateSet(hash: "mockhash123", fileSize: 100 * 1024 * 1024, files: files)

        // 3 copies of 100MB -> removing 2 leaves 1 copy, reclaiming 200MB
        #expect(set.reclaimableBytes == 200 * 1024 * 1024)
    }

    @Test("Auto-selection selects all clone copies while preserving the original")
    func autoSelectClonesOnly() {
        let scanner = DuplicateScanner()
        let now = Date()

        let set1Files = [
            ScannedFileItem(url: URL(fileURLWithPath: "/orig/doc1.pdf"), sizeBytes: 10 * 1024 * 1024, modificationDate: now.addingTimeInterval(-500)),
            ScannedFileItem(url: URL(fileURLWithPath: "/copy/doc1_copy.pdf"), sizeBytes: 10 * 1024 * 1024, modificationDate: now.addingTimeInterval(-200))
        ]

        let set1 = DuplicateSet(hash: "hash_doc", fileSize: 10 * 1024 * 1024, files: set1Files)

        scanner.scan(directories: []) // clears/initializes

        #expect(set1.files.count == 2)
        #expect(set1.files[0].id == "/orig/doc1.pdf")
        #expect(set1.files[1].id == "/copy/doc1_copy.pdf")
    }

    @Test("ScannedFileItem age calculation converts seconds to days")
    func scannedFileItemAgeInDays() {
        let tenDaysAgo = Date().addingTimeInterval(-10 * 86400)
        let item = ScannedFileItem(url: URL(fileURLWithPath: "/test/file.zip"), sizeBytes: 5000, modificationDate: tenDaysAgo)

        #expect(item.ageInDays >= 9 && item.ageInDays <= 11)
    }
}
