// BetterClipTests/DatabaseTests.swift
import XCTest
@testable import BetterClip

final class DatabaseTests: XCTestCase {
    var db: Database!

    override func setUp() {
        super.setUp()
        db = Database() // in-memory
    }

    func testInsertAndFetch() throws {
        var clip = Clip(id: nil, type: .text, textContent: "hello world",
                        blobHash: nil, appSource: "com.test",
                        createdAt: Date(), lastUsedAt: Date())
        try db.insertClip(&clip)
        let results = try db.fetchRecentClips(limit: 10)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].textContent, "hello world")
    }

    func testFTS5Search() throws {
        var c1 = Clip(id: nil, type: .text, textContent: "swift programming language",
                      blobHash: nil, appSource: nil, createdAt: Date(), lastUsedAt: Date())
        var c2 = Clip(id: nil, type: .text, textContent: "python scripting tools",
                      blobHash: nil, appSource: nil, createdAt: Date(), lastUsedAt: Date())
        try db.insertClip(&c1)
        try db.insertClip(&c2)
        let results = try db.searchClips(query: "swift")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].textContent, "swift programming language")
    }

    func testEmptySearchReturnsRecent() throws {
        var clip = Clip(id: nil, type: .text, textContent: "anything",
                        blobHash: nil, appSource: nil, createdAt: Date(), lastUsedAt: Date())
        try db.insertClip(&clip)
        let results = try db.searchClips(query: "")
        XCTAssertEqual(results.count, 1)
    }

    func testTrimKeepsLatest() throws {
        let baseDate = Date()
        for i in 1...5 {
            var clip = Clip(id: nil, type: .text, textContent: "item \(i)",
                            blobHash: nil, appSource: nil,
                            createdAt: baseDate.addingTimeInterval(Double(i)),
                            lastUsedAt: baseDate.addingTimeInterval(Double(i)))
            try db.insertClip(&clip)
        }
        try db.trimClips(keepingLatest: 3)
        let remaining = try db.fetchRecentClips(limit: 10)
        XCTAssertEqual(remaining.count, 3)
        XCTAssertEqual(remaining[0].textContent, "item 5")
    }

    func testSnippetCRUD() throws {
        var folder = SnippetFolder(id: nil, name: "Work", parentId: nil, sortOrder: 0)
        try db.insertFolder(&folder)
        XCTAssertNotNil(folder.id)

        var snippet = Snippet(id: nil, folderId: folder.id, name: "Email sig",
                              content: "Best, Yarin", shortcut: nil,
                              createdAt: Date(), sortOrder: 0)
        try db.insertSnippet(&snippet)

        let fetched = try db.fetchSnippets(folderId: folder.id)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].content, "Best, Yarin")
    }

    func testDeleteAllClipsRemovesHistory() throws {
        // Create multiple clips
        for i in 1...5 {
            var clip = Clip(id: nil, type: .text, textContent: "clip \(i)",
                            blobHash: nil, appSource: nil,
                            createdAt: Date().addingTimeInterval(Double(i)),
                            lastUsedAt: Date())
            try db.insertClip(&clip)
        }

        // Verify clips exist
        let beforeDelete = try db.fetchRecentClips(limit: 10)
        XCTAssertEqual(beforeDelete.count, 5)

        // Delete all clips
        let result = try db.deleteAllClips()
        XCTAssertEqual(result.clipsDeleted, 5)

        // Verify all clips are gone
        let afterDelete = try db.fetchRecentClips(limit: 10)
        XCTAssertEqual(afterDelete.count, 0)
    }

    func testDeleteAllClipsPreservesSnippets() throws {
        // Create a folder and snippet
        var folder = SnippetFolder(id: nil, name: "Saved", parentId: nil, sortOrder: 0)
        try db.insertFolder(&folder)

        var snippet = Snippet(id: nil, folderId: folder.id, name: "Important",
                              content: "Must keep this", shortcut: nil,
                              createdAt: Date(), sortOrder: 0)
        try db.insertSnippet(&snippet)

        // Create clips
        for i in 1...3 {
            var clip = Clip(id: nil, type: .text, textContent: "clip \(i)",
                            blobHash: nil, appSource: nil,
                            createdAt: Date(), lastUsedAt: Date())
            try db.insertClip(&clip)
        }

        // Delete all clips
        let result = try db.deleteAllClips()
        XCTAssertEqual(result.clipsDeleted, 3)

        // Verify snippets are still there
        let snippets = try db.fetchSnippets(folderId: folder.id)
        XCTAssertEqual(snippets.count, 1)
        XCTAssertEqual(snippets[0].content, "Must keep this")

        // Verify history is gone
        let clips = try db.fetchRecentClips(limit: 10)
        XCTAssertEqual(clips.count, 0)
    }

    func testRecoveryFromCorruptDatabase() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("corrupt-\(UUID().uuidString).sqlite")
        try "not a sqlite file".write(to: tmp, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try Database(path: tmp.path),
            "Opening a corrupt SQLite file must throw, not crash")
        try? FileManager.default.removeItem(at: tmp)
    }

    func testDatabaseFallsBackToMemoryWhenPathUnwritable() throws {
        let readOnlyDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: readOnlyDir, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o444)],
                                               ofItemAtPath: readOnlyDir.path)
        let unwritablePath = readOnlyDir.appendingPathComponent("test.sqlite").path

        XCTAssertThrowsError(try Database(path: unwritablePath),
            "Opening a DB in a read-only directory must throw, not crash with try!")

        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)],
                                               ofItemAtPath: readOnlyDir.path)
        try FileManager.default.removeItem(at: readOnlyDir)
    }

    func testSearchClipsEmptyQueryRespectsExplicitLimit() throws {
        for i in 1...60 {
            var clip = Clip(id: nil, type: .text, textContent: "item \(i)",
                            blobHash: nil, appSource: nil,
                            createdAt: Date().addingTimeInterval(Double(i)),
                            lastUsedAt: Date())
            try db.insertClip(&clip)
        }
        let defaultResult = try db.searchClips(query: "")
        XCTAssertEqual(defaultResult.count, 50,
            "Default limit of 50 must cap results at 50")

        let fullResult = try db.searchClips(query: "", limit: 60)
        XCTAssertEqual(fullResult.count, 60,
            "Explicit limit of 60 must return all 60 clips")
    }

    func testSearchClipsEmptyQueryReturnsMostRecent() throws {
        let baseDate = Date()
        for i in 1...60 {
            var clip = Clip(id: nil, type: .text, textContent: "item \(i)",
                            blobHash: nil, appSource: nil,
                            createdAt: baseDate.addingTimeInterval(Double(i)),
                            lastUsedAt: baseDate.addingTimeInterval(Double(i)))
            try db.insertClip(&clip)
        }
        let result = try db.searchClips(query: "", limit: 60)
        XCTAssertEqual(result.first?.textContent, "item 60",
            "Results must be ordered by most recently used first")
    }

    func testCleanHistoryCountsBlobsCorrectly() throws {
        // Create clips with blob hashes
        var c1 = Clip(id: nil, type: .image, textContent: nil,
                      blobHash: "hash1", appSource: nil,
                      createdAt: Date(), lastUsedAt: Date())
        var c2 = Clip(id: nil, type: .image, textContent: nil,
                      blobHash: "hash2", appSource: nil,
                      createdAt: Date(), lastUsedAt: Date())
        var c3 = Clip(id: nil, type: .image, textContent: nil,
                      blobHash: "hash1", appSource: nil,  // duplicate hash
                      createdAt: Date(), lastUsedAt: Date())

        try db.insertClip(&c1)
        try db.insertClip(&c2)
        try db.insertClip(&c3)

        // Delete should report 2 unique blobs (hash1 and hash2)
        let result = try db.deleteAllClips()
        XCTAssertEqual(result.clipsDeleted, 3)
        XCTAssertEqual(result.blobsCleaned, 2)
    }
}
