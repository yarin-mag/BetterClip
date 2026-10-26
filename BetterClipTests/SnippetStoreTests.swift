// BetterClipTests/SnippetStoreTests.swift
import XCTest
@testable import BetterClip

final class SnippetStoreTests: XCTestCase {
    var store: SnippetStore!

    override func setUp() {
        super.setUp()
        store = SnippetStore(db: Database()) // in-memory
    }

    func testCreateSnippetInDeletedFolderFallsBackToNoFolder() throws {
        let folder = try store.createFolder(name: "Gone")
        try store.deleteFolder(id: folder.id!)

        let snippet = try store.createSnippet(name: "S", content: "c", folderId: folder.id)

        XCTAssertNil(snippet.folderId)
        XCTAssertEqual(try store.snippets().count, 1)
    }

    func testCreateSnippetInExistingFolderKeepsFolder() throws {
        let folder = try store.createFolder(name: "Work")
        let snippet = try store.createSnippet(name: "S", content: "c", folderId: folder.id)
        XCTAssertEqual(snippet.folderId, folder.id)
        XCTAssertEqual(try store.snippets(folderId: folder.id).count, 1)
    }

    func testUpdateSnippetIntoDeletedFolderFallsBackToNoFolder() throws {
        let folder = try store.createFolder(name: "Gone")
        var snippet = try store.createSnippet(name: "S", content: "c")
        try store.deleteFolder(id: folder.id!)

        snippet.folderId = folder.id
        try store.update(snippet)

        XCTAssertNil(try store.snippets().first?.folderId)
    }

    func testCreateSnippetPostsChangeNotificationWithFolderId() throws {
        let folder = try store.createFolder(name: "Work")
        let exp = expectation(forNotification: SnippetStore.didChangeNotification, object: store) { note in
            note.userInfo?[SnippetStore.folderIdKey] as? Int64 == folder.id
        }
        _ = try store.createSnippet(name: "S", content: "c", folderId: folder.id)
        wait(for: [exp], timeout: 1)
    }

    func testDeleteFolderPostsChangeNotification() throws {
        let folder = try store.createFolder(name: "Work")
        let exp = expectation(forNotification: SnippetStore.didChangeNotification, object: store)
        try store.deleteFolder(id: folder.id!)
        wait(for: [exp], timeout: 1)
    }
}

final class SnippetRowViewEquatableTests: XCTestCase {
    private func row(_ name: String, _ content: String) -> SnippetRowView {
        let s = Snippet(id: 1, folderId: nil, name: name, content: content,
                        shortcut: nil, createdAt: Date(), sortOrder: 0)
        return SnippetRowView(snippet: s, isSelected: false, index: 1)
    }

    func testRowsWithEditedContentAreNotEqual() {
        XCTAssertNotEqual(row("A", "old"), row("A", "new"))
    }

    func testRowsWithEditedNameAreNotEqual() {
        XCTAssertNotEqual(row("old", "c"), row("new", "c"))
    }
}

final class AppViewModelSnippetTests: XCTestCase {
    func testSnippetChangeNotificationExpandsTargetFolder() {
        let vm = AppViewModel()
        NotificationCenter.default.post(name: SnippetStore.didChangeNotification,
                                        object: SnippetStore.shared,
                                        userInfo: [SnippetStore.folderIdKey: Int64(9999)])
        XCTAssertTrue(vm.expandedFolderIds.contains(9999))
    }
}