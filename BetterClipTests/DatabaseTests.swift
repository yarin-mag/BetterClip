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
        for i in 1...5 {
            var clip = Clip(id: nil, type: .text, textContent: "item \(i)",
                            blobHash: nil, appSource: nil,
                            createdAt: Date().addingTimeInterval(Double(i)),
                            lastUsedAt: Date())
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
}
