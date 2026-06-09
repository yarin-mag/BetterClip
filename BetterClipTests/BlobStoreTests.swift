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

    func testWriteAndRead() {
        let data = Data("hello betterclip".utf8)
        let hash = store.write(data)
        XCTAssertEqual(store.read(hash: hash), data)
    }

    func testDedupSameHash() {
        let data = Data("same content".utf8)
        let h1 = store.write(data)
        let h2 = store.write(data)
        XCTAssertEqual(h1, h2)
    }

    func testDeleteRemovesFile() {
        let data = Data("to delete".utf8)
        let hash = store.write(data)
        store.delete(hash: hash)
        XCTAssertNil(store.read(hash: hash))
    }
}
