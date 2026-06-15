// BetterClipTests/BlobStoreTests.swift
import XCTest
@testable import BetterClip

final class BlobStoreTests: XCTestCase {
    var store: BlobStore!

    override func setUp() {
        super.setUp()
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = BlobStore(directory: tmpDir)
    }

    override func tearDown() {
        store.deleteAll()
        super.tearDown()
    }

    func testWriteAndRead() throws {
        let data = Data("hello betterclip".utf8)
        let hash = try store.write(data)
        XCTAssertEqual(store.read(hash: hash), data)
    }

    func testDedupSameHash() throws {
        let data = Data("same content".utf8)
        let h1 = try store.write(data)
        let h2 = try store.write(data)
        XCTAssertEqual(h1, h2)
    }

    func testDeleteRemovesFile() throws {
        let data = Data("to delete".utf8)
        let hash = try store.write(data)
        store.delete(hash: hash)
        XCTAssertNil(store.read(hash: hash))
    }

    func testWriteThrowsOnReadOnlyDirectory() throws {
        let readOnlyDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: readOnlyDir, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o444)],
                                               ofItemAtPath: readOnlyDir.path)
        let roStore = BlobStore(directory: readOnlyDir)
        let data = Data("test".utf8)

        XCTAssertThrowsError(try roStore.write(data),
            "write() to a read-only directory must throw, not silently return a hash")

        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)],
                                               ofItemAtPath: readOnlyDir.path)
        try FileManager.default.removeItem(at: readOnlyDir)
    }
}
